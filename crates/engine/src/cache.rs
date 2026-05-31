use std::collections::HashMap;

use chrono::NaiveDate;
use polars::prelude::DataFrame;

use crate::provider::DataProvider;

/// 分时缓存：key = (symbol, date)，整天加载，Stage 执行期间保持内存
/// Stage 结束后整个 cache drop，不跨 Stage 持久
#[derive(Default)]
pub struct IntradayCache {
    inner: HashMap<(String, NaiveDate), DataFrame>,
}

impl IntradayCache {
    /// 若已缓存直接返回引用；否则整天加载后缓存
    pub fn get_or_load(
        &mut self,
        symbol: &str,
        date: NaiveDate,
        provider: &dyn DataProvider,
    ) -> &DataFrame {
        self.inner
            .entry((symbol.to_string(), date))
            .or_insert_with(|| {
                provider
                    .intraday(symbol, date)
                    .collect()
                    .unwrap_or_else(|e| {
                        eprintln!("[intraday] load failed {symbol} {date}: {e}");
                        DataFrame::empty()
                    })
            })
    }

    pub fn clear(&mut self) {
        self.inner.clear();
    }
}
