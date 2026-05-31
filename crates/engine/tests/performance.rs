//! 性能基准测试（默认 #[ignore]，通过 --ignored 运行）。
//! 运行时建议设置 RUST_MIN_STACK=8388608（8MB）以免栈溢出。

mod common;

use common::*;
use std::time::Instant;
use kline_dsl::{Expr, PathExpr};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

#[test]
#[ignore]
fn bench_scan_simple_condition() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let (from, to) = recent_trade_dates(250);

    let sample_sizes = [30, 100, 300];
    for &n in &sample_sizes {
        let sample = sample_symbols(&symbols, n);
        let stage = make_stage_with_indicators(
            "daily",
            vec![kline_dsl::pipeline::IndicatorCall::new(
                "sma",
                kline_dsl::params! { "period" => 5_i64 },
            )],
            vec![(
                "above_ma5",
                compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0)),
            )],
        );

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();

        let start = Instant::now();
        let results = run_on_real_data(&pipeline, &registry, &sample, from, to);
        let elapsed = start.elapsed();

        let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
        println!(
            "[bench_simple] n={n}: {elapsed:.2?}, {passed} passed ({:.1}/s)",
            (passed as f64) / elapsed.as_secs_f64().max(0.001)
        );
    }
}

#[test]
#[ignore]
fn bench_batch_vs_individual_load() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 50);
    let (from, to) = recent_trade_dates(120);

    // Individual loads
    let start = Instant::now();
    for sym in &sample {
        let lf = provider.kline(sym, kline_dsl::Timeframe::Daily, from, to);
        let _ = lf.collect();
    }
    let individual_time = start.elapsed();

    // Batch load
    let start = Instant::now();
    let batch = provider.load_batch(&sample, kline_dsl::Timeframe::Daily, from, to);
    let batch_time = start.elapsed();

    println!(
        "[bench_load] individual={individual_time:.2?} batch={batch_time:.2?} \
         speedup={:.1}x symbols={} frames={}",
        individual_time.as_secs_f64() / batch_time.as_secs_f64().max(0.001),
        sample.len(),
        batch.len()
    );
    assert!(!batch.is_empty());
}

#[test]
#[ignore]
fn bench_multi_stage_pipeline() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    // 多阶段 + Polars 形态匹配消耗大量栈，减小到 30 只
    let sample = sample_symbols(&symbols, 30);
    let (from, to) = recent_trade_dates(120);

    let stage1 = make_stage("s1_candle", vec![
        ("up", Expr::CandleIs {
            stock: kline_dsl::StockId::Current,
            at: kline_dsl::PathExpr::window_end(0),
            candle: kline_dsl::CandleType::Up,
        }),
    ]);
    let stage2 = make_stage("s2_volume", vec![
        ("vol_gt_0", compare_expr(volume_expr(), CompareOp::Gt, Expr::Num(0.0))),
    ]);
    let stage3 = make_stage("s3_spread", vec![
        ("spread_gt_0", compare_expr(high_expr(), CompareOp::Gt, low_expr())),
    ]);

    let pipeline = kline_dsl::Pipeline {
        stages: vec![stage1, stage2, stage3],
    };
    let registry = default_registry();

    let start = Instant::now();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);
    let elapsed = start.elapsed();

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    println!(
        "[bench_multi_stage] n={}: {elapsed:.2?}, {passed} passed all 3 stages, \
         avg={:.2?}/symbol",
        sample.len(),
        elapsed / sample.len() as u32
    );
}

#[test]
#[ignore]
fn bench_indicator_compute() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 30);
    let (from, to) = recent_trade_dates(250);

    let stage = make_stage_with_indicators(
        "boll",
        vec![kline_dsl::pipeline::IndicatorCall::new(
            "boll",
            kline_dsl::params! { "period" => 20_i64, "k" => 2.0_f64 },
        )],
        vec![(
            "above_mid",
            compare_expr(close_expr(), CompareOp::Gt, col_expr("boll_mid_20", 0)),
        )],
    );

    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();

    let start = Instant::now();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);
    let elapsed = start.elapsed();

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    println!(
        "[bench_indicator] n={}: {elapsed:.2?}, {passed} passed, \
         avg={:.2?}/symbol",
        sample.len(),
        elapsed / sample.len() as u32
    );
}
