pub mod cache;
pub mod compiler;
pub mod evaluator;
pub mod matcher;
pub mod planner;
pub mod provider;
pub mod runner;

use std::collections::HashMap;

use chrono::NaiveDate;
use polars::prelude::{AnyValue, DataFrame, DataType};

// ── 日期索引：O(1) 日期→行号查找 ──────────────────────────────

#[derive(Clone, Debug)]
pub struct DateIndex {
    pub dates: Vec<NaiveDate>,
    row_map: HashMap<NaiveDate, usize>,
}

impl DateIndex {
    pub fn new(dates: Vec<NaiveDate>) -> Self {
        let row_map = dates
            .iter()
            .enumerate()
            .map(|(i, d)| (*d, i))
            .collect();
        DateIndex { dates, row_map }
    }

    pub fn row_of(&self, date: NaiveDate) -> Option<usize> {
        self.row_map.get(&date).copied()
    }

    pub fn len(&self) -> usize {
        self.dates.len()
    }

    pub fn is_empty(&self) -> bool {
        self.dates.is_empty()
    }

    pub fn get_date(&self, row: usize) -> Option<NaiveDate> {
        self.dates.get(row).copied()
    }
}

// ── Pass1 的输出：一次形态命中的窗口 ──────────────────────────

#[derive(Debug, Clone)]
pub struct MatchedWindow {
    pub global_start: usize,
    pub global_end: usize,
    pub block_ranges: HashMap<String, (usize, usize)>,
}

impl MatchedWindow {
    pub fn block_start(&self, name: &str) -> Option<usize> {
        self.block_ranges.get(name).map(|r| r.0)
    }

    pub fn block_last(&self, name: &str) -> Option<usize> {
        self.block_ranges.get(name).and_then(|r| r.1.checked_sub(1))
    }
}

// ── 全局辅助函数 ─────────────────────────────────────────────

pub fn anyval_to_f64(v: AnyValue<'_>) -> Option<f64> {
    match v {
        AnyValue::Float64(f) => Some(f),
        AnyValue::Float32(f) => Some(f as f64),
        AnyValue::Int64(i) => Some(i as f64),
        AnyValue::Int32(i) => Some(i as f64),
        AnyValue::Int16(i) => Some(i as f64),
        AnyValue::Int8(i) => Some(i as f64),
        AnyValue::UInt64(i) => Some(i as f64),
        AnyValue::UInt32(i) => Some(i as f64),
        AnyValue::UInt16(i) => Some(i as f64),
        AnyValue::UInt8(i) => Some(i as f64),
        AnyValue::Null => None,
        _ => None,
    }
}

pub fn get_f64(df: &DataFrame, row: usize, col: &str) -> Option<f64> {
    df.column(col)
        .ok()
        .and_then(|s| s.get(row).ok())
        .and_then(anyval_to_f64)
}

pub fn extract_f64_col(df: &DataFrame, col: &str) -> Vec<f64> {
    let s = df.column(col).unwrap_or_else(|_| panic!("列不存在: {col}"));
    let s = s
        .cast(&DataType::Float64)
        .unwrap_or_else(|_| panic!("列 {col} 无法转 f64"));
    s.f64()
        .unwrap()
        .into_iter()
        .map(|v| v.unwrap_or(f64::NAN))
        .collect()
}

pub fn extract_dates(df: &DataFrame) -> Vec<NaiveDate> {
    df.column("date")
        .ok()
        .and_then(|s| {
            s.str().ok().map(|ca| {
                ca.into_iter()
                    .map(|v| {
                        v.and_then(|s| NaiveDate::parse_from_str(s, "%Y-%m-%d").ok())
                            .unwrap_or_else(|| NaiveDate::from_ymd_opt(1970, 1, 1).unwrap())
                    })
                    .collect()
            })
        })
        .unwrap_or_default()
}
