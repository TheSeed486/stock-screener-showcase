use serde::{Deserialize, Serialize};

// ── 分时序列 & 时刻引用 ──────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum IntradaySeries {
    /// White line (实时价格)
    White,
    /// Yellow line (均价)
    Yellow,
    Volume,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum IntradayTimeRef {
    /// Mod 被调用时传入的 time_from
    RangeStart,
    /// Mod 被调用时传入的 time_to
    RangeEnd,
    /// 固定时刻 "HH:MM"
    At(String),
    /// 仅在 AllMinutes/AnyMinute 内有效：当前被遍历的分钟
    EachMinute,
    /// 引用参数中的时间字符串
    Param(String),
}

// ── 分时数值表达式 ───────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum IntradayVal {
    Lit(f64),
    Param(String),
    White(IntradayTimeRef),
    Yellow(IntradayTimeRef),
    Close(IntradayTimeRef),
    Open(IntradayTimeRef),
    Volume(IntradayTimeRef),
    YesterdayOpen,
    LimitUpPrice,
    LimitDownPrice,
    /// (last - first) / n 近似斜率
    Slope {
        series: IntradaySeries,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
    },
    /// [from,to] 内满足 pred 的分钟数
    Duration {
        pred: Box<IntradayBoolExpr>,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
    },
    /// [from,to] 内 a 穿越 b 的次数
    CrossCount {
        a: IntradaySeries,
        b: IntradaySeries,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
    },
    /// [from,to] 内 series 上穿 threshold 常量的次数
    CrossAbove {
        series: IntradaySeries,
        threshold: Box<IntradayVal>,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
    },
    Add(Box<IntradayVal>, Box<IntradayVal>),
    Sub(Box<IntradayVal>, Box<IntradayVal>),
    Mul(Box<IntradayVal>, Box<IntradayVal>),
    Div(Box<IntradayVal>, Box<IntradayVal>),
    Abs(Box<IntradayVal>),
}

// ── 分时布尔表达式 ───────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum IntradayBoolExpr {
    Gt(IntradayVal, IntradayVal),
    Lt(IntradayVal, IntradayVal),
    Gte(IntradayVal, IntradayVal),
    Lte(IntradayVal, IntradayVal),
    Eq(IntradayVal, IntradayVal),
    And(Box<IntradayBoolExpr>, Box<IntradayBoolExpr>),
    Or(Box<IntradayBoolExpr>, Box<IntradayBoolExpr>),
    Not(Box<IntradayBoolExpr>),
    /// [from,to] 内每分钟都满足（pred 内可用 EachMinute）
    AllMinutes {
        pred: Box<IntradayBoolExpr>,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
    },
    AnyMinute {
        pred: Box<IntradayBoolExpr>,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
    },
    /// [from,to] 内满足 pred 的分钟数 >= minutes
    /// minutes 用 IntradayVal 支持 Param("min_minutes")
    DurationGte {
        pred: Box<IntradayBoolExpr>,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
        minutes: Box<IntradayVal>,
    },
    DurationLte {
        pred: Box<IntradayBoolExpr>,
        from: IntradayTimeRef,
        to: IntradayTimeRef,
        minutes: Box<IntradayVal>,
    },
}

// ── 分时 Mod 定义 ────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntradayModDef {
    pub id: String,
    pub param_names: Vec<String>,
    pub expr: IntradayBoolExpr,
}
