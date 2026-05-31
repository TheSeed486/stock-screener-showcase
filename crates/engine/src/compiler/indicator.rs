use kline_dsl::{
    mod_def::indicator::{IndicatorFormula, IndicatorModDef},
    ParamVal, Params,
};
use polars::prelude::*;

/// 将一个 IndicatorModDef（Flutter 序列化传入）编译为 Polars Expr 列表
/// 每个 Expr 都带 .alias()，可直接用于 lf.with_column()
pub fn compile_mod(def: &IndicatorModDef, params: &Params) -> Vec<Expr> {
    def.outputs
        .iter()
        .map(|out| {
            let col_name = render_template(&out.col_name_template, params);
            compile_formula(&out.formula, params).alias(&col_name)
        })
        .collect()
}

pub fn compile_formula(f: &IndicatorFormula, params: &Params) -> Expr {
    match f {
        IndicatorFormula::Col(name) => col(name.as_str()),
        IndicatorFormula::Lit(v) => lit(*v),
        IndicatorFormula::Param(key) => lit(params
            .get(key.as_str())
            .and_then(|p| p.as_f64())
            .unwrap_or_else(|| panic!("缺少参数: {key}"))),

        IndicatorFormula::RollingMean { src, period } => {
            compile_formula(src, params).rolling_mean(fixed_opts(resolve_usize(period, params)))
        }

        IndicatorFormula::RollingStd { src, period } => {
            compile_formula(src, params).rolling_std(fixed_opts(resolve_usize(period, params)))
        }

        IndicatorFormula::RollingMax { src, period } => {
            compile_formula(src, params).rolling_max(fixed_opts(resolve_usize(period, params)))
        }

        IndicatorFormula::RollingMin { src, period } => {
            compile_formula(src, params).rolling_min(fixed_opts(resolve_usize(period, params)))
        }

        IndicatorFormula::RollingSum { src, period } => {
            compile_formula(src, params).rolling_sum(fixed_opts(resolve_usize(period, params)))
        }

        IndicatorFormula::Shift { src, periods } => {
            compile_formula(src, params).shift(lit(resolve_i64(periods, params)))
        }

        IndicatorFormula::Add(a, b) => compile_formula(a, params) + compile_formula(b, params),
        IndicatorFormula::Sub(a, b) => compile_formula(a, params) - compile_formula(b, params),
        IndicatorFormula::Mul(a, b) => compile_formula(a, params) * compile_formula(b, params),
        IndicatorFormula::Div(a, b) => compile_formula(a, params) / compile_formula(b, params),
        IndicatorFormula::Abs(a) => {
            let expr = compile_formula(a, params);
            when(expr.clone().lt(lit(0.0)))
                .then(expr.clone() * lit(-1.0f64))
                .otherwise(expr)
        }
        IndicatorFormula::Neg(a) => compile_formula(a, params) * lit(-1.0f64),

        IndicatorFormula::Sqrt(a) => compile_formula(a, params).sqrt(),

        IndicatorFormula::IfElse {
            cond,
            then_val,
            else_val,
        } => when(compile_formula(cond, params))
            .then(compile_formula(then_val, params))
            .otherwise(compile_formula(else_val, params)),
    }
}

// ── 辅助 ─────────────────────────────────────────────────────

fn fixed_opts(win: usize) -> RollingOptionsFixedWindow {
    RollingOptionsFixedWindow {
        window_size: win,
        min_periods: win,
        weights: None,
        center: false,
        fn_params: None,
    }
}

fn resolve_usize(f: &IndicatorFormula, params: &Params) -> usize {
    match f {
        IndicatorFormula::Lit(v) => *v as usize,
        IndicatorFormula::Param(key) => params[key.as_str()].as_i64().unwrap() as usize,
        _ => panic!("period 必须是 Lit 或 Param"),
    }
}

fn resolve_i64(f: &IndicatorFormula, params: &Params) -> i64 {
    match f {
        IndicatorFormula::Lit(v) => *v as i64,
        IndicatorFormula::Param(key) => params[key.as_str()].as_i64().unwrap(),
        _ => panic!("periods 必须是 Lit 或 Param"),
    }
}

fn render_template(template: &str, params: &Params) -> String {
    let mut out = template.to_string();
    for (k, v) in params {
        let ph = format!("{{{k}}}");
        let val = match v {
            ParamVal::Int(i) => i.to_string(),
            ParamVal::Float(f) => f.to_string(),
            ParamVal::Str(s) => s.clone(),
            ParamVal::Bool(b) => b.to_string(),
        };
        out = out.replace(&ph, &val);
    }
    out
}
