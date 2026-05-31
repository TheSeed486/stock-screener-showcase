//! K 线形态匹配测试：kline_pattern + start_date + windowsize
mod common;

use common::*;
use chrono::NaiveDate;
use kline_dsl::{CandleType, PatternBlock, KlinePattern, WindowSize, Expr, StockId};
use kline_engine::provider::{DataProvider, ParquetDataProvider};

/// 加载单标的 DataFrame 和其日期列
fn load_single(symbol: &str, n_days: usize) -> (polars::prelude::DataFrame, String, Vec<NaiveDate>) {
    let provider = ParquetDataProvider::new();
    let (from, to) = recent_trade_dates(n_days);
    let lf = provider.kline(symbol, kline_dsl::Timeframe::Daily, from, to);
    let df = lf.collect().unwrap_or_default();
    let dates = kline_engine::extract_dates(&df);
    (df, symbol.to_string(), dates)
}

/// 在 DataFrame 中找到符合 candle 类型的第一个日期（从后往前）
fn find_candle_date(df: &polars::prelude::DataFrame, candle: CandleType) -> Option<NaiveDate> {
    let dates = kline_engine::extract_dates(df);
    let open = kline_engine::extract_f64_col(df, "open");
    let close = kline_engine::extract_f64_col(df, "close");
    for i in (0..df.height()).rev() {
        let is_up = close[i] > open[i];
        let is_down = close[i] < open[i];
        let matches = match candle {
            CandleType::Up => is_up,
            CandleType::Down => is_down,
            CandleType::Neutral => (close[i] - open[i]).abs() < 0.001,
            CandleType::Any => true,
            CandleType::Doji => {
                let body = (close[i] - open[i]).abs();
                let range = high_at(df, i) - low_at(df, i);
                range > 0.0 && body / range < 0.1
            }
        };
        if matches {
            return Some(dates[i]);
        }
    }
    None
}

/// 找到连续满足 candle 序列的起始日期（从后往前找）
fn find_pattern_dates(
    df: &polars::prelude::DataFrame,
    candles: &[CandleType],
) -> Option<Vec<NaiveDate>> {
    let dates = kline_engine::extract_dates(df);
    let n = df.height();
    let open = kline_engine::extract_f64_col(df, "open");
    let close = kline_engine::extract_f64_col(df, "close");
    for end in (candles.len()..n).rev() {
        let mut matched = true;
        for offset in 0..candles.len() {
            let i = end - offset - 1;
            let candle = &candles[offset];
            let ok = match candle {
                CandleType::Up => close[i] > open[i],
                CandleType::Down => close[i] < open[i],
                CandleType::Any => true,
                _ => false,
            };
            if !ok {
                matched = false;
                break;
            }
        }
        if matched {
            let result: Vec<NaiveDate> = (0..candles.len())
                .map(|off| dates[end - off - 1])
                .collect();
            return Some(result);
        }
    }
    None
}

fn high_at(df: &polars::prelude::DataFrame, i: usize) -> f64 {
    kline_engine::extract_f64_col(df, "high")[i]
}
fn low_at(df: &polars::prelude::DataFrame, i: usize) -> f64 {
    kline_engine::extract_f64_col(df, "low")[i]
}

// ── 简单形态：单根阳线 Up{1} ──────────────────────────────────

#[test]
fn test_pattern_single_up_candle() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 5);

    let mut matched = 0;
    for sym in &sample {
        let (df, _name, dates) = load_single(sym, 120);
        if df.height() < 10 { continue; }

        // 找到最近一根阳线的日期
        let Some(start_date) = find_candle_date(&df, CandleType::Up) else { continue; };

        // 构建 Up{1} 形态
        let pattern = KlinePattern {
            name: "single_up".to_string(),
            pattern: vec![PatternBlock {
                block_name: "up1".to_string(),
                pattern: CandleType::Up,
                block_size: WindowSize::Exact(1),
                optional: false,
                allow_overlap_next: false,
            }],
        };

        let mut stage = make_stage("pattern", vec![]);
        stage.kline_pattern = Some(pattern);
        stage.start_date = Some(start_date);
        stage.windowsize = Some(WindowSize::Exact(1));

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let results = run_on_real_data(
            &pipeline, &registry, &[sym.clone()],
            dates.first().copied().unwrap_or(start_date),
            start_date,
        );

        assert_eq!(results.len(), 1);
        if results[0].eliminated_at.is_none() {
            matched += 1;
            eprintln!("[up1] {sym} matched at {start_date}");
        } else {
            eprintln!("[up1] {sym} failed at {start_date}: {:?}", results[0].eliminated_reason);
        }
    }
    assert!(matched > 0, "至少应有 1 只股匹配到阳线形态");
    eprintln!("[up1] {matched}/{} matched", sample.len());
}

// ── 双 K 线形态：阳包阴 (Down{1} + Up{1}) ─────────────────────

#[test]
fn test_pattern_bullish_engulfing() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    // 多扫几只股找吞噬形态
    let sample = sample_symbols(&symbols, 30);

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

    let mut matched = 0;
    for sym in &sample {
        let (df, _name, dates) = load_single(sym, 120);
        if df.height() < 10 { continue; }

        // 找 Down+Up 序列的日期
        let Some(pat_dates) = find_pattern_dates(&df, &[CandleType::Down, CandleType::Up])
        else { continue; };
        let start_date = pat_dates[1]; // Up candle date = pattern end

        let mut stage = make_stage("engulfing", vec![]);
        stage.kline_pattern = Some(pattern.clone());
        stage.start_date = Some(start_date);
        stage.windowsize = Some(WindowSize::Exact(2));

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let results = run_on_real_data(
            &pipeline, &registry, &[sym.clone()],
            dates.first().copied().unwrap_or(start_date),
            start_date,
        );

        assert_eq!(results.len(), 1);
        if results[0].eliminated_at.is_none() {
            matched += 1;
            eprintln!("[engulfing] {sym} matched at {start_date} (prev={})", pat_dates[0]);
        } else {
            eprintln!("[engulfing] {sym} failed at {start_date}: {:?}", results[0].eliminated_reason);
        }
    }
    eprintln!("[engulfing] {matched}/{} matched", sample.len());
    // 30 只股中大概率至少有几只出现吞噬形态
    assert!(matched > 0, "30 只股中应至少有几只出现阳包阴");
}

// ── 形态 + 条件组合 ─────────────────────────────────────────────

#[test]
fn test_pattern_with_conditions() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 20);

    // 吞噬形态 + 成交量放大条件
    let pattern = KlinePattern {
        name: "engulfing_vol".to_string(),
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

    let mut matched = 0;
    for sym in &sample {
        let (df, _name, dates) = load_single(sym, 120);
        if df.height() < 10 { continue; }

        let Some(pat_dates) = find_pattern_dates(&df, &[CandleType::Down, CandleType::Up])
        else { continue; };
        let start_date = pat_dates[1];

        let mut stage = make_stage("engulfing_vol", vec![
            ("vol_positive", compare_expr(volume_expr(), CompareOp::Gt, Expr::Num(0.0))),
        ]);
        stage.kline_pattern = Some(pattern.clone());
        stage.start_date = Some(start_date);
        stage.windowsize = Some(WindowSize::Exact(2));

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let results = run_on_real_data(
            &pipeline, &registry, &[sym.clone()],
            dates.first().copied().unwrap_or(start_date),
            start_date,
        );

        assert_eq!(results.len(), 1);
        if results[0].eliminated_at.is_none() {
            matched += 1;
            eprintln!("[pattern+cond] {sym} matched engulfing + vol at {start_date}");
        }
    }
    eprintln!("[pattern+cond] {matched}/{} matched", sample.len());
    assert!(matched > 0, "至少应有 1 只股满足形态+条件");
}

// ── 三白兵 (Up{3}) ──────────────────────────────────────────────

#[test]
fn test_pattern_three_white_soldiers() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 30);

    let pattern = KlinePattern {
        name: "three_white".to_string(),
        pattern: vec![PatternBlock {
            block_name: "ups".to_string(),
            pattern: CandleType::Up,
            block_size: WindowSize::Exact(3),
            optional: false,
            allow_overlap_next: false,
        }],
    };

    let mut matched = 0;
    for sym in &sample {
        let (df, _name, dates) = load_single(sym, 120);
        if df.height() < 10 { continue; }

        // 找 Up×3 的连续阳线
        let Some(pat_dates) = find_pattern_dates(
            &df,
            &[CandleType::Up, CandleType::Up, CandleType::Up],
        ) else { continue; };
        let start_date = pat_dates[2]; // 最后一根阳线的日期

        let mut stage = make_stage("three_white", vec![]);
        stage.kline_pattern = Some(pattern.clone());
        stage.start_date = Some(start_date);
        stage.windowsize = Some(WindowSize::Exact(3));

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let results = run_on_real_data(
            &pipeline, &registry, &[sym.clone()],
            dates.first().copied().unwrap_or(start_date),
            start_date,
        );

        assert_eq!(results.len(), 1);
        if results[0].eliminated_at.is_none() {
            matched += 1;
            eprintln!("[三白兵] {sym} matched at {start_date} ({}, {}, {})",
                pat_dates[0], pat_dates[1], pat_dates[2]);
        }
    }
    eprintln!("[三白兵] {matched}/{} matched", sample.len());
    assert!(matched > 0, "30 只股中应至少有几只出现三连阳");
}

// ── 形态匹配 + 指标 ─────────────────────────────────────────────

#[test]
fn test_pattern_with_indicators() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 20);

    let pattern = KlinePattern {
        name: "up".to_string(),
        pattern: vec![PatternBlock {
            block_name: "up1".to_string(),
            pattern: CandleType::Up,
            block_size: WindowSize::Exact(1),
            optional: false,
            allow_overlap_next: false,
        }],
    };

    let mut matched = 0;
    for sym in &sample {
        let (df, _name, dates) = load_single(sym, 120);
        if df.height() < 10 { continue; }

        let Some(start_date) = find_candle_date(&df, CandleType::Up) else { continue; };

        // 形态 + SMA 指标 + 条件：阳线 且 close > SMA(5)
        let mut stage = make_stage_with_indicators(
            "up_with_sma",
            vec![kline_dsl::pipeline::IndicatorCall::new(
                "sma",
                kline_dsl::params! { "period" => 5_i64 },
            )],
            vec![(
                "above_sma5",
                compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0)),
            )],
        );
        stage.kline_pattern = Some(pattern.clone());
        stage.start_date = Some(start_date);
        stage.windowsize = Some(WindowSize::Exact(1));

        let pipeline = make_single_stage_pipeline(stage);
        let registry = default_registry();
        let results = run_on_real_data(
            &pipeline, &registry, &[sym.clone()],
            dates.first().copied().unwrap_or(start_date),
            start_date,
        );

        assert_eq!(results.len(), 1);
        if results[0].eliminated_at.is_none() {
            matched += 1;
        }
    }
    eprintln!("[pattern+indicator] {matched}/{} matched", sample.len());
}

// ── 无形态时只按条件求值 ──────────────────────────────────────

#[test]
fn test_no_pattern_falls_back_to_conditions() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    if symbols.is_empty() { return; }
    let sample = sample_symbols(&symbols, 5);
    let (from, to) = recent_trade_dates(60);

    // 无 kline_pattern，只有条件
    let stage = make_stage("no_pattern", vec![
        ("trivial", Expr::Bool(true)),
    ]);
    let pipeline = make_single_stage_pipeline(stage);
    let registry = default_registry();
    let results = run_on_real_data(&pipeline, &registry, &sample, from, to);

    for r in &results {
        assert_passed(r);
    }
}
