pub mod parquet;

use std::collections::HashMap;

use chrono::NaiveDate;
use kline_dsl::Timeframe;
use polars::prelude::{DataFrame, LazyFrame};

pub use parquet::ParquetDataProvider;

pub trait DataProvider: Send + Sync {
    fn kline(&self, symbol: &str, tf: Timeframe, from: NaiveDate, to: NaiveDate) -> LazyFrame;
    fn intraday(&self, symbol: &str, date: NaiveDate) -> LazyFrame;
    fn market_index(&self, symbol: &str) -> String;

    /// 批量加载为 LazyFrame（含 market, code, date），不过滤标的。
    /// 返回 None 表示不支持，调用方回退逐标处理。
    fn load_batch_joined_lf(&self, _symbols: &[String], tf: Timeframe, from: NaiveDate, to: NaiveDate) -> Option<LazyFrame> {
        let _ = (_symbols, tf, from, to);
        None
    }

    fn load_batch(
        &self,
        symbols: &[String],
        tf: Timeframe,
        from: NaiveDate,
        to: NaiveDate,
    ) -> HashMap<String, DataFrame> {
        symbols
            .iter()
            .map(|s| {
                let df = self.kline(s, tf, from, to).collect().unwrap_or_default();
                (s.clone(), df)
            })
            .collect()
    }
}
