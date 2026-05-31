use crate::{Expr, KlinePattern, Params, PathExpr, StockId, Timeframe, WindowSize};
use chrono::NaiveDate;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ── 命名点 ───────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum PointSelect {
    First,
    Last,
    Nth(usize),
    /// 从后往前第 N 根（0-indexed）
    NthFromEnd(usize),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum PointDef {
    /// 在 [from, to] 内找满足 pred 的 bar，pred 内用 PathExpr::each()
    Where {
        stock: StockId,
        from: PathExpr,
        to: PathExpr,
        pred: Expr,
        select: PointSelect,
    },
    /// 在已有点基础上偏移（越界 → None）
    Offset {
        from: String,
        delta: i64,
    },
    BlockStart(String),
    BlockEnd(String),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NamedPoint {
    pub name: String,
    pub def: PointDef,
}

// ── 变量 & 标记 ──────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VarDef {
    pub name: String,
    pub expr: Expr,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Mark {
    pub name: String,
    pub anchor: PathExpr,
    pub value: Option<Expr>,
    pub label: Option<String>,
}

// ── 指标调用 & 准备阶段 ──────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndicatorCall {
    pub module_id: String,
    pub params: Params,
}

impl IndicatorCall {
    pub fn new(id: &str, params: Params) -> Self {
        Self {
            module_id: id.into(),
            params,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PrepareStage {
    pub indicators: Vec<IndicatorCall>,
}

// ── Stage（管道中的一个筛选环节）────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Stage {
    pub name: String,
    pub timeframe: Timeframe,
    /// 扫描目标日期（窗口右边界 = 最新 bar 所在日期）
    pub start_date: Option<NaiveDate>,
    /// 扫描窗口大小（从 start_date 往左数多少根 bar）
    pub windowsize: Option<WindowSize>,
    /// 往回看多少个自然日（0 = 不限，已废弃，由 plan_stage 自动计算）
    // pub lookback_days: u32,
    pub prepare: PrepareStage,
    pub kline_pattern: Option<KlinePattern>,
    /// 变量（顺序求值）
    pub vars: Vec<VarDef>,
    /// 命名点（顺序求值，后面可引用前面）
    pub points: Vec<NamedPoint>,
    /// (condition_name, expr)，全部 AND，失败时 name 作为失败原因
    pub conditions: Vec<(String, Expr)>,
    pub marks: Vec<Mark>,
    /// 需要跨股票数据的 ticker
    pub extra_stocks: Vec<String>,
}

impl Stage {
    /// 扫描所有表达式和点位，若引用 Market 则自动加载大盘数据
    pub fn needs_market_data(&self) -> bool {
        let check_expr = |e: &Expr| -> bool { expr_refs_market(e) };
        self.vars.iter().any(|v| check_expr(&v.expr))
            || self.points.iter().any(|p| point_refs_market(&p.def))
            || self.conditions.iter().any(|(_, e)| check_expr(e))
            || self.marks.iter().any(|m| {
                check_expr(&m.anchor.clone().col("close")) // 只需检测 anchor 的 stock
                    || m.value.as_ref().map_or(false, |v| check_expr(v))
            })
    }
}

// ── Pipeline ─────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pipeline {
    pub stages: Vec<Stage>,
}

// ── 输出结果 ─────────────────────────────────────────────────

/// 单次窗口匹配的结果（一个 stage 内可能有多个匹配）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowMatch {
    pub window_start: usize,
    pub window_end: usize,
    pub resolved_points: HashMap<String, Option<usize>>,
    pub marks: HashMap<String, (NaiveDate, Option<f64>)>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StageResult {
    pub stage_name: String,
    pub symbol: String,
    pub passed: bool,
    pub passed_conditions: Vec<String>,
    pub failed_condition: Option<String>,
    /// 第一个匹配窗口的点位/标记（向后兼容）
    pub resolved_points: HashMap<String, Option<usize>>,
    pub marks: HashMap<String, (NaiveDate, Option<f64>)>,
    /// 所有匹配窗口
    pub matches: Vec<WindowMatch>,
}

impl StageResult {
    pub fn first_match(stage_name: String, symbol: String, points: HashMap<String, Option<usize>>, marks: HashMap<String, (NaiveDate, Option<f64>)>, conditions: Vec<String>, matches: Vec<WindowMatch>) -> Self {
        StageResult {
            stage_name, symbol, passed: true,
            passed_conditions: conditions,
            failed_condition: None,
            resolved_points: points, marks,
            matches,
        }
    }

    pub fn failed(stage_name: String, symbol: String, reason: String, points: HashMap<String, Option<usize>>) -> Self {
        StageResult {
            stage_name, symbol, passed: false,
            passed_conditions: Vec::new(),
            failed_condition: Some(reason),
            resolved_points: points, marks: HashMap::new(),
            matches: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ScreenResult {
    pub symbol: String,
    pub passed_stages: Vec<String>,
    pub eliminated_at: Option<String>,
    pub eliminated_reason: Option<String>,
    pub stage_results: Vec<StageResult>,
}

// ── 大盘引用自动检测 ───────────────────────────────────────

fn path_refs_market(p: &PathExpr) -> bool {
    matches!(p.stock, StockId::Market | StockId::MarketNamed(_))
}

fn expr_refs_market(e: &Expr) -> bool {
    match e {
        Expr::Path(p) => path_refs_market(p),
        Expr::Neg(a) | Expr::Abs(a) | Expr::Not(a) => expr_refs_market(a),
        Expr::Add(a,b) | Expr::Sub(a,b) | Expr::Mul(a,b) | Expr::Div(a,b)
        | Expr::Gt(a,b) | Expr::Lt(a,b) | Expr::Gte(a,b) | Expr::Lte(a,b)
        | Expr::Eq(a,b) | Expr::And(a,b) | Expr::Or(a,b) => expr_refs_market(a) || expr_refs_market(b),
        Expr::PctChange { from, to } => expr_refs_market(from) || expr_refs_market(to),
        Expr::Between { val, low, high } => expr_refs_market(val) || expr_refs_market(low) || expr_refs_market(high),
        Expr::Implies { antecedent, consequent } => expr_refs_market(antecedent) || expr_refs_market(consequent),
        Expr::Agg { stock, .. } | Expr::RangeVal { stock, .. } => {
            matches!(stock, StockId::Market | StockId::MarketNamed(_))
        }
        Expr::SyncWithMarket { .. } => true,
        Expr::All { stock, .. } | Expr::Any { stock, .. }
        | Expr::CrossUp { stock, .. } | Expr::CrossDown { stock, .. }
        | Expr::CandleIs { stock, .. } | Expr::Monotone { stock, .. } => {
            matches!(stock, StockId::Market | StockId::MarketNamed(_))
        }
        Expr::CountBars { from, to, pred, .. } => {
            path_refs_market(from) || path_refs_market(to) || expr_refs_market(pred)
        }
        Expr::Intraday(r) => matches!(r.stock, StockId::Market | StockId::MarketNamed(_)),
        _ => false,
    }
}

fn point_refs_market(d: &PointDef) -> bool {
    match d {
        PointDef::Where { stock, from, to, pred, .. } => {
            matches!(stock, StockId::Market | StockId::MarketNamed(_))
                || path_refs_market(from) || path_refs_market(to) || expr_refs_market(pred)
        }
        _ => false,
    }
}
