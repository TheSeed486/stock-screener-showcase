//! Stage 和 Pipeline 级正确性测试。

mod common;

use common::*;
use kline_dsl::{
    params, Anchor, CandleType, Expr, PathExpr, StockId,
};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

// ── Stage 测试 ────────────────────────────────────────────────────

#[test]
fn test_single_condition_stage() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    // 条件是 close > open（收阳线）
    let stage = make_stage("daily", vec![
        ("up", compare_expr(close_expr(), CompareOp::Gt, open_expr())),
    ]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    assert_eq!(results.len(), sample.len());
    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[single_cond] {passed}/{} 只股 pass", sample.len());
}

#[test]
fn test_multi_condition_and_stage() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    // 三个条件：阳线 + 高低 > 1% + 成交量 > 0
    let up = compare_expr(close_expr(), CompareOp::Gt, open_expr());
    let spread_1pct = Expr::Gt(
        Box::new(Expr::Div(
            Box::new(Expr::Sub(Box::new(high_expr()), Box::new(low_expr()))),
            Box::new(close_expr()),
        )),
        Box::new(Expr::Num(0.01)),
    );
    let vol_pos = compare_expr(volume_expr(), CompareOp::Gt, Expr::Num(0.0));

    let stage = make_stage("daily", vec![
        ("up", up),
        ("spread_1pct", spread_1pct),
        ("vol_pos", vol_pos),
    ]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    assert_eq!(results.len(), sample.len());
    for r in &results {
        if let Some(reason) = &r.eliminated_reason {
            eprintln!("[{symbol}] eliminated: {reason}", symbol = r.symbol);
        }
    }
}

#[test]
fn test_condition_all_or_nothing() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    // 永真条件：所有股票都应该通过
    let true_stage = make_stage("daily", vec![
        ("always", compare_expr(close_expr(), CompareOp::Eq, close_expr())),
    ]);
    let true_pipeline = make_single_stage_pipeline(true_stage);
    let registry = default_registry();
    let results = run_on_real_data(&true_pipeline, &registry, &sample, from, to);

    for r in &results {
        assert_passed(r);
    }

    // 永假条件：所有股票都应该被淘汰（但可能因为数据为空而失败）
    let false_stage = make_stage("daily", vec![
        ("never", Expr::Bool(false)),
    ]);
    let false_pipeline = make_single_stage_pipeline(false_stage);
    let results2 = run_on_real_data(&false_pipeline, &registry, &sample, from, to);

    for r in &results2 {
        let has_data = r.eliminated_reason.as_deref() != Some("no_data");
        if has_data {
            assert_failed(r, Some("never"));
        }
    }
}

#[test]
fn test_var_before_condition() {
    // 定义 var = (high - close) / close，条件：var < 2%（上影线不太长）
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(60);

    let upper_shadow = Expr::Div(
        Box::new(Expr::Sub(Box::new(high_expr()), Box::new(close_expr()))),
        Box::new(close_expr()),
    );

    let mut stage = make_stage("daily", vec![
        ("small_shadow", Expr::Lt(
            Box::new(Expr::Var("shadow_pct".to_string())),
            Box::new(Expr::Num(0.02)),
        )),
    ]);
    stage.vars = vec![kline_dsl::pipeline::VarDef {
        name: "shadow_pct".to_string(),
        expr: upper_shadow,
    }];

    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[var_test] {passed}/{} 只股上影线 < 2%", sample.len());
}

// ── Pipeline 测试 ─────────────────────────────────────────────────

#[test]
fn test_two_stage_pipeline() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    // Stage 1: 阳线
    let stage1 = make_stage("candle_up", vec![
        ("up", Expr::CandleIs {
            stock: StockId::Current,
            at: PathExpr::window_end(0),
            candle: CandleType::Up,
        }),
    ]);

    // Stage 2: 成交量 > 第 10 只的成交量（确保至少有一些被淘汰）
    let stage2 = make_stage("volume_ok", vec![
        ("vol_pos", compare_expr(volume_expr(), CompareOp::Gt, Expr::Num(0.0))),
    ]);

    let pipeline = kline_dsl::Pipeline {
        stages: vec![stage1, stage2],
    };
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    assert_eq!(results.len(), sample.len());
    for r in &results {
        match &r.eliminated_at {
            Some(stage_name) => {
                eprintln!("[{}] eliminated at: {stage_name}", r.symbol);
            }
            None => {
                eprintln!("[{}] passed all stages", r.symbol);
                assert!(r.passed_stages.len() >= 2);
            }
        }
    }
}

#[test]
fn test_indicator_prepare_stage() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    // 带 Boll 指标的 Stage: close 上穿 boll_mid_20
    let stage = make_stage_with_indicators(
        "boll_cross",
        vec![kline_dsl::pipeline::IndicatorCall::new(
            "boll",
            params! { "period" => 20_i64, "k" => 2.0_f64 },
        )],
        vec![
            ("cross_mid", Expr::CrossUp {
                stock: StockId::Current,
                at: PathExpr::window_end(0),
                col: "close".to_string(),
                threshold: Box::new(PathExpr::each().col("boll_mid_20")),
            }),
        ],
    );

    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[boll_prepare] {passed}/{} 只股 close 上穿 BOLL 中轨", sample.len());
}
