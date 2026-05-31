//! 表达式级正确性测试：逐项验证每种 Expr 变体在真实 K 线数据上的行为。
//!
//! 验证策略：
//!   - 对可编译的表达式：编译路径与解释路径结果交叉验证
//!   - 对不可编译的表达式：验证解释路径结果的一致性与逻辑合理性

mod common;

use common::*;
use kline_dsl::{
    Anchor, CandleType, Expr, PathExpr, StockId,
};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

/// 加载一个单标的 K 线 DataFrame（日线，最近 n 天）。
fn load_single_df(symbol: &str, n_days: usize) -> (polars::prelude::DataFrame, String) {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(n_days);
    let lf = provider.kline(symbol, kline_dsl::Timeframe::Daily, from, to);
    let df = lf.collect().unwrap_or_default();
    (df, symbol.to_string())
}

/// 对一组表达式做交叉验证（编译 vs 解释）。
fn cross_validate_all(exprs: &[(String, Expr)], df: &polars::prelude::DataFrame, symbol: &str) {
    for (name, expr) in exprs {
        cross_validate_expr(expr, df, symbol);
    }
}

// ── 比较运算 ──────────────────────────────────────────────────────

#[test]
fn test_literal_comparison() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 3);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 60);
        if df.height() < 5 { continue; }

        let exprs = vec![
            ("close_gt_open".to_string(), compare_expr(close_expr(), CompareOp::Gt, open_expr())),
            ("close_lt_open".to_string(), compare_expr(close_expr(), CompareOp::Lt, open_expr())),
            ("close_gte_close".to_string(), compare_expr(close_expr(), CompareOp::Gte, close_expr())),
            ("close_lte_high".to_string(), compare_expr(close_expr(), CompareOp::Lte, high_expr())),
            ("close_eq_close".to_string(), compare_expr(close_expr(), CompareOp::Eq, close_expr())),
        ];
        cross_validate_all(&exprs, &df, &name);
    }
}

// ── 算术运算 ──────────────────────────────────────────────────────

#[test]
fn test_arithmetic_operations() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 3);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 60);
        if df.height() < 5 { continue; }

        // (high - low) / close 应 ≥ 0
        let spread = Expr::Div(
            Box::new(Expr::Sub(Box::new(high_expr()), Box::new(low_expr()))),
            Box::new(close_expr()),
        );
        // abs(close - open)
        let abs_diff = Expr::Abs(Box::new(Expr::Sub(Box::new(close_expr()), Box::new(open_expr()))));
        // -close
        let neg_close = Expr::Neg(Box::new(close_expr()));

        let exprs = vec![
            ("spread".to_string(), spread),
            ("abs_diff".to_string(), abs_diff),
        ];
        cross_validate_all(&exprs, &df, &name);

        // neg_close 可能是不可编译的（Neg 可能不被编译器支持），用解释路径验证
        // 至少在解释路径下应正确求值
    }
}

// ── 布尔逻辑 ──────────────────────────────────────────────────────

#[test]
fn test_boolean_logic() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 3);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 60);
        if df.height() < 5 { continue; }

        let up = compare_expr(close_expr(), CompareOp::Gt, open_expr());
        let pos = compare_expr(close_expr(), CompareOp::Gt, Expr::Num(0.0));

        let exprs = vec![
            ("up_and_pos".to_string(), Expr::And(Box::new(up.clone()), Box::new(pos.clone()))),
            ("up_or_pos".to_string(), Expr::Or(Box::new(up.clone()), Box::new(pos.clone()))),
            ("not_up".to_string(), Expr::Not(Box::new(up.clone()))),
        ];
        cross_validate_all(&exprs, &df, &name);
    }
}

// ── 路径偏移引用 ──────────────────────────────────────────────────

#[test]
fn test_path_offset_reference() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 3);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 60);
        if df.height() < 5 { continue; }

        // close[1] > close[0] — 与前一日比上涨
        let close_prev = Expr::Path(PathExpr {
            stock: StockId::Current,
            anchor: Anchor::WindowEnd,
            offset: -1,
            field: Some("close".to_string()),
        });
        let rising = Expr::Gt(Box::new(close_expr()), Box::new(close_prev));

        let exprs = vec![
            ("rising".to_string(), rising),
        ];
        cross_validate_all(&exprs, &df, &name);
    }
}

#[test]
fn test_candle_check() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);

    let stage = make_stage("daily", vec![
        ("candle_up", Expr::CandleIs {
            stock: StockId::Current,
            at: PathExpr::window_end(0),
            candle: CandleType::Up,
        }),
    ]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let (from, to) = recent_trade_dates(120);
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    assert_eq!(results.len(), sample.len());
    // 至少应有部分股有阳线（极大概率）
    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[candle_check] {passed}/{} 只股最近有阳线", sample.len());
    assert!(passed > 0, "至少应有 1 只股最近有阳线");

    // 也测试阴线
    let stage2 = make_stage("daily", vec![
        ("candle_down", Expr::CandleIs {
            stock: StockId::Current,
            at: PathExpr::window_end(0),
            candle: CandleType::Down,
        }),
    ]);
    let pipeline2 = make_single_stage_pipeline(stage2);
    let results2 = run_on_real_data(&pipeline2, &registry, &sample, from, to);
    let passed2 = results2.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[candle_check] {passed2}/{} 只股最近有阴线", sample.len());
}

// ── 穿越检测 ─────────────────────────────────────────────────────

#[test]
fn test_cross_detection() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(250);

    // close 穿越 MA(close, 5) 向上
    let stage = make_stage_with_indicators(
        "daily",
        vec![kline_dsl::pipeline::IndicatorCall::new(
            "sma",
            kline_dsl::params! { "period" => 5_i64 },
        )],
        vec![
            ("cross_up_sma5", Expr::CrossUp {
                stock: StockId::Current,
                at: PathExpr::window_end(0),
                col: "close".to_string(),
                threshold: Box::new(PathExpr::each().col("sma_5")),
            }),
        ],
    );
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[cross] {passed}/{} 只股 close 上穿 MA5", sample.len());
}

// ── 范围聚合 ──────────────────────────────────────────────────────

#[test]
fn test_range_aggregation() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 5);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 120);
        if df.height() < 10 { continue; }

        // max(high, 5) > min(low, 5) — 5 日最高应该 > 5 日最低
        let max_high_5 = Expr::Agg {
            stock: StockId::Current,
            from: PathExpr { stock: StockId::Current, anchor: Anchor::WindowEnd, offset: -4, field: None },
            to: PathExpr::window_end(0),
            col: "high".to_string(),
            func: kline_dsl::AggFunc::Max,
        };
        let min_low_5 = Expr::Agg {
            stock: StockId::Current,
            from: PathExpr { stock: StockId::Current, anchor: Anchor::WindowEnd, offset: -4, field: None },
            to: PathExpr::window_end(0),
            col: "low".to_string(),
            func: kline_dsl::AggFunc::Min,
        };
        let spread_ok = Expr::Gt(Box::new(max_high_5), Box::new(min_low_5));

        cross_validate_expr(&spread_ok, &df, &name);
    }
}

// ── 涨跌幅 ────────────────────────────────────────────────────────

#[test]
fn test_pct_change() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 5);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 120);
        if df.height() < 10 { continue; }

        // pct_change from prev close: (close - close[-1]) / close[-1] * 100 > 5
        let prev_close = Expr::Path(PathExpr {
            stock: StockId::Current,
            anchor: Anchor::WindowEnd,
            offset: -1,
            field: Some("close".to_string()),
        });
        let big_up = Expr::Gt(
            Box::new(Expr::PctChange {
                from: Box::new(prev_close),
                to: Box::new(close_expr()),
            }),
            Box::new(Expr::Num(5.0)),
        );
        cross_validate_expr(&big_up, &df, &name);
    }
}

// ── 区间取值 Between ─────────────────────────────────────────────

#[test]
fn test_between_expr() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 5);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 60);
        if df.height() < 5 { continue; }

        // close between open and high
        let between_oh = Expr::Between {
            val: Box::new(close_expr()),
            low: Box::new(open_expr()),
            high: Box::new(high_expr()),
        };
        cross_validate_expr(&between_oh, &df, &name);
    }
}
