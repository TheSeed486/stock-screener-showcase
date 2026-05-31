//! 结果正确性验证：手动计算 K 线数据，与 DSL 管道输出对比。
//! 这是"已知答案"测试——如果 DSL 结果与手算不一致，说明有 bug。
mod common;

use common::*;
use kline_dsl::{params, CandleType, Expr, PatternBlock, KlinePattern, PathExpr, StockId, WindowSize};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

/// 加载单标的最近 n 天数据
fn load(symbol: &str, n_days: usize) -> polars::prelude::DataFrame {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(n_days);
    let lf = provider.kline(symbol, kline_dsl::Timeframe::Daily, from, to);
    lf.collect().unwrap_or_default()
}

/// 手算 SMA(close, period)
fn manual_sma(close: &[f64], period: usize) -> Vec<f64> {
    let n = close.len();
    let mut result = vec![f64::NAN; n];
    for i in period - 1..n {
        let sum: f64 = close[i + 1 - period..=i].iter().sum();
        result[i] = sum / period as f64;
    }
    result
}

/// 提取列
fn col(df: &polars::prelude::DataFrame, name: &str) -> Vec<f64> {
    kline_engine::extract_f64_col(df, name)
}

#[test]
fn verify_close_gt_sma5() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    // 取几只股票验证
    let sample = sample_symbols(&symbols, 10);

    for sym in &sample {
        let df = load(sym, 120);
        if df.height() < 10 { continue; }

        let close = col(&df, "close");
        let open = col(&df, "open");
        let high = col(&df, "high");
        let low = col(&df, "low");
        let volume = col(&df, "volume");
        let n = close.len();
        let last = n - 1;

        // ── 手算 SMA(5) ──
        let sma5 = manual_sma(&close, 5);
        let manual_result = close[last] > sma5[last];
        println!(
            "[{sym}] close={:.4} sma5={:.4} manual={manual_result}",
            close[last],
            if sma5[last].is_nan() { -1.0 } else { sma5[last] },
        );

        // ── DSL 管道 ──
        let stage = make_stage_with_indicators(
            "daily",
            vec![kline_dsl::pipeline::IndicatorCall::new(
                "sma",
                params! { "period" => 5_i64 },
            )],
            vec![("above_sma5", compare_expr(
                close_expr(), CompareOp::Gt, col_expr("sma_5", 0),
            ))],
        );

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let dates = kline_engine::extract_dates(&df);
        let from = dates.first().copied().unwrap_or(chrono::Local::now().date_naive());
        let to = dates.last().copied().unwrap_or(chrono::Local::now().date_naive());
        let results = run_on_real_data(&pipeline, &registry, &[sym.clone()], from, to);

        assert_eq!(results.len(), 1, "应返回 1 个结果");
        let dsl_passed = results[0].eliminated_at.is_none();
        println!("[{sym}] DSL passed={dsl_passed}  manual={manual_result}");

        assert_eq!(
            dsl_passed, manual_result,
            "[{sym}] DSL 与手算不一致！DSL={dsl_passed} manual={manual_result}"
        );
    }
}

#[test]
fn verify_candle_type() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);

    for sym in &sample {
        let df = load(sym, 120);
        if df.height() < 10 { continue; }

        let close = col(&df, "close");
        let open = col(&df, "open");
        let last = close.len() - 1;
        let is_up = close[last] > open[last];
        let is_down = close[last] < open[last];

        // ── DSL：Up candle ──
        let stage_up = make_stage("up", vec![
            ("candle_up", Expr::CandleIs {
                stock: StockId::Current,
                at: PathExpr::window_end(0),
                candle: CandleType::Up,
            }),
        ]);
        let pipeline_up = make_single_stage_pipeline(stage_up);
        let registry = default_registry();
        let dates = kline_engine::extract_dates(&df);
        let from = dates.first().copied().unwrap_or(chrono::Local::now().date_naive());
        let to = dates.last().copied().unwrap_or(chrono::Local::now().date_naive());
        let res_up = run_on_real_data(&pipeline_up, &registry, &[sym.clone()], from, to);
        let dsl_up = res_up[0].eliminated_at.is_none();

        println!("[{sym}] close={:.4} open={:.4} is_up={is_up} is_down={is_down} DSL_up={dsl_up}",
            close[last], open[last]);

        assert_eq!(dsl_up, is_up, "[{sym}] Up candle 判断错误: DSL={dsl_up} manual={is_up}");
    }
}

#[test]
fn verify_cross_up() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 10);

    for sym in &sample {
        let df = load(sym, 250);
        if df.height() < 20 { continue; }

        let close = col(&df, "close");
        let sma5 = manual_sma(&close, 5);
        let n = close.len();
        let last = n - 1;

        // 手算 CrossUp(close, sma5): close[n-1] > sma5[n-1] ∧ close[n-2] ≤ sma5[n-2]
        let manual_cross = n >= 2
            && close[last] > sma5[last]
            && close[last - 1] <= sma5[last - 1];

        // ── DSL ──
        let stage = make_stage_with_indicators(
            "daily",
            vec![kline_dsl::pipeline::IndicatorCall::new(
                "sma",
                params! { "period" => 5_i64 },
            )],
            vec![("cross_sma5", Expr::CrossUp {
                stock: StockId::Current,
                at: PathExpr::window_end(0),
                col: "close".to_string(),
                threshold: Box::new(PathExpr::each().col("sma_5")),
            })],
        );

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let dates = kline_engine::extract_dates(&df);
        let from = dates.first().copied().unwrap_or(chrono::Local::now().date_naive());
        let to = dates.last().copied().unwrap_or(chrono::Local::now().date_naive());
        let results = run_on_real_data(&pipeline, &registry, &[sym.clone()], from, to);

        let dsl_passed = results[0].eliminated_at.is_none();
        println!(
            "[{sym}] close[{last}]={:.4} sma5[{last}]={:.4} close[{}]={:.4} sma5[{}]={:.4} manual={manual_cross} DSL={dsl_passed}",
            close[last],
            if sma5[last].is_nan() { -1.0 } else { sma5[last] },
            last - 1, close[last - 1],
            last - 1,
            if sma5[last - 1].is_nan() { -1.0 } else { sma5[last - 1] },
        );

        assert_eq!(
            dsl_passed, manual_cross,
            "[{sym}] CrossUp 判断错误: DSL={dsl_passed} manual={manual_cross}"
        );
    }
}

#[test]
fn verify_pattern_bullish_engulfing() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 20);

    let pattern = KlinePattern {
        name: "bullish_engulfing".to_string(),
        pattern: vec![
            PatternBlock {
                block_name: "down".to_string(),
                pattern: CandleType::Down,
                block_size: WindowSize::Exact(1),
                optional: false,
                allow_overlap_next: false,
            },
            PatternBlock {
                block_name: "up".to_string(),
                pattern: CandleType::Up,
                block_size: WindowSize::Exact(1),
                optional: false,
                allow_overlap_next: false,
            },
        ],
    };

    let mut checked = 0;
    for sym in &sample {
        let df = load(sym, 120);
        if df.height() < 10 { continue; }

        let close = col(&df, "close");
        let open = col(&df, "open");
        let dates = kline_engine::extract_dates(&df);
        let n = close.len();

        // 从后往前找 Down+Up 对
        for i in (1..n).rev() {
            let prev_down = close[i - 1] < open[i - 1];
            let cur_up = close[i] > open[i];
            if prev_down && cur_up {
                let start_date = dates[i];

                let mut stage = make_stage("engulfing", vec![]);
                stage.kline_pattern = Some(pattern.clone());
                stage.start_date = Some(start_date);
                stage.windowsize = Some(WindowSize::Exact(2));

                let pipeline = make_single_stage_pipeline(stage);
                let registry = default_registry();
                let from = dates.first().copied().unwrap();
                let results = run_on_real_data(
                    &pipeline, &registry, &[sym.clone()],
                    from, start_date,
                );

                let dsl_passed = results[0].eliminated_at.is_none();
                println!(
                    "[{sym}] row[{i}]={start_date} prev(D)={prev_down} cur(U)={cur_up} DSL={dsl_passed}"
                );
                assert!(
                    dsl_passed,
                    "[{sym}] {start_date}: 手算阳包阴，DSL 却未匹配"
                );
                checked += 1;
                break; // 只查最近一个
            }
        }
    }
    assert!(checked > 0, "至少应找到 1 个阳包阴并验证");
    println!("[verify_engulfing] 验证了 {checked} 只股票的阳包阴形态");
}
