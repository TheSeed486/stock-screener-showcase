pub mod fallback;
pub mod polars_pattern;

use std::collections::HashMap;

use kline_dsl::{CandleType, PatternBlock, WindowSize};
use regex::Regex;

use crate::MatchedWindow;

// ── 蜡烛字符串编码 ───────────────────────────────────────────

fn candle_char(open: f64, close: f64) -> char {
    if close > open {
        'U'
    } else if close < open {
        'D'
    } else {
        'N'
    }
}

fn ct_regex_class(ct: CandleType) -> &'static str {
    match ct {
        CandleType::Up => "U",
        CandleType::Down => "D",
        CandleType::Neutral | CandleType::Doji => "N",
        CandleType::Any => ".",
    }
}

fn ct_matches(ct: CandleType, open: f64, close: f64) -> bool {
    match ct {
        CandleType::Any => true,
        CandleType::Up => close > open,
        CandleType::Down => close < open,
        CandleType::Neutral | CandleType::Doji => (close - open).abs() < 1e-9,
    }
}

// ── 构建正则（最小尺寸 + 贪心 Range）─────────────────────────

fn build_blocks_regex(blocks: &[PatternBlock]) -> Regex {
    let mut pattern = String::new();

    for block in blocks {
        let cls = ct_regex_class(block.pattern);
        let min_size = window_size_min(block.block_size);

        let re_size = if block.allow_overlap_next {
            min_size.saturating_sub(1)
        } else {
            min_size
        };

        if re_size == 0 && block.optional {
            continue;
        }

        let quant = if block.block_size.is_range() && !block.allow_overlap_next {
            format!("{{{re_size},}}")
        } else {
            format!("{{{re_size}}}")
        };

        let re_fragment = format!("{cls}{quant}");
        let group_pattern = if block.optional {
            format!("(?:{re_fragment})?")
        } else {
            format!("{re_fragment}")
        };

        pattern.push_str(&group_pattern);
    }

    Regex::new(&pattern).expect("形态正则编译失败")
}

fn window_size_min(ws: WindowSize) -> usize {
    match ws {
        WindowSize::Exact(n) => n,
        WindowSize::Range { min, max: _ } => min.unwrap_or(1).max(1),
    }
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

// ── 公共入口 ─────────────────────────────────────────────────

pub fn build_candle_string(open: &[f64], close: &[f64]) -> String {
    let mut s = String::with_capacity(open.len());
    for (o, c) in open.iter().zip(close.iter()) {
        s.push(candle_char(*o, *c));
    }
    s
}

pub fn match_pattern(
    open: &[f64],
    close: &[f64],
    blocks: &[PatternBlock],
    window_size: WindowSize,
    start_row: usize,
    requested_start: usize,
    requested_end: usize,
) -> Vec<MatchedWindow> {
    let mut windows = if let Ok(w) = try_regex_match(
        open, close, blocks, window_size, start_row, requested_start, requested_end,
    ) {
        w
    } else {
        crate::matcher::fallback::dfs_match(
            open, close, blocks, window_size, start_row, requested_start, requested_end,
        )
    };

    // 固定规则：窗口末尾必须锚定在请求区间末端（从右往左）
    if requested_end > 0 {
        windows.retain(|w| w.global_end == requested_end);
    }

    windows
}

// ── 正则路径：最小尺寸正则定位 + 游程展开 Range 变体 ─────────

fn try_regex_match(
    open: &[f64],
    close: &[f64],
    blocks: &[PatternBlock],
    window_size: WindowSize,
    start_row: usize,
    requested_start: usize,
    requested_end: usize,
) -> Result<Vec<MatchedWindow>, ()> {
    let n = open.len();
    if start_row >= n {
        return Ok(Vec::new());
    }

    let min_regex = build_blocks_regex(blocks);
    let candle_str = build_candle_string(open, close);

    let has_range = blocks.iter().any(|b| matches!(b.block_size, WindowSize::Range { .. }));

    // 预计算游程
    let run_fw: HashMap<CandleType, Vec<usize>> = {
        let mut map = HashMap::new();
        for &ct in &[CandleType::Up, CandleType::Down, CandleType::Neutral] {
            let mut fw = vec![0usize; n];
            if n > 0 {
                fw[n - 1] = if ct_matches(ct, open[n - 1], close[n - 1]) { 1 } else { 0 };
                for i in (0..n - 1).rev() {
                    fw[i] = if ct_matches(ct, open[i], close[i]) {
                        fw[i + 1] + 1
                    } else {
                        0
                    };
                }
            }
            map.insert(ct, fw);
        }
        // Any 类型游程 = 到末尾的剩余 bar 数
        let fw_any: Vec<usize> = (0..n).rev().collect();
        map.insert(CandleType::Any, fw_any);
        map
    };

    let mut windows = Vec::new();
    let mut search_pos = start_row;

    while search_pos < n {
        let Some(caps) = min_regex.captures_at(&candle_str, search_pos) else {
            break;
        };
        let start = caps.get(0).unwrap().start();

        if has_range {
            dfs_expand(
                open, close, blocks, &run_fw,
                window_size, start, 0, start,
                requested_start, requested_end,
                &mut HashMap::new(), &mut windows,
            );
        } else {
            build_exact_window(start, blocks, window_size, requested_start, requested_end)
                .map(|w| windows.push(w));
        }

        search_pos = start + 1;
    }

    Ok(windows)
}

/// 无 Range 块：从 blocks 直接构建单个窗口
fn build_exact_window(
    win_start: usize,
    blocks: &[PatternBlock],
    window_size: WindowSize,
    requested_start: usize,
    requested_end: usize,
) -> Option<MatchedWindow> {
    let mut cursor = win_start;
    let mut block_ranges = HashMap::new();

    for block in blocks {
        let matched_len = window_size_min(block.block_size);
        if matched_len == 0 && !block.optional {
            return None;
        }
        if matched_len > 0 {
            block_ranges.insert(block.block_name.clone(), (cursor, cursor + matched_len));
        }
        cursor += if block.allow_overlap_next { matched_len.saturating_sub(1) } else { matched_len };
    }

    let end = cursor;
    let wlen = end.saturating_sub(win_start);
    if wlen > 0 && window_size_contains(window_size, wlen) {
        let last_bar = end.saturating_sub(1);
        // requested_end == 0 means "no upper bound"
        let end_ok = requested_end == 0 || last_bar < requested_end;
        if last_bar >= requested_start && end_ok {
            return Some(MatchedWindow { global_start: win_start, global_end: end, block_ranges });
        }
    }
    None
}

/// DFS：对 Range 块枚举 [min, max] 所有尺寸，独立验证每个尺寸
fn dfs_expand(
    open: &[f64],
    close: &[f64],
    blocks: &[PatternBlock],
    run_fw: &HashMap<CandleType, Vec<usize>>,
    window_size: WindowSize,
    win_start: usize,
    block_idx: usize,
    cursor: usize,
    requested_start: usize,
    requested_end: usize,
    ranges: &mut HashMap<String, (usize, usize)>,
    out: &mut Vec<MatchedWindow>,
) {
    if block_idx >= blocks.len() {
        let wlen = cursor.saturating_sub(win_start);
        if wlen > 0 && window_size_contains(window_size, wlen) {
            let last_bar = cursor.saturating_sub(1);
            if last_bar >= requested_start && last_bar < requested_end {
                out.push(MatchedWindow {
                    global_start: win_start,
                    global_end: cursor,
                    block_ranges: ranges.clone(),
                });
            }
        }
        return;
    }

    let n = open.len();
    if cursor >= n {
        return;
    }

    let block = &blocks[block_idx];
    let ct = block.pattern;

    if block.optional {
        // 尝试跳过
        dfs_expand(open, close, blocks, run_fw, window_size, win_start, block_idx + 1,
            cursor, requested_start, requested_end, ranges, out);
    }

    let min_size = match block.block_size {
        WindowSize::Exact(n) => n,
        WindowSize::Range { min, max: _ } => min.unwrap_or(1).max(1),
    };

    let max_run = run_fw.get(&ct).and_then(|r| r.get(cursor)).copied().unwrap_or(0);
    let max_size = match block.block_size {
        WindowSize::Exact(n) => n,
        WindowSize::Range { min: _, max } => {
            let m = max.unwrap_or(max_run).min(max_run);
            if m < min_size { return; }
            m
        }
    };

    // Any 大范围优化：不枚举所有尺寸，跳到下一块能匹配的位
    if ct == CandleType::Any && max_size - min_size > 64 && block_idx + 1 < blocks.len() {
        let next = &blocks[block_idx + 1];
        let next_ct = next.pattern;
        let next_min = window_size_min(next.block_size);
        let fw = run_fw.get(&next_ct).map(|r| r.as_slice()).unwrap_or(&[]);

        let scan_start = cursor + min_size;
        let scan_end = (cursor + max_size).min(n);
        let mut p = scan_start;

        while p < scan_end {
            // 跳到 next_ct 的连续游程 ≥ next_min 的位
            let run_at_p = fw.get(p).copied().unwrap_or(0);
            if run_at_p >= next_min {
                ranges.insert(block.block_name.clone(), (cursor, p));
                dfs_expand(open, close, blocks, run_fw, window_size, win_start, block_idx + 1,
                    p, requested_start, requested_end, ranges, out);
                p += 1;
            } else {
                // 跳过整段不匹配的区域
                p += if run_at_p == 0 { 1 } else { run_at_p };
            }
        }
    } else {
        for actual_len in min_size..=max_size {
            if (0..actual_len).any(|j| {
                let idx = cursor + j;
                idx >= n || !ct_matches(ct, open[idx], close[idx])
            }) { continue; }

            ranges.insert(block.block_name.clone(), (cursor, cursor + actual_len));
            let next_cursor = if block.allow_overlap_next {
                cursor + actual_len.saturating_sub(1)
            } else {
                cursor + actual_len
            };

            dfs_expand(open, close, blocks, run_fw, window_size, win_start, block_idx + 1,
                next_cursor, requested_start, requested_end, ranges, out);
        }
    }

    ranges.remove(&block.block_name);
}

#[cfg(test)]
mod tests {
    use kline_dsl::{CandleType, PatternBlock, WindowSize};

    use crate::matcher::fallback as matcher_fallback;

    use super::{build_candle_string, build_blocks_regex, match_pattern, window_size_contains};

    #[test]
    fn candle_string_encoding() {
        let s = build_candle_string(&[10.0, 9.0, 10.0, 8.0], &[11.0, 8.0, 10.0, 7.0]);
        assert_eq!(s, "UDND");
    }

    #[test]
    fn regex_exact_blocks() {
        let blocks = vec![
            PatternBlock { block_name: "U1".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "D".into(), pattern: CandleType::Down,
                block_size: WindowSize::Exact(2), optional: false, allow_overlap_next: false },
        ];
        let re = build_blocks_regex(&blocks);
        assert!(re.as_str().contains("U{1}"));
        assert!(re.as_str().contains("D{2}"));
    }

    #[test]
    fn regex_optional_block() {
        let blocks = vec![
            PatternBlock { block_name: "opt".into(), pattern: CandleType::Down,
                block_size: WindowSize::Exact(1), optional: true, allow_overlap_next: false },
            PatternBlock { block_name: "U".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let re = build_blocks_regex(&blocks);
        assert!(re.is_match("DU"));
        assert!(re.is_match("U"));
    }

    #[test]
    fn match_simple_udu() {
        let blocks = vec![
            PatternBlock { block_name: "U1".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "D".into(), pattern: CandleType::Down,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "U2".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let open = &[10.0, 10.0, 10.0, 11.0, 10.0];
        let close = &[11.0, 11.0, 11.0, 10.0, 11.0]; // U U U D U → 尾部UDU
        // requested_end=5: 窗口必须 anchor 在末尾, UDU 结束位置3≠5, 暂无匹配
        // 但底部UDU匹配: U@2 D@3 U@4 → [2,5) → end=5 ✓
        let windows = match_pattern(open, close, &blocks,
            WindowSize::Range { min: None, max: None }, 0, 0, 5);
        assert_eq!(windows.len(), 1);
        let w = &windows[0];
        assert_eq!(w.global_start, 2);
        assert_eq!(w.global_end, 5);
    }

    #[test]
    fn match_range_variants() {
        let blocks = vec![
            PatternBlock { block_name: "U1".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "any_range".into(), pattern: CandleType::Any,
                block_size: WindowSize::Range { min: Some(2), max: Some(4) },
                optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "U2".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let open =  &[10.0, 10.0, 10.0, 10.0, 10.0];
        let close = &[11.0, 11.0, 11.0, 11.0, 11.0]; // U U U U U
        // anchor at end=5: 最后一块U2必须在pos4. Any块=2U/3U/4U在pos1-4?
        // size2: U[0,1) Any[1,3) U[3,4) → 不可能, U1+Any+U2=1+2+1=4≠5
        // size3: U[0,1) Any[1,4) U[4,5) → 1+3+1=5 ✓
        // 所以仅1个匹配
        let windows = match_pattern(open, close, &blocks,
            WindowSize::Range { min: None, max: None }, 0, 0, 5);
        assert!(windows.len() >= 1, "至少1个变体");
    }

    #[test]
    fn match_with_requested_range() {
        let blocks = vec![
            PatternBlock { block_name: "U".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let open = &[10.0, 10.0, 10.0];
        let close = &[11.0, 11.0, 11.0];
        let windows = match_pattern(open, close, &blocks, WindowSize::Exact(1), 0, 1, 2);
        assert_eq!(windows.len(), 1);
        assert_eq!(windows[0].global_start, 1);
    }

    #[test]
    fn match_with_overlap() {
        let blocks = vec![
            PatternBlock { block_name: "A".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(2), optional: false, allow_overlap_next: true },
            PatternBlock { block_name: "B".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(2), optional: false, allow_overlap_next: false },
        ];
        // U U U → overlap: A=[0,2), B=[1,3) → end=3
        let open = &[10.0, 10.0, 10.0];
        let close = &[11.0, 11.0, 11.0];
        let windows = match_pattern(open, close, &blocks,
            WindowSize::Range { min: None, max: None }, 0, 0, 3);
        assert!(!windows.is_empty());
        let w = &windows[0];
        assert_eq!(w.global_start, 0);
        assert_eq!(w.global_end, 3);
        assert_eq!(w.block_start("A"), Some(0));
        assert_eq!(w.block_start("B"), Some(1));
    }

    #[test]
    fn window_size_filter() {
        assert!(window_size_contains(WindowSize::Exact(3), 3));
        assert!(!window_size_contains(WindowSize::Exact(3), 2));
        assert!(window_size_contains(WindowSize::Range { min: Some(2), max: Some(5) }, 3));
    }

    #[test]
    fn fallback_dfs_simple() {
        let blocks = vec![
            PatternBlock { block_name: "U".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let open = &[10.0, 9.0];
        let close = &[11.0, 8.0];
        let windows = matcher_fallback::dfs_match(open, close, &blocks,
            WindowSize::Exact(1), 0, 0, 2);
        assert_eq!(windows.len(), 1);
    }

    /// 1[2,3]0 = Up(2~3根) + Down(1根) — 两块
    #[test]
    fn up_range_plus_down() {
        let blocks = vec![
            PatternBlock { block_name: "阳".into(), pattern: CandleType::Up,
                block_size: WindowSize::Range { min: Some(2), max: Some(3) },
                optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "阴".into(), pattern: CandleType::Down,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let ws = WindowSize::Range { min: None, max: None };

        // "1110" = UUU D → 2个窗口: [0,4) 3U+1D, [1,4) 2U+1D
        let w1 = match_pattern(&[10.0, 10.0, 10.0, 11.0], &[11.0, 11.0, 11.0, 10.0],
            &blocks, ws, 0, 0, 4);
        assert_eq!(w1.len(), 2, "1110 有两个起始位");
        assert_eq!(w1[0].global_start, 0);
        assert_eq!(w1[0].global_end, 4);
        assert_eq!(w1[1].global_start, 1);
        assert_eq!(w1[1].global_end, 4);

        // "1100"(UUDD) limit window=4: 2U+1D=3bar≠4, 3U+1D fail(pos2≠U) → 0 matches
        let w2 = match_pattern(&[10.0, 10.0, 11.0, 11.0], &[11.0, 11.0, 10.0, 10.0],
            &blocks, WindowSize::Exact(4), 0, 0, 4);
        assert_eq!(w2.len(), 0, "UUDD 不应匹配 4 窗口");

        // "11110" ... (same as before)
        let w3 = match_pattern(&[10.0, 10.0, 10.0, 10.0, 11.0], &[11.0, 11.0, 11.0, 11.0, 10.0],
            &blocks, ws, 0, 0, 5);
        assert_eq!(w3.len(), 2, "11110 仅 [1,5) [2,5)");
    }

    /// U + Any* + U + Any* + D — 多任意块的全分区枚举
    #[test]
    fn multi_any_partitioning() {
        let blocks = vec![
            PatternBlock { block_name: "U1".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "A1".into(), pattern: CandleType::Any,
                block_size: WindowSize::Range { min: Some(1), max: None },
                optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "U2".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "A2".into(), pattern: CandleType::Any,
                block_size: WindowSize::Range { min: Some(1), max: None },
                optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "D".into(), pattern: CandleType::Down,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let ws = WindowSize::Range { min: None, max: None };

        // "111100" = UUUUDD (6 bars: 4U + 2D)
        let open =  &[10.0, 10.0, 10.0, 10.0, 11.0, 11.0];
        let close = &[11.0, 11.0, 11.0, 11.0, 10.0, 10.0];
        let w = match_pattern(open, close, &blocks, ws, 0, 0, 6);

        eprintln!("U+Any*+U+Any*+D on 111100: {} partitions:", w.len());
        for (i, win) in w.iter().enumerate() {
            eprintln!("  [{},{}) U1@{} A1@{} U2@{} A2@{} D@{}",
                win.global_start, win.global_end,
                win.block_start("U1").unwrap(),
                win.block_start("A1").unwrap(),
                win.block_start("U2").unwrap(),
                win.block_start("A2").unwrap(),
                win.block_start("D").unwrap(),
            );
        }
        assert!(!w.is_empty(), "至少应有匹配");
    }

    /// U + Any* + D — 任意块无界，不应爆炸
    #[test]
    fn unbounded_any_block() {
        let blocks = vec![
            PatternBlock { block_name: "U".into(), pattern: CandleType::Up,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "Any".into(), pattern: CandleType::Any,
                block_size: WindowSize::Range { min: Some(1), max: None },
                optional: false, allow_overlap_next: false },
            PatternBlock { block_name: "D".into(), pattern: CandleType::Down,
                block_size: WindowSize::Exact(1), optional: false, allow_overlap_next: false },
        ];
        let ws = WindowSize::Range { min: None, max: None };

        // U + AAAAAA + D = 8 bars → 应该找到多个窗口: Any可以是1,2,...,6
        let n = 500; // 500 bars, Any块可达到~498
        let mut open = vec![0.0; n];
        let mut close = vec![0.0; n];
        open[0] = 10.0; close[0] = 11.0;     // U
        for i in 1..n-1 { open[i] = 10.0; close[i] = 11.0; } // Any (all U)
        open[n-1] = 11.0; close[n-1] = 10.0;  // D

        let t = std::time::Instant::now();
        let w = match_pattern(&open, &close, &blocks, ws, 0, 0, n);
        let ms = t.elapsed().as_secs_f64() * 1000.0;

        eprintln!("U+Any*+D on {n} bars: {} windows in {ms:.1}ms", w.len());
        assert!(!w.is_empty());
        assert!(ms < 50.0, "不应超过50ms, got {ms:.1}ms");
    }

    #[test]
    fn exact_window_size_must_match_effective_pattern_len() {
        // 用户 pipeline: Any*1 + Up*1 + Down*1 + Up*1 = 4 Exact(1) blocks
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
        // 构造数据: 4根bar正好匹配 Any/Up/Down/Up (N, U, D, U)
        let open = &[10.0, 10.0, 11.0, 10.0];
        let close = &[10.0, 11.0, 10.0, 11.0]; // N, U, D, U

        // Bug: Exact(120) 无法匹配4根bar的有效窗口
        let exact_120 = match_pattern(open, close, &blocks,
            WindowSize::Exact(120), 0, 0, 4);
        assert!(exact_120.is_empty(),
            "Exact(120) with 4 Exact(1) blocks should yield 0 matches (bug)");

        // Fix: Range允许4根bar匹配
        let range = match_pattern(open, close, &blocks,
            WindowSize::Range { min: Some(1), max: Some(120) }, 0, 0, 4);
        assert!(!range.is_empty(),
            "Range with 4 Exact(1) blocks should find matches (fix)");
        assert_eq!(range[0].global_start, 0);
        assert_eq!(range[0].global_end, 4);
    }
}
