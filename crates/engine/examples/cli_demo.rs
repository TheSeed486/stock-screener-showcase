//! CLI Demo: runs stock screening strategies against sample data.
//!
//! Usage:
//!   STOCK_DB_DIR=./sample_data cargo run --example cli_demo
//!
//! Demonstrates:
//!   1. SMA crossover (close > SMA20)
//!   2. Bollinger Band squeeze (close below mid-band)
//!   3. Volume spike (volume > 2x avg + bullish candle)
//!   4. Multi-condition pipeline

use std::env;

use chrono::NaiveDate;
use kline_dsl::mod_def::registry::ModuleRegistry;
use kline_dsl::params;
use kline_dsl::pipeline::{IndicatorCall, Pipeline, PrepareStage, Stage};
use kline_dsl::{Expr, PathExpr, StockId, Anchor, Timeframe, WindowSize};
use kline_engine::provider::ParquetDataProvider;
use kline_engine::runner::run_pipeline_df;

fn main() {
    let db_dir = env::var("STOCK_DB_DIR").unwrap_or_else(|_| "./sample_data".to_string());
    eprintln!("=== Stock Screener DSL -- CLI Demo ===\n");
    eprintln!("Data dir: {db_dir}");

    let provider = ParquetDataProvider::with_dir(db_dir.into());
    if !provider.is_available() {
        eprintln!("ERROR: sample data not found. Set STOCK_DB_DIR=./sample_data");
        std::process::exit(1);
    }

    let symbols = load_symbols(&provider);
    if symbols.is_empty() {
        eprintln!("ERROR: no symbols in catalog");
        std::process::exit(1);
    }
    eprintln!("Loaded {} symbols\n", symbols.len());

    let from = NaiveDate::from_ymd_opt(2024, 6, 1).unwrap();
    let to = NaiveDate::from_ymd_opt(2025, 12, 31).unwrap();

    demo_sma_crossover(&provider, &symbols, from, to);
    demo_bollinger_squeeze(&provider, &symbols, from, to);
    demo_volume_spike(&provider, &symbols, from, to);
    demo_multi_condition(&provider, &symbols, from, to);
}

// ── Registry ──────────────────────────────────────────────────────

fn default_registry() -> ModuleRegistry {
    use kline_dsl::mod_def::indicator::{FormulaOutput, IndicatorFormula, IndicatorModDef};
    let mut r = ModuleRegistry::default();
    for (id, col, kind) in [
        ("sma", "close", "mean"),
        ("high_n", "high", "max"),
        ("low_n", "low", "min"),
        ("vol_ma", "volume", "mean"),
    ] {
        let formula = match kind {
            "mean" => IndicatorFormula::RollingMean {
                src: Box::new(IndicatorFormula::Col(col.to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
            "max" => IndicatorFormula::RollingMax {
                src: Box::new(IndicatorFormula::Col(col.to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
            _ => IndicatorFormula::RollingMin {
                src: Box::new(IndicatorFormula::Col(col.to_string())),
                period: Box::new(IndicatorFormula::Param("period".to_string())),
            },
        };
        r.register_indicator(IndicatorModDef {
            id: id.to_string(),
            param_names: vec!["period".to_string()],
            outputs: vec![FormulaOutput {
                col_name_template: format!("{id}_{{period}}"),
                formula,
            }],
        });
    }
    // Bollinger Bands
    r.register_indicator(IndicatorModDef {
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
            FormulaOutput {
                col_name_template: "boll_lower_{period}".to_string(),
                formula: IndicatorFormula::Sub(
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
    r
}

// ── Builders ──────────────────────────────────────────────────────

fn col_expr(field: &str, offset: i64) -> Expr {
    Expr::Path(PathExpr {
        stock: StockId::Current,
        anchor: Anchor::WindowEnd,
        offset,
        field: Some(field.into()),
    })
}

fn make_stage(name: &str, indicators: Vec<IndicatorCall>, conditions: Vec<(&str, Expr)>) -> Stage {
    Stage {
        name: name.to_string(),
        timeframe: Timeframe::Daily,
        start_date: None,
        windowsize: Some(WindowSize::Exact(3)),
        prepare: PrepareStage { indicators },
        kline_pattern: None,
        vars: Vec::new(),
        points: Vec::new(),
        conditions: conditions.into_iter().map(|(n, e)| (n.to_string(), e)).collect(),
        marks: Vec::new(),
        extra_stocks: Vec::new(),
    }
}

fn condition(name: &str, expr: Expr) -> (&str, Expr) {
    (name, expr)
}

// ── Demo 1: SMA crossover ──────────────────────────────────────────

fn demo_sma_crossover(provider: &ParquetDataProvider, symbols: &[String], from: NaiveDate, to: NaiveDate) {
    eprintln!("--- Demo 1: Close above SMA20 ---");
    let stage = make_stage(
        "above_sma20",
        vec![IndicatorCall::new("sma", params! {"period" => 20_i64})],
        vec![condition("above_sma20",
            Expr::Gt(Box::new(col_expr("close", 0)), Box::new(col_expr("sma_20", 0)))
        )],
    );
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();
    run_and_print(provider, symbols, from, to, &pipeline, &registry);
}

// ── Demo 2: Bollinger Band squeeze ─────────────────────────────────

fn demo_bollinger_squeeze(provider: &ParquetDataProvider, symbols: &[String], from: NaiveDate, to: NaiveDate) {
    eprintln!("--- Demo 2: Close below Bollinger mid-band (squeeze) ---");
    let stage = make_stage(
        "boll_squeeze",
        vec![IndicatorCall::new("boll", params! {"period" => 20_i64, "k" => 2.0_f64})],
        vec![condition("below_mid",
            Expr::Lt(Box::new(col_expr("close", 0)), Box::new(col_expr("boll_mid_20", 0)))
        )],
    );
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();
    run_and_print(provider, symbols, from, to, &pipeline, &registry);
}

// ── Demo 3: Volume spike ───────────────────────────────────────────

fn demo_volume_spike(provider: &ParquetDataProvider, symbols: &[String], from: NaiveDate, to: NaiveDate) {
    eprintln!("--- Demo 3: Volume 2x above average + bullish close ---");
    let stage = make_stage(
        "vol_spike",
        vec![IndicatorCall::new("vol_ma", params! {"period" => 20_i64})],
        vec![
            condition("bullish",
                Expr::Gt(Box::new(col_expr("close", 0)), Box::new(col_expr("open", 0)))
            ),
            condition("vol_spike",
                Expr::Gt(
                    Box::new(col_expr("volume", 0)),
                    Box::new(Expr::Mul(
                        Box::new(col_expr("vol_ma_20", 0)),
                        Box::new(Expr::Num(2.0)),
                    )),
                )
            ),
        ],
    );
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();
    run_and_print(provider, symbols, from, to, &pipeline, &registry);
}

// ── Demo 4: Multi-condition ────────────────────────────────────────

fn demo_multi_condition(provider: &ParquetDataProvider, symbols: &[String], from: NaiveDate, to: NaiveDate) {
    eprintln!("--- Demo 4: Multi-condition (SMA trend + high range + volume) ---");
    let stage = make_stage(
        "multi",
        vec![
            IndicatorCall::new("sma", params! {"period" => 5_i64}),
            IndicatorCall::new("sma", params! {"period" => 20_i64}),
            IndicatorCall::new("vol_ma", params! {"period" => 20_i64}),
            IndicatorCall::new("high_n", params! {"period" => 20_i64}),
        ],
        vec![
            condition("sma_uptrend",
                Expr::Gt(Box::new(col_expr("sma_5", 0)), Box::new(col_expr("sma_20", 0)))
            ),
            condition("volume_ok",
                Expr::Gt(Box::new(col_expr("volume", 0)), Box::new(col_expr("vol_ma_20", 0)))
            ),
            condition("near_20d_high",
                Expr::Gt(
                    Box::new(col_expr("close", 0)),
                    Box::new(Expr::Mul(
                        Box::new(col_expr("high_n_20", 0)),
                        Box::new(Expr::Num(0.85)),
                    )),
                )
            ),
        ],
    );
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();
    run_and_print(provider, symbols, from, to, &pipeline, &registry);
}

// ── Helpers ────────────────────────────────────────────────────────

fn load_symbols(provider: &ParquetDataProvider) -> Vec<String> {
    let Some(dir) = provider.klines_dir_path() else { return Vec::new() };
    let db_path = dir.parent().unwrap().join("stock.db");
    if !db_path.exists() { return Vec::new(); }

    let conn = match rusqlite::Connection::open(&db_path) { Ok(c) => c, Err(_) => return Vec::new() };
    let mut stmt = match conn.prepare(
        "SELECT market, code FROM catalog WHERE security_kind='stock' ORDER BY market, code"
    ) { Ok(s) => s, Err(_) => return Vec::new() };
    stmt.query_map([], |row| {
        let market: i32 = row.get(0)?;
        let code_str: String = row.get(1)?;
        let prefix = match market { 0 => "SZ", 1 => "SH", 2 => "BJ", _ => "??" };
        Ok(format!("{prefix}.{code_str}"))
    })
    .unwrap()
    .flatten()
    .collect()
}

fn run_and_print(
    provider: &ParquetDataProvider, symbols: &[String],
    from: NaiveDate, to: NaiveDate,
    pipeline: &Pipeline, registry: &ModuleRegistry,
) {
    let t = std::time::Instant::now();
    let df = run_pipeline_df(pipeline, registry, provider, symbols, from, to, None);
    let elapsed = t.elapsed();

    let total = df.height();
    let passed = df.column("\u{901a}\u{8fc7}")  // 通过
        .ok()
        .and_then(|s| s.bool().ok())
        .map(|c| c.into_iter().filter(|v| matches!(v, Some(true))).count())
        .unwrap_or(0);

    eprintln!("  {passed}/{total} passed in {elapsed:.2?}");

    // Print top 5 passing results
    let code_col = df.column("\u{4ee3}\u{7801}").ok();  // 代码
    let mut shown = 0;
    for i in 0..df.height() {
        if shown >= 5 { break; }
        let is_pass = df.column("\u{901a}\u{8fc7}").ok()
            .and_then(|s| s.bool().ok())
            .and_then(|c| c.get(i))
            .unwrap_or(false);
        if !is_pass { continue; }
        let code = code_col
            .and_then(|c| c.str().ok())
            .and_then(|s| {
                let val = s.get(i);
                val.map(|v| v.to_string())
            })
            .or_else(|| {
                code_col.and_then(|c| c.i32().ok())
                    .and_then(|c| {
                        let val = c.get(i);
                        val.map(|v| format!("{:06}", v))
                    })
            })
            .unwrap_or_else(|| "?".to_string());
        eprintln!("    {}", code);
        shown += 1;
    }
    if shown == 0 { eprintln!("    (no results)"); }
    eprintln!();
}
