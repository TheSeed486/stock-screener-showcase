use std::collections::HashMap;

use kline_dsl::{CandleType, PatternBlock, WindowSize};

use crate::MatchedWindow;

/// DFS 回退：处理正则无法精确表达的复杂重叠组合。
/// 逻辑与旧 `CandleMasks` 匹配器一致，但直接从 f64 切片计算。
pub fn dfs_match(
    open: &[f64],
    close: &[f64],
    blocks: &[PatternBlock],
    window_size: WindowSize,
    start_row: usize,
    requested_start: usize,
    requested_end: usize,
) -> Vec<MatchedWindow> {
    let n = open.len();
    if n == 0 {
        return Vec::new();
    }

    let mut windows = Vec::new();

    for cursor in start_row..n {
        if let Some(window) = try_match_from(open, close, blocks, window_size, cursor, requested_start, requested_end)
        {
            windows.push(window);
        }
    }

    windows
}

fn try_match_from(
    open: &[f64],
    close: &[f64],
    blocks: &[PatternBlock],
    window_size: WindowSize,
    start: usize,
    requested_start: usize,
    requested_end: usize,
) -> Option<MatchedWindow> {
    let mut ranges = HashMap::new();
    let end = try_blocks(open, close, blocks, 0, start, &mut ranges)?;
    let wlen = end.saturating_sub(start);
    if wlen == 0 || !window_size_contains(window_size, wlen) {
        return None;
    }
    let last_bar = end.saturating_sub(1);
    if last_bar < requested_start || last_bar >= requested_end {
        return None;
    }
    Some(MatchedWindow {
        global_start: start,
        global_end: end,
        block_ranges: ranges,
    })
}

fn try_blocks(
    open: &[f64],
    close: &[f64],
    blocks: &[PatternBlock],
    block_idx: usize,
    cursor: usize,
    ranges: &mut HashMap<String, (usize, usize)>,
) -> Option<usize> {
    if block_idx >= blocks.len() {
        return Some(cursor);
    }

    let block = &blocks[block_idx];
    let n = open.len();
    let available = n.saturating_sub(cursor);

    for size in candidate_sizes(open, close, block, cursor, available) {
        let block_end = cursor + size;
        let old = ranges.insert(block.block_name.clone(), (cursor, block_end));

        let next_cursor = if block.allow_overlap_next {
            block_end.saturating_sub(1)
        } else {
            block_end
        };

        if let Some(final_end) = try_blocks(open, close, blocks, block_idx + 1, next_cursor, ranges) {
            return Some(final_end);
        }

        if let Some(prev) = old {
            ranges.insert(block.block_name.clone(), prev);
        } else {
            ranges.remove(&block.block_name);
        }
    }

    if block.optional {
        return try_blocks(open, close, blocks, block_idx + 1, cursor, ranges);
    }

    None
}

fn candidate_sizes(open: &[f64], close: &[f64], block: &PatternBlock, cursor: usize, available: usize) -> Vec<usize> {
    let max_run = consecutive_run(open, close, block.pattern, cursor, available);
    if max_run == 0 {
        return Vec::new();
    }

    match block.block_size {
        WindowSize::Exact(n) => {
            if n > 0 && n <= max_run {
                vec![n]
            } else {
                Vec::new()
            }
        }
        WindowSize::Range { min, max } => {
            let min_size = min.unwrap_or(1).max(1);
            let max_size = max_run.min(max.unwrap_or(max_run));
            if min_size > max_size {
                return Vec::new();
            }
            let range = max_size - min_size + 1;
            if range <= 64 {
                (min_size..=max_size).collect()
            } else {
                sample_range(min_size, max_size)
            }
        }
    }
}

fn consecutive_run(open: &[f64], close: &[f64], ct: CandleType, cursor: usize, available: usize) -> usize {
    let mut count = 0usize;
    for i in cursor..cursor + available {
        if candle_matches(ct, open[i], close[i]) {
            count += 1;
        } else {
            break;
        }
    }
    count
}

fn candle_matches(ct: CandleType, open: f64, close: f64) -> bool {
    match ct {
        CandleType::Any => true,
        CandleType::Up => close > open,
        CandleType::Down => close < open,
        CandleType::Neutral | CandleType::Doji => (close - open).abs() < 1e-9,
    }
}

fn sample_range(min: usize, max: usize) -> Vec<usize> {
    let edge = 16usize;
    let mut sizes = Vec::with_capacity(64);

    let front_end = (min + edge).min(max);
    sizes.extend(min..=front_end);

    let mid_start = front_end + 1;
    let mid_end = max.saturating_sub(edge);
    if mid_start <= mid_end {
        let step = ((mid_end - mid_start) as f64 / 32.0).ceil() as usize;
        let step = step.max(1);
        let mut s = mid_start;
        while s <= mid_end {
            sizes.push(s);
            s += step;
        }
    }

    let back_start = (max.saturating_sub(edge - 1)).max(mid_end.saturating_add(1));
    if back_start <= max {
        sizes.extend(back_start..=max);
    }

    sizes.sort();
    sizes.dedup();
    sizes
}

fn window_size_contains(size: WindowSize, len: usize) -> bool {
    match size {
        WindowSize::Exact(n) => len == n,
        WindowSize::Range { min, max } => {
            let lower_ok = min.map(|v| len >= v).unwrap_or(true);
            let upper_ok = max.map(|v| len <= v).unwrap_or(true);
            lower_ok && upper_ok
        }
    }
}
