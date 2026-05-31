//! Range 形态测试 + 极限性能
mod common;
use common::*;
use kline_dsl::*;
use kline_engine::provider::{DataProvider, ParquetDataProvider};
use std::time::Instant;

#[test]
fn test_range_pattern_up_2_to_5() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    let all: Vec<String> = symbols.iter().take(500).map(|(_,_,s)| s.clone()).collect();
    let (from, to) = recent_trade_dates(250);

    // 形态：Up{2..5} — 连续 2-5 根阳线（Range）
    let stage = Stage {
        name: "up_range".into(), timeframe: Timeframe::Daily,
        start_date: None, windowsize: Some(WindowSize::Range { min: Some(2), max: Some(5) }),
        prepare: PrepareStage { indicators: vec![IndicatorCall::new("sma", params!{"period"=>5_i64})] },
        kline_pattern: Some(KlinePattern {
            name: "up_range".into(),
            pattern: vec![PatternBlock {
                block_name: "ups".into(), pattern: CandleType::Up,
                block_size: WindowSize::Range { min: Some(2), max: Some(5) },
                optional: false, allow_overlap_next: false,
            }],
        }),
        vars: vec![], points: vec![],
        conditions: vec![
            ("close_gt_ma5".into(), compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0))),
        ],
        marks: vec![], extra_stocks: vec![],
    };
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();

    let t0 = Instant::now();
    let results = run_on_real_data(&pipeline, &registry, &all, from, to);
    let elapsed = t0.elapsed();
    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    println!("Range Up{{2..5}} + close>MA5: {passed}/{} passed in {:.2?}", all.len(), elapsed);
    assert!(passed > 0, "应至少有几只匹配");
}

#[test]
fn test_extreme_many_conditions() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }
    let symbols = load_available_symbols(&provider);
    let all: Vec<String> = symbols.iter().take(1000).map(|(_,_,s)| s.clone()).collect();
    let (from, to) = recent_trade_dates(250);

    // 极限：5 个条件 + BOLL + VOL_MA + SMA + 形态匹配
    let stage = Stage {
        name: "extreme".into(), timeframe: Timeframe::Daily,
        start_date: None, windowsize: Some(WindowSize::Exact(2)),
        prepare: PrepareStage {
            indicators: vec![
                IndicatorCall::new("boll", params!{"period"=>20_i64,"k"=>2.0_f64}),
                IndicatorCall::new("vol_ma", params!{"period"=>5_i64}),
                IndicatorCall::new("sma", params!{"period"=>5_i64}),
            ],
        },
        kline_pattern: Some(KlinePattern {
            name: "du".into(),
            pattern: vec![
                PatternBlock{block_name:"D".into(),pattern:CandleType::Down,block_size:WindowSize::Exact(1),optional:false,allow_overlap_next:false},
                PatternBlock{block_name:"U".into(),pattern:CandleType::Up,  block_size:WindowSize::Exact(1),optional:false,allow_overlap_next:false},
            ],
        }),
        vars: vec![], points: vec![],
        conditions: vec![
            ("close_gt_sma5".into(), compare_expr(close_expr(), CompareOp::Gt, col_expr("sma_5", 0))),
            ("close_gt_boll_mid".into(), compare_expr(close_expr(), CompareOp::Gt, col_expr("boll_mid_20", 0))),
            ("vol_gt_vol_ma5".into(), compare_expr(volume_expr(), CompareOp::Gt, col_expr("vol_ma_5", 0))),
            ("high_gt_low".into(), compare_expr(high_expr(), CompareOp::Gt, low_expr())),
            ("close_gt_open".into(), compare_expr(close_expr(), CompareOp::Gt, open_expr())),
        ],
        marks: vec![], extra_stocks: vec![],
    };
    let pipeline = Pipeline { stages: vec![stage] };
    let registry = default_registry();

    let t0 = Instant::now();
    let results = run_on_real_data(&pipeline, &registry, &all, from, to);
    let elapsed = t0.elapsed();
    let passed = results.iter().filter(|r| r.eliminated_at.is_none()).count();
    println!("极限(5条件+3指标+形态): {passed}/{} passed in {:.2?}", all.len(), elapsed);
}
