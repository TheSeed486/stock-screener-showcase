use crate::{CandleType, WindowSize};
use serde::{Deserialize, Serialize};

/// 单个形态块
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PatternBlock {
    pub block_name: String,
    pub pattern: CandleType,
    pub block_size: WindowSize,
    /// optional=true 时允许该块缺失
    pub optional: bool,
    /// 允许与下一个块重叠 1 根 bar
    pub allow_overlap_next: bool,
}

/// K 线形态定义（纯形状，不绑定日期/窗口大小）。
/// 日期和窗口大小由 Stage 的 `start_date` / `windowsize` 控制。
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct KlinePattern {
    pub name: String,
    pub pattern: Vec<PatternBlock>,
}
