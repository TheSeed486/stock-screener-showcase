//! 手动可验证的 DSL 执行详情
mod common;
use common::*;
use kline_dsl::params;
use kline_engine::provider::{DataProvider, ParquetDataProvider};

#[test]
fn dump_dsl_and_data() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }

    for &sym in &["SZ.300702", "SZ.300107"] {
        let (from, to) = recent_trade_dates(60);
        let lf = provider.kline(sym, kline_dsl::Timeframe::Daily, from, to);
        let df = lf.collect().unwrap_or_default();
        let n = df.height();
        let close = kline_engine::extract_f64_col(&df, "close");
        let dates = kline_engine::extract_dates(&df);
        let last = n - 1;

        // 手算最近 5 日 SMA
        let sma5_raw: f64 = close[last - 4..=last].iter().sum::<f64>() / 5.0;

        println!("=== {sym} ===");
        println!("DSL: Stage {{ prepare=[sma(period=5)], conditions=[close > sma_5] }}");
        println!();
        println!("最近 5 日收盘价 (SMA5 输入):");
        for i in last - 4..=last {
            println!("  {}  close={:.4}", dates[i], close[i]);
        }
        println!("  SMA(5) = {:.4}", sma5_raw);
        println!("  close[{}]({}) = {:.4}", dates[last], dates[last], close[last]);
        println!("  close > SMA(5) ?  {:.4} > {:.4} = {}", close[last], sma5_raw, close[last] > sma5_raw);

        // DSL 结果
        let stage = make_stage_with_indicators(
            "daily",
            vec![kline_dsl::pipeline::IndicatorCall::new(
                "sma", params! { "period" => 5_i64 },
            )],
            vec![("above_sma5", compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0)))],
        );
        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let results = run_on_real_data(&pipeline, &registry, &[sym.to_string()], dates[0], dates[last]);
        let dsl_passed = results[0].eliminated_at.is_none();
        println!("  DSL 结果: {}", if dsl_passed { "PASS" } else { "FAIL" });
        println!();
    }
}
