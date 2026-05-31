use chrono::{NaiveTime, Timelike};
use kline_dsl::mod_def::intraday::*;
use kline_dsl::Params;
use polars::prelude::*;

use crate::evaluator::ctx::EvalCtx;
use crate::extract_f64_col;

// ── 时间工具 ────────────────────────────────────────────────────

fn time_to_minute(t: NaiveTime) -> Option<i32> {
    let total = t.hour() as i32 * 60 + t.minute() as i32;
    if total >= 9 * 60 + 31 && total <= 11 * 60 + 30 {
        return Some(total - (9 * 60 + 31));
    }
    if total >= 13 * 60 + 1 && total <= 15 * 60 {
        return Some(total - (13 * 60 + 1) + 120);
    }
    // Edge: 09:30 maps to 0
    if total == 9 * 60 + 30 {
        return Some(0);
    }
    // Edge: times in lunch break round to nearest session
    if total > 11 * 60 + 30 && total < 13 * 60 + 1 {
        if total <= 12 * 60 { return Some(119); }   // closer to morning end
        else { return Some(120); }                    // closer to afternoon start
    }
    // Before 09:30 → 0, after 15:00 → 239
    if total <= 9 * 60 + 30 { return Some(0); }
    if total >= 15 * 60 { return Some(239); }
    None
}

fn extract_i32_col(df: &DataFrame, col: &str) -> Vec<i32> {
    df.column(col)
        .ok()
        .and_then(|s| {
            s.i32().ok().map(|ca| {
                ca.into_iter()
                    .map(|v| v.unwrap_or(-1))
                    .collect::<Vec<i32>>()
            })
            .or_else(|| {
                s.f64().ok().map(|ca| {
                    ca.into_iter()
                        .map(|v| v.unwrap_or(-1.0) as i32)
                        .collect::<Vec<i32>>()
                })
            })
        })
        .unwrap_or_default()
}

fn find_row_le(minutes: &[i32], target: i32) -> Option<usize> {
    if minutes.is_empty() || target < minutes[0] {
        return Some(0);
    }
    let mut lo = 0usize;
    let mut hi = minutes.len();
    while lo + 1 < hi {
        let mid = (lo + hi) / 2;
        if minutes[mid] <= target {
            lo = mid;
        } else {
            hi = mid;
        }
    }
    Some(lo)
}

fn find_row_ge(minutes: &[i32], target: i32) -> Option<usize> {
    match minutes.binary_search(&target) {
        Ok(i) => Some(i),
        Err(i) if i < minutes.len() => Some(i),
        _ => minutes.len().checked_sub(1),
    }
}

// ── 求值上下文 ──────────────────────────────────────────────────

#[derive(Clone, Copy)]
pub(crate) struct IntradayEvalCtx<'a> {
    minute_col: &'a [i32],
    price_col: &'a [f64],
    avg_col: &'a [f64],
    volume_col: &'a [f64],
    pre_close: f64,
    limit_up: f64,
    limit_down: f64,
    range_start: i32,
    range_end: i32,
    each_minute: Option<i32>,
    params: &'a Params,
}

impl<'a> IntradayEvalCtx<'a> {
    fn with_each(&self, m: i32) -> IntradayEvalCtx<'a> {
        IntradayEvalCtx {
            each_minute: Some(m),
            ..*self
        }
    }

    fn row_for(&self, target: i32) -> Option<usize> {
        find_row_le(self.minute_col, target)
    }

    fn val(&self, row: usize, col: &[f64]) -> f64 {
        col.get(row).copied().unwrap_or(f64::NAN)
    }
}

// ── 时间引用求值 ────────────────────────────────────────────────

fn resolve_time_ref(tref: &IntradayTimeRef, ctx: &IntradayEvalCtx<'_>) -> Option<i32> {
    match tref {
        IntradayTimeRef::RangeStart => Some(ctx.range_start),
        IntradayTimeRef::RangeEnd => Some(ctx.range_end),
        IntradayTimeRef::EachMinute => ctx.each_minute,
        IntradayTimeRef::At(s) => NaiveTime::parse_from_str(s, "%H:%M")
            .ok()
            .and_then(time_to_minute),
        IntradayTimeRef::Param(k) => {
            let s = ctx.params.get(k)?.as_str()?;
            NaiveTime::parse_from_str(s, "%H:%M").ok().and_then(time_to_minute)
        }
    }
}

fn series_col<'a>(series: &IntradaySeries, ctx: &IntradayEvalCtx<'a>) -> &'a [f64] {
    match series {
        IntradaySeries::White => ctx.price_col,
        IntradaySeries::Yellow => ctx.avg_col,
        IntradaySeries::Volume => ctx.volume_col,
    }
}

// ── 数值表达式求值 ──────────────────────────────────────────────

fn eval_intraday_val(val: &IntradayVal, ctx: &IntradayEvalCtx<'_>) -> f64 {
    let col_at = |tref: &IntradayTimeRef, col: &[f64]| -> Option<f64> {
        let m = resolve_time_ref(tref, ctx)?;
        let row = ctx.row_for(m)?;
        Some(ctx.val(row, col))
    };

    match val {
        IntradayVal::Lit(v) => *v,
        IntradayVal::Param(k) => ctx
            .params
            .get(k)
            .and_then(|p| p.as_f64())
            .unwrap_or(f64::NAN),

        IntradayVal::White(tref) | IntradayVal::Close(tref) => {
            col_at(tref, ctx.price_col).unwrap_or(f64::NAN)
        }
        IntradayVal::Yellow(tref) => col_at(tref, ctx.avg_col).unwrap_or(f64::NAN),
        IntradayVal::Open(tref) => col_at(tref, ctx.price_col).unwrap_or(f64::NAN),
        IntradayVal::Volume(tref) => col_at(tref, ctx.volume_col).unwrap_or(f64::NAN),

        IntradayVal::YesterdayOpen => ctx.pre_close,
        IntradayVal::LimitUpPrice => ctx.limit_up,
        IntradayVal::LimitDownPrice => ctx.limit_down,

        IntradayVal::Slope { series, from, to } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return f64::NAN;
            };
            let col = series_col(series, ctx);
            let (Some(fr), Some(tr)) = (ctx.row_for(fm), ctx.row_for(tm)) else {
                return f64::NAN;
            };
            let n = (tr as i32 - fr as i32).max(1) as f64;
            (ctx.val(tr, col) - ctx.val(fr, col)) / n
        }

        IntradayVal::Duration { pred, from, to } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return 0.0;
            };
            count_matching(pred, fm, tm, ctx) as f64
        }

        IntradayVal::CrossCount { a, b, from, to } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return 0.0;
            };
            count_crosses(a, b, fm, tm, ctx) as f64
        }

        IntradayVal::CrossAbove { series, threshold, from, to } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return 0.0;
            };
            let thresh = eval_intraday_val(threshold, ctx);
            count_crosses_above(series, thresh, fm, tm, ctx) as f64
        }

        IntradayVal::Add(l, r) => eval_intraday_val(l, ctx) + eval_intraday_val(r, ctx),
        IntradayVal::Sub(l, r) => eval_intraday_val(l, ctx) - eval_intraday_val(r, ctx),
        IntradayVal::Mul(l, r) => eval_intraday_val(l, ctx) * eval_intraday_val(r, ctx),
        IntradayVal::Div(l, r) => {
            let d = eval_intraday_val(r, ctx);
            if d.abs() < 1e-12 {
                f64::NAN
            } else {
                eval_intraday_val(l, ctx) / d
            }
        }
        IntradayVal::Abs(v) => eval_intraday_val(v, ctx).abs(),
    }
}

// ── 布尔表达式求值 ──────────────────────────────────────────────

fn eval_intraday_bool(expr: &IntradayBoolExpr, ctx: &IntradayEvalCtx<'_>) -> bool {
    match expr {
        IntradayBoolExpr::Gt(l, r) => eval_intraday_val(l, ctx) > eval_intraday_val(r, ctx),
        IntradayBoolExpr::Lt(l, r) => eval_intraday_val(l, ctx) < eval_intraday_val(r, ctx),
        IntradayBoolExpr::Gte(l, r) => eval_intraday_val(l, ctx) >= eval_intraday_val(r, ctx),
        IntradayBoolExpr::Lte(l, r) => eval_intraday_val(l, ctx) <= eval_intraday_val(r, ctx),
        IntradayBoolExpr::Eq(l, r) => {
            (eval_intraday_val(l, ctx) - eval_intraday_val(r, ctx)).abs() < 1e-9
        }
        IntradayBoolExpr::And(l, r) => {
            eval_intraday_bool(l, ctx) && eval_intraday_bool(r, ctx)
        }
        IntradayBoolExpr::Or(l, r) => {
            eval_intraday_bool(l, ctx) || eval_intraday_bool(r, ctx)
        }
        IntradayBoolExpr::Not(v) => !eval_intraday_bool(v, ctx),

        IntradayBoolExpr::AllMinutes { pred, from, to } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return false;
            };
            for m in minute_range(fm, tm, ctx) {
                let ictx = ctx.with_each(m);
                if !eval_intraday_bool(pred, &ictx) {
                    return false;
                }
            }
            true
        }

        IntradayBoolExpr::AnyMinute { pred, from, to } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return false;
            };
            for m in minute_range(fm, tm, ctx) {
                let ictx = ctx.with_each(m);
                if eval_intraday_bool(pred, &ictx) {
                    return true;
                }
            }
            false
        }

        IntradayBoolExpr::DurationGte {
            pred,
            from,
            to,
            minutes,
        } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return false;
            };
            count_matching(pred, fm, tm, ctx) >= eval_intraday_val(minutes, ctx) as i32
        }

        IntradayBoolExpr::DurationLte {
            pred,
            from,
            to,
            minutes,
        } => {
            let (Some(fm), Some(tm)) =
                (resolve_time_ref(from, ctx), resolve_time_ref(to, ctx))
            else {
                return false;
            };
            count_matching(pred, fm, tm, ctx) <= eval_intraday_val(minutes, ctx) as i32
        }
    }
}

// ── 分钟遍历 / 统计 ─────────────────────────────────────────────

/// Lazy iterator over minute values in a range — no Vec allocation.
fn minute_range<'a>(
    from_minute: i32,
    to_minute: i32,
    ctx: &'a IntradayEvalCtx<'a>,
) -> impl Iterator<Item = i32> + 'a {
    if ctx.minute_col.is_empty() {
        return [].iter().copied(); // empty, lifetime elision ok
    }
    let start = find_row_ge(ctx.minute_col, from_minute).unwrap_or(0);
    let end = find_row_le(ctx.minute_col, to_minute)
        .unwrap_or(ctx.minute_col.len().saturating_sub(1));
    let end = end.min(ctx.minute_col.len().saturating_sub(1));
    ctx.minute_col[start..=end].iter().copied()
}

fn count_matching(
    pred: &IntradayBoolExpr,
    from_minute: i32,
    to_minute: i32,
    ctx: &IntradayEvalCtx<'_>,
) -> i32 {
    minute_range(from_minute, to_minute, ctx)
        .filter(|&m| {
            let ictx = ctx.with_each(m);
            eval_intraday_bool(pred, &ictx)
        })
        .count() as i32
}

fn count_max_continuous(
    pred: &IntradayBoolExpr,
    from_minute: i32,
    to_minute: i32,
    ctx: &IntradayEvalCtx<'_>,
) -> i32 {
    let mut max_streak = 0i32;
    let mut cur_streak = 0i32;
    for m in minute_range(from_minute, to_minute, ctx) {
        let ictx = ctx.with_each(m);
        if eval_intraday_bool(pred, &ictx) {
            cur_streak += 1;
            max_streak = max_streak.max(cur_streak);
        } else {
            cur_streak = 0;
        }
    }
    max_streak
}

fn count_crosses(
    a: &IntradaySeries,
    b: &IntradaySeries,
    from_minute: i32,
    to_minute: i32,
    ctx: &IntradayEvalCtx<'_>,
) -> i32 {
    let col_a = series_col(a, ctx);
    let col_b = series_col(b, ctx);
    let mut count = 0;
    let mut prev: Option<bool> = None;
    for m in minute_range(from_minute, to_minute, ctx) {
        let Some(row) = ctx.row_for(m) else { continue };
        let cur = ctx.val(row, col_a) > ctx.val(row, col_b);
        if prev == Some(false) && cur {
            count += 1;
        }
        prev = Some(cur);
    }
    count
}

fn count_crosses_above(
    series: &IntradaySeries,
    threshold: f64,
    from_minute: i32,
    to_minute: i32,
    ctx: &IntradayEvalCtx<'_>,
) -> i32 {
    let col = series_col(series, ctx);
    let mut count = 0;
    let mut prev: Option<bool> = None;
    for m in minute_range(from_minute, to_minute, ctx) {
        let Some(row) = ctx.row_for(m) else { continue };
        let cur = ctx.val(row, col) >= threshold;
        if prev == Some(false) && cur {
            count += 1;
        }
        prev = Some(cur);
    }
    count
}

/// Round price to 2 decimal places (A-share tick size = 0.01 yuan).
fn round2(v: f64) -> f64 { (v * 100.0).round() / 100.0 }

/// Compute exact limit-up price with rounding to fen.
fn calc_limit_up(pre_close: f64, rate: f64) -> f64 {
    round2(pre_close * (1.0 + rate))
}
fn calc_limit_down(pre_close: f64, rate: f64) -> f64 {
    round2(pre_close * (1.0 - rate))
}

/// Determine price limit rate based on market and board type.
/// 主板 ±10%, 双创(STAR/GEM) ±20%, 北交所 ±30%.
fn limit_rate(symbol: &str) -> f64 {
    if symbol.starts_with("BJ.") {
        return 0.30;
    }
    // SH.688xxx / SH.689xxx = STAR Market, SZ.300xxx / SZ.301xxx = ChiNext
    if let Some(code) = symbol.split('.').nth(1) {
        if code.starts_with("688") || code.starts_with("689") || code.starts_with("300") || code.starts_with("301") {
            return 0.20;
        }
    }
    0.10
}

// ── 公共入口 ────────────────────────────────────────────────────

pub fn evaluate_intraday(cond: &kline_dsl::IntradayCondRef, ctx: &EvalCtx<'_>) -> bool {
    let Some(date) = ctx
        .resolved_points
        .get(&cond.anchor_point)
        .copied()
        .flatten()
        .and_then(|row| ctx.dates.get_date(row))
    else {
        return false;
    };

    // Resolve the actual symbol for intraday data: cond.stock may be Market/Named/Current
    let market_symbol: String;
    let intraday_symbol: &str = match &cond.stock {
        kline_dsl::StockId::Current => ctx.symbol,
        kline_dsl::StockId::Market => {
            market_symbol = match ctx.symbol.split('.').next() {
                Some("SZ") => "SZ.399001".to_string(),
                Some("BJ") => "BJ.899050".to_string(),
                _ => "SH.000001".to_string(),
            };
            &market_symbol
        }
        kline_dsl::StockId::Named(s) | kline_dsl::StockId::MarketNamed(s) => s.as_str(),
    };

    let minute_col;
    let price_col;
    let avg_col;
    let volume_col;
    let pre_close;
    {
        let mut cache = ctx.intraday_cache.borrow_mut();
        let df = cache.get_or_load(intraday_symbol, date, ctx.data_provider);
        if df.height() == 0 {
            eprintln!("[intraday] no data for {intraday_symbol} on {date} — condition evaluates to false");
            return false;
        }
        minute_col = extract_i32_col(df, "minute");
        price_col = extract_f64_col(df, "price");
        avg_col = extract_f64_col(df, "avg");
        volume_col = extract_f64_col(df, "volume");
        pre_close = price_col.first().copied().unwrap_or(0.0);
    }

    let Some(mod_def) = ctx.registry.intraday.get(&cond.module_id) else {
        return false;
    };

    let rate = limit_rate(intraday_symbol);
    let ictx = IntradayEvalCtx {
        minute_col: &minute_col,
        price_col: &price_col,
        avg_col: &avg_col,
        volume_col: &volume_col,
        pre_close,
        limit_up: calc_limit_up(pre_close, rate),
        limit_down: calc_limit_down(pre_close, rate),
        range_start: time_to_minute(cond.time_from).unwrap_or(0),
        range_end: time_to_minute(cond.time_to).unwrap_or(239),
        each_minute: None,
        params: &cond.params,
    };

    // Try state machine first for O(1) range queries on qualifying expressions
    let result = if let Some(r) = try_eval_sm(&mod_def.expr, &price_col, &avg_col, pre_close,
                                               ictx.limit_up, ictx.limit_down, ictx.range_start, ictx.range_end) {
        r
    } else {
        eval_intraday_bool(&mod_def.expr, &ictx)
    };
    result
}

/// Attempt O(1) state-machine evaluation. Returns Some(result) on success, None to fall back to AST.
fn try_eval_sm(
    expr: &IntradayBoolExpr, price_col: &[f64], avg_col: &[f64],
    pre_close: f64, limit_up: f64, limit_down: f64, from: i32, to: i32,
) -> Option<bool> {
    use crate::evaluator::state_machine::*;
    let fu = from.max(0) as usize;
    let tu = to.min(239) as usize;
    if fu > tu { return Some(true); }

    let state = MinuteState::build(price_col, avg_col, pre_close, limit_up, limit_down);
    let eval = StateEvaluator::new(&state, expr);
    let atoms = collect_atoms(expr);

    if atoms.is_empty() { return None; }

    match expr {
        IntradayBoolExpr::AllMinutes { pred, .. } => {
            if atoms.len() == 1 {
                let a = atoms[0];
                for (atom, pref) in eval.all_prefixes() { if *atom == a { return Some(pref.all(fu, tu)); } }
            }
            None
        }
        IntradayBoolExpr::AnyMinute { pred, .. } => {
            if atoms.len() == 1 {
                let a = atoms[0];
                for (atom, pref) in eval.any_prefixes() { if *atom == a { return Some(pref.any(fu, tu)); } }
            }
            None
        }
        IntradayBoolExpr::DurationGte { pred, minutes, .. } => {
            if atoms.len() == 1 {
                let a = atoms[0];
                let min = match **minutes { IntradayVal::Lit(v) => v as u32, _ => return None };
                for (atom, pref) in eval.count_prefixes() { if *atom == a { return Some(pref.count(fu, tu) as u32 >= min); } }
            }
            None
        }
        IntradayBoolExpr::DurationLte { pred, minutes, .. } => {
            if atoms.len() == 1 {
                let a = atoms[0];
                let min = match **minutes { IntradayVal::Lit(v) => v as u32, _ => return None };
                for (atom, pref) in eval.count_prefixes() { if *atom == a { return Some(pref.count(fu, tu) as u32 <= min); } }
            }
            None
        }
        IntradayBoolExpr::And(a, b) => {
            let la = try_eval_sm(a, price_col, avg_col, pre_close, limit_up, limit_down, from, to);
            let lb = try_eval_sm(b, price_col, avg_col, pre_close, limit_up, limit_down, from, to);
            match (la, lb) { (Some(va), Some(vb)) => Some(va && vb), _ => None }
        }
        IntradayBoolExpr::Or(a, b) => {
            let la = try_eval_sm(a, price_col, avg_col, pre_close, limit_up, limit_down, from, to);
            let lb = try_eval_sm(b, price_col, avg_col, pre_close, limit_up, limit_down, from, to);
            match (la, lb) { (Some(va), Some(vb)) => Some(va || vb), _ => None }
        }
        IntradayBoolExpr::Not(a) => {
            try_eval_sm(a, price_col, avg_col, pre_close, limit_up, limit_down, from, to).map(|v| !v)
        }
        _ => None,
    }
}

/// Strip AllMinutes/AnyMinute wrappers to get the raw per-minute predicate.
fn strip_quantifiers<'a>(expr: &'a IntradayBoolExpr) -> &'a IntradayBoolExpr {
    match expr {
        IntradayBoolExpr::AllMinutes { pred, .. } => strip_quantifiers(pred),
        IntradayBoolExpr::AnyMinute { pred, .. } => strip_quantifiers(pred),
        _ => expr,
    }
}

pub fn evaluate_intraday_duration(
    anchor_point: &str,
    _stock: &kline_dsl::StockId,
    time_from: NaiveTime,
    time_to: NaiveTime,
    module_id: &str,
    params: &Params,
    op: kline_dsl::CmpOp,
    minutes: u32,
    ctx: &EvalCtx<'_>,
) -> bool {
    let Some(date) = ctx
        .resolved_points
        .get(anchor_point)
        .copied()
        .flatten()
        .and_then(|row| ctx.dates.get_date(row))
    else {
        return false;
    };

    let minute_col;
    let price_col;
    let avg_col;
    let volume_col;
    let pre_close;
    {
        let mut cache = ctx.intraday_cache.borrow_mut();
        let df = cache.get_or_load(ctx.symbol, date, ctx.data_provider);
        if df.height() == 0 {
            return false; // no intraday data available
        }
        minute_col = extract_i32_col(df, "minute");
        price_col = extract_f64_col(df, "price");
        avg_col = extract_f64_col(df, "avg");
        volume_col = extract_f64_col(df, "volume");
        pre_close = price_col.first().copied().unwrap_or(0.0);
    }

    let Some(mod_def) = ctx.registry.intraday.get(module_id) else {
        return false;
    };

    let rate = limit_rate(ctx.symbol);
    let ictx = IntradayEvalCtx {
        minute_col: &minute_col,
        price_col: &price_col,
        avg_col: &avg_col,
        volume_col: &volume_col,
        pre_close,
        limit_up: calc_limit_up(pre_close, rate),
        limit_down: calc_limit_down(pre_close, rate),
        range_start: time_to_minute(time_from).unwrap_or(0),
        range_end: time_to_minute(time_to).unwrap_or(239),
        each_minute: None,
        params,
    };

    // Extract inner predicate from AllMinutes/AnyMinute wrappers.
    // Modules like price_above_avg = AllMinutes(price > avg) are meant for
    // intraday-range checks. For duration counting, we need the raw per-minute
    // predicate, not the full quantified expression.
    let per_minute_pred = strip_quantifiers(&mod_def.expr);
    let actual = count_max_continuous(per_minute_pred, ictx.range_start, ictx.range_end, &ictx) as u32;
    match op {
        kline_dsl::CmpOp::Gt => actual > minutes,
        kline_dsl::CmpOp::Gte => actual >= minutes,
        kline_dsl::CmpOp::Lt => actual < minutes,
        kline_dsl::CmpOp::Lte => actual <= minutes,
        kline_dsl::CmpOp::Eq => actual == minutes,
    }
}

// ── 测试 ────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use polars::prelude::*;
    use std::collections::HashMap;

    fn make_minute_df(
        minutes: &[i32],
        prices: &[f64],
        avgs: &[f64],
        volumes: &[i64],
    ) -> DataFrame {
        df!(
            "minute" => minutes.to_vec(),
            "price" => prices.to_vec(),
            "avg" => avgs.to_vec(),
            "volume" => volumes.iter().map(|&v| v as f64).collect::<Vec<_>>(),
        )
        .unwrap()
    }

    #[test]
    fn eval_directly_price_above_avg() {
        // minute: 0..4, price > avg for minutes 0,2,4; price < avg for 1,3
        let _df = make_minute_df(
            &[0, 1, 2, 3, 4],
            &[11.0, 10.5, 11.2, 10.3, 11.1],
            &[10.8, 10.8, 10.8, 10.8, 10.8],
            &[100, 200, 300, 400, 500],
        );

        let pre_close = 10.80;
        let ictx = IntradayEvalCtx {
            minute_col: &[0, 1, 2, 3, 4],
            price_col: &[11.0, 10.5, 11.2, 10.3, 11.1],
            avg_col: &[10.8, 10.8, 10.8, 10.8, 10.8],
            volume_col: &[100.0, 200.0, 300.0, 400.0, 500.0],
            pre_close,
            limit_up: pre_close * 1.10,
            limit_down: pre_close * 0.90,
            range_start: 0,
            range_end: 4,
            each_minute: None,
            params: &HashMap::new(),
        };

        // price > avg => should match at minute 0
        let any_match = IntradayBoolExpr::AnyMinute {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
        };
        assert!(eval_intraday_bool(&any_match, &ictx));

        // AllMinutes should fail (minute 1 has price < avg)
        let all_match = IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
        };
        assert!(!eval_intraday_bool(&all_match, &ictx));

        // DurationGte: 3 minutes where price > avg (minutes 0, 2, 4)
        let dur = IntradayBoolExpr::DurationGte {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
            minutes: Box::new(IntradayVal::Lit(3.0)),
        };
        assert!(eval_intraday_bool(&dur, &ictx));

        let dur_fail = IntradayBoolExpr::DurationGte {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
            minutes: Box::new(IntradayVal::Lit(4.0)),
        };
        assert!(!eval_intraday_bool(&dur_fail, &ictx));
    }

    #[test]
    fn eval_price_positive_above_yesterday_open() {
        let _df = make_minute_df(
            &[0, 1, 2],
            &[10.5, 11.0, 11.2],
            &[10.5, 10.8, 11.0],
            &[100, 200, 300],
        );

        let pre_close = 10.00;
        let ictx = IntradayEvalCtx {
            minute_col: &[0, 1, 2],
            price_col: &[10.5, 11.0, 11.2],
            avg_col: &[10.5, 10.8, 11.0],
            volume_col: &[100.0, 200.0, 300.0],
            pre_close,
            limit_up: 11.0,
            limit_down: 9.0,
            range_start: 0,
            range_end: 2,
            each_minute: None,
            params: &HashMap::new(),
        };

        // price > YesterdayOpen (= pre_close = 10.00) at every minute (10.5, 11.0, 11.2)
        let all_positive = IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::YesterdayOpen,
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
        };
        assert!(eval_intraday_bool(&all_positive, &ictx));

        // Duration >= 3
        let dur = IntradayBoolExpr::DurationGte {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::YesterdayOpen,
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
            minutes: Box::new(IntradayVal::Lit(3.0)),
        };
        assert!(eval_intraday_bool(&dur, &ictx));
    }

    #[test]
    fn eval_both_positive_both_price_and_avg_above_yesterday() {
        let _df = make_minute_df(
            &[0, 1, 2, 3],
            &[10.5, 9.8, 11.0, 10.5],
            &[10.3, 9.9, 11.0, 10.3],
            &[100, 200, 300, 400],
        );

        let pre_close = 10.00;
        let ictx = IntradayEvalCtx {
            minute_col: &[0, 1, 2, 3],
            price_col: &[10.5, 9.8, 11.0, 10.5],
            avg_col: &[10.3, 9.9, 11.0, 10.3],
            volume_col: &[100.0, 200.0, 300.0, 400.0],
            pre_close,
            limit_up: 11.0,
            limit_down: 9.0,
            range_start: 0,
            range_end: 3,
            each_minute: None,
            params: &HashMap::new(),
        };

        // both price and avg above pre_close: minutes 0, 2, 3 (but minute 1 fails)
        let both_positive_pred = IntradayBoolExpr::And(
            Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::YesterdayOpen,
            )),
            Box::new(IntradayBoolExpr::Gt(
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
                IntradayVal::YesterdayOpen,
            )),
        );

        // AnyMinute: true (minute 0 is both positive)
        let any_match = IntradayBoolExpr::AnyMinute {
            pred: Box::new(both_positive_pred.clone()),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
        };
        assert!(eval_intraday_bool(&any_match, &ictx));

        // AllMinutes: false (minute 1 fails)
        let all_match = IntradayBoolExpr::AllMinutes {
            pred: Box::new(both_positive_pred.clone()),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
        };
        assert!(!eval_intraday_bool(&all_match, &ictx));

        // DurationGte >= 3: 3 minutes match (0, 2, 3)
        let dur_gte3 = IntradayBoolExpr::DurationGte {
            pred: Box::new(both_positive_pred),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
            minutes: Box::new(IntradayVal::Lit(3.0)),
        };
        assert!(eval_intraday_bool(&dur_gte3, &ictx));
    }

    // ── Realistic intraday screening scenarios ────────────────────

    /// 开盘 30 分钟内白线一直在均线上方 → 强势
    #[test]
    fn scenario_price_above_avg_early_session() {
        let prices = [11.0, 11.2, 11.1, 11.3, 11.5];
        let avgs = [10.8; 5];
        let minutes: Vec<i32> = (0..5).collect();
        let volumes = [100.0; 5];
        let pre_close = 10.50;
        let ictx = IntradayEvalCtx {
            minute_col: &minutes,
            price_col: &prices,
            avg_col: &avgs,
            volume_col: &volumes,
            pre_close,
            limit_up: pre_close * 1.10,
            limit_down: pre_close * 0.90,
            range_start: 0,
            range_end: 4,
            each_minute: None,
            params: &HashMap::new(),
        };
        let cond = IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::At("10:00".into()),
        };
        assert!(eval_intraday_bool(&cond, &ictx));
    }

    /// 盘中任一分钟跌破昨收 → 排雷
    #[test]
    fn scenario_any_minute_below_yesterday_close() {
        let prices = [10.3, 9.9, 10.1, 10.2];
        let avgs = [10.1, 10.0, 10.1, 10.1];
        let minutes: Vec<i32> = (0..4).collect();
        let volumes = [100.0; 4];
        let ictx = IntradayEvalCtx {
            minute_col: &minutes,
            price_col: &prices,
            avg_col: &avgs,
            volume_col: &volumes,
            pre_close: 10.00,
            limit_up: 11.00,
            limit_down: 9.00,
            range_start: 0,
            range_end: 3,
            each_minute: None,
            params: &HashMap::new(),
        };
        let cond = IntradayBoolExpr::AnyMinute {
            pred: Box::new(IntradayBoolExpr::Lt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::YesterdayOpen,
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::At("10:00".into()),
        };
        assert!(eval_intraday_bool(&cond, &ictx));
    }

    /// 白线高于均线持续 > 30 分钟 → 确认强势
    #[test]
    fn scenario_price_above_avg_for_30min() {
        let n: usize = 35;
        let prices = vec![11.0; n]; // all above 10.8 avg
        let avgs = vec![10.8; n];
        let minutes: Vec<i32> = (0..n as i32).collect();
        let volumes = vec![100.0; n];
        let ictx = IntradayEvalCtx {
            minute_col: &minutes,
            price_col: &prices,
            avg_col: &avgs,
            volume_col: &volumes,
            pre_close: 10.50,
            limit_up: 11.55,
            limit_down: 9.45,
            range_start: 0,
            range_end: (n - 1) as i32,
            each_minute: None,
            params: &HashMap::new(),
        };
        // 09:30→30, 10:00→29. Range [0,29] = 30 minutes. All above avg → 30 >= 30.
        let dur = IntradayBoolExpr::DurationGte {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::At("10:00".into()),
            minutes: Box::new(IntradayVal::Lit(30.0)),
        };
        assert!(eval_intraday_bool(&dur, &ictx));
    }

    /// 白线和均线均高于昨收 → 量价齐升
    #[test]
    fn scenario_both_above_yesterday_close_all_minutes() {
        let prices = [10.5, 10.6, 10.7];
        let avgs = [10.3, 10.4, 10.5];
        let minutes: Vec<i32> = (0..3).collect();
        let volumes = [100.0; 3];
        let ictx = IntradayEvalCtx {
            minute_col: &minutes,
            price_col: &prices,
            avg_col: &avgs,
            volume_col: &volumes,
            pre_close: 10.00,
            limit_up: 11.00,
            limit_down: 9.00,
            range_start: 0,
            range_end: 2,
            each_minute: None,
            params: &HashMap::new(),
        };
        let cond = IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::And(
                Box::new(IntradayBoolExpr::Gt(
                    IntradayVal::White(IntradayTimeRef::EachMinute),
                    IntradayVal::YesterdayOpen,
                )),
                Box::new(IntradayBoolExpr::Gt(
                    IntradayVal::Yellow(IntradayTimeRef::EachMinute),
                    IntradayVal::YesterdayOpen,
                )),
            )),
            from: IntradayTimeRef::RangeStart,
            to: IntradayTimeRef::RangeEnd,
        };
        assert!(eval_intraday_bool(&cond, &ictx));
    }
}
