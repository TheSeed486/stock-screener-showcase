use std::collections::HashMap;

use anyhow::{anyhow, bail, Context, Result};
use kline_dsl::{
    mod_def::{
        indicator::{IndicatorFormula, IndicatorModDef},
        registry::ModuleRegistry,
    },
    pipeline::{Mark, NamedPoint, PointDef, PrepareStage, Stage, VarDef},
    Anchor, Expr, ParamVal, Params, PathExpr, WindowSize,
};

/// 一个 stage 在执行前需要额外预热的历史/未来 bar 数量。
#[derive(Debug, Clone)]
pub struct StagePlan {
    pub lookback_bars: usize,
    pub lookahead_bars: usize,
    pub max_window_bars: usize,
    /// 预编译的指标 Polars 表达式（避免每个标的重复编译）
    pub compiled_indicators: Vec<Vec<polars::prelude::Expr>>,
    /// 指标输出列名（用于 group_by 聚合时保留这些列）
    pub indicator_columns: Vec<String>,
}

impl StagePlan {
    fn empty() -> Self {
        Self {
            lookback_bars: 0,
            lookahead_bars: 0,
            max_window_bars: 0,
            compiled_indicators: Vec::new(),
            indicator_columns: Vec::new(),
        }
    }

    fn from_requirement(req: Requirement) -> Self {
        Self {
            lookback_bars: req.lookback,
            lookahead_bars: req.lookahead,
            max_window_bars: 0,
            compiled_indicators: Vec::new(),
            indicator_columns: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
struct Requirement {
    lookback: usize,
    lookahead: usize,
}

impl Requirement {
    fn max(self, other: Self) -> Self {
        Self {
            lookback: self.lookback.max(other.lookback),
            lookahead: self.lookahead.max(other.lookahead),
        }
    }

    fn then(self, other: Self) -> Self {
        Self {
            lookback: self.lookback.saturating_add(other.lookback),
            lookahead: self.lookahead.saturating_add(other.lookahead),
        }
    }

    fn from_offset(offset: i64) -> Self {
        if offset < 0 {
            Self {
                lookback: (-offset) as usize,
                lookahead: 0,
            }
        } else {
            Self {
                lookback: 0,
                lookahead: offset as usize,
            }
        }
    }
}

/// 计算一个 stage 需要补拉多少额外 K 线。
///
/// 当前主要面向日线/周线/月线执行层，覆盖：
/// - prepare 指标公式
/// - vars
/// - points
/// - conditions
/// - marks
/// - K 线形态窗口
pub fn plan_stage(stage: &Stage, registry: &ModuleRegistry) -> Result<StagePlan> {
    let field_requirements = collect_prepare_field_requirements(&stage.prepare, registry)?;
    let indicator_requirement = field_requirements
        .values()
        .copied()
        .fold(Requirement::default(), Requirement::max);

    // Process points first — BlockEnd doesn't need vars, and vars may reference points
    let point_requirements =
        collect_point_requirements(&stage.points, &field_requirements, &HashMap::new())?;
    let var_requirements = collect_var_requirements(&stage.vars, &field_requirements, &point_requirements)?;

    let mut total = indicator_requirement;

    for (_, expr) in &stage.conditions {
        total = total.max(plan_expr(
            expr,
            &field_requirements,
            &var_requirements,
            &point_requirements,
        )?);
    }

    for mark in &stage.marks {
        total = total.max(plan_mark(
            mark,
            &field_requirements,
            &var_requirements,
            &point_requirements,
        )?);
    }

    let mut plan = StagePlan::from_requirement(total);

    if let Some(pattern) = &stage.kline_pattern {
        total = total.max(plan_pattern(&pattern.pattern, stage.windowsize)?);
        plan.lookback_bars = total.lookback;
        plan.lookahead_bars = total.lookahead;
        plan.max_window_bars = compute_max_window(&pattern.pattern, stage.windowsize)?;
    }

    // 收集指标输出列名，供 runner group_by 聚合时保留这些列
    plan.indicator_columns = field_requirements.keys().cloned().collect();

    // 预编译所有指标表达式（缓存，避免每个标的重复编译）
    plan.compiled_indicators = stage
        .prepare
        .indicators
        .iter()
        .map(|call| {
            let def = registry
                .indicators
                .get(call.module_id.as_str())
                .ok_or_else(|| anyhow::anyhow!("indicator module not found: {}", call.module_id))?;
            Ok(crate::compiler::indicator::compile_mod(def, &call.params))
        })
        .collect::<Result<Vec<_>>>()?;

    Ok(plan)
}

fn collect_prepare_field_requirements(
    prepare: &PrepareStage,
    registry: &ModuleRegistry,
) -> Result<HashMap<String, Requirement>> {
    let mut fields = HashMap::new();
    for call in &prepare.indicators {
        let def = registry
            .indicators
            .get(call.module_id.as_str())
            .with_context(|| format!("indicator module not found: {}", call.module_id))?;
        let outputs = plan_indicator_call(def, &call.params)?;
        for (name, req) in outputs {
            fields
                .entry(name)
                .and_modify(|existing: &mut Requirement| *existing = existing.max(req))
                .or_insert(req);
        }
    }
    Ok(fields)
}

fn plan_indicator_call(
    def: &IndicatorModDef,
    params: &Params,
) -> Result<HashMap<String, Requirement>> {
    let mut outputs = HashMap::new();
    for output in &def.outputs {
        let name = render_template(&output.col_name_template, params);
        let req = plan_indicator_formula(&output.formula, params)?;
        outputs.insert(name, req);
    }
    Ok(outputs)
}

fn plan_indicator_formula(formula: &IndicatorFormula, params: &Params) -> Result<Requirement> {
    match formula {
        IndicatorFormula::Col(_) | IndicatorFormula::Lit(_) | IndicatorFormula::Param(_) => {
            Ok(Requirement::default())
        }
        IndicatorFormula::RollingMean { src, period }
        | IndicatorFormula::RollingStd { src, period }
        | IndicatorFormula::RollingMax { src, period }
        | IndicatorFormula::RollingMin { src, period }
        | IndicatorFormula::RollingSum { src, period } => {
            let period = resolve_positive_usize(period, params)?;
            Ok(plan_indicator_formula(src, params)?.then(Requirement {
                lookback: period.saturating_sub(1),
                lookahead: 0,
            }))
        }
        IndicatorFormula::Shift { src, periods } => {
            let shift = resolve_i64(periods, params)?;
            Ok(plan_indicator_formula(src, params)?.then(Requirement::from_offset(-shift)))
        }
        IndicatorFormula::Add(a, b)
        | IndicatorFormula::Sub(a, b)
        | IndicatorFormula::Mul(a, b)
        | IndicatorFormula::Div(a, b) => {
            Ok(plan_indicator_formula(a, params)?.max(plan_indicator_formula(b, params)?))
        }
        IndicatorFormula::Abs(inner) | IndicatorFormula::Neg(inner) | IndicatorFormula::Sqrt(inner) => {
            plan_indicator_formula(inner, params)
        }
        IndicatorFormula::IfElse {
            cond,
            then_val,
            else_val,
        } => Ok(plan_indicator_formula(cond, params)?
            .max(plan_indicator_formula(then_val, params)?)
            .max(plan_indicator_formula(else_val, params)?)),
    }
}

fn collect_var_requirements(
    vars: &[VarDef],
    field_requirements: &HashMap<String, Requirement>,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<HashMap<String, Requirement>> {
    let mut requirements = HashMap::new();
    for var in vars {
        let req = plan_expr(&var.expr, field_requirements, &requirements, point_requirements)
            .with_context(|| format!("plan var failed: {}", var.name))?;
        requirements.insert(var.name.clone(), req);
    }
    Ok(requirements)
}

fn collect_point_requirements(
    points: &[NamedPoint],
    field_requirements: &HashMap<String, Requirement>,
    var_requirements: &HashMap<String, Requirement>,
) -> Result<HashMap<String, Requirement>> {
    let mut requirements = HashMap::new();
    for point in points {
        let req = plan_point_def(
            &point.def,
            field_requirements,
            var_requirements,
            &requirements,
        )
        .with_context(|| format!("plan point failed: {}", point.name))?;
        requirements.insert(point.name.clone(), req);
    }
    Ok(requirements)
}

fn plan_point_def(
    def: &PointDef,
    field_requirements: &HashMap<String, Requirement>,
    var_requirements: &HashMap<String, Requirement>,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    match def {
        PointDef::BlockStart(_) | PointDef::BlockEnd(_) => Ok(Requirement::default()),
        PointDef::Offset { from, delta } => {
            let base = resolve_point_requirement(from, point_requirements)?;
            Ok(base.then(Requirement::from_offset(*delta)))
        }
        PointDef::Where {
            stock: _,
            from,
            to,
            pred,
            select: _,
        } => {
            let range_req = plan_path_row(from, point_requirements)?
                .max(plan_path_row(to, point_requirements)?);
            let pred_req = plan_expr(
                pred,
                field_requirements,
                var_requirements,
                point_requirements,
            )?;
            Ok(range_req.max(pred_req))
        }
    }
}

fn plan_mark(
    mark: &Mark,
    field_requirements: &HashMap<String, Requirement>,
    var_requirements: &HashMap<String, Requirement>,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    let mut req = plan_path_value(&mark.anchor, field_requirements, point_requirements)?;
    if let Some(value) = &mark.value {
        req = req.max(plan_expr(
            value,
            field_requirements,
            var_requirements,
            point_requirements,
        )?);
    }
    Ok(req)
}

fn plan_expr(
    expr: &Expr,
    field_requirements: &HashMap<String, Requirement>,
    var_requirements: &HashMap<String, Requirement>,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    match expr {
        Expr::Num(_) | Expr::Bool(_) => Ok(Requirement::default()),
        Expr::Path(path) => plan_path_value(path, field_requirements, point_requirements),
        Expr::Var(name) => resolve_var_requirement(name, var_requirements),
        Expr::Neg(inner) | Expr::Abs(inner) | Expr::Not(inner) => plan_expr(
            inner,
            field_requirements,
            var_requirements,
            point_requirements,
        ),
        Expr::Add(a, b)
        | Expr::Sub(a, b)
        | Expr::Mul(a, b)
        | Expr::Div(a, b)
        | Expr::Gt(a, b)
        | Expr::Lt(a, b)
        | Expr::Gte(a, b)
        | Expr::Lte(a, b)
        | Expr::Eq(a, b)
        | Expr::And(a, b)
        | Expr::Or(a, b) => {
            Ok(
                plan_expr(a, field_requirements, var_requirements, point_requirements)?.max(
                    plan_expr(b, field_requirements, var_requirements, point_requirements)?,
                ),
            )
        }
        Expr::PctChange { from, to } => Ok(plan_expr(
            from,
            field_requirements,
            var_requirements,
            point_requirements,
        )?
        .max(plan_expr(
            to,
            field_requirements,
            var_requirements,
            point_requirements,
        )?)),
        Expr::Between { val, low, high } => Ok(plan_expr(
            val,
            field_requirements,
            var_requirements,
            point_requirements,
        )?
        .max(plan_expr(
            low,
            field_requirements,
            var_requirements,
            point_requirements,
        )?)
        .max(plan_expr(
            high,
            field_requirements,
            var_requirements,
            point_requirements,
        )?)),
        Expr::Implies {
            antecedent,
            consequent,
        } => Ok(plan_expr(
            antecedent,
            field_requirements,
            var_requirements,
            point_requirements,
        )?
        .max(plan_expr(
            consequent,
            field_requirements,
            var_requirements,
            point_requirements,
        )?)),
        Expr::Agg {
            stock: _,
            from,
            to,
            col,
            func: _,
        }
        | Expr::RangeVal {
            stock: _,
            from,
            to,
            col,
            func: _,
        } => {
            let col_req = resolve_field_requirement(col, field_requirements);
            let from_req = plan_path_row(from, point_requirements)?.then(col_req);
            let to_req = plan_path_row(to, point_requirements)?.then(col_req);
            Ok(from_req.max(to_req))
        }
        Expr::All {
            stock: _,
            from,
            to,
            pred,
        }
        | Expr::Any {
            stock: _,
            from,
            to,
            pred,
        } => plan_range_predicate(
            from,
            to,
            pred,
            field_requirements,
            var_requirements,
            point_requirements,
        ),
        Expr::CountBars {
            from,
            to,
            pred,
            op: _,
            n: _,
        } => plan_range_predicate(
            from,
            to,
            pred,
            field_requirements,
            var_requirements,
            point_requirements,
        ),
        Expr::CrossUp {
            stock: _,
            at,
            col,
            threshold,
        }
        | Expr::CrossDown {
            stock: _,
            at,
            col,
            threshold,
        } => {
            let col_req = resolve_field_requirement(col, field_requirements);
            let row_req = plan_path_row(at, point_requirements)?;
            let threshold_req = plan_expr(
                threshold,
                field_requirements,
                var_requirements,
                point_requirements,
            )?;
            let cross_prev = Requirement {
                lookback: 1,
                lookahead: 0,
            };
            Ok(row_req
                .then(col_req)
                .then(cross_prev)
                .max(threshold_req.then(cross_prev)))
        }
        Expr::CandleIs {
            stock: _,
            at,
            candle: _,
        } => plan_path_row(at, point_requirements),
        Expr::PointExists(name) => resolve_point_requirement(name, point_requirements),
        Expr::Monotone {
            stock: _,
            from,
            to,
            col,
            dir: _,
        } => {
            let col_req = resolve_field_requirement(col, field_requirements);
            let from_req = plan_path_row(from, point_requirements)?.then(col_req);
            let to_req = plan_path_row(to, point_requirements)?.then(col_req);
            Ok(from_req.max(to_req))
        }
        Expr::SyncWithMarket { from, to } => Ok(
            plan_path_row(from, point_requirements)?.max(plan_path_row(to, point_requirements)?)
        ),
        Expr::Intraday(_) | Expr::IntradayDuration { .. } => Ok(Requirement::default()),
    }
}

fn plan_range_predicate(
    from: &PathExpr,
    to: &PathExpr,
    pred: &Expr,
    field_requirements: &HashMap<String, Requirement>,
    var_requirements: &HashMap<String, Requirement>,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    let pred_req = plan_expr(
        pred,
        field_requirements,
        var_requirements,
        point_requirements,
    )?;
    let from_req = plan_path_row(from, point_requirements)?.then(pred_req);
    let to_req = plan_path_row(to, point_requirements)?.then(pred_req);
    Ok(from_req
        .max(to_req)
        .max(plan_path_row(from, point_requirements)?)
        .max(plan_path_row(to, point_requirements)?))
}

fn plan_path_value(
    path: &PathExpr,
    field_requirements: &HashMap<String, Requirement>,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    let row_req = plan_path_row(path, point_requirements)?;
    let field_req = path
        .field
        .as_ref()
        .map(|field| resolve_field_requirement(field, field_requirements))
        .unwrap_or_default();
    Ok(row_req.then(field_req))
}

fn plan_path_row(
    path: &PathExpr,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    let anchor_req = match &path.anchor {
        Anchor::Point(name) => resolve_point_requirement(name, point_requirements)?,
        Anchor::WindowStart | Anchor::WindowEnd | Anchor::EachBar => Requirement::default(),
    };
    Ok(anchor_req.then(Requirement::from_offset(path.offset)))
}

fn plan_pattern(blocks: &[kline_dsl::PatternBlock], windowsize: Option<WindowSize>) -> Result<Requirement> {
    let total_from_window = windowsize.and_then(|ws| window_size_max(ws).ok()).unwrap_or(0);
    let total_from_blocks = pattern_blocks_max_len(blocks)?;
    let max_window = total_from_window.max(total_from_blocks);
    Ok(Requirement {
        lookback: max_window.saturating_sub(1),
        lookahead: 0,
    })
}

fn pattern_blocks_max_len(blocks: &[kline_dsl::PatternBlock]) -> Result<usize> {
    let mut total = 0usize;
    for (index, block) in blocks.iter().enumerate() {
        let size = window_size_max(block.block_size)?;
        total = total.saturating_add(size);
        if block.allow_overlap_next && index + 1 < blocks.len() {
            total = total.saturating_sub(1);
        }
    }
    Ok(total)
}

fn window_size_max(size: WindowSize) -> Result<usize> {
    match size {
        WindowSize::Exact(n) => Ok(n),
        WindowSize::Range { min: _, max } => {
            max.ok_or_else(|| anyhow!("cannot infer lookback from unbounded WindowSize::Range"))
        }
    }
}

/// 不报错的窗口尺寸估算：Exact → n；Range 有 max → max；Range 无 max → 回退到 blocks 推算值
fn window_size_max_or_blocks(size: WindowSize, from_blocks: usize) -> usize {
    match size {
        WindowSize::Exact(n) => n,
        WindowSize::Range { min: _, max } => max.unwrap_or(from_blocks),
    }
}

/// 综合 pattern.windowsize 与各 block 计算最大窗口 bar 数，
/// 用于 PatternMatcher 裁剪大范围候选尺寸。
fn compute_max_window(blocks: &[kline_dsl::PatternBlock], windowsize: Option<WindowSize>) -> Result<usize> {
    let from_blocks = pattern_blocks_max_len(blocks)?;
    let from_window = windowsize
        .map(|ws| window_size_max_or_blocks(ws, from_blocks))
        .unwrap_or(from_blocks);
    Ok(from_blocks.max(from_window))
}

fn resolve_positive_usize(formula: &IndicatorFormula, params: &Params) -> Result<usize> {
    let value = resolve_i64(formula, params)?;
    if value <= 0 {
        bail!("window period must be positive, got {value}");
    }
    Ok(value as usize)
}

fn resolve_i64(formula: &IndicatorFormula, params: &Params) -> Result<i64> {
    match formula {
        IndicatorFormula::Lit(v) => Ok(*v as i64),
        IndicatorFormula::Param(key) => params
            .get(key.as_str())
            .and_then(ParamVal::as_i64)
            .with_context(|| format!("missing or non-integer indicator param: {key}")),
        _ => bail!("indicator period/shift must be Lit or Param"),
    }
}

fn render_template(template: &str, params: &Params) -> String {
    let mut out = template.to_string();
    for (key, value) in params {
        let placeholder = format!("{{{key}}}");
        let rendered = match value {
            ParamVal::Int(v) => v.to_string(),
            ParamVal::Float(v) => v.to_string(),
            ParamVal::Str(v) => v.clone(),
            ParamVal::Bool(v) => v.to_string(),
        };
        out = out.replace(&placeholder, &rendered);
    }
    out
}

fn resolve_field_requirement(
    field: &str,
    field_requirements: &HashMap<String, Requirement>,
) -> Requirement {
    field_requirements.get(field).copied().unwrap_or_default()
}

fn resolve_var_requirement(
    name: &str,
    var_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    var_requirements
        .get(name)
        .copied()
        .with_context(|| format!("unknown var reference: {name}"))
}

fn resolve_point_requirement(
    name: &str,
    point_requirements: &HashMap<String, Requirement>,
) -> Result<Requirement> {
    point_requirements
        .get(name)
        .copied()
        .with_context(|| format!("unknown point reference: {name}"))
}

#[cfg(test)]
mod tests {
    use kline_dsl::{
        mod_def::{
            indicator::{FormulaOutput, IndicatorFormula, IndicatorModDef},
            registry::ModuleRegistry,
        },
        pipeline::{IndicatorCall, PrepareStage, Stage},
        Expr, PathExpr, Timeframe,
    };

    use super::plan_stage;

    #[test]
    fn planner_infers_boll_cross_lookback() {
        let mut registry = ModuleRegistry::default();
        registry.register_indicator(IndicatorModDef {
            id: "boll".to_string(),
            param_names: vec!["period".to_string(), "k".to_string()],
            outputs: vec![
                FormulaOutput {
                    col_name_template: "boll_mid_{period}".to_string(),
                    formula: IndicatorFormula::RollingMean {
                        src: Box::new(IndicatorFormula::Col("close".to_string())),
                        period: Box::new(IndicatorFormula::Param("period".to_string())),
                    },
                },
                FormulaOutput {
                    col_name_template: "boll_upper_{period}".to_string(),
                    formula: IndicatorFormula::Add(
                        Box::new(IndicatorFormula::RollingMean {
                            src: Box::new(IndicatorFormula::Col("close".to_string())),
                            period: Box::new(IndicatorFormula::Param("period".to_string())),
                        }),
                        Box::new(IndicatorFormula::Mul(
                            Box::new(IndicatorFormula::RollingStd {
                                src: Box::new(IndicatorFormula::Col("close".to_string())),
                                period: Box::new(IndicatorFormula::Param("period".to_string())),
                            }),
                            Box::new(IndicatorFormula::Param("k".to_string())),
                        )),
                    ),
                },
            ],
        });

        let stage = Stage {
            name: "daily".to_string(),
            timeframe: Timeframe::Daily,
            start_date: None,
            windowsize: None,
            // lookback_days: 0,
            prepare: PrepareStage {
                indicators: vec![IndicatorCall::new(
                    "boll",
                    kline_dsl::params! { "period" => 20_i64, "k" => 2.0_f64 },
                )],
            },
            kline_pattern: None,
            vars: Vec::new(),
            points: Vec::new(),
            conditions: vec![(
                "cross".to_string(),
                Expr::CrossUp {
                    stock: kline_dsl::StockId::Current,
                    at: PathExpr::window_end(0),
                    col: "close".to_string(),
                    threshold: Box::new(PathExpr::each().col("boll_upper_20")),
                },
            )],
            marks: Vec::new(),
            extra_stocks: Vec::new(),
        };

        let plan = plan_stage(&stage, &registry).unwrap();
        assert_eq!(plan.lookback_bars, 20);
        assert_eq!(plan.lookahead_bars, 0);
        assert_eq!(plan.max_window_bars, 0);
    }
}
