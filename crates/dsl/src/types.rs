use serde::{Deserialize, Serialize};
use std::collections::HashMap;

// ── 参数 ────────────────────────────────────────────────────

pub type Params = HashMap<String, ParamVal>;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", content = "value")]
pub enum ParamVal {
    Int(i64),
    Float(f64),
    Str(String),
    Bool(bool),
}

impl ParamVal {
    pub fn as_f64(&self) -> Option<f64> {
        match self {
            Self::Float(v) => Some(*v),
            Self::Int(v) => Some(*v as f64),
            _ => None,
        }
    }

    pub fn as_i64(&self) -> Option<i64> {
        if let Self::Int(v) = self {
            Some(*v)
        } else {
            None
        }
    }

    pub fn as_str(&self) -> Option<&str> {
        if let Self::Str(v) = self {
            Some(v)
        } else {
            None
        }
    }
}

impl From<i64> for ParamVal {
    fn from(v: i64) -> Self {
        Self::Int(v)
    }
}

impl From<f64> for ParamVal {
    fn from(v: f64) -> Self {
        Self::Float(v)
    }
}

impl From<&str> for ParamVal {
    fn from(v: &str) -> Self {
        Self::Str(v.to_string())
    }
}

impl From<bool> for ParamVal {
    fn from(v: bool) -> Self {
        Self::Bool(v)
    }
}

#[macro_export]
macro_rules! params {
    ($($k:expr => $v:expr),* $(,)?) => {{
        let mut m = $crate::Params::new();
        $(m.insert($k.into(), $crate::ParamVal::from($v));)*
        m
    }};
}

// ── K 线基础类型 ─────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum WindowSize {
    Exact(usize),
    Range {
        min: Option<usize>,
        max: Option<usize>,
    },
}

impl WindowSize {
    pub fn is_range(&self) -> bool {
        matches!(self, WindowSize::Range { .. })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub enum CandleType {
    Up,   // close > open
    Down, // close < open
    Neutral,
    Doji, // close == open（精确相等）
    Any,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum Timeframe {
    Minutes(u32),
    Daily,
    Weekly,
    Monthly,
}

// ── 表达式辅助类型 ───────────────────────────────────────────

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum AggFunc {
    Max,
    Min,
    Mean,
    Sum,
    First,
    Last,
    StdDev,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum CmpOp {
    Gt,
    Gte,
    Lt,
    Lte,
    Eq,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
pub enum MonotoneDir {
    StrictInc,
    StrictDec,
    NonDec,
    NonInc,
}
