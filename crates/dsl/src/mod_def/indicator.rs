use serde::{Deserialize, Serialize};

/// K 线指标公式节点
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", content = "v")]
pub enum IndicatorFormula {
    Col(String),
    Lit(f64),
    /// 引用 Mod 调用时传入的参数，e.g. Param("period")
    Param(String),
    RollingMean {
        src: Box<IndicatorFormula>,
        period: Box<IndicatorFormula>,
    },
    RollingStd {
        src: Box<IndicatorFormula>,
        period: Box<IndicatorFormula>,
    },
    RollingMax {
        src: Box<IndicatorFormula>,
        period: Box<IndicatorFormula>,
    },
    RollingMin {
        src: Box<IndicatorFormula>,
        period: Box<IndicatorFormula>,
    },
    RollingSum {
        src: Box<IndicatorFormula>,
        period: Box<IndicatorFormula>,
    },
    Shift {
        src: Box<IndicatorFormula>,
        periods: Box<IndicatorFormula>,
    },
    Add(Box<IndicatorFormula>, Box<IndicatorFormula>),
    Sub(Box<IndicatorFormula>, Box<IndicatorFormula>),
    Mul(Box<IndicatorFormula>, Box<IndicatorFormula>),
    Div(Box<IndicatorFormula>, Box<IndicatorFormula>),
    Abs(Box<IndicatorFormula>),
    Neg(Box<IndicatorFormula>),
    Sqrt(Box<IndicatorFormula>),
    IfElse {
        cond: Box<IndicatorFormula>,
        then_val: Box<IndicatorFormula>,
        else_val: Box<IndicatorFormula>,
    },
}

/// 一个输出列定义
/// col_name_template 支持 {param} 插值，e.g. "boll_upper_{period}"
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FormulaOutput {
    pub col_name_template: String,
    pub formula: IndicatorFormula,
}

/// 一个 K 线指标 Mod 的完整定义（Flutter 构建，JSON 序列化传给 Rust）
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct IndicatorModDef {
    pub id: String,
    pub param_names: Vec<String>,
    pub outputs: Vec<FormulaOutput>,
}
