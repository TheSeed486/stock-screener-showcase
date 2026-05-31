//! ParquetDataProvider — 从 .stock_storage/klines/ Parquet 文件读取 K 线数据。
//!
//! Parquet 中存储的 schema：
//!   market: i32, code: i32, date: i32 (epoch days),
//!   open: i32, high: i32, low: i32, close: i32 (×10000),
//!   volume: i64, amount: i64 (×10000)
//!
//! 通过 Polars 向量化表达式转换为 engine 期望的格式：
//!   date: String ("YYYY-MM-DD"), open: f64, high: f64, low: f64,
//!   close: f64, volume: f64, amount: f64

use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;

use chrono::{Datelike, NaiveDate};
use kline_dsl::Timeframe;
use polars::prelude::*;

use super::DataProvider;

const KLINE_PRICE_SCALE: f64 = 10000.0;
const KLINES_DIR: &str = "klines";

// ── Path helpers ──────────────────────────────────────────────────

fn storage_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("STOCK_DB_DIR") {
        return Some(PathBuf::from(dir));
    }
    if let Ok(exe_path) = std::env::current_exe() {
        if let Some(dir) = workspace_storage_dir_from_exe(&exe_path) {
            return Some(dir);
        }
    }
    #[cfg(target_os = "windows")]
    {
        if let Some(local) = std::env::var_os("LOCALAPPDATA") {
            return Some(PathBuf::from(local).join(".stock_storage"));
        }
    }
    None
}

fn workspace_storage_dir_from_exe(exe_path: &std::path::Path) -> Option<PathBuf> {
    let exe_dir = exe_path.parent()?;
    let root = exe_dir.ancestors().find(|c| {
        c.join("pubspec.yaml").is_file() && c.join("rust").join("Cargo.toml").is_file()
    })?;
    Some(root.join(".stock_storage"))
}

fn klines_dir() -> Option<PathBuf> {
    storage_dir().map(|d| d.join(KLINES_DIR)).filter(|d| d.exists())
}

fn year_parquet_path(dir: &std::path::Path, year: i32) -> PathBuf {
    dir.join(format!("{year}.parquet"))
}

// ── Symbol parsing ─────────────────────────────────────────────────

fn parse_symbol(symbol: &str) -> Option<(i32, i32)> {
    let (market_str, code_str) = symbol.split_once('.')?;
    let market = match market_str {
        "SZ" => 0i32,
        "SH" => 1i32,
        "BJ" => 2i32,
        _ => return None,
    };
    let code: i32 = code_str.parse().ok()?;
    Some((market, code))
}

fn format_symbol_key(market: i32, code: i32) -> String {
    let prefix = match market {
        0 => "SZ",
        1 => "SH",
        2 => "BJ",
        _ => "??",
    };
    format!("{prefix}.{code:06}")
}

fn naive_date_to_epoch_days(date: NaiveDate) -> i32 {
    let epoch = NaiveDate::from_ymd_opt(1970, 1, 1).unwrap();
    (date - epoch).num_days() as i32
}

// ── 向量化列转换（Polars LazyFrame 表达式，零额外 collect）─────

/// 将原始 parquet LazyFrame 添加转换列（向量化），返回仍为 LazyFrame。
/// 转换仅在 engine 调用 `.collect()` 时执行一次。
fn parse_symbol_parts(sym: &str) -> Option<(i32, i32)> {
    let (mkt_str, code_str) = sym.split_once('.')?;
    let mkt = match mkt_str { "SZ" => 0i32, "SH" => 1, "BJ" => 2, _ => return None };
    let code: i32 = code_str.parse().ok()?;
    Some((mkt, code))
}

fn with_parquet_column_transforms(lf: LazyFrame) -> LazyFrame {
    // date: Date type (migrated from epoch days i32)
    lf.with_columns([
        col("date").cast(DataType::Datetime(TimeUnit::Milliseconds, None))
            .dt().to_string("%Y-%m-%d").alias("date_str"),
        // prices: scaled i32 → f64
        (col("open").cast(DataType::Float64) / lit(KLINE_PRICE_SCALE)).alias("open_f64"),
        (col("high").cast(DataType::Float64) / lit(KLINE_PRICE_SCALE)).alias("high_f64"),
        (col("low").cast(DataType::Float64) / lit(KLINE_PRICE_SCALE)).alias("low_f64"),
        (col("close").cast(DataType::Float64) / lit(KLINE_PRICE_SCALE)).alias("close_f64"),
        col("volume").cast(DataType::Float64).alias("volume_f64"),
        (col("amount").cast(DataType::Float64) / lit(KLINE_PRICE_SCALE)).alias("amount_f64"),
    ])
    .select([
        col("market"),
        col("code"),
        col("date_str").alias("date"),
        col("open_f64").alias("open"),
        col("high_f64").alias("high"),
        col("low_f64").alias("low"),
        col("close_f64").alias("close"),
        col("volume_f64").alias("volume"),
        col("amount_f64").alias("amount"),
    ])
}

// ── ParquetDataProvider ────────────────────────────────────────────

pub struct ParquetDataProvider {
    klines_dir: Option<PathBuf>,
}

impl ParquetDataProvider {
    pub fn new() -> Self {
        let dir = klines_dir();
        if dir.is_none() {
            eprintln!(
                "[ParquetDataProvider] .stock_storage/klines/ 未找到。\
                 请设置 STOCK_DB_DIR 或确保项目根目录存在 .stock_storage。"
            );
        }
        Self { klines_dir: dir }
    }

    pub fn with_dir(dir: PathBuf) -> Self {
        let klines = dir.join(KLINES_DIR);
        if !klines.exists() {
            eprintln!("[ParquetDataProvider] 指定目录下无 klines 子目录: {}", klines.display());
            return Self { klines_dir: None };
        }
        Self { klines_dir: Some(klines) }
    }

    pub fn is_available(&self) -> bool {
        self.klines_dir.is_some()
    }

    pub fn klines_dir_path(&self) -> Option<&PathBuf> {
        self.klines_dir.as_ref()
    }

    pub fn available_years(&self) -> Vec<i32> {
        let Some(ref dir) = self.klines_dir else { return Vec::new(); };
        let mut years: Vec<i32> = Vec::new();
        if let Ok(entries) = fs::read_dir(dir) {
            for entry in entries.flatten() {
                let name = entry.file_name();
                let name = name.to_string_lossy();
                if let Some(year) = name.strip_suffix(".parquet").and_then(|s| s.parse::<i32>().ok()) {
                    years.push(year);
                }
            }
        }
        years.sort_unstable();
        years
    }

    /// 扫描单标的 parquet → 过滤 → 向量化转换 → 返回纯 LazyFrame（无提前 collect）。
    fn scan_single_lf(&self, market: i32, code: i32, from: NaiveDate, to: NaiveDate) -> LazyFrame {
        let Some(ref dir) = self.klines_dir else { return empty_lazy_frame(); };

        let start_year = from.year();
        let end_year = to.year();
        let args = ScanArgsParquet::default();
        let from_days = naive_date_to_epoch_days(from);
        let to_days = naive_date_to_epoch_days(to);

        let mut lfs: Vec<LazyFrame> = Vec::new();
        for year in start_year..=end_year {
            let path = year_parquet_path(dir, year);
            if !path.exists() { continue; }
            let path_str = path.to_string_lossy().to_string();
            let Ok(lf) = LazyFrame::scan_parquet(path_str.as_str().into(), args.clone()) else {
                continue;
            };
            lfs.push(
                lf.filter(col("market").eq(lit(market)))
                    .filter(col("code").eq(lit(code)))
                    .filter(col("date").gt_eq(lit(from_days)))
                    .filter(col("date").lt_eq(lit(to_days))),
            );
        }

        if lfs.is_empty() {
            return empty_lazy_frame();
        }

        let combined = concat_lfs(lfs);
        with_parquet_column_transforms(combined)
    }

    /// 批量加载，返回 LazyFrame（含 market, code, date 列，不过滤标的）。
    /// 调用方加指标+条件后 group_by 一键求值，全程 lazy 到最后 collect。
    pub fn load_batch_joined_lf(
        &self,
        tf: Timeframe,
        from: NaiveDate,
        to: NaiveDate,
    ) -> LazyFrame {
        if !matches!(tf, Timeframe::Daily) || self.klines_dir.is_none() { return empty_lazy_frame(); }
        let dir = self.klines_dir.as_ref().unwrap();
        let start_year = from.year();
        let end_year = to.year();
        let args = ScanArgsParquet::default();
        let from_days = naive_date_to_epoch_days(from);
        let to_days = naive_date_to_epoch_days(to);

        let mut lfs: Vec<LazyFrame> = Vec::new();
        for year in start_year..=end_year {
            let path = year_parquet_path(dir, year);
            if !path.exists() { continue; }
            let path_str = path.to_string_lossy().to_string();
            let Ok(lf) = LazyFrame::scan_parquet(path_str.as_str().into(), args.clone()) else { continue; };
            lfs.push(
                lf.filter(col("date").gt_eq(lit(from_days)))
                    .filter(col("date").lt_eq(lit(to_days))),
            );
        }
        if lfs.is_empty() { return empty_lazy_frame(); }
        // Sort while date is still epoch days (i32), before transform converts it to string
        let sorted = concat_lfs(lfs).sort(
            ["market", "code", "date"],
            SortMultipleOptions::default(),
        );
        with_parquet_column_transforms(sorted)
    }

    fn load_batch_internal(
        &self,
        symbols: &[(i32, i32)],
        from: NaiveDate,
        to: NaiveDate,
    ) -> HashMap<String, DataFrame> {
        if symbols.is_empty() {
            return HashMap::new();
        }

        let Some(ref dir) = self.klines_dir else {
            return symbols.iter().map(|&(m, c)| (format_symbol_key(m, c), DataFrame::default())).collect();
        };

        let start_year = from.year();
        let end_year = to.year();
        let args = ScanArgsParquet::default();
        let from_days = naive_date_to_epoch_days(from);
        let to_days = naive_date_to_epoch_days(to);

        // 只按日期过滤，不做符号过滤（避免 OR 链过深）
        // 后续按 symbol split 时只取需要的标的
        let query_set: HashMap<(i32, i32), String> = symbols
            .iter()
            .map(|&(m, c)| ((m, c), format_symbol_key(m, c)))
            .collect();

        // 扫描所有年份，仅按日期过滤
        let mut lfs: Vec<LazyFrame> = Vec::new();
        for year in start_year..=end_year {
            let path = year_parquet_path(dir, year);
            if !path.exists() { continue; }
            let path_str = path.to_string_lossy().to_string();
            let Ok(lf) = LazyFrame::scan_parquet(path_str.as_str().into(), args.clone()) else {
                continue;
            };
            lfs.push(
                lf.filter(col("date").gt_eq(lit(from_days)))
                    .filter(col("date").lt_eq(lit(to_days))),
            );
        }

        if lfs.is_empty() {
            return symbols.iter().map(|&(m, c)| (format_symbol_key(m, c), DataFrame::default())).collect();
        }

        let combined = with_parquet_column_transforms(concat_lfs(lfs));
        let Ok(df) = combined.collect() else {
            return symbols.iter().map(|&(m, c)| (format_symbol_key(m, c), DataFrame::default())).collect();
        };

        // 按 (market, code) 分组拆分（用 take 保证正确性）
        let market_ca = match df.column("market").ok().and_then(|s| s.i32().ok()) {
            Some(ca) => ca,
            None => return symbols.iter().map(|&(m, c)| (format_symbol_key(m, c), DataFrame::default())).collect(),
        };
        let code_ca = match df.column("code").ok().and_then(|s| s.i32().ok()) {
            Some(ca) => ca,
            None => return symbols.iter().map(|&(m, c)| (format_symbol_key(m, c), DataFrame::default())).collect(),
        };

        let mut groups: HashMap<(i32, i32), Vec<usize>> = HashMap::new();
        for i in 0..df.height() {
            let m = market_ca.get(i).unwrap_or(-1);
            let c = code_ca.get(i).unwrap_or(-1);
            if query_set.contains_key(&(m, c)) {
                groups.entry((m, c)).or_default().push(i);
            }
        }

        let mut result: HashMap<String, DataFrame> = HashMap::new();
        for &(m, c) in symbols {
            result.insert(format_symbol_key(m, c), DataFrame::default());
        }
        for ((m, c), rows) in &groups {
            if rows.is_empty() { continue; }
            let indices: Vec<u32> = rows.iter().map(|&r| r as u32).collect();
            let idx = UInt32Chunked::from_vec("take".into(), indices);
            let Ok(sub) = df.take(&idx) else { continue; };
            let date_col = match sub.column("date") {
                Ok(c) => c,
                Err(_) => { result.insert(format_symbol_key(*m, *c), sub); continue; }
            };
            let sorted_idx = date_col.arg_sort(SortOptions::default());
            let Ok(sorted) = sub.take(&sorted_idx) else {
                result.insert(format_symbol_key(*m, *c), sub);
                continue;
            };
            result.insert(format_symbol_key(*m, *c), sorted);
        }
        result
    }
}

impl Default for ParquetDataProvider {
    fn default() -> Self { Self::new() }
}

impl DataProvider for ParquetDataProvider {
    fn kline(&self, symbol: &str, tf: Timeframe, from: NaiveDate, to: NaiveDate) -> LazyFrame {
        let Some((market, code)) = parse_symbol(symbol) else {
            return empty_lazy_frame();
        };
        let daily = self.scan_single_lf(market, code, from, to);
        resample_if_needed(daily, tf)
    }

    fn load_batch_joined_lf(&self, _symbols: &[String], tf: Timeframe, from: NaiveDate, to: NaiveDate) -> Option<LazyFrame> {
        let daily = self.load_batch_joined_lf(Timeframe::Daily, from, to);
        Some(resample_batch_if_needed(daily, tf))
    }

    fn intraday(&self, symbol: &str, date: NaiveDate) -> LazyFrame {
        let Some(ref kdir) = self.klines_dir else { return empty_lazy_frame(); };
        let root = kdir.parent().unwrap();
        let mdir = root.join("minutes");
        if !mdir.exists() { return empty_lazy_frame(); }

        let (mkt, code) = match parse_symbol_parts(symbol) {
            Some(v) => v, None => return empty_lazy_frame(),
        };
        let (year, month) = (date.year(), date.month());
        let path = mdir.join(format!("{year}")).join(format!("{month:02}.parquet"));
        if !path.exists() { return empty_lazy_frame(); }

        let args = ScanArgsParquet::default();
        let path_str = path.to_string_lossy().to_string();
        let lf = match LazyFrame::scan_parquet(path_str.as_str().into(), args) {
            Ok(lf) => lf,
            Err(_) => return empty_lazy_frame(),
        };

        lf.filter(col("market").eq(lit(mkt)))
            .filter(col("code").eq(lit(code)))
            .filter(col("date").eq(lit(date)))
            .select([
                col("minute"),
                (col("price").cast(DataType::Float64) / lit(10000.0)).alias("price"),
                (col("avg").cast(DataType::Float64) / lit(10000.0)).alias("avg"),
                col("volume").cast(DataType::Float64).alias("volume"),
            ])
    }

    fn market_index(&self, symbol: &str) -> String {
        match symbol.split('.').next().unwrap_or("") {
            "SZ" => "SZ.399001".to_string(),
            "BJ" => "BJ.899050".to_string(),
            _ => "SH.000001".to_string(),
        }
    }

    fn load_batch(
        &self,
        symbols: &[String],
        tf: Timeframe,
        from: NaiveDate,
        to: NaiveDate,
    ) -> HashMap<String, DataFrame> {
        if !matches!(tf, Timeframe::Daily | Timeframe::Weekly | Timeframe::Monthly) {
            return symbols.iter().map(|s| (s.clone(), DataFrame::default())).collect();
        }
        let parsed: Vec<(i32, i32)> = symbols.iter().filter_map(|s| parse_symbol(s)).collect();
        if parsed.len() != symbols.len() {
            eprintln!(
                "[ParquetDataProvider] load_batch: {} 个符号中有 {} 个无法解析。",
                symbols.len(),
                symbols.len() - parsed.len(),
            );
        }
        let mut result = self.load_batch_internal(&parsed, from, to);
        for symbol in symbols {
            result.entry(symbol.clone()).or_insert_with(DataFrame::default);
        }
        if matches!(tf, Timeframe::Weekly | Timeframe::Monthly) {
            for (_sym, df) in result.iter_mut() {
                *df = resample_df(std::mem::take(df), tf);
            }
        }
        result
    }
}

// ── Weekly / Monthly resampling from daily data ─────────────────────
// Uses manual ISO-week / year-month grouping.

fn resample_if_needed(lf: LazyFrame, tf: Timeframe) -> LazyFrame {
    match tf {
        Timeframe::Daily => lf,
        Timeframe::Weekly | Timeframe::Monthly => {
            let df = lf.collect().unwrap_or_default();
            resample_df(df, tf).lazy()
        }
        Timeframe::Minutes(_) => empty_lazy_frame(),
    }
}

fn resample_batch_if_needed(lf: LazyFrame, tf: Timeframe) -> LazyFrame {
    match tf {
        Timeframe::Daily => lf,
        Timeframe::Weekly | Timeframe::Monthly => {
            let df = lf.collect().unwrap_or_default();
            resample_batch_df(df, tf).lazy()
        }
        Timeframe::Minutes(_) => empty_lazy_frame(),
    }
}

/// ISO week number (Mon=1..Sun=7, week containing Thursday defines year).
fn iso_week(date: NaiveDate) -> i32 {
    let iso = date.iso_week();
    // Encode as year*100 + week for group key
    iso.year() * 100 + iso.week() as i32
}

fn year_month(date: NaiveDate) -> i32 {
    date.year() * 100 + date.month() as i32
}

fn split_by_period(df: &DataFrame, tf: Timeframe) -> Vec<(i32, Vec<usize>)> {
    let mut groups: HashMap<i32, Vec<usize>> = HashMap::new();
    let date_col = match df.column("date").ok().and_then(|s| s.str().ok()) {
        Some(ca) => ca,
        None => return vec![],
    };
    for i in 0..df.height() {
        let Some(date_str) = date_col.get(i) else { continue };
        let Ok(date) = NaiveDate::parse_from_str(date_str, "%Y-%m-%d") else { continue };
        let pkey = match tf {
            Timeframe::Weekly => iso_week(date),
            Timeframe::Monthly => year_month(date),
            _ => 0,
        };
        groups.entry(pkey).or_default().push(i);
    }
    let mut keys: Vec<i32> = groups.keys().cloned().collect();
    keys.sort();
    keys.into_iter().map(|k| (k, groups.remove(&k).unwrap_or_default())).collect()
}

fn df_col_f64(df: &DataFrame, col: &str, rows: &[usize], func: fn(&[f64]) -> f64) -> f64 {
    let vals: Vec<f64> = df.column(col).ok()
        .and_then(|s| s.f64().ok())
        .map(|ca| rows.iter().filter_map(|&i| ca.get(i)).collect())
        .unwrap_or_default();
    if vals.is_empty() { f64::NAN } else { func(&vals) }
}

fn resample_df(mut df: DataFrame, tf: Timeframe) -> DataFrame {
    if df.height() == 0 { return df; }
    let groups = split_by_period(&df, tf);
    if groups.is_empty() { return df; }

    // Extract single-symbol market/code once (same for all rows)
    let mkt: i32 = df.column("market").ok()
        .and_then(|s| s.i32().ok())
        .and_then(|ca| ca.get(0))
        .unwrap_or(-1);
    let code: i32 = df.column("code").ok()
        .and_then(|s| s.i32().ok())
        .and_then(|ca| ca.get(0))
        .unwrap_or(-1);

    let n = groups.len();
    let mut opens: Vec<f64> = Vec::with_capacity(n);
    let mut highs: Vec<f64> = Vec::with_capacity(n);
    let mut lows: Vec<f64> = Vec::with_capacity(n);
    let mut closes: Vec<f64> = Vec::with_capacity(n);
    let mut volumes: Vec<f64> = Vec::with_capacity(n);
    let mut amounts: Vec<f64> = Vec::with_capacity(n);
    let mut dates: Vec<String> = Vec::with_capacity(n);

    for (_key, rows) in groups {
        let first_idx = rows[0];
        let last_idx = rows[rows.len() - 1];
        opens.push(df_col_f64(&df, "open", &[first_idx], |v| v[0]));
        highs.push(df_col_f64(&df, "high", &rows, |v| v.iter().cloned().fold(f64::NAN, f64::max)));
        lows.push(df_col_f64(&df, "low", &rows, |v| v.iter().cloned().fold(f64::NAN, f64::min)));
        closes.push(df_col_f64(&df, "close", &[last_idx], |v| v[0]));
        volumes.push(df_col_f64(&df, "volume", &rows, |v| v.iter().sum()));
        amounts.push(df_col_f64(&df, "amount", &rows, |v| v.iter().sum()));
        let date_str = df.column("date").ok()
            .and_then(|s| s.str().ok())
            .and_then(|ca| ca.get(last_idx))
            .map(|s| s.to_string())
            .unwrap_or_default();
        dates.push(date_str);
    }

    let _ = df;
    DataFrame::new(n, vec![
        Column::new("market".into(), Series::new("market".into(), vec![mkt; n])),
        Column::new("code".into(), Series::new("code".into(), vec![code; n])),
        Column::new("open".into(), Series::new("open".into(), opens)),
        Column::new("high".into(), Series::new("high".into(), highs)),
        Column::new("low".into(), Series::new("low".into(), lows)),
        Column::new("close".into(), Series::new("close".into(), closes)),
        Column::new("volume".into(), Series::new("volume".into(), volumes)),
        Column::new("amount".into(), Series::new("amount".into(), amounts)),
        Column::new("date".into(), Series::new("date".into(), dates)),
    ]).unwrap_or(DataFrame::empty())
}

fn resample_batch_df(df: DataFrame, tf: Timeframe) -> DataFrame {
    if df.height() == 0 { return df; }
    // Multi-symbol batch: group by (market, code, period)
    let mut group_map: HashMap<(i32, i32, i32), Vec<usize>> = HashMap::new();
    let date_col = match df.column("date").ok().and_then(|s| s.str().ok()) {
        Some(ca) => ca,
        None => return df,
    };
    let market_col = match df.column("market").ok().and_then(|s| s.i32().ok()) {
        Some(ca) => ca,
        None => return df,
    };
    let code_col = match df.column("code").ok().and_then(|s| s.i32().ok()) {
        Some(ca) => ca,
        None => return df,
    };

    for i in 0..df.height() {
        let Some(date_str) = date_col.get(i) else { continue };
        let Ok(date) = NaiveDate::parse_from_str(date_str, "%Y-%m-%d") else { continue };
        let Some(mkt) = market_col.get(i) else { continue };
        let Some(code) = code_col.get(i) else { continue };
        let key = match tf {
            Timeframe::Weekly => iso_week(date),
            Timeframe::Monthly => year_month(date),
            _ => 0,
        };
        group_map.entry((mkt, code, key)).or_default().push(i);
    }

    let mut keys_sorted: Vec<_> = group_map.keys().cloned().collect();
    keys_sorted.sort();

    let n = keys_sorted.len();
    let mut markets: Vec<i32> = Vec::with_capacity(n);
    let mut codes: Vec<i32> = Vec::with_capacity(n);
    let mut opens: Vec<f64> = Vec::with_capacity(n);
    let mut highs: Vec<f64> = Vec::with_capacity(n);
    let mut lows: Vec<f64> = Vec::with_capacity(n);
    let mut closes: Vec<f64> = Vec::with_capacity(n);
    let mut volumes: Vec<f64> = Vec::with_capacity(n);
    let mut amounts: Vec<f64> = Vec::with_capacity(n);
    let mut dates: Vec<String> = Vec::with_capacity(n);

    for (mkt, code, _period) in &keys_sorted {
        let rows = &group_map[&(*mkt, *code, *_period)];
        let first_idx = rows[0];
        let last_idx = rows[rows.len() - 1];
        markets.push(*mkt);
        codes.push(*code);
        opens.push(df_col_f64(&df, "open", &[first_idx], |v| v[0]));
        highs.push(df_col_f64(&df, "high", &rows, |v| v.iter().cloned().fold(f64::NAN, f64::max)));
        lows.push(df_col_f64(&df, "low", &rows, |v| v.iter().cloned().fold(f64::NAN, f64::min)));
        closes.push(df_col_f64(&df, "close", &[last_idx], |v| v[0]));
        volumes.push(df_col_f64(&df, "volume", &rows, |v| v.iter().sum()));
        amounts.push(df_col_f64(&df, "amount", &rows, |v| v.iter().sum()));
        let ds = date_col.get(last_idx).map(|s| s.to_string()).unwrap_or_default();
        dates.push(ds);
    }

    DataFrame::new(n, vec![
        Column::new("market".into(), Series::new("market".into(), markets)),
        Column::new("code".into(), Series::new("code".into(), codes)),
        Column::new("open".into(), Series::new("open".into(), opens)),
        Column::new("high".into(), Series::new("high".into(), highs)),
        Column::new("low".into(), Series::new("low".into(), lows)),
        Column::new("close".into(), Series::new("close".into(), closes)),
        Column::new("volume".into(), Series::new("volume".into(), volumes)),
        Column::new("amount".into(), Series::new("amount".into(), amounts)),
        Column::new("date".into(), Series::new("date".into(), dates)),
    ]).unwrap_or(df)
}

// ── Helpers ────────────────────────────────────────────────────────

fn concat_lfs(lfs: Vec<LazyFrame>) -> LazyFrame {
    if lfs.is_empty() {
        return empty_lazy_frame();
    }
    let mut iter = lfs.into_iter();
    let first = iter.next().unwrap();
    iter.fold(first, |acc, lf| {
        concat(&[acc, lf], UnionArgs::default()).unwrap_or_else(|_| empty_lazy_frame())
    })
}

fn empty_lazy_frame() -> LazyFrame {
    let schema = Schema::from_iter(vec![
        Field::new("market".into(), DataType::Int32),
        Field::new("code".into(), DataType::Int32),
        Field::new("date".into(), DataType::String),
        Field::new("open".into(), DataType::Float64),
        Field::new("high".into(), DataType::Float64),
        Field::new("low".into(), DataType::Float64),
        Field::new("close".into(), DataType::Float64),
        Field::new("volume".into(), DataType::Float64),
        Field::new("amount".into(), DataType::Float64),
    ]);
    DataFrame::empty_with_schema(&schema).lazy()
}
