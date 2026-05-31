use super::{indicator::IndicatorModDef, intraday::IntradayModDef};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

/// 全局 Mod 注册表（纯数据，可完整序列化）
/// Flutter 端构建后序列化成 JSON 传给 Rust 引擎
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct ModuleRegistry {
    pub indicators: HashMap<String, IndicatorModDef>,
    pub intraday: HashMap<String, IntradayModDef>,
}

impl ModuleRegistry {
    pub fn register_indicator(&mut self, def: IndicatorModDef) {
        self.indicators.insert(def.id.clone(), def);
    }

    pub fn register_intraday(&mut self, def: IntradayModDef) {
        self.intraday.insert(def.id.clone(), def);
    }

    pub fn from_json(json: &str) -> Self {
        serde_json::from_str(json).expect("ModuleRegistry JSON 解析失败")
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string_pretty(self).unwrap()
    }
}
