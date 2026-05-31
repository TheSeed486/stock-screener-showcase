mod common;
use common::*;
use kline_dsl::*;
use std::collections::HashMap;
use kline_engine::provider::{DataProvider, ParquetDataProvider};
use kline_engine::runner::run_pipeline;

#[test]
fn verify_batch() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    let sample: Vec<String> = symbols.iter().take(5).map(|(_,_,s)| s.clone()).collect();
    let (from, to) = recent_trade_dates(120);
    let tf = Timeframe::Daily;

    let stage = make_stage_with_indicators("daily",
        vec![IndicatorCall::new("sma", params!{"period"=>5_i64})],
        vec![("above_sma5", compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0)))],
    );
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();
    let results = run_pipeline(&pipeline, &registry, &provider, &sample, from, to);

    for r in &results {
        let df = provider.kline(&r.symbol, tf, from, to).collect().unwrap_or_default();
        let close = kline_engine::extract_f64_col(&df, "close");
        let last = close.len().saturating_sub(1);
        let sma5: f64 = if last >= 4 { close[last-4..=last].iter().sum::<f64>() / 5.0 } else { f64::NAN };
        let manual = close[last] > sma5;
        println!("[{}] DSL={} manual={}", r.symbol, r.eliminated_at.is_none(), manual);
    }
}
