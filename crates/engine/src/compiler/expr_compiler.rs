//! Compile kline-dsl `Expr` AST nodes to Polars `Expr` expressions.
//!
//! Only expressions with fixed offsets from `WindowEnd` on `Current` stock
//! can be vectorized.  Dynamic points, cross-stock refs, and intraday
//! conditions fall back to per-bar AST evaluation.
//!
//! Before compilation, call `resolve_point_windowend_offsets` and
//! `rewrite_expr_points` to convert `Anchor::Point` references to
//! `Anchor::WindowEnd` + computed offset, enabling batch compilation
//! of point-based conditions.

use std::collections::HashMap;

use kline_dsl::pipeline::{NamedPoint, PointDef, Stage};
use kline_dsl::{Anchor, CandleType, Expr as DslExpr, StockId, WindowSize};
use polars::prelude::Expr as PolarsExpr;
use polars::prelude::*;

/// A successfully compiled condition.
pub struct CompiledCondition {
    pub column_name: String,      // safe internal name (e.g. `_c_0`)
    pub condition_name: String,   // user-facing name for eliminated_reason
    pub expr: PolarsExpr,
}

/// Try to compile a single condition expression.
pub fn try_compile_condition(
    condition_name: &str,
    expr: &DslExpr,
) -> Option<CompiledCondition> {
    let compiled = try_compile(expr)?;
    let col = sanitize_name(condition_name);
    Some(CompiledCondition {
        column_name: format!("_c_{col}"),
        condition_name: condition_name.to_string(),
        expr: compiled.alias(format!("_c_{col}")),
    })
}

/// Compile all compilable conditions, assigning sequential column aliases.
pub fn compile_conditions(
    conditions: &[(String, DslExpr)],
) -> Vec<CompiledCondition> {
    let mut seq = 0usize;
    conditions
        .iter()
        .filter_map(|(name, expr)| {
            let compiled = try_compile(expr)?;
            let idx = seq;
            seq += 1;
            Some(CompiledCondition {
                column_name: format!("_c_{idx}"),
                condition_name: name.clone(),
                expr: compiled.alias(format!("_c_{idx}")),
            })
        })
        .collect()
}

fn sanitize_name(name: &str) -> String {
    name.replace(|c: char| !c.is_alphanumeric() && c != '_', "_")
}

// ── Recursive compiler ───────────────────────────────────────────────────

fn try_compile(expr: &DslExpr) -> Option<PolarsExpr> {
    match expr {
        // literals
        DslExpr::Num(v) => Some(lit(*v)),
        DslExpr::Bool(b) => Some(lit(*b)),

        // Path: Current stock + WindowEnd anchor only
        DslExpr::Path(path) => {
            if !matches!(path.stock, StockId::Current) { return None; }
            if !matches!(path.anchor, Anchor::WindowEnd) { return None; }
            let field = path.field.as_deref()?;
            let base = col(field);
            // DSL offset -1 (older bar) → Polars shift(1)
            Some(if path.offset == 0 { base } else { base.shift(lit(-path.offset)) })
        }

        // Var: column already in the DataFrame (from prepare stage)
        DslExpr::Var(name) => Some(col(name.as_str())),

        // arithmetic
        DslExpr::Neg(a) => Some(try_compile(a)? * lit(-1.0)),
        DslExpr::Abs(a) => {
            let inner = try_compile(a)?;
            // Polars Expr::abs() available with "abs" feature
            Some(inner.abs())
        }
        DslExpr::Add(a, b) => Some(try_compile(a)? + try_compile(b)?),
        DslExpr::Sub(a, b) => Some(try_compile(a)? - try_compile(b)?),
        DslExpr::Mul(a, b) => Some(try_compile(a)? * try_compile(b)?),
        DslExpr::Div(a, b) => Some(try_compile(a)? / try_compile(b)?),
        DslExpr::PctChange { from, to } => {
            let f = try_compile(from)?;
            let t = try_compile(to)?;
            Some((t.clone() - f.clone()) / f * lit(100.0))
        }

        // comparisons
        DslExpr::Gt(a, b) => Some(try_compile(a)?.gt(try_compile(b)?)),
        DslExpr::Lt(a, b) => Some(try_compile(a)?.lt(try_compile(b)?)),
        DslExpr::Gte(a, b) => Some(try_compile(a)?.gt_eq(try_compile(b)?)),
        DslExpr::Lte(a, b) => Some(try_compile(a)?.lt_eq(try_compile(b)?)),
        DslExpr::Eq(a, b) => Some(try_compile(a)?.eq(try_compile(b)?)),
        DslExpr::Between { val, low, high } => {
            let v = try_compile(val)?;
            let lo = try_compile(low)?;
            let hi = try_compile(high)?;
            Some(v.clone().gt_eq(lo).and(v.lt_eq(hi)))
        }

        // boolean
        DslExpr::And(a, b) => Some(try_compile(a)?.and(try_compile(b)?)),
        DslExpr::Or(a, b) => Some(try_compile(a)?.or(try_compile(b)?)),
        DslExpr::Not(a) => Some(try_compile(a)?.not()),
        DslExpr::Implies { antecedent, consequent } => {
            Some(try_compile(antecedent)?.not().or(try_compile(consequent)?))
        }

        // candle type
        DslExpr::CandleIs { stock, at, candle } => {
            if !matches!(stock, StockId::Current) { return None; }
            let at_offset = match &at.anchor {
                Anchor::WindowEnd => at.offset,
                _ => return None,
            };
            let o = col("open").shift(lit(-at_offset));
            let c = col("close").shift(lit(-at_offset));
            Some(match candle {
                CandleType::Up => c.gt(o),
                CandleType::Down => c.lt(o),
                CandleType::Neutral | CandleType::Doji => c.eq(o),
                CandleType::Any => return Some(lit(true)),
            })
        }

        // cross detection
        DslExpr::CrossUp { stock, at, col: col_name, threshold } => {
            let at_offset = fixed_at_offset(stock, at)?;
            let thresh = try_compile(threshold)?;
            let base = col(col_name.as_str());
            let curr = if at_offset == 0 { base.clone() } else { base.clone().shift(lit(-at_offset)) };
            let prev = base.shift(lit(-at_offset + 1));
            Some(prev.lt_eq(thresh.clone()).and(curr.gt(thresh)))
        }
        DslExpr::CrossDown { stock, at, col: col_name, threshold } => {
            let at_offset = fixed_at_offset(stock, at)?;
            let thresh = try_compile(threshold)?;
            let base = col(col_name.as_str());
            let curr = if at_offset == 0 { base.clone() } else { base.clone().shift(lit(-at_offset)) };
            let prev = base.shift(lit(-at_offset + 1));
            Some(prev.gt_eq(thresh.clone()).and(curr.lt(thresh)))
        }

        // rolling aggregation (fixed-range WindowEnd only)
        DslExpr::Agg { stock, from, to, col: col_name, func }
        | DslExpr::RangeVal { stock, from, to, col: col_name, func } => {
            if !matches!(stock, StockId::Current) { return None; }
            let from_off = window_end_offset(from)?;
            let to_off = window_end_offset(to)?;
            let window = (to_off - from_off).unsigned_abs() as usize + 1;
            if window == 0 || window > 500 { return None; }
            let base = col(col_name.as_str());
            let shifted = if to_off == 0 { base } else { base.shift(lit(-(to_off as i64))) };
            let opts = RollingOptionsFixedWindow {
                window_size: window,
                min_periods: window,
                ..Default::default()
            };
            Some(match func {
                kline_dsl::AggFunc::Mean => shifted.rolling_mean(opts),
                kline_dsl::AggFunc::Sum => shifted.rolling_sum(opts),
                kline_dsl::AggFunc::Max => shifted.rolling_max(opts),
                kline_dsl::AggFunc::Min => shifted.rolling_min(opts),
                kline_dsl::AggFunc::StdDev => shifted.rolling_std(opts),
                kline_dsl::AggFunc::First => col(col_name.as_str()).shift(lit(-from_off)),
                kline_dsl::AggFunc::Last => col(col_name.as_str()).shift(lit(-to_off)),
            })
        }

        // All / Any / CountBars (fixed-range, Current stock)
        DslExpr::All { stock, from, to, pred } => {
            let (fo, to) = fixed_range(stock, from, to)?;
            let (w, shifted) = shift_inner(pred, to, fo)?;
            Some(shifted.rolling_min(RollingOptionsFixedWindow {
                window_size: w, min_periods: w, ..Default::default()
            }))
        }
        DslExpr::Any { stock, from, to, pred } => {
            let (fo, to) = fixed_range(stock, from, to)?;
            let (w, shifted) = shift_inner(pred, to, fo)?;
            Some(shifted.rolling_max(RollingOptionsFixedWindow {
                window_size: w, min_periods: w, ..Default::default()
            }))
        }
        DslExpr::CountBars { from, to, pred, op, n } => {
            let (fo, to) = fixed_range(&StockId::Current, from, to)?;
            let (w, shifted) = shift_inner(pred, to, fo)?;
            let count = shifted.rolling_sum(RollingOptionsFixedWindow {
                window_size: w, min_periods: w, ..Default::default()
            });
            let n = lit(*n as f64);
            Some(match op {
                kline_dsl::CmpOp::Gt => count.gt(n),
                kline_dsl::CmpOp::Gte => count.gt_eq(n),
                kline_dsl::CmpOp::Lt => count.lt(n),
                kline_dsl::CmpOp::Lte => count.lt_eq(n),
                kline_dsl::CmpOp::Eq => count.eq(n),
            })
        }

        // not compilable
        DslExpr::PointExists(_)
        | DslExpr::Monotone { .. }
        | DslExpr::SyncWithMarket { .. }
        | DslExpr::Intraday(_)
        | DslExpr::IntradayDuration { .. } => None,
    }
}

// ── Helpers ──────────────────────────────────────────────────────────────

fn fixed_at_offset(stock: &StockId, at: &kline_dsl::PathExpr) -> Option<i64> {
    if !matches!(stock, StockId::Current) { return None; }
    match &at.anchor {
        Anchor::WindowEnd => Some(at.offset),
        _ => None,
    }
}

fn window_end_offset(path: &kline_dsl::PathExpr) -> Option<i64> {
    match &path.anchor {
        Anchor::WindowEnd => Some(path.offset),
        _ => None,
    }
}

fn fixed_range(
    stock: &StockId,
    from: &kline_dsl::PathExpr,
    to: &kline_dsl::PathExpr,
) -> Option<(i64, i64)> {
    if !matches!(stock, StockId::Current) { return None; }
    let fo = window_end_offset(from)?;
    let to = window_end_offset(to)?;
    Some((fo, to))
}

fn shift_inner(pred: &DslExpr, to_off: i64, from_off: i64) -> Option<(usize, PolarsExpr)> {
    let window = (to_off - from_off).unsigned_abs() as usize + 1;
    if window == 0 || window > 500 { return None; }
    let inner = try_compile(pred)?;
    let shifted = if to_off == 0 { inner } else { inner.shift(lit(-to_off)) };
    Some((window, shifted))
}

// ── Point → WindowEnd offset resolution ─────────────────────────────────

/// Compute the WindowEnd offset for each named point based on the pattern's
/// block structure.  Only works when all blocks have `Exact` size.
pub fn resolve_point_windowend_offsets(stage: &Stage) -> HashMap<String, i64> {
    let mut offsets = HashMap::new();
    let Some(ref pattern) = stage.kline_pattern else {
        return offsets;
    };

    // 1. Scan blocks from last to first to compute block start/end offsets
    let mut block_end: HashMap<&str, i64> = HashMap::new();
    let mut block_start: HashMap<&str, i64> = HashMap::new();
    let mut cumulative: i64 = 0;
    for block in pattern.pattern.iter().rev() {
        let size = match block.block_size {
            WindowSize::Exact(n) => n as i64,
            _ => return HashMap::new(), // variable-sized blocks: can't resolve
        };
        block_end.insert(block.block_name.as_str(), cumulative);
        block_start.insert(block.block_name.as_str(), cumulative - (size - 1));
        cumulative -= size;
    }

    // 2. Resolve each point definition to its WindowEnd offset
    for point in &stage.points {
        let off = match &point.def {
            PointDef::BlockEnd(name) => block_end.get(name.as_str()).copied(),
            PointDef::BlockStart(name) => block_start.get(name.as_str()).copied(),
            PointDef::Offset { from, delta } => {
                offsets.get(from.as_str()).map(|base| base + delta)
            }
            PointDef::Where { .. } => None,
        };
        if let Some(o) = off {
            offsets.insert(point.name.clone(), o);
        }
    }
    offsets
}

/// Recursively rewrite `Anchor::Point(name)` → `Anchor::WindowEnd` + offset.
/// Returns the rewritten expression and whether any rewrite occurred.
pub fn rewrite_expr_points(expr: &DslExpr, offsets: &HashMap<String, i64>) -> DslExpr {
    match expr {
        DslExpr::Path(path) => {
            if let Anchor::Point(ref name) = path.anchor {
                if let Some(&off) = offsets.get(name.as_str()) {
                    let mut p = path.clone();
                    p.anchor = Anchor::WindowEnd;
                    p.offset = off; // point offset replaces expression offset
                    DslExpr::Path(p)
                } else {
                    expr.clone()
                }
            } else {
                expr.clone()
            }
        }
        DslExpr::Num(_) | DslExpr::Bool(_) | DslExpr::Var(_) => expr.clone(),

        DslExpr::Neg(a) => DslExpr::Neg(Box::new(rewrite_expr_points(a, offsets))),
        DslExpr::Abs(a) => DslExpr::Abs(Box::new(rewrite_expr_points(a, offsets))),
        DslExpr::Not(a) => DslExpr::Not(Box::new(rewrite_expr_points(a, offsets))),

        DslExpr::Add(a, b) => DslExpr::Add(rw(a, offsets), rw(b, offsets)),
        DslExpr::Sub(a, b) => DslExpr::Sub(rw(a, offsets), rw(b, offsets)),
        DslExpr::Mul(a, b) => DslExpr::Mul(rw(a, offsets), rw(b, offsets)),
        DslExpr::Div(a, b) => DslExpr::Div(rw(a, offsets), rw(b, offsets)),
        DslExpr::Gt(a, b) => DslExpr::Gt(rw(a, offsets), rw(b, offsets)),
        DslExpr::Lt(a, b) => DslExpr::Lt(rw(a, offsets), rw(b, offsets)),
        DslExpr::Gte(a, b) => DslExpr::Gte(rw(a, offsets), rw(b, offsets)),
        DslExpr::Lte(a, b) => DslExpr::Lte(rw(a, offsets), rw(b, offsets)),
        DslExpr::Eq(a, b) => DslExpr::Eq(rw(a, offsets), rw(b, offsets)),
        DslExpr::And(a, b) => DslExpr::And(rw(a, offsets), rw(b, offsets)),
        DslExpr::Or(a, b) => DslExpr::Or(rw(a, offsets), rw(b, offsets)),

        DslExpr::Implies { antecedent, consequent } => DslExpr::Implies {
            antecedent: rw(antecedent, offsets),
            consequent: rw(consequent, offsets),
        },
        DslExpr::PctChange { from, to } => DslExpr::PctChange {
            from: rw(from, offsets),
            to: rw(to, offsets),
        },
        DslExpr::Between { val, low, high } => DslExpr::Between {
            val: rw(val, offsets),
            low: rw(low, offsets),
            high: rw(high, offsets),
        },

        DslExpr::All { stock, from, to, pred } => DslExpr::All {
            stock: stock.clone(),
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
            pred: rw(pred, offsets),
        },
        DslExpr::Any { stock, from, to, pred } => DslExpr::Any {
            stock: stock.clone(),
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
            pred: rw(pred, offsets),
        },
        DslExpr::CountBars { from, to, pred, op, n } => DslExpr::CountBars {
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
            pred: rw(pred, offsets),
            op: *op,
            n: *n,
        },
        DslExpr::Agg { stock, from, to, col, func } => DslExpr::Agg {
            stock: stock.clone(),
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
            col: col.clone(),
            func: *func,
        },
        DslExpr::RangeVal { stock, from, to, col, func } => DslExpr::RangeVal {
            stock: stock.clone(),
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
            col: col.clone(),
            func: *func,
        },

        DslExpr::CrossUp { stock, at, col, threshold } => DslExpr::CrossUp {
            stock: stock.clone(),
            at: rewrite_path(at, offsets),
            col: col.clone(),
            threshold: rw(threshold, offsets),
        },
        DslExpr::CrossDown { stock, at, col, threshold } => DslExpr::CrossDown {
            stock: stock.clone(),
            at: rewrite_path(at, offsets),
            col: col.clone(),
            threshold: rw(threshold, offsets),
        },
        DslExpr::CandleIs { stock, at, candle } => DslExpr::CandleIs {
            stock: stock.clone(),
            at: rewrite_path(at, offsets),
            candle: *candle,
        },
        DslExpr::Monotone { stock, from, to, col, dir } => DslExpr::Monotone {
            stock: stock.clone(),
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
            col: col.clone(),
            dir: *dir,
        },
        DslExpr::SyncWithMarket { from, to } => DslExpr::SyncWithMarket {
            from: rewrite_path(from, offsets),
            to: rewrite_path(to, offsets),
        },

        DslExpr::PointExists(_)
        | DslExpr::Intraday(_)
        | DslExpr::IntradayDuration { .. } => expr.clone(),
    }
}

fn rw(e: &DslExpr, offsets: &HashMap<String, i64>) -> Box<DslExpr> {
    Box::new(rewrite_expr_points(e, offsets))
}

fn rewrite_path(p: &kline_dsl::PathExpr, offsets: &HashMap<String, i64>) -> kline_dsl::PathExpr {
    if let Anchor::Point(ref name) = p.anchor {
        if let Some(&off) = offsets.get(name.as_str()) {
            let mut np = p.clone();
            np.anchor = Anchor::WindowEnd;
            np.offset = off;
            return np;
        }
    }
    p.clone()
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use kline_dsl::{AggFunc, Anchor, PathExpr};

    fn make_df(open: &[f64], close: &[f64]) -> DataFrame {
        df!("open" => open.to_vec(), "close" => close.to_vec()).unwrap()
    }

    fn evaluate(expr: &DslExpr, df: &DataFrame) -> Vec<Option<bool>> {
        let compiled = try_compile_condition("test", expr).unwrap();
        let result = df.clone().lazy()
            .with_column(compiled.expr)
            .collect().unwrap();
        let mask = result.column("_c_test").unwrap().bool().unwrap();
        (0..mask.len()).map(|i| mask.get(i)).collect()
    }

    fn p(field: &str, offset: i64) -> DslExpr {
        DslExpr::Path(PathExpr {
            stock: StockId::Current,
            anchor: Anchor::WindowEnd,
            offset,
            field: Some(field.to_string()),
        })
    }

    fn pat() -> PathExpr {
        PathExpr { stock: StockId::Current, anchor: Anchor::WindowEnd, offset: 0, field: None }
    }

    // ── Simple comparisons ────────────────────────────────────────

    #[test]
    fn close_gt_open() {
        let expr = DslExpr::Gt(Box::new(p("close", 0)), Box::new(p("open", 0)));
        let df = make_df(&[10.0, 11.0, 10.0], &[11.0, 10.0, 11.0]);
        assert_eq!(evaluate(&expr, &df), vec![Some(true), Some(false), Some(true)]);
    }

    #[test]
    fn shifted_compare() {
        let expr = DslExpr::Gt(Box::new(p("close", -1)), Box::new(p("close", 0)));
        let df = make_df(&[10.0, 10.0, 10.0], &[11.0, 12.0, 10.0]);
        // Polars shift(1) at row 0 → null; null > anything → null
        assert_eq!(evaluate(&expr, &df), vec![None, Some(false), Some(true)]);
    }

    #[test]
    fn logic_and() {
        let expr = DslExpr::And(
            Box::new(DslExpr::Gt(Box::new(p("close", 0)), Box::new(p("open", 0)))),
            Box::new(DslExpr::Bool(true)),
        );
        let df = make_df(&[10.0, 11.0], &[11.0, 10.0]);
        assert_eq!(evaluate(&expr, &df), vec![Some(true), Some(false)]);
    }

    #[test]
    fn between_expr() {
        let expr = DslExpr::Between {
            val: Box::new(p("close", 0)),
            low: Box::new(DslExpr::Num(10.0)),
            high: Box::new(DslExpr::Num(15.0)),
        };
        let df = make_df(&[10.; 3], &[9.0, 12.0, 16.0]);
        assert_eq!(evaluate(&expr, &df), vec![Some(false), Some(true), Some(false)]);
    }

    // ── Cross ──────────────────────────────────────────────────────

    #[test]
    fn cross_up() {
        let expr = DslExpr::CrossUp {
            stock: StockId::Current, at: pat(), col: "close".into(),
            threshold: Box::new(DslExpr::Num(10.0)),
        };
        let df = make_df(&[10.; 4], &[9.0, 11.0, 10.0, 12.0]);
        let r = evaluate(&expr, &df);
        assert_eq!(r, vec![Some(false), Some(true), Some(false), Some(true)]);
    }

    #[test]
    fn cross_down() {
        let expr = DslExpr::CrossDown {
            stock: StockId::Current, at: pat(), col: "close".into(),
            threshold: Box::new(DslExpr::Num(10.0)),
        };
        let df = make_df(&[10.; 4], &[12.0, 9.0, 11.0, 8.0]);
        assert_eq!(evaluate(&expr, &df), vec![Some(false), Some(true), Some(false), Some(true)]);
    }

    // ── Candle ─────────────────────────────────────────────────────

    #[test]
    fn candle_up() {
        let expr = DslExpr::CandleIs {
            stock: StockId::Current, at: pat(), candle: CandleType::Up,
        };
        let df = make_df(&[10.0, 11.0], &[11.0, 10.0]);
        assert_eq!(evaluate(&expr, &df), vec![Some(true), Some(false)]);
    }

    // ── Rolling aggregation ────────────────────────────────────────

    #[test]
    fn rolling_mean_3() {
        let expr = DslExpr::Agg {
            stock: StockId::Current,
            from: PathExpr { stock: StockId::Current, anchor: Anchor::WindowEnd, offset: -2, field: None },
            to:   PathExpr { stock: StockId::Current, anchor: Anchor::WindowEnd, offset: 0, field: None },
            col: "close".into(), func: AggFunc::Mean,
        };
        let df = make_df(&[10.; 5], &[1.0, 2.0, 3.0, 4.0, 5.0]);
        let compiled = try_compile_condition("m", &expr).unwrap();
        let result = df.clone().lazy().with_column(compiled.expr).collect().unwrap();
        let vals = result.column("_c_m").unwrap().f64().unwrap();
        assert!(vals.get(0).is_none(), "min_periods=3 → row0 should be null");
        assert!(vals.get(1).is_none(), "min_periods=3 → row1 should be null");
        assert!((vals.get(2).unwrap() - 2.0).abs() < 0.01);
        assert!((vals.get(3).unwrap() - 3.0).abs() < 0.01);
        assert!((vals.get(4).unwrap() - 4.0).abs() < 0.01);
    }

    // ── Non-compilable ─────────────────────────────────────────────

    #[test]
    fn point_returns_none() {
        let expr = DslExpr::Path(PathExpr {
            stock: StockId::Current, anchor: Anchor::Point("A".into()),
            offset: 0, field: Some("close".into()),
        });
        assert!(try_compile_condition("x", &expr).is_none());
    }

    #[test]
    fn cross_stock_returns_none() {
        let expr = DslExpr::Path(PathExpr {
            stock: StockId::Named("600000".into()), anchor: Anchor::WindowEnd,
            offset: 0, field: Some("close".into()),
        });
        assert!(try_compile_condition("x", &expr).is_none());
    }

    #[test]
    fn intraday_returns_none() {
        let expr = DslExpr::Intraday(kline_dsl::IntradayCondRef::new(
            "A", "09:30", "10:00", "price_above_avg", Default::default(),
        ));
        assert!(try_compile_condition("x", &expr).is_none());
    }

    // ── Batch ──────────────────────────────────────────────────────

    #[test]
    fn compile_mixed() {
        let conds: Vec<(String, DslExpr)> = vec![
            ("a".into(), DslExpr::Gt(Box::new(p("close", 0)), Box::new(p("open", 0)))),
            ("b".into(), DslExpr::PointExists("A".into())),
            ("c".into(), DslExpr::Gt(Box::new(p("close", 0)), Box::new(DslExpr::Num(5.0)))),
        ];
        let compiled = compile_conditions(&conds);
        assert_eq!(compiled.len(), 2);
        // Sequential indices: only compilable conditions get _c_0, _c_1, ...
        assert_eq!(compiled[0].column_name, "_c_0");
        assert_eq!(compiled[0].condition_name, "a");
        assert_eq!(compiled[1].column_name, "_c_1");
        assert_eq!(compiled[1].condition_name, "c");
    }

    #[test]
    fn compile_all_compilable_sequential() {
        let conds: Vec<(String, DslExpr)> = vec![
            ("x".into(), DslExpr::Gt(Box::new(p("close", 0)), Box::new(p("open", 0)))),
            ("y".into(), DslExpr::Gt(Box::new(p("close", 0)), Box::new(DslExpr::Num(5.0)))),
            ("z".into(), DslExpr::Lt(Box::new(p("close", 0)), Box::new(DslExpr::Num(20.0)))),
        ];
        let compiled = compile_conditions(&conds);
        assert_eq!(compiled.len(), 3);
        assert_eq!(compiled[0].column_name, "_c_0");
        assert_eq!(compiled[0].condition_name, "x");
        assert_eq!(compiled[1].column_name, "_c_1");
        assert_eq!(compiled[1].condition_name, "y");
        assert_eq!(compiled[2].column_name, "_c_2");
        assert_eq!(compiled[2].condition_name, "z");
    }

    #[test]
    fn compile_non_compilable_first() {
        let conds: Vec<(String, DslExpr)> = vec![
            ("a".into(), DslExpr::PointExists("X".into())),
            ("b".into(), DslExpr::Gt(Box::new(p("close", 0)), Box::new(p("open", 0)))),
            ("c".into(), DslExpr::Gt(Box::new(p("close", 0)), Box::new(DslExpr::Num(5.0)))),
        ];
        let compiled = compile_conditions(&conds);
        assert_eq!(compiled.len(), 2);
        assert_eq!(compiled[0].column_name, "_c_0");
        assert_eq!(compiled[0].condition_name, "b");
        assert_eq!(compiled[1].column_name, "_c_1");
        assert_eq!(compiled[1].condition_name, "c");
    }

    #[test]
    fn compile_all_non_compilable() {
        let conds: Vec<(String, DslExpr)> = vec![
            ("a".into(), DslExpr::PointExists("X".into())),
            ("b".into(), DslExpr::Intraday(kline_dsl::IntradayCondRef::new(
                "A", "09:30", "10:00", "x", Default::default(),
            ))),
        ];
        let compiled = compile_conditions(&conds);
        assert_eq!(compiled.len(), 0);
    }
}
