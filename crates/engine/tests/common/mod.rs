//! 测试工具集：股票列表加载、registry 构建、DSL 结构体构造辅助。

use std::collections::HashMap;

use chrono::NaiveDate;
use kline_dsl::mod_def::indicator::{
    FormulaOutput, IndicatorFormula, IndicatorModDef,
};
use kline_dsl::mod_def::registry::ModuleRegistry;
use kline_dsl::pipeline::{IndicatorCall, Pipeline, PrepareStage, Stage};
use kline_dsl::{Anchor, Expr, PathExpr, ScreenResult, StockId, Timeframe};
use polars::prelude::*;

use kline_engine::provider::{DataProvider, ParquetDataProvider};
use kline_engine::runner::run_pipeline;

// ── DataProvider 工具 ─────────────────────────────────────────────

/// 从 stock.db 的 catalog 表中加载所有 A 股标的。
/// 通过 security_kind 字段精确过滤，排除指数/ETF/债券。
pub fn load_available_symbols(provider: &ParquetDataProvider) -> Vec<(i32, i32, String)> {
    let Some(dir) = provider.klines_dir_path() else {
        return Vec::new();
    };

    // stock.db 在 klines 的父目录
    let db_path = dir.parent().map(|p| p.join("stock.db"));
    let Some(db_path) = db_path else { return Vec::new() };
    if !db_path.exists() {
        eprintln!("[load_symbols] stock.db 未找到: {}", db_path.display());
        return Vec::new();
    }

    let conn = match rusqlite::Connection::open(&db_path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("[load_symbols] 打开 stock.db 失败: {e}");
            return Vec::new();
        }
    };

    let mut stmt = match conn.prepare(
        "SELECT market, code FROM catalog WHERE security_kind = 'stock' ORDER BY market, code"
    ) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("[load_symbols] 查询 catalog 失败: {e}");
            return Vec::new();
        }
    };

    let rows = stmt.query_map([], |row| {
        Ok((row.get::<_, i32>(0)?, row.get::<_, String>(1)?))
    });

    let mut symbols = Vec::new();
    match rows {
        Ok(iter) => {
            for row in iter.flatten() {
                let (market, code_str) = row;
                let code: i32 = match code_str.parse() {
                    Ok(c) => c,
                    Err(_) => continue,
                };
                let prefix = match market {
                    0 => "SZ",
                    1 => "SH",
                    2 => "BJ",
                    _ => continue,
                };
                let s = format!("{prefix}.{code:06}");
                symbols.push((market, code, s));
            }
        }
        Err(e) => eprintln!("[load_symbols] 读取 catalog 行失败: {e}"),
    }

    symbols
}

/// 随机采样 n 个股票符号。
pub fn sample_symbols(symbols: &[(i32, i32, String)], n: usize) -> Vec<String> {
    use std::collections::hash_map::DefaultHasher;
    use std::hash::{Hash, Hasher};
    if symbols.len() <= n {
        return symbols.iter().map(|(_, _, s)| s.clone()).collect();
    }
    let mut indices: Vec<usize> = (0..symbols.len()).collect();
    indices.sort_by_key(|&i| {
        let mut h = DefaultHasher::new();
        symbols[i].2.hash(&mut h);
        h.finish()
    });
    indices.truncate(n);
    indices.sort_unstable();
    indices
        .iter()
        .map(|&i| symbols[i].2.clone())
        .collect()
}

/// 获取用于数据加载的起止日期范围。
pub fn recent_trade_dates(n: usize) -> (NaiveDate, NaiveDate) {
    let today = chrono::Local::now().date_naive();
    let to = today;
    let from = to - chrono::Duration::days((n * 2 + 14) as i64);
    (from, to)
}

// ── Registry 工具 ─────────────────────────────────────────────────

/// 构建包含常用指标的默认 ModuleRegistry。
pub fn default_registry() -> ModuleRegistry {
    let mut registry = ModuleRegistry::default();

    registry.register_indicator(IndicatorModDef {
        id: "sma".to_string(),
        param_names: vec!["period".to_string()],
        outputs: vec![FormulaOutput {
            col_name_template: "sma_{period}".to_string(),
            formula: IndicatorFormula::RollingMean {
                src: Box::new(IndicatorFormula::Col("close".to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
        }],
    });

    registry.register_indicator(IndicatorModDef {
        id: "boll".to_string(),
        param_names: vec!["period".to_string(), "k".to_string()],
        outputs: vec![
            FormulaOutput {
                col_name_template: "boll_mid_{period}".to_string(),
                formula: IndicatorFormula::RollingMean {
                    src: Box::new(IndicatorFormula::Col("close".to_string())),
                    period: Box::new(IndicatorFormula::Param("period".to_string())),
                },
            },
            FormulaOutput {
                col_name_template: "boll_upper_{period}".to_string(),
                formula: IndicatorFormula::Add(
                    Box::new(IndicatorFormula::RollingMean {
                        src: Box::new(IndicatorFormula::Col("close".to_string())),
                        period: Box::new(IndicatorFormula::Param("period".to_string())),
                    }),
                    Box::new(IndicatorFormula::Mul(
                        Box::new(IndicatorFormula::RollingStd {
                            src: Box::new(IndicatorFormula::Col("close".to_string())),
                            period: Box::new(IndicatorFormula::Param("period".to_string())),
                        }),
                        Box::new(IndicatorFormula::Param("k".to_string())),
                    )),
                ),
            },
        ],
    });

    registry.register_indicator(IndicatorModDef {
        id: "vol_ma".to_string(),
        param_names: vec!["period".to_string()],
        outputs: vec![FormulaOutput {
            col_name_template: "vol_ma_{period}".to_string(),
            formula: IndicatorFormula::RollingMean {
                src: Box::new(IndicatorFormula::Col("volume".to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
        }],
    });

    registry.register_indicator(IndicatorModDef {
        id: "high_n".to_string(),
        param_names: vec!["period".to_string()],
        outputs: vec![FormulaOutput {
            col_name_template: "high_{period}".to_string(),
            formula: IndicatorFormula::RollingMax {
                src: Box::new(IndicatorFormula::Col("high".to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
        }],
    });

    registry.register_indicator(IndicatorModDef {
        id: "low_n".to_string(),
        param_names: vec!["period".to_string()],
        outputs: vec![FormulaOutput {
            col_name_template: "low_{period}".to_string(),
            formula: IndicatorFormula::RollingMin {
                src: Box::new(IndicatorFormula::Col("low".to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
        }],
    });

    // ── Built-in intraday modules (mirrors rust/src/api/screener.rs) ──
    use kline_dsl::mod_def::intraday::{IntradayBoolExpr, IntradayModDef, IntradayTimeRef, IntradayVal};

    registry.register_intraday(IntradayModDef {
        id: "price_above_avg".into(), param_names: vec![],
        expr: IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::Gt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart, to: IntradayTimeRef::RangeEnd,
        },
    });
    registry.register_intraday(IntradayModDef {
        id: "price_below_avg".into(), param_names: vec![],
        expr: IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::Lt(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::Yellow(IntradayTimeRef::EachMinute),
            )),
            from: IntradayTimeRef::RangeStart, to: IntradayTimeRef::RangeEnd,
        },
    });
    registry.register_intraday(IntradayModDef {
        id: "price_cross_avg".into(), param_names: vec![],
        expr: IntradayBoolExpr::And(
            Box::new(IntradayBoolExpr::AnyMinute {
                pred: Box::new(IntradayBoolExpr::Gt(
                    IntradayVal::White(IntradayTimeRef::EachMinute),
                    IntradayVal::Yellow(IntradayTimeRef::EachMinute),
                )),
                from: IntradayTimeRef::RangeStart, to: IntradayTimeRef::RangeEnd,
            }),
            Box::new(IntradayBoolExpr::AnyMinute {
                pred: Box::new(IntradayBoolExpr::Lt(
                    IntradayVal::White(IntradayTimeRef::EachMinute),
                    IntradayVal::Yellow(IntradayTimeRef::EachMinute),
                )),
                from: IntradayTimeRef::RangeStart, to: IntradayTimeRef::RangeEnd,
            }),
        ),
    });
    registry.register_intraday(IntradayModDef {
        id: "limit_up_touch".into(), param_names: vec![],
        expr: IntradayBoolExpr::AnyMinute {
            pred: Box::new(IntradayBoolExpr::Gte(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::LimitUpPrice,
            )),
            from: IntradayTimeRef::RangeStart, to: IntradayTimeRef::RangeEnd,
        },
    });
    registry.register_intraday(IntradayModDef {
        id: "limit_up_sealed".into(), param_names: vec![],
        expr: IntradayBoolExpr::AllMinutes {
            pred: Box::new(IntradayBoolExpr::Gte(
                IntradayVal::White(IntradayTimeRef::EachMinute),
                IntradayVal::LimitUpPrice,
            )),
            from: IntradayTimeRef::RangeStart, to: IntradayTimeRef::RangeEnd,
        },
    });

    registry
}

// ── DSL 结构体构造辅助 ────────────────────────────────────────────

pub fn col_expr(field: &str, offset: i64) -> Expr {
    Expr::Path(PathExpr {
        stock: StockId::Current,
        anchor: Anchor::WindowEnd,
        offset,
        field: Some(field.to_string()),
    })
}

pub fn close_expr() -> Expr { col_expr("close", 0) }
pub fn open_expr() -> Expr { col_expr("open", 0) }
pub fn high_expr() -> Expr { col_expr("high", 0) }
pub fn low_expr() -> Expr { col_expr("low", 0) }
pub fn volume_expr() -> Expr { col_expr("volume", 0) }

#[derive(Debug, Clone, Copy)]
pub enum CompareOp {
    Gt,
    Lt,
    Gte,
    Lte,
    Eq,
}

pub fn compare_expr(lhs: Expr, op: CompareOp, rhs: Expr) -> Expr {
    match op {
        CompareOp::Gt => Expr::Gt(Box::new(lhs), Box::new(rhs)),
        CompareOp::Lt => Expr::Lt(Box::new(lhs), Box::new(rhs)),
        CompareOp::Gte => Expr::Gte(Box::new(lhs), Box::new(rhs)),
        CompareOp::Lte => Expr::Lte(Box::new(lhs), Box::new(rhs)),
        CompareOp::Eq => Expr::Eq(Box::new(lhs), Box::new(rhs)),
    }
}

fn empty_prepare_stage() -> PrepareStage {
    PrepareStage {
        indicators: Vec::new(),
    }
}

pub fn make_stage(name: &str, conditions: Vec<(&str, Expr)>) -> Stage {
    Stage {
        name: name.to_string(),
        timeframe: Timeframe::Daily,
        start_date: None,
        windowsize: None, // lookback_days: 0,
        prepare: empty_prepare_stage(),
        kline_pattern: None,
        vars: Vec::new(),
        points: Vec::new(),
        conditions: conditions
            .into_iter()
            .map(|(n, e)| (n.to_string(), e))
            .collect(),
        marks: Vec::new(),
        extra_stocks: Vec::new(),
    }
}

pub fn make_stage_with_indicators(
    name: &str,
    indicators: Vec<IndicatorCall>,
    conditions: Vec<(&str, Expr)>,
) -> Stage {
    let mut stage = make_stage(name, conditions);
    stage.prepare = PrepareStage { indicators };
    stage
}

pub fn make_single_stage_pipeline(stage: Stage) -> Pipeline {
    Pipeline {
        stages: vec![stage],
    }
}

// ── 运行工具 ──────────────────────────────────────────────────────

pub fn run_on_real_data(
    pipeline: &Pipeline,
    registry: &ModuleRegistry,
    symbols: &[String],
    from: NaiveDate,
    to: NaiveDate,
) -> Vec<ScreenResult> {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() {
        eprintln!("[test] ParquetDataProvider 不可用，跳过测试。");
        return Vec::new();
    }
    run_pipeline(pipeline, registry, &provider, symbols, from, to)
}

// ── 断言工具 ──────────────────────────────────────────────────────

pub fn assert_passed(result: &ScreenResult) {
    assert!(
        result.eliminated_at.is_none(),
        "expected pass but eliminated at {:?}: {}",
        result.eliminated_at,
        result.eliminated_reason.as_deref().unwrap_or("")
    );
}

pub fn assert_failed(result: &ScreenResult, expected_reason: Option<&str>) {
    assert!(
        result.eliminated_at.is_some(),
        "expected failure but passed"
    );
    if let Some(reason) = expected_reason {
        assert!(
            result
                .eliminated_reason
                .as_deref()
                .map_or(false, |r| r.contains(reason)),
            "expected reason containing '{reason}' but got '{:?}'",
            result.eliminated_reason
        );
    }
}

#[allow(dead_code)]
pub fn print_result(result: &ScreenResult) {
    println!(
        "symbol={} passed_stages={:?} eliminated_at={:?} reason={:?}",
        result.symbol,
        result.passed_stages,
        result.eliminated_at,
        result.eliminated_reason
    );
    for (i, sr) in result.stage_results.iter().enumerate() {
        println!(
            "  stage[{}] passed={} conditions={:?} matches={}",
            i,
            sr.passed,
            sr.passed_conditions,
            sr.matches.len()
        );
    }
}

// ── 编译一致性验证 ────────────────────────────────────────────────

pub fn cross_validate_expr(
    expr: &Expr,
    df: &DataFrame,
    symbol: &str,
) {
    use kline_engine::compiler::expr_compiler::try_compile_condition;
    use kline_engine::{
        evaluator::{ctx::EvalCtx, expr::eval_bool},
        DateIndex, MatchedWindow,
    };
    use std::cell::RefCell;

    if df.height() < 5 {
        return;
    }

    let compiled = try_compile_condition("_crossval", expr);

    let n = df.height();
    let dates = kline_engine::extract_dates(df);
    let date_index = DateIndex::new(dates);
    // 窗口覆盖整个数据范围，WindowEnd 锚点落在最后一行。
    let window = MatchedWindow {
        global_start: 0,
        global_end: n,
        block_ranges: HashMap::new(),
    };

    let cache = RefCell::new(kline_engine::cache::IntradayCache::default());
    let registry = ModuleRegistry::default();
    let dummy_provider = kline_engine::runner::HashMapProvider::from_data(HashMap::new());
    let empty_dfs: HashMap<String, &DataFrame> = HashMap::new();
    let empty_dates: HashMap<String, &kline_engine::DateIndex> = HashMap::new();

    let mut ctx = EvalCtx::new(
        df,
        &date_index,
        symbol,
        None,
        None,
        &empty_dfs,
        &empty_dates,
        &window,
        &registry,
        &cache,
        &dummy_provider,
    );

    // 解释器：传入 None，在 WindowEnd（窗口末尾，即最后一行 n）求值。
    // 编译器：对整列计算，取 WindowEnd 行（n-1）。
    let eval_result = eval_bool(expr, &mut ctx, None);
    let window_end_row = n.saturating_sub(1);

    if let Some(ref comp) = compiled {
        match df
            .clone()
            .lazy()
            .with_column(comp.expr.clone().alias("_crossval"))
            .collect()
        {
            Ok(result_df) => {
                if let Ok(mask_col) = result_df.column("_crossval") {
                    if let Ok(mask) = mask_col.bool() {
                        if let Some(comp_val) = mask.get(window_end_row) {
                            if comp_val != eval_result {
                                eprintln!(
                                    "[cross_validate] MISMATCH symbol={symbol} row={window_end_row}: \
                                     compiled={comp_val}, interpreted={eval_result}"
                                );
                            }
                            // 只在 WindowsEnd 行做一次比较
                            assert_eq!(
                                comp_val, eval_result,
                                "symbol={symbol} row={window_end_row}: compiler={comp_val}, interpreter={eval_result}"
                            );
                        }
                    }
                }
            }
            Err(_) => {}
        }
    }
}
