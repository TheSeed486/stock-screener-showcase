mod common;
use common::*;
use kline_dsl::*;
use kline_engine::provider::{DataProvider, ParquetDataProvider};
use polars::prelude::*;

#[test]
fn check_market_join() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let (from, to) = recent_trade_dates(30);
    let mut syms = vec!["SZ.000001".to_string(), "SH.600000".to_string()];
    syms.extend(["SH.000001", "SZ.399001"].iter().map(|s| s.to_string()));

    let lf = DataProvider::load_batch_joined_lf(&provider, &syms, Timeframe::Daily, from, to).unwrap();
    let collected = lf.collect().unwrap();
    println!("total rows: {}", collected.height());
    println!("cols: {:?}", collected.get_column_names());

    // Check market index rows
    let market_ca = collected.column("market").unwrap().i32().unwrap();
    let code_ca = collected.column("code").unwrap().i32().unwrap();
    let close_ca = collected.column("close").unwrap().f64().unwrap();
    let date_ca = collected.column("date").unwrap().str().unwrap();
    for i in 0..collected.height().min(10) {
        let m = market_ca.get(i).unwrap_or(-1);
        let c = code_ca.get(i).unwrap_or(-1);
        let prefix = match m { 0=>"SZ", 1=>"SH", _=>"??" };
        let date = date_ca.get(i).unwrap_or("?");
        println!("  [{i}] {prefix}.{c:06} date={date} close={:.4}", close_ca.get(i).unwrap_or(f64::NAN));
    }
}
