mod common;
use common::*;
use kline_dsl::*;
use kline_engine::provider::{DataProvider, ParquetDataProvider};
use kline_engine::runner::run_pipeline;

#[test]
fn isolated_debug() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    let all: Vec<String> = symbols.iter().map(|(_,_,s)| s.clone()).collect();
    let (from, to) = recent_trade_dates(250);
    let pipeline = Pipeline { stages: vec![
        make_stage_with_indicators("daily",
            vec![IndicatorCall::new("sma", params!{"period"=>5_i64})],
            vec![("above_sma5", compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0)))],
        ),
    ]};
    let registry = default_registry();

    for &n in &[5, 50, 500, 5525] {
        let batch_syms: Vec<String> = all.iter().take(n).cloned().collect();
        let results = run_pipeline(&pipeline, &registry, &provider, &batch_syms, from, to);
        let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
        let first = results.first().unwrap();
        println!("n={n}: passed={passed}  first=({} passed={} reason={:?})",
            first.symbol, first.eliminated_at.is_none(), first.eliminated_reason);
    }
}
