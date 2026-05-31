//! 检查有多少股票的 pattern 恰好在 2026-05-15 结束。
mod common;

use chrono::NaiveDate;
use kline_dsl::{CandleType, PatternBlock, WindowSize};
use kline_engine::matcher::match_pattern;
use kline_engine::provider::{DataProvider, ParquetDataProvider};
use kline_engine::{extract_f64_col, extract_dates};

#[test]
fn find_stocks_ending_on_target_date() {
    let provider = ParquetDataProvider::new();
    if !provider.is_available() { return; }

    let start_date = NaiveDate::from_ymd_opt(2026, 5, 15).unwrap();
    let from = start_date - chrono::Duration::days(200);

    let blocks = vec![
        PatternBlock { block_name: "Ap".into(), pattern: CandleType::Any,
            block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        PatternBlock { block_name: "A".into(), pattern: CandleType::Up,
            block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        PatternBlock { block_name: "B".into(), pattern: CandleType::Down,
            block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        PatternBlock { block_name: "C".into(), pattern: CandleType::Up,
            block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
    ];

    let all = common::load_available_symbols(&provider);
    eprintln!("=== Scanning {} stocks for pattern ending on {start_date} ===", all.len());

    let mut found_stocks = Vec::new();
    let mut count_checked = 0;
    let mut count_with_data = 0;
    let mut count_any_match = 0;

    for (_, _, sym) in all.iter().take(200) {
        count_checked += 1;
        let lf = provider.kline(sym, kline_dsl::Timeframe::Daily, from, start_date);
        if let Ok(df) = lf.collect() {
            if df.height() < 10 { continue; }
            count_with_data += 1;

            let open = extract_f64_col(&df, "open");
            let close = extract_f64_col(&df, "close");
            let dates = extract_dates(&df);

            // 找到 start_date 的行号
            let anchor = dates.iter().position(|d| *d == start_date)
                .unwrap_or_else(|| dates.iter().rposition(|d| *d < start_date).unwrap_or(df.height()));
            if anchor >= df.height() { continue; }

            let requested_end = anchor + 1;

            // 检查 pattern 在 anchor 处是否匹配
            let windows = match_pattern(&open, &close, &blocks,
                WindowSize::Exact(4), 0, 0, requested_end);
            if !windows.is_empty() {
                count_any_match += 1;
                found_stocks.push((sym.clone(), dates[anchor], open[anchor], close[anchor]));
                if found_stocks.len() <= 10 {
                    // 打印最后 4 根 bar
                    let a = anchor.saturating_sub(3);
                    eprintln!("  {sym} at {}:", dates[anchor]);
                    for i in a..=anchor {
                        let c = if close[i] > open[i] { "阳" } else if close[i] < open[i] { "阴" } else { "平" };
                        eprintln!("    [{i}] {} O={:.2} C={:.2} {}", dates[i], open[i], close[i], c);
                    }
                }
            }
        }
    }

    eprintln!("=== Results ===");
    eprintln!("  checked: {count_checked}");
    eprintln!("  with data: {count_with_data}");
    eprintln!("  any pattern match: {count_any_match}");
    eprintln!("  stocks with match at target: {}", found_stocks.len());

    // 再试：不筛选 requested_end，只是看哪些股票在最后位置有 pattern
    eprintln!("=== Checking pattern at anchor position [manually] ===");
    let mut manual_count = 0;
    for (_, _, sym) in all.iter().take(200) {
        let lf = provider.kline(sym, kline_dsl::Timeframe::Daily, from, start_date);
        if let Ok(df) = lf.collect() {
            if df.height() < 4 { continue; }
            let open = extract_f64_col(&df, "open");
            let close = extract_f64_col(&df, "close");
            let dates = extract_dates(&df);
            let anchor = dates.iter().position(|d| *d == start_date)
                .unwrap_or_else(|| dates.iter().rposition(|d| *d < start_date).unwrap_or(df.height()));
            if anchor < 3 { continue; }
            // Check: Ap(Any)=anchor-3, A(Up)=anchor-2, B(Down)=anchor-1, C(Up)=anchor
            let a_up = close[anchor-2] > open[anchor-2];
            let b_down = close[anchor-1] < open[anchor-1];
            let c_up = close[anchor-0] > open[anchor-0];
            if a_up && b_down && c_up {
                manual_count += 1;
                if manual_count <= 5 {
                    eprintln!("  {sym} date={}", dates[anchor]);
                }
            }
        }
    }
    eprintln!("  manual count ending on {start_date}: {manual_count}");
}
