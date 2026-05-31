//! 边界情况测试：空数据、偏移越界、停牌等。

mod common;

use common::*;
use kline_dsl::{CandleType, Expr, PathExpr, StockId};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

#[test]
fn test_empty_symbols_vec() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let (from, to) = recent_trade_dates(60);

    let stage = make_stage("daily", vec![("up", compare_expr(close_expr(), CompareOp::Gt, open_expr()))]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();

    let results = run_on_real_data(&pipeline, &registry, &[], from, to);
    assert!(results.is_empty(), "空标的列表应返回空结果");
}

#[test]
fn test_missing_symbol() {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(60);

    // 一个不存在的标的
    let stage = make_stage("daily", vec![("up", compare_expr(close_expr(), CompareOp::Gt, open_expr()))]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();

    let results = run_on_real_data(
        &pipeline,
        &registry,
        &["SZ.999999".to_string()],
        from,
        to,
    );

    // 不应 panic，应返回结果（被淘汰或空数据）
    assert_eq!(results.len(), 1);
    // 未知标的应该被淘汰为 no_data
    assert_failed(&results[0], Some("no_data"));
}

#[test]
fn test_invalid_symbol_format() {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(60);

    // 不是 "XX.YYYYYY" 格式
    let lf = provider.kline("invalid", kline_dsl::Timeframe::Daily, from, to);
    let df = lf.collect().unwrap_or_default();
    assert_eq!(df.height(), 0, "无效格式应返回空 DataFrame");
}

#[test]
fn test_large_offset_boundary() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 5);

    for sym in &sample {
        let (df, name) = load_single_df(sym, 120);
        if df.height() < 10 { continue; }

        // close[-100] 在只有几十行数据时应该安全处理
        let far_past = Expr::Path(PathExpr {
            stock: StockId::Current,
            anchor: kline_dsl::Anchor::WindowEnd,
            offset: -100,
            field: Some("close".to_string()),
        });

        // 不应该 panic
        use kline_engine::evaluator::{ctx::EvalCtx, expr::eval_bool};
        use std::cell::RefCell;
        use kline_engine::DateIndex;

        let dates = kline_engine::extract_dates(&df);
        let date_index = DateIndex::new(dates);
        let n = df.height();
        let window = kline_engine::MatchedWindow {
            global_start: 0,
            global_end: n,
            block_ranges: std::collections::HashMap::new(),
        };

        let cache = RefCell::new(kline_engine::cache::IntradayCache::default());
        let registry = kline_dsl::ModuleRegistry::default();
        let dummy_provider = kline_engine::runner::HashMapProvider::from_data(
            std::collections::HashMap::new(),
        );
        let empty_dfs: std::collections::HashMap<String, &polars::prelude::DataFrame> =
            std::collections::HashMap::new();
        let empty_dates: std::collections::HashMap<String, &DateIndex> =
            std::collections::HashMap::new();

        let mut ctx = EvalCtx::new(
            &df, &date_index, &name,
            None, None,
            &empty_dfs, &empty_dates,
            &window, &registry, &cache,
            &dummy_provider,
        );

        // 对每行求值 close[-100] > 0 — 不应 panic
        for row in 0..n {
            let val = eval_bool(&Expr::Gt(Box::new(far_past.clone()), Box::new(Expr::Num(0.0))), &mut ctx, Some(row));
            // 结果可以是 true/false，没有 panic 就是通过
            let _ = val;
        }
    }
}

fn load_single_df(symbol: &str, n_days: usize) -> (polars::prelude::DataFrame, String) {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(n_days);
    let lf = provider.kline(symbol, kline_dsl::Timeframe::Daily, from, to);
    let df = lf.collect().unwrap_or_default();
    (df, symbol.to_string())
}

#[test]
fn test_empty_pipeline() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 3);
    let (from, to) = recent_trade_dates(60);

    let pipeline = kline_dsl::Pipeline { stages: vec![] };
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    // 空 Pipeline 应该全部通过（无阶段可淘汰）
    for r in &results {
        assert_passed(r);
    }
}

#[test]
fn test_empty_stage() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 3);
    let (from, to) = recent_trade_dates(60);

    // Stage 无条件：应全部通过
    let stage = make_stage("daily", vec![]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    for r in &results {
        assert_passed(r);
    }
}

#[test]
fn test_requested_date_range_has_no_data() {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(60);

    // 请求一个远在未来的日期范围
    let future_from = chrono::NaiveDate::from_ymd_opt(2050, 1, 1).unwrap();
    let future_to = chrono::NaiveDate::from_ymd_opt(2050, 12, 31).unwrap();

    let lf = provider.kline("SZ.000001", kline_dsl::Timeframe::Daily, future_from, future_to);
    let df = lf.collect().unwrap_or_default();
    assert_eq!(df.height(), 0, "未来日期应无数据");
}
