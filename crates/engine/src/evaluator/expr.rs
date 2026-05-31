use kline_dsl::{AggFunc, Anchor, CandleType, CmpOp, Expr, MonotoneDir, PathExpr, StockId};
use polars::prelude::DataFrame;

use crate::{
    evaluator::{
        ctx::EvalCtx,
        intraday::{evaluate_intraday, evaluate_intraday_duration},
    },
    DateIndex,
};

// ── 路径解析 ─────────────────────────────────────────────────

pub fn resolve_path_row(path: &PathExpr, ctx: &EvalCtx, each_row: Option<usize>) -> Option<usize> {
    let base: i64 = match &path.anchor {
        Anchor::EachBar => each_row? as i64,
        Anchor::WindowStart => ctx.window.global_start as i64,
        Anchor::WindowEnd => ctx.window.global_end as i64 - 1,
        Anchor::Point(name) => *ctx.resolved_points.get(name.as_str())?.as_ref()? as i64,
    };
    let (df, _) = stock_data(&path.stock, ctx);
    let row = base + path.offset;
    if row >= 0 && (row as usize) < df.height() { Some(row as usize) } else { None }
}

fn stock_data<'a>(s: &StockId, ctx: &'a EvalCtx) -> (&'a DataFrame, &'a DateIndex) {
    match s {
        StockId::Current => (ctx.df, ctx.dates),
        StockId::Market | StockId::MarketNamed(_) => (
            ctx.market_df.expect("missing market df"),
            ctx.market_dates.expect("missing market dates"),
        ),
        StockId::Named(name) => (
            ctx.extra_dfs.get(name.as_str()).copied().unwrap_or_else(|| panic!("missing df: {name}")),
            ctx.extra_dates.get(name.as_str()).unwrap_or_else(|| panic!("missing dates: {name}")),
        ),
    }
}

pub fn resolve_range_rows(_: &StockId, from: &PathExpr, to: &PathExpr, ctx: &EvalCtx) -> Option<(usize, usize)> {
    let s = resolve_path_row(from, ctx, None)?;
    let e = resolve_path_row(to, ctx, None)?;
    Some(if s <= e { (s, e) } else { (e, s) })
}

/// O(1) 列缓存取值
fn cell(df: &DataFrame, ctx: &EvalCtx, row: usize, col: &str) -> f64 {
    if std::ptr::eq(df, ctx.df) { ctx.val(row, col) } else { ctx.val_at(row, col, df) }
}

// ── 数值求值 ─────────────────────────────────────────────────

pub fn eval_num(expr: &Expr, ctx: &EvalCtx, each_row: Option<usize>) -> f64 {
    match expr {
        Expr::Num(v) => *v,
        Expr::Bool(b) => if *b { 1.0 } else { 0.0 },
        Expr::Var(name) => *ctx.vars.get(name.as_str()).unwrap_or_else(|| panic!("undefined var: {name}")),
        Expr::Path(path) => {
            let field = path.field.as_deref().expect("Path missing field");
            let Some(row) = resolve_path_row(path, ctx, each_row) else { return f64::NAN };
            let (df, _) = stock_data(&path.stock, ctx);
            cell(df, ctx, row, field)
        }
        Expr::Neg(a) => -eval_num(a, ctx, each_row),
        Expr::Abs(a) => eval_num(a, ctx, each_row).abs(),
        Expr::Add(a, b) => eval_num(a, ctx, each_row) + eval_num(b, ctx, each_row),
        Expr::Sub(a, b) => eval_num(a, ctx, each_row) - eval_num(b, ctx, each_row),
        Expr::Mul(a, b) => eval_num(a, ctx, each_row) * eval_num(b, ctx, each_row),
        Expr::Div(a, b) => { let d = eval_num(b, ctx, each_row); if d.abs() < 1e-12 { f64::NAN } else { eval_num(a, ctx, each_row) / d } }
        Expr::PctChange { from, to } => {
            let f = eval_num(from, ctx, each_row);
            if f.abs() < 1e-12 { f64::NAN } else { (eval_num(to, ctx, each_row) - f) / f * 100.0 }
        }
        Expr::Agg { stock, from, to, col, func } | Expr::RangeVal { stock, from, to, col, func } => {
            let Some((s, e)) = resolve_range_rows(stock, from, to, ctx) else { return f64::NAN };
            let (df, _) = stock_data(stock, ctx);
            let vals: Vec<f64> = (s..=e).map(|r| cell(df, ctx, r, col)).collect();
            agg(&vals, *func)
        }
        _ => if eval_bool(expr, ctx, each_row) { 1.0 } else { 0.0 },
    }
}

// ── 布尔求值 ─────────────────────────────────────────────────

pub fn eval_bool(expr: &Expr, ctx: &EvalCtx, each_row: Option<usize>) -> bool {
    match expr {
        Expr::Bool(b) => *b,
        Expr::Num(v) => *v != 0.0,
        Expr::Var(name) => ctx.vars.get(name.as_str()).copied().unwrap_or(0.0) != 0.0,
        Expr::And(a, b) => eval_bool(a, ctx, each_row) && eval_bool(b, ctx, each_row),
        Expr::Or(a, b) => eval_bool(a, ctx, each_row) || eval_bool(b, ctx, each_row),
        Expr::Not(a) => !eval_bool(a, ctx, each_row),
        Expr::Implies { antecedent, consequent } => !eval_bool(antecedent, ctx, each_row) || eval_bool(consequent, ctx, each_row),
        Expr::Gt(a, b) => eval_num(a, ctx, each_row) > eval_num(b, ctx, each_row),
        Expr::Lt(a, b) => eval_num(a, ctx, each_row) < eval_num(b, ctx, each_row),
        Expr::Gte(a, b) => eval_num(a, ctx, each_row) >= eval_num(b, ctx, each_row),
        Expr::Lte(a, b) => eval_num(a, ctx, each_row) <= eval_num(b, ctx, each_row),
        Expr::Eq(a, b) => (eval_num(a, ctx, each_row) - eval_num(b, ctx, each_row)).abs() < 1e-9,
        Expr::Between { val, low, high } => {
            let v = eval_num(val, ctx, each_row); let lo = eval_num(low, ctx, each_row); let hi = eval_num(high, ctx, each_row);
            !v.is_nan() && !lo.is_nan() && !hi.is_nan() && v >= lo && v <= hi
        }
        Expr::PointExists(name) => ctx.resolved_points.get(name.as_str()).and_then(|v| *v).is_some(),
        Expr::CandleIs { stock, at, candle } => {
            let Some(row) = resolve_path_row(at, ctx, each_row) else { return false };
            let (df, _) = stock_data(stock, ctx);
            let o = cell(df, ctx, row, "open"); let c = cell(df, ctx, row, "close");
            match candle { CandleType::Up => c > o, CandleType::Down => c < o, CandleType::Neutral | CandleType::Doji => (c - o).abs() < 1e-9, CandleType::Any => true }
        }
        Expr::CrossUp { stock, at, col, threshold } => {
            let Some(row) = resolve_path_row(at, ctx, each_row) else { return false };
            if row == 0 { return false; }
            let (df, _) = stock_data(stock, ctx);
            cell(df, ctx, row - 1, col) < eval_num(threshold, ctx, Some(row - 1))
                && cell(df, ctx, row, col) >= eval_num(threshold, ctx, Some(row))
        }
        Expr::CrossDown { stock, at, col, threshold } => {
            let Some(row) = resolve_path_row(at, ctx, each_row) else { return false };
            if row == 0 { return false; }
            let (df, _) = stock_data(stock, ctx);
            cell(df, ctx, row - 1, col) > eval_num(threshold, ctx, Some(row - 1))
                && cell(df, ctx, row, col) <= eval_num(threshold, ctx, Some(row))
        }
        Expr::All { stock, from, to, pred } => {
            let Some((s, e)) = resolve_range_rows(stock, from, to, ctx) else { return false };
            (s..=e).all(|row| eval_bool(pred, ctx, Some(row)))
        }
        Expr::Any { stock, from, to, pred } => {
            let Some((s, e)) = resolve_range_rows(stock, from, to, ctx) else { return false };
            (s..=e).any(|row| eval_bool(pred, ctx, Some(row)))
        }
        Expr::CountBars { from, to, pred, op, n } => {
            let Some((s, e)) = resolve_range_rows(&StockId::Current, from, to, ctx) else { return false };
            let cnt = (s..=e).filter(|&row| eval_bool(pred, ctx, Some(row))).count();
            match op { CmpOp::Gt => cnt > *n, CmpOp::Gte => cnt >= *n, CmpOp::Lt => cnt < *n, CmpOp::Lte => cnt <= *n, CmpOp::Eq => cnt == *n }
        }
        Expr::Monotone { stock, from, to, col, dir } => {
            let Some((s, e)) = resolve_range_rows(stock, from, to, ctx) else { return false };
            let (df, _) = stock_data(stock, ctx);
            let vals: Vec<f64> = (s..=e).map(|r| cell(df, ctx, r, col)).collect();
            if vals.len() < 2 { return false; }
            vals.windows(2).all(|w| match dir { MonotoneDir::StrictInc => w[1] > w[0], MonotoneDir::StrictDec => w[1] < w[0], MonotoneDir::NonDec => w[1] >= w[0], MonotoneDir::NonInc => w[1] <= w[0] })
        }
        Expr::SyncWithMarket { from, to } => {
            let Some(market_df) = ctx.market_df else { return false };
            let Some(market_dates) = ctx.market_dates else { return false };
            let Some((s, e)) = resolve_range_rows(&StockId::Current, from, to, ctx) else { return false };
            (s..=e).all(|row| {
                let date = ctx.dates.get_date(row);
                let m_row = date.and_then(|d| market_dates.row_of(d));
                let (Some(_d), Some(mr)) = (date, m_row) else { return false };
                let s_up = cell(ctx.df, ctx, row, "close") > cell(ctx.df, ctx, row, "open");
                let m_up = cell(market_df, ctx, mr, "close") > cell(market_df, ctx, mr, "open");
                s_up == m_up
            })
        }
        Expr::Intraday(cond) => evaluate_intraday(cond, ctx),
        Expr::IntradayDuration { anchor_point, stock, time_from, time_to, module_id, params, op, minutes } => {
            evaluate_intraday_duration(anchor_point, stock, *time_from, *time_to, module_id, params, *op, *minutes, ctx)
        }
        _ => eval_num(expr, ctx, each_row) != 0.0,
    }
}

fn agg(vals: &[f64], func: AggFunc) -> f64 {
    if vals.is_empty() { return f64::NAN; }
    match func {
        AggFunc::Max => vals.iter().cloned().fold(f64::NEG_INFINITY, f64::max),
        AggFunc::Min => vals.iter().cloned().fold(f64::INFINITY, f64::min),
        AggFunc::Sum => vals.iter().sum(),
        AggFunc::Mean => vals.iter().sum::<f64>() / vals.len() as f64,
        AggFunc::First => vals[0],
        AggFunc::Last => *vals.last().unwrap(),
        AggFunc::StdDev => {
            let mean = vals.iter().sum::<f64>() / vals.len() as f64;
            (vals.iter().map(|v| (v - mean).powi(2)).sum::<f64>() / vals.len() as f64).sqrt()
        }
    }
}
