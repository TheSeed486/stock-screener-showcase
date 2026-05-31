//! 指标公式正确性测试：SMA, EMA, BOLL 等指标公式编译和执行。

mod common;

use common::*;
use kline_dsl::{
    mod_def::indicator::{FormulaOutput, IndicatorFormula, IndicatorModDef},
    params, Expr, PathExpr,
};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

/// 加载单标的 DataFrame（有足够数据用于指标计算）。
fn load_single_df(symbol: &str, n_days: usize) -> (polars::prelude::DataFrame, String) {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(n_days);
    let lf = provider.kline(symbol, kline_dsl::Timeframe::Daily, from, to);
    let df = lf.collect().unwrap_or_default();
    (df, symbol.to_string())
}

#[test]
fn test_sma_indicator_compiles_and_runs() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    let stage = make_stage_with_indicators(
        "sma_test",
        vec![kline_dsl::pipeline::IndicatorCall::new(
            "sma",
            params! { "period" => 10_i64 },
        )],
        vec![
            ("close_gt_sma10", {
                Expr::Gt(
                    Box::new(close_expr()),
                    Box::new(col_expr("sma_10", 0)),
                )
            }),
        ],
    );

    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    assert_eq!(results.len(), sample.len());
    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[sma] {passed}/{} 只股 close > SMA(10)", sample.len());
    // 不是全部数据为空就行
    let not_no_data = results.iter()
        .filter(|r| r.eliminated_reason.as_deref() != Some("no_data"))
        .count();
    assert!(not_no_data > 0, "至少有一些标的有数据");
}

#[test]
fn test_boll_indicator_compiles_and_runs() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    let stage = make_stage_with_indicators(
        "boll_test",
        vec![kline_dsl::pipeline::IndicatorCall::new(
            "boll",
            params! { "period" => 20_i64, "k" => 2.0_f64 },
        )],
        vec![
            ("close_gt_boll_mid", {
                Expr::Gt(
                    Box::new(close_expr()),
                    Box::new(col_expr("boll_mid_20", 0)),
                )
            }),
        ],
    );

    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[boll] {passed}/{} 只股 close > BOLL(20,2) 中轨", sample.len());
}

#[test]
fn test_vol_ma_indicator() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);
    let (from, to) = recent_trade_dates(120);

    let stage = make_stage_with_indicators(
        "vol_test",
        vec![kline_dsl::pipeline::IndicatorCall::new(
            "vol_ma",
            params! { "period" => 5_i64 },
        )],
        vec![
            ("volume_gt_vol_ma5", {
                Expr::Gt(
                    Box::new(volume_expr()),
                    Box::new(col_expr("vol_ma_5", 0)),
                )
            }),
        ],
    );

    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    eprintln!("[vol_ma] {passed}/{} 只股 成交 > VOL_MA(5)", sample.len());
}

#[test]
fn test_formula_compilation_consistency() {
    // 验证 compile_formula 输出的一致性：
    // 同一个公式编译两次应得到相同结果
    use kline_engine::compiler::indicator::compile_formula;
    use kline_dsl::Params;

    let mut params = Params::new();
    params.insert("period".to_string(), kline_dsl::ParamVal::Int(10));

    let formula = IndicatorFormula::RollingMean {
        src: Box::new(IndicatorFormula::Col("close".to_string())),
        period: Box::new(IndicatorFormula::Param("period".to_string())),
    };

    let expr1 = compile_formula(&formula, &params);
    let expr2 = compile_formula(&formula, &params);

    // 两次编译结果应相同（比较 debug 输出）
    assert_eq!(
        format!("{:?}", expr1),
        format!("{:?}", expr2),
        "同一公式两次编译结果应一致"
    );
}
