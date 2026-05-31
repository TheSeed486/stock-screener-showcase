use crate::{AggFunc, CandleType, CmpOp, MonotoneDir, Params};
use chrono::NaiveTime;
use serde::{Deserialize, Serialize};

// ── 股票引用 ─────────────────────────────────────────────────

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum StockId {
    Current,
    Named(String),
    /// 自动对应大盘指数（引擎通过 DataProvider::market_index 解析）
    Market,
    MarketNamed(String),
}

// ── 路径表达式：stock.point.A[-1].close ──────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum Anchor {
    Point(String),
    WindowStart,
    WindowEnd,
    /// 范围谓词内部：指代当前被遍历的 bar
    EachBar,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PathExpr {
    pub stock: StockId,
    pub anchor: Anchor,
    pub offset: i64,
    pub field: Option<String>,
}

impl PathExpr {
    pub fn point(name: impl Into<String>, offset: i64) -> Self {
        Self {
            stock: StockId::Current,
            anchor: Anchor::Point(name.into()),
            offset,
            field: None,
        }
    }

    pub fn ext(stock: impl Into<String>, name: impl Into<String>, offset: i64) -> Self {
        Self {
            stock: StockId::Named(stock.into()),
            anchor: Anchor::Point(name.into()),
            offset,
            field: None,
        }
    }

    pub fn market(name: impl Into<String>, offset: i64) -> Self {
        Self {
            stock: StockId::Market,
            anchor: Anchor::Point(name.into()),
            offset,
            field: None,
        }
    }

    pub fn window_start(offset: i64) -> Self {
        Self {
            stock: StockId::Current,
            anchor: Anchor::WindowStart,
            offset,
            field: None,
        }
    }

    pub fn window_end(offset: i64) -> Self {
        Self {
            stock: StockId::Current,
            anchor: Anchor::WindowEnd,
            offset,
            field: None,
        }
    }

    pub fn each() -> Self {
        Self {
            stock: StockId::Current,
            anchor: Anchor::EachBar,
            offset: 0,
            field: None,
        }
    }

    fn field(self, f: &str) -> Expr {
        Expr::Path(Self {
            field: Some(f.to_string()),
            ..self
        })
    }

    pub fn close(self) -> Expr {
        self.field("close")
    }

    pub fn open(self) -> Expr {
        self.field("open")
    }

    pub fn high(self) -> Expr {
        self.field("high")
    }

    pub fn low(self) -> Expr {
        self.field("low")
    }

    pub fn volume(self) -> Expr {
        self.field("volume")
    }

    pub fn col(self, c: &str) -> Expr {
        self.field(c)
    }
}

// ── 统一表达式 ───────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum Expr {
    // 字面量
    Num(f64),
    Bool(bool),

    // 路径引用：stock.point.A[-1].close
    Path(PathExpr),

    // 变量引用
    Var(String),

    // 算术
    Neg(Box<Expr>),
    Add(Box<Expr>, Box<Expr>),
    Sub(Box<Expr>, Box<Expr>),
    Mul(Box<Expr>, Box<Expr>),
    Div(Box<Expr>, Box<Expr>),
    Abs(Box<Expr>),
    PctChange {
        from: Box<Expr>,
        to: Box<Expr>,
    },

    // 比较
    Gt(Box<Expr>, Box<Expr>),
    Lt(Box<Expr>, Box<Expr>),
    Gte(Box<Expr>, Box<Expr>),
    Lte(Box<Expr>, Box<Expr>),
    Eq(Box<Expr>, Box<Expr>),
    Between {
        val: Box<Expr>,
        low: Box<Expr>,
        high: Box<Expr>,
    },

    // 布尔
    And(Box<Expr>, Box<Expr>),
    Or(Box<Expr>, Box<Expr>),
    Not(Box<Expr>),
    /// A → B，等价于 Or(Not(A), B)，但语义更清晰
    Implies {
        antecedent: Box<Expr>,
        consequent: Box<Expr>,
    },

    // 范围聚合
    Agg {
        stock: StockId,
        from: PathExpr,
        to: PathExpr,
        col: String,
        func: AggFunc,
    },

    // 范围谓词（pred 内用 PathExpr::each()）
    All {
        stock: StockId,
        from: PathExpr,
        to: PathExpr,
        pred: Box<Expr>,
    },
    Any {
        stock: StockId,
        from: PathExpr,
        to: PathExpr,
        pred: Box<Expr>,
    },

    // [from,to] 内满足 pred 的 K 线数量比较
    CountBars {
        from: PathExpr,
        to: PathExpr,
        pred: Box<Expr>,
        op: CmpOp,
        n: usize,
    },

    // 范围最值（「A..D中最低」等）
    RangeVal {
        stock: StockId,
        from: PathExpr,
        to: PathExpr,
        col: String,
        func: AggFunc,
    },

    // K 线事件
    CrossUp {
        stock: StockId,
        at: PathExpr,
        col: String,
        threshold: Box<Expr>,
    },
    CrossDown {
        stock: StockId,
        at: PathExpr,
        col: String,
        threshold: Box<Expr>,
    },
    CandleIs {
        stock: StockId,
        at: PathExpr,
        candle: CandleType,
    },

    // 点存在性（溢出保护）
    PointExists(String),

    // 单调性
    Monotone {
        stock: StockId,
        from: PathExpr,
        to: PathExpr,
        col: String,
        dir: MonotoneDir,
    },

    // 与大盘 K 线方向同步（逐根对比）
    SyncWithMarket {
        from: PathExpr,
        to: PathExpr,
    },

    // 分时条件（嵌入 Expr，可与 K 线条件自由 And/Or）
    Intraday(IntradayCondRef),

    // 分时时长条件
    IntradayDuration {
        anchor_point: String,
        stock: StockId,
        time_from: NaiveTime,
        time_to: NaiveTime,
        module_id: String,
        params: Params,
        op: CmpOp,
        minutes: u32,
    },
}

// ── 链式方法 ─────────────────────────────────────────────────

impl Expr {
    pub fn gt(self, r: impl Into<Expr>) -> Expr {
        Expr::Gt(bx(self), bx(r.into()))
    }

    pub fn lt(self, r: impl Into<Expr>) -> Expr {
        Expr::Lt(bx(self), bx(r.into()))
    }

    pub fn gte(self, r: impl Into<Expr>) -> Expr {
        Expr::Gte(bx(self), bx(r.into()))
    }

    pub fn lte(self, r: impl Into<Expr>) -> Expr {
        Expr::Lte(bx(self), bx(r.into()))
    }

    pub fn and(self, r: impl Into<Expr>) -> Expr {
        Expr::And(bx(self), bx(r.into()))
    }

    pub fn or(self, r: impl Into<Expr>) -> Expr {
        Expr::Or(bx(self), bx(r.into()))
    }

    pub fn not(self) -> Expr {
        Expr::Not(bx(self))
    }

    pub fn implies(self, r: impl Into<Expr>) -> Expr {
        Expr::Implies {
            antecedent: bx(self),
            consequent: bx(r.into()),
        }
    }

    pub fn between(self, lo: impl Into<Expr>, hi: impl Into<Expr>) -> Expr {
        Expr::Between {
            val: bx(self),
            low: bx(lo.into()),
            high: bx(hi.into()),
        }
    }

    pub fn pct_to(self, to: impl Into<Expr>) -> Expr {
        Expr::PctChange {
            from: bx(self),
            to: bx(to.into()),
        }
    }
}

pub fn bx(e: Expr) -> Box<Expr> {
    Box::new(e)
}

/// 变量引用快捷函数：var("name")
pub fn var(n: &str) -> Expr {
    Expr::Var(n.to_string())
}

impl From<f64> for Expr {
    fn from(v: f64) -> Self {
        Expr::Num(v)
    }
}

impl From<i32> for Expr {
    fn from(v: i32) -> Self {
        Expr::Num(v as f64)
    }
}

impl From<i64> for Expr {
    fn from(v: i64) -> Self {
        Expr::Num(v as f64)
    }
}

impl From<bool> for Expr {
    fn from(v: bool) -> Self {
        Expr::Bool(v)
    }
}

impl std::ops::Add for Expr {
    type Output = Expr;

    fn add(self, r: Expr) -> Expr {
        Expr::Add(bx(self), bx(r))
    }
}

impl std::ops::Sub for Expr {
    type Output = Expr;

    fn sub(self, r: Expr) -> Expr {
        Expr::Sub(bx(self), bx(r))
    }
}

impl std::ops::Mul for Expr {
    type Output = Expr;

    fn mul(self, r: Expr) -> Expr {
        Expr::Mul(bx(self), bx(r))
    }
}

impl std::ops::Div for Expr {
    type Output = Expr;

    fn div(self, r: Expr) -> Expr {
        Expr::Div(bx(self), bx(r))
    }
}

impl std::ops::Neg for Expr {
    type Output = Expr;

    fn neg(self) -> Expr {
        Expr::Neg(bx(self))
    }
}

impl std::ops::Not for Expr {
    type Output = Expr;

    fn not(self) -> Expr {
        Expr::Not(bx(self))
    }
}

// ── 分时条件引用（嵌入 Expr::Intraday）───────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IntradayCondRef {
    pub anchor_point: String,
    pub stock: StockId,
    pub time_from: NaiveTime,
    pub time_to: NaiveTime,
    pub module_id: String,
    pub params: Params,
}

impl IntradayCondRef {
    pub fn new(
        anchor_point: &str,
        time_from: &str,
        time_to: &str,
        module_id: &str,
        params: Params,
    ) -> Self {
        Self {
            anchor_point: anchor_point.into(),
            stock: StockId::Current,
            time_from: NaiveTime::parse_from_str(time_from, "%H:%M").unwrap(),
            time_to: NaiveTime::parse_from_str(time_to, "%H:%M").unwrap(),
            module_id: module_id.into(),
            params,
        }
    }

    pub fn for_stock(mut self, stock: StockId) -> Self {
        self.stock = stock;
        self
    }

    pub fn into_expr(self) -> Expr {
        Expr::Intraday(self)
    }
}
