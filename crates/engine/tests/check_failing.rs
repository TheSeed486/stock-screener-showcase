mod common;
use common::*;
use kline_engine::provider::{DataProvider, ParquetDataProvider};
use rusqlite::Connection;

#[test]
fn check_failing_stocks() {
    // 从 stock.db 查这 4 只
    let dir = ParquetDataProvider::new().klines_dir_path().cloned();
    let Some(dir) = dir else { return; };
    let db_path = dir.parent().unwrap().join("stock.db");
    let conn = Connection::open(&db_path).unwrap();

    for code in &["301669", "688635", "920161", "920218"] {
        for (mkt, prefix) in &[(0, "SZ"), (1, "SH"), (2, "BJ")] {
            let mut stmt = conn.prepare(
                "SELECT code, name, security_kind FROM catalog WHERE market=?1 AND code=?2"
            ).unwrap();
            let rows: Vec<_> = stmt.query_map(rusqlite::params![mkt, code], |row| {
                Ok((row.get::<_,String>(0)?, row.get::<_,String>(1)?, row.get::<_,String>(2)?))
            }).unwrap().flatten().collect();
            for (c, n, k) in &rows {
                println!("{prefix}.{c} name={n} kind={k}");
            }
        }
    }

    // 查 parquet 中这些标的的数据量
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(250);
    for code in &["SZ.301669", "SH.688635", "BJ.920161", "BJ.920218"] {
        let df = provider.kline(code, kline_dsl::Timeframe::Daily, from, to).collect().unwrap_or_default();
        println!("{code}: {} rows", df.height());
        if df.height() > 0 {
            let close = kline_engine::extract_f64_col(&df, "close");
            println!("  close has NaN: {}", close.iter().any(|x| x.is_nan()));
            println!("  close[last]={:.4}", close.last().copied().unwrap_or(f64::NAN));
        }
    }
}
