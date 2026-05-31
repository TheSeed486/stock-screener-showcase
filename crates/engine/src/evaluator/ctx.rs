use std::{cell::RefCell, collections::HashMap};

use kline_dsl::mod_def::registry::ModuleRegistry;
use polars::prelude::DataFrame;

use crate::{cache::IntradayCache, extract_f64_col, provider::DataProvider, DateIndex, MatchedWindow};

pub struct EvalCtx<'a> {
    pub df: &'a DataFrame,
    pub dates: &'a DateIndex,
    pub symbol: &'a str,

    pub market_df: Option<&'a DataFrame>,
    pub market_dates: Option<&'a DateIndex>,

    pub extra_dfs: &'a HashMap<String, &'a DataFrame>,
    pub extra_dates: &'a HashMap<String, &'a DateIndex>,

    pub window: &'a MatchedWindow,

    pub resolved_points: HashMap<String, Option<usize>>,
    pub vars: HashMap<String, f64>,

    pub registry: &'a ModuleRegistry,
    pub intraday_cache: &'a RefCell<IntradayCache>,
    pub data_provider: &'a dyn DataProvider,

    /// 预提取的列（延迟缓存，首次访问后 O(1) 数组下标）
    cols: RefCell<HashMap<String, Vec<f64>>>,
}

impl<'a> EvalCtx<'a> {
    pub fn new(
        df: &'a DataFrame,
        dates: &'a DateIndex,
        symbol: &'a str,
        market_df: Option<&'a DataFrame>,
        market_dates: Option<&'a DateIndex>,
        extra_dfs: &'a HashMap<String, &'a DataFrame>,
        extra_dates: &'a HashMap<String, &'a DateIndex>,
        window: &'a MatchedWindow,
        registry: &'a ModuleRegistry,
        intraday_cache: &'a RefCell<IntradayCache>,
        data_provider: &'a dyn DataProvider,
    ) -> Self {
        // 预提取标准列
        let mut cols = HashMap::new();
        for col in &["open", "high", "low", "close", "volume"] {
            cols.insert(col.to_string(), extract_f64_col(df, col));
        }
        EvalCtx {
            df, dates, symbol, market_df, market_dates,
            extra_dfs, extra_dates, window,
            resolved_points: HashMap::new(), vars: HashMap::new(),
            registry, intraday_cache, data_provider,
            cols: RefCell::new(cols),
        }
    }

    /// O(1) 取当前股票 df 指定列的行值
    pub fn val(&self, row: usize, col: &str) -> f64 {
        let mut cache = self.cols.borrow_mut();
        if !cache.contains_key(col) {
            cache.insert(col.to_string(), extract_f64_col(self.df, col));
        }
        cache[col].get(row).copied().unwrap_or(f64::NAN)
    }

    /// 取指定 stock 的列值
    pub fn val_at(&self, row: usize, col: &str, df: &DataFrame) -> f64 {
        let mut cache = self.cols.borrow_mut();
        let key = format!("_{col}"); // 简化：非 Current df 用独立 key
        if !cache.contains_key(&key) {
            cache.insert(key.clone(), extract_f64_col(df, col));
        }
        cache[&key].get(row).copied().unwrap_or(f64::NAN)
    }
}
