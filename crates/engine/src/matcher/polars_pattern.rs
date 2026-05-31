//! Polars-native pattern matching via shift() expressions.
//!
//! Pattern blocks are defined in chronological order (old → new).
//! Matching direction is new → old: the newest bar matches the last block (offset 0),
//! then we step backward through older blocks.
//!
//! `Any*` blocks fill the remaining window space (after fixed blocks).
//! Multiple `Any*` blocks split the space → each split is a separate partition.

use std::collections::HashMap;

use anyhow::{bail, Result};
use kline_dsl::{CandleType, PatternBlock, WindowSize};
use polars::prelude::*;

// ── Public types ──────────────────────────────────────────────────────────

/// One partition (valid block-size assignment) with its Polars expression.
pub struct PartitionExpr {
    /// Size of each block in original order.
    pub sizes: Vec<usize>,
    /// Polars boolean expression for this partition.
    pub expr: polars::prelude::Expr,
    /// Effective window bar count.
    pub window_len: usize,
}

/// Compile a pattern into all valid partition expressions.
///
/// Returns `Err` when the pattern is too complex (unbounded Range with no
/// data-dependent cap); caller should fall back to DFS.
pub fn compile_partitions(
    blocks: &[PatternBlock],
    window_size: WindowSize,
) -> Result<Vec<PartitionExpr>> {
    let sizes_list = match window_size {
        WindowSize::Exact(w) => enumerate_partitions(blocks, w)?,
        WindowSize::Range { min, max } => {
            let mut all = Vec::new();
            let lo = min.unwrap_or(1).max(1);
            let hi = compute_range_max(blocks, max, lo);
            for w in lo..=hi {
                if let Ok(sizes) = enumerate_partitions(blocks, w) {
                    all.extend(sizes);
                }
            }
            if all.is_empty() {
                bail!("no valid partition for range window");
            }
            all
        }
    };

    let is_up = col("close").gt(col("open"));
    let is_down = col("close").lt(col("open"));
    let is_neutral = col("close").eq(col("open"));

    let mut results = Vec::with_capacity(sizes_list.len());
    for sizes in sizes_list {
        let (expr, wlen) =
            build_sized_expr(blocks, &sizes, &is_up, &is_down, &is_neutral)?;
        results.push(PartitionExpr { sizes, expr, window_len: wlen });
    }
    Ok(results)
}

/// Legacy: single OR'd expression (used by runner fallback path).
pub fn try_compile(
    blocks: &[PatternBlock],
    window_size: WindowSize,
) -> Result<(Expr, Option<usize>)> {
    let partitions = compile_partitions(blocks, window_size)?;
    let mut combined: Option<Expr> = None;
    for p in &partitions {
        combined = match combined {
            None => Some(p.expr.clone()),
            Some(e) => Some(e.or(p.expr.clone())),
        };
    }
    let expr = combined.unwrap_or_else(|| lit(true));
    let wlen = partitions.first().map(|p| p.window_len);
    Ok((expr, wlen))
}

// ── Range max helper ──────────────────────────────────────────────────────

fn compute_range_max(blocks: &[PatternBlock], max: Option<usize>, lo: usize) -> usize {
    let block_max: usize = blocks
        .iter()
        .map(|b| match b.block_size {
            WindowSize::Exact(n) => n,
            WindowSize::Range { max, .. } => max.unwrap_or(usize::MAX),
        })
        .sum();
    max.unwrap_or_else(|| block_max.min(500))
        .min(block_max)
        .max(lo)
}

// ── Partition enumeration ────────────────────────────────────────────────

// ── Effective window length (accounting for overlap) ────────────────────────

/// Compute the effective window bar-count for a given size assignment.
/// Each block with `allow_overlap_next` shares 1 bar with its successor,
/// so the total window is `sum(sizes) - count(overlaps)`.
fn effective_window_len(blocks: &[PatternBlock], sizes: &[usize]) -> usize {
    let mut total = 0usize;
    let mut prev_overlap = false;
    for (i, block) in blocks.iter().enumerate() {
        total += sizes[i];
        if prev_overlap {
            total = total.saturating_sub(1);
        }
        prev_overlap = block.allow_overlap_next;
    }
    total
}

/// Enumerate all valid block-size assignments whose effective length equals
/// `target_bars`.
fn enumerate_partitions(
    blocks: &[PatternBlock],
    target_bars: usize,
) -> Result<Vec<Vec<usize>>> {
    let mut range_indices: Vec<usize> = Vec::new();
    let mut range_bounds: Vec<(usize, usize)> = Vec::new();
    let mut current: Vec<usize> = vec![0; blocks.len()];

    for (i, block) in blocks.iter().enumerate() {
        match &block.block_size {
            WindowSize::Exact(n) => current[i] = *n,
            WindowSize::Range { min, max } => {
                range_indices.push(i);
                if block.pattern == CandleType::Any {
                    // `Any*` blocks fill remaining space. Can be 0 (empty).
                    let lo = min.unwrap_or(0);
                    let hi = max.unwrap_or(target_bars).min(target_bars);
                    range_bounds.push((lo, hi));
                } else {
                    let lo = min.unwrap_or(1).max(1);
                    let hi = max.unwrap_or(target_bars).min(target_bars);
                    range_bounds.push((lo, hi));
                }
            }
        }
    }

    if range_indices.is_empty() {
        let eff = effective_window_len(blocks, &current);
        if eff != target_bars {
            bail!("all-exact effective window {eff} != target {target_bars}");
        }
        return Ok(vec![current]);
    }

    const MAX_PARTITIONS: usize = 2000;
    let mut results = Vec::new();
    dfs_enumerate(blocks, &range_indices, &range_bounds, 0, target_bars, &mut current, &mut results);
    // Cap at MAX_PARTITIONS to prevent combinatorial explosion
    results.truncate(MAX_PARTITIONS);

    if results.is_empty() {
        bail!("no valid partition for effective window_size={target_bars}");
    }
    Ok(results)
}

fn dfs_enumerate(
    blocks: &[PatternBlock],
    range_indices: &[usize],
    range_bounds: &[(usize, usize)],
    pos: usize,
    target_bars: usize,
    current: &mut Vec<usize>,
    results: &mut Vec<Vec<usize>>,
) {
    dfs_enumerate_capped(blocks, range_indices, range_bounds, pos, target_bars, current, results, usize::MAX)
}

fn dfs_enumerate_capped(
    blocks: &[PatternBlock],
    range_indices: &[usize],
    range_bounds: &[(usize, usize)],
    pos: usize,
    target_bars: usize,
    current: &mut Vec<usize>,
    results: &mut Vec<Vec<usize>>,
    cap: usize,
) {
    if results.len() >= cap { return; }
    if pos >= range_indices.len() {
        if effective_window_len(blocks, current) == target_bars {
            results.push(current.clone());
        }
        return;
    }

    let idx = range_indices[pos];
    let (lo, hi) = range_bounds[pos];

    for s in lo..=hi {
        current[idx] = s;
        dfs_enumerate_capped(
            blocks, range_indices, range_bounds,
            pos + 1, target_bars, current, results, cap,
        );
        if results.len() >= cap { break; }
    }
}

// ── Expression builder ────────────────────────────────────────────────────

/// Build a Polars expression for a specific block-size assignment.
///
/// Blocks are in chronological order (old → new), so we iterate in reverse
/// (newest first), assigning shift offsets from 0 upward (going backward in time).
///
/// Returns `(expression, effective_window_bar_count)`.
fn build_sized_expr(
    blocks: &[PatternBlock],
    sizes: &[usize],
    is_up: &Expr,
    is_down: &Expr,
    is_neutral: &Expr,
) -> Result<(Expr, usize)> {
    let mut offset: i64 = 0; // start at newest bar (offset 0)
    let mut combined: Option<Expr> = None;

    // Walk blocks newest → oldest (chronological order reversed)
    for rev_idx in 0..blocks.len() {
        let block_idx = blocks.len() - 1 - rev_idx;
        let block = &blocks[block_idx];
        let size = sizes[block_idx];

        // Non-Any blocks require specific candle types at their offsets
        if block.pattern != CandleType::Any {
            for i in 0..size {
                let bar_offset = offset + i as i64;
                let candle =
                    candle_to_expr(block.pattern, bar_offset, is_up, is_down, is_neutral);
                combined = match combined {
                    None => Some(candle),
                    Some(e) => Some(e.and(candle)),
                };
            }
        }

        // Advance offset for the next (older) block.
        offset += size as i64;

        // If the NEXT older block has allow_overlap_next, it overlaps
        // with THIS block by 1 bar, so its start shifts left by 1.
        if block_idx > 0 {
            let older = &blocks[block_idx - 1];
            if older.allow_overlap_next {
                offset = (offset - 1).max(0);
            }
        }
    }

    let expr = combined.unwrap_or_else(|| lit(true));
    Ok((expr, offset as usize))
}

// ── Block range reconstruction ────────────────────────────────────────────

/// Compute the absolute row ranges for each named block, given the partition
/// sizes and the anchor row (window end).
///
/// Uses the same offset logic as `build_sized_expr`.
pub fn compute_block_ranges(
    blocks: &[PatternBlock],
    sizes: &[usize],
    anchor_row: usize,
) -> HashMap<String, (usize, usize)> {
    let mut ranges = HashMap::new();
    let mut offset: i64 = 0;

    // Walk blocks newest → oldest, same as build_sized_expr
    for rev_idx in 0..blocks.len() {
        let block_idx = blocks.len() - 1 - rev_idx;
        let block = &blocks[block_idx];
        let size = sizes[block_idx];

        if block.pattern != CandleType::Any {
            let start_abs = anchor_row.saturating_sub((offset + size as i64 - 1) as usize);
            let end_abs = anchor_row.saturating_sub(offset as usize) + 1;
            ranges.insert(block.block_name.clone(), (start_abs, end_abs));
        }

        offset += size as i64;
        if block_idx > 0 {
            let older = &blocks[block_idx - 1];
            if older.allow_overlap_next {
                offset = (offset - 1).max(0);
            }
        }
    }
    ranges
}

/// Emit a Polars expression for a single candle-type check at a given offset.
fn candle_to_expr(
    ct: CandleType,
    offset: i64,
    is_up: &Expr,
    is_down: &Expr,
    is_neutral: &Expr,
) -> Expr {
    let base = match ct {
        CandleType::Up => is_up.clone(),
        CandleType::Down => is_down.clone(),
        CandleType::Neutral | CandleType::Doji => is_neutral.clone(),
        CandleType::Any => return lit(true),
    };

    if offset == 0 {
        base
    } else {
        base.shift(lit(offset))
    }
}

// ── Helpers for extracting match windows from a boolean mask ─────────────

/// Given a boolean mask column and the window length, extract the row indices
/// where the mask is true.  Each row `i` in the result means a window
/// `[i - window_len + 1, i + 1)` matched.
pub fn collect_match_rows(mask: &BooleanChunked, window_len: usize) -> Vec<usize> {
    let n = mask.len();
    let mut rows = Vec::new();
    let start = window_len.saturating_sub(1);
    for i in start..n {
        if mask.get(i).unwrap_or(false) {
            // Only valid if window doesn't go before row 0
            if i >= window_len - 1 {
                rows.push(i);
            }
        }
    }
    rows
}

// ── Tests ─────────────────────────────────────────────────────────────────

#[cfg(test)]
mod tests {
    use super::*;
    use kline_dsl::{CandleType, PatternBlock, WindowSize};

    fn block(name: &str, ct: CandleType, size: WindowSize) -> PatternBlock {
        PatternBlock {
            block_name: name.into(),
            pattern: ct,
            block_size: size,
            optional: false,
            allow_overlap_next: false,
        }
    }

    fn exact(n: usize) -> WindowSize {
        WindowSize::Exact(n)
    }

    fn make_df(open: &[f64], close: &[f64]) -> DataFrame {
        df!(
            "open" => open.to_vec(),
            "close" => close.to_vec(),
        )
        .unwrap()
    }

    /// Evaluate the compiled expression on a DataFrame and return the boolean
    /// column.
    fn evaluate(blocks: &[PatternBlock], ws: WindowSize, df: &DataFrame) -> Vec<bool> {
        let (expr, _len) = try_compile(blocks, ws).unwrap();
        let result = df
            .clone()
            .lazy()
            .with_column(expr.alias("_match"))
            .collect()
            .unwrap();
        let mask = result
            .column("_match")
            .unwrap()
            .bool()
            .unwrap();
        (0..mask.len()).map(|i| mask.get(i).unwrap_or(false)).collect()
    }

    // ── Fixed-size patterns ───────────────────────────────────────────

    #[test]
    fn exact_udu_pattern() {
        // Pattern [U, D, U] chronological, new→old: U(offset 2)=U, D(offset 1)=D, U(offset 0)=U
        let blocks = vec![
            block("U1", CandleType::Up, exact(1)),
            block("D", CandleType::Down, exact(1)),
            block("U2", CandleType::Up, exact(1)),
        ];
        // Data: U U U D U (rows 0..4)
        // Expected: window [2,5) = rows {2=U, 3=D, 4=U} → match at row 4
        let df = make_df(
            &[10.0, 10.0, 10.0, 11.0, 10.0],
            &[11.0, 11.0, 11.0, 10.0, 11.0], // U U U D U
        );
        let mask = evaluate(&blocks, exact(3), &df);
        assert!(mask[4], "row 4 should match UDU window [2,5)");
        assert!(!mask[3], "row 3 should not match (last bar is D)");
    }

    #[test]
    fn exact_down_down_up_pattern() {
        // Pattern [D, D, U] chronological, new→old: U(offset 0), D(offset 1), D(offset 2)
        let blocks = vec![
            block("D1", CandleType::Down, exact(1)),
            block("D2", CandleType::Down, exact(1)),
            block("U", CandleType::Up, exact(1)),
        ];
        // Data: D D U D D U
        let df = make_df(
            &[11.0, 11.0, 10.0, 11.0, 11.0, 10.0],
            &[10.0, 10.0, 11.0, 10.0, 10.0, 11.0], // D D U D D U
        );
        let mask = evaluate(&blocks, exact(3), &df);
        assert!(mask[2], "row 2: D@0 D@1 U@2 → match");
        assert!(mask[5], "row 5: D@3 D@4 U@5 → match");
        assert!(!mask[3], "row 3: U@1 D@2 U@3 ✗");
    }

    #[test]
    fn exact_overlap_blocks() {
        // [Up{2, overlap}, Up{2}], total 3 bars
        let blocks = vec![
            PatternBlock {
                block_name: "A".into(),
                pattern: CandleType::Up,
                block_size: exact(2),
                optional: false,
                allow_overlap_next: true,
            },
            PatternBlock {
                block_name: "B".into(),
                pattern: CandleType::Up,
                block_size: exact(2),
                optional: false,
                allow_overlap_next: false,
            },
        ];
        // U U U → overlap A=[1,3) B=[0,2), window [0,3), match at row 2
        let df = make_df(&[10.0, 10.0, 10.0], &[11.0, 11.0, 11.0]);
        let mask = evaluate(&blocks, exact(3), &df);
        assert!(mask[2], "overlap U+U should match at row 2");
    }

    // ── Range patterns ────────────────────────────────────────────────

    #[test]
    fn range_down_range_up() {
        // [D{2,3}, U{1}] chronological, new→old: U(offset 0), D{2,3} at offsets 1..3
        let blocks = vec![
            block("Down", CandleType::Down, WindowSize::Range {
                min: Some(2), max: Some(3),
            }),
            block("Up", CandleType::Up, exact(1)),
        ];
        let df = make_df(
            &[10.0, 10.0, 11.0, 11.0, 10.0],
            &[11.0, 11.0, 10.0, 10.0, 11.0], // U U D D U
        );
        // window size 3: D{2}+U → D@3 D@4? No...
        // Actually let me think: rows U U D D U
        // Window=3: D at offset1-2 + U at offset0
        // Row 4: U@4 D@3 D@2 → D=2, U=1 ✓
        let mask = evaluate(&blocks, WindowSize::Range {
            min: Some(3), max: Some(4),
        }, &df);
        assert!(mask[4], "row 4: U D D matches [D{{2}},U] with window=3");
        // Row 3: D@3 D@2 U@1 → D=2, U=1 ✓ (window=3)
        // But row 3's match would be [1,4): U@1 D@2 D@3, with newest at 3 → U ✓
        // Up at offset 0 means row 3 should be U. Row 3 is D. So no match.
        assert!(!mask[3], "row 3 is D, can't be U at offset 0");
    }

    #[test]
    fn range_with_any_block() {
        // [D{1,2}, Any*, U] window=5
        let blocks = vec![
            block("D", CandleType::Down, WindowSize::Range {
                min: Some(1), max: Some(2),
            }),
            block("Any", CandleType::Any, WindowSize::Range {
                min: Some(1), max: None,
            }),
            block("U", CandleType::Up, exact(1)),
        ];
        // Data: D U U U U (row 0=D, 1..4=U)
        // window=5, partitions:
        //   D=1: Any=3, U=1 → D@offset4, Any@offsets1-3, U@offset0 → row4: U@4,U@3,U@2,U@1,D@0 ✓
        //   D=2: Any=2, U=1 → D@offset3-4, Any@offsets1-2, U@offset0
        let df = make_df(
            &[11.0, 10.0, 10.0, 10.0, 10.0],
            &[10.0, 11.0, 11.0, 11.0, 11.0], // D U U U U
        );
        let mask = evaluate(&blocks, exact(5), &df);
        assert!(mask[4], "D U U U U should match with D=1 Any=3 U=1");
    }

    #[test]
    fn exact_no_range_blocks() {
        // Single block: [U], window=1
        let blocks = vec![block("U", CandleType::Up, exact(1))];
        let df = make_df(
            &[10.0, 11.0, 10.0],
            &[11.0, 10.0, 11.0], // U D U
        );
        let mask = evaluate(&blocks, exact(1), &df);
        assert!(mask[0]);
        assert!(!mask[1]);
        assert!(mask[2]);
    }

    #[test]
    fn collect_match_rows_simple() {
        // 10 rows, window_len=3, mask true at rows 3 and 7
        let mask = BooleanChunked::from_iter(
            (0..10).map(|i| i == 3 || i == 7),
        );
        let rows = collect_match_rows(&mask, 3);
        assert_eq!(rows, vec![3, 7]);
    }

    #[test]
    fn collect_match_rows_skips_too_early() {
        // window_len=5 requires at least 4 preceding rows, so rows 0-3 can't match
        let mask = BooleanChunked::from_iter(
            (0..10).map(|i| i == 2 || i == 5),
        );
        let rows = collect_match_rows(&mask, 5);
        assert_eq!(rows, vec![5], "row 2 is too early for 5-bar window");
    }

    // ── Consistency: Polars vs DFS ────────────────────────────────────

    /// Run DFS match_pattern on raw slices and return set of window-end row indices.
    fn dfs_end_rows(
        blocks: &[PatternBlock],
        ws: WindowSize,
        open: &[f64],
        close: &[f64],
    ) -> std::collections::BTreeSet<usize> {
        // Use DFS fallback directly.  requested_end must be > max row to
        // avoid clipping valid windows (dfs_match uses it as exclusive upper bound).
        let n = open.len();
        let windows = crate::matcher::fallback::dfs_match(open, close, blocks, ws, 0, 0, n);
        windows
            .iter()
            .map(|w| w.global_end.saturating_sub(1))
            .collect()
    }

    /// Run Polars compile+evaluate and return set of window-end row indices.
    fn polars_end_rows(
        blocks: &[PatternBlock],
        ws: WindowSize,
        open: &[f64],
        close: &[f64],
    ) -> std::collections::BTreeSet<usize> {
        let df = make_df(open, close);
        let mask = evaluate(blocks, ws, &df);
        (0..open.len())
            .filter(|&i| mask[i])
            .collect()
    }

    #[test]
    fn consistency_exact_udu_vs_dfs() {
        let blocks = vec![
            block("U1", CandleType::Up, exact(1)),
            block("D", CandleType::Down, exact(1)),
            block("U2", CandleType::Up, exact(1)),
        ];
        let open = &[10.0, 10.0, 10.0, 11.0, 10.0];
        let close = &[11.0, 11.0, 11.0, 10.0, 11.0]; // U U U D U
        let dfs = dfs_end_rows(&blocks, exact(3), open, close);
        let polars = polars_end_rows(&blocks, exact(3), open, close);
        assert_eq!(dfs, polars, "UDU exact(3)");
    }

    #[test]
    fn consistency_exact_ddu_vs_dfs() {
        let blocks = vec![
            block("D1", CandleType::Down, exact(1)),
            block("D2", CandleType::Down, exact(1)),
            block("U", CandleType::Up, exact(1)),
        ];
        let open = &[11.0, 11.0, 10.0, 11.0, 11.0, 10.0];
        let close = &[10.0, 10.0, 11.0, 10.0, 10.0, 11.0]; // D D U D D U
        let dfs = dfs_end_rows(&blocks, exact(3), open, close);
        let polars = polars_end_rows(&blocks, exact(3), open, close);
        assert_eq!(dfs, polars, "DDU exact(3)");
    }

    #[test]
    fn consistency_overlap_vs_dfs() {
        let blocks = vec![
            PatternBlock {
                block_name: "A".into(), pattern: CandleType::Up,
                block_size: exact(2), optional: false,
                allow_overlap_next: true,
            },
            PatternBlock {
                block_name: "B".into(), pattern: CandleType::Up,
                block_size: exact(2), optional: false,
                allow_overlap_next: false,
            },
        ];
        let open = &[10.0, 10.0, 10.0, 10.0];
        let close = &[11.0, 11.0, 11.0, 11.0]; // U U U U
        let dfs = dfs_end_rows(&blocks, exact(3), open, close);
        let polars = polars_end_rows(&blocks, exact(3), open, close);
        assert_eq!(dfs, polars, "overlap Up+Up exact(3)");
    }

    #[test]
    fn consistency_range_down_plus_up_vs_dfs() {
        let blocks = vec![
            block("Down", CandleType::Down, WindowSize::Range { min: Some(2), max: Some(3) }),
            block("Up", CandleType::Up, exact(1)),
        ];
        // 1110 = UUU D → windows with D ending
        let open = &[10.0, 10.0, 10.0, 11.0];
        let close = &[11.0, 11.0, 11.0, 10.0]; // U U U D
        let ws = WindowSize::Range { min: Some(3), max: Some(4) };
        let dfs = dfs_end_rows(&blocks, ws, open, close);
        let polars = polars_end_rows(&blocks, ws, open, close);
        assert_eq!(dfs, polars, "D{{2,3}} U range");
    }

    #[test]
    fn consistency_random_exact() {
        use rand::Rng;
        let mut rng = rand::thread_rng();
        let n = 20;
        let open: Vec<f64> = (0..n).map(|_| rng.gen_range(9.0..11.0)).collect();
        let close: Vec<f64> = (0..n).map(|_| rng.gen_range(9.0..11.0)).collect();

        let blocks = vec![
            block("a", CandleType::Down, exact(1)),
            block("b", CandleType::Up, exact(2)),
        ];
        let dfs = dfs_end_rows(&blocks, exact(3), &open, &close);
        let polars = polars_end_rows(&blocks, exact(3), &open, &close);
        assert_eq!(dfs, polars, "random D+UU exact(3)");
    }

    // ── Any* fill-space semantics ────────────────────────────────────

    fn any_star() -> WindowSize {
        WindowSize::Range { min: None, max: None }
    }

    /// Evaluate per-partition at a specific anchor row, returning block_ranges.
    fn partition_matches_at(
        blocks: &[PatternBlock],
        ws: WindowSize,
        df: &DataFrame,
        anchor_row: usize,
    ) -> Vec<HashMap<String, (usize, usize)>> {
        let partitions = compile_partitions(blocks, ws).unwrap();
        let df2 = {
            let mut lf = df.clone().lazy();
            for (i, p) in partitions.iter().enumerate() {
                lf = lf.with_column(p.expr.clone().alias(format!("_p{i}")));
            }
            lf.collect().unwrap()
        };
        let mut matches = Vec::new();
        for (i, p) in partitions.iter().enumerate() {
            let mask = df2.column(&format!("_p{i}")).unwrap().bool().unwrap();
            if mask.get(anchor_row).unwrap_or(false) {
                matches.push(compute_block_ranges(blocks, &p.sizes, anchor_row));
            }
        }
        matches
    }

    #[test]
    fn any_fill_single() {
        // [D, Any*, U] window=4: D at oldest, U newest, Any fills 2 in between
        let blocks = vec![
            block("D", CandleType::Down, exact(1)),
            block("A", CandleType::Any, any_star()),
            block("U", CandleType::Up, exact(1)),
        ];
        // Data: D U U U (row 0=D, 1-3=U) → window [0,4): D@0 Any@1-2 U@3
        let df = make_df(
            &[11.0, 10.0, 10.0, 10.0],
            &[10.0, 11.0, 11.0, 11.0], // D U U U
        );
        let matches = partition_matches_at(&blocks, exact(4), &df, 3);
        assert_eq!(matches.len(), 1, "D Any* U window=4 on D U U U should match");
        let br = &matches[0];
        assert_eq!(br.get("D"), Some(&(0, 1)), "D block at row 0");
        assert_eq!(br.get("U"), Some(&(3, 4)), "U block at row 3");
        // Any* block not in block_ranges
        assert!(!br.contains_key("A"));
    }

    #[test]
    fn any_fill_single_not_match() {
        let blocks = vec![
            block("D", CandleType::Down, exact(1)),
            block("A", CandleType::Any, any_star()),
            block("U", CandleType::Up, exact(1)),
        ];
        // Data: U U U U → oldest bar is U, not D → no match
        let df = make_df(&[10.0; 4], &[11.0; 4]);
        let matches = partition_matches_at(&blocks, exact(4), &df, 3);
        assert!(matches.is_empty());
    }

    #[test]
    fn any_fill_multiple_any_blocks() {
        // [D, Any*, U, Any*, U] window=5
        // Fixed: D(1) + U(1) + U(1) = 3. Any* × 2 share remaining 2.
        // Partitions: (0,2), (1,1), (2,0) for the two Any* blocks
        let blocks = vec![
            block("D", CandleType::Down, exact(1)),
            block("A1", CandleType::Any, any_star()),
            block("U1", CandleType::Up, exact(1)),
            block("A2", CandleType::Any, any_star()),
            block("U2", CandleType::Up, exact(1)),
        ];
        // D U U U U → D@0, Any1=0, U1@1, Any2=2, U2@3..5?
        // Actually: U1 at offset ?, let me compute:
        // reversed: U2@[0,1) U1@[1+?, ...
        // Simpler: D U U U U, 5 bars, exact 5.
        // Partition (Any1=0, Any2=2): U2@0, A2@[1,3), U1@3, A1=none, D@4
        //   → check: U@4 D@3 U@0? No...
        // Let me just test: the data is D U U U U (row0=D, rows1-4=U)
        let df = make_df(
            &[11.0, 10.0, 10.0, 10.0, 10.0],
            &[10.0, 11.0, 11.0, 11.0, 11.0], // D U U U U
        );
        // window=5, anchor_row=4
        let matches = partition_matches_at(&blocks, exact(5), &df, 4);
        // Should have multiple partitions matching
        assert!(!matches.is_empty(), "D U+U+U should match some partition");
        // Every match should have D at row 0
        for m in &matches {
            assert_eq!(m.get("D"), Some(&(0, 1)), "D always at oldest bar");
        }
    }

    #[test]
    fn any_fill_leading_and_trailing() {
        // [Any*, D, Any*, U, Any*] window=6
        // Two fixed (D, U), three Any* share remaining 4
        let blocks = vec![
            block("A0", CandleType::Any, any_star()),
            block("D", CandleType::Down, exact(1)),
            block("A1", CandleType::Any, any_star()),
            block("U", CandleType::Up, exact(1)),
            block("A2", CandleType::Any, any_star()),
        ];
        // U U D U U U → D@2, U@3
        let df = make_df(
            &[10.0, 10.0, 11.0, 10.0, 10.0, 10.0],
            &[11.0, 11.0, 10.0, 11.0, 11.0, 11.0], // U U D U U U
        );
        // window=6, anchor_row=5
        let matches = partition_matches_at(&blocks, exact(6), &df, 5);
        // At least one partition should match (A0=2, A1=0, A2=2 → D@3, U@2... wait)
        assert!(!matches.is_empty(), "U U D U U U should match D+U with fill");
    }

    #[test]
    fn block_ranges_offset_correct() {
        let blocks = vec![
            block("D", CandleType::Down, exact(2)),
            block("U", CandleType::Up, exact(1)),
        ];
        let df = make_df(
            &[11.0, 11.0, 10.0],
            &[10.0, 10.0, 11.0],
        );
        let matches = partition_matches_at(&blocks, exact(3), &df, 2);
        assert_eq!(matches.len(), 1);
        let br = &matches[0];
        assert_eq!(br.get("D"), Some(&(0, 2)));
        assert_eq!(br.get("U"), Some(&(2, 3)));
    }

    // ── Realistic screening scenarios ──────────────────────────────

    /// 阴跌反转：最近 5 根 bar 内，开头有 1-2 根阴线，末尾是阳线，中间任意。
    /// DSL: window=5, pattern=[阴{1,2}, 任意*, 阳]
    #[test]
    fn scenario_bearish_reversal() {
        let blocks = vec![
            block("D", CandleType::Down, WindowSize::Range { min: Some(1), max: Some(2) }),
            block("A", CandleType::Any, any_star()),
            block("U", CandleType::Up, exact(1)),
        ];
        // D U D D U: D=1@row0, D=2@rows0-1←但row1=U所以D=2不匹配。只D=1匹配。
        let df = make_df(
            &[11.0, 10.0, 11.0, 11.0, 10.0],
            &[10.0, 11.0, 10.0, 10.0, 11.0], // D U D D U
        );
        let matches = partition_matches_at(&blocks, exact(5), &df, 4);
        // D=1: row4=U✓ row0=D✓ → match
        // D=2: need rows0-1 both D but row1=U → no match
        assert_eq!(matches.len(), 1, "only D=1 partition matches");
    }

    /// 放量阳包阴：阳线吞噬前一根阴线，且成交量放大。
    /// 形态部分：window=2, pattern=[阴, 阳]
    /// 条件部分（不在本测试）：volume > volume.shift(1)
    #[test]
    fn scenario_bullish_engulfing_pattern() {
        let blocks = vec![
            block("D", CandleType::Down, exact(1)),
            block("U", CandleType::Up, exact(1)),
        ];
        // D U → match at row 1
        let df = make_df(
            &[11.0, 10.0],
            &[10.0, 11.0],
        );
        let matches = partition_matches_at(&blocks, exact(2), &df, 1);
        assert_eq!(matches.len(), 1);
    }

    /// 三连阳突破：window=5, pattern=[任意*, 阳{3}, 任意*]
    /// 在 5 根 bar 的窗口内，存在连续 3 根阳线。
    #[test]
    fn scenario_three_white_soldiers() {
        let blocks = vec![
            block("A1", CandleType::Any, any_star()),
            block("U3", CandleType::Up, exact(3)),
            block("A2", CandleType::Any, any_star()),
        ];
        // U D U U U → U at rows 2,3,4 = 3 consecutive U
        let df = make_df(
            &[10.0, 11.0, 10.0, 10.0, 10.0],
            &[11.0, 10.0, 11.0, 11.0, 11.0], // U D U U U
        );
        let matches = partition_matches_at(&blocks, exact(5), &df, 4);
        assert!(!matches.is_empty(), "should find 3 consecutive U");
    }

    /// 窗口内出现至少一根十字星+一根阳线（Any* 隔开）。
    /// window=4, pattern=[十字, 任意*, 阳]
    #[test]
    fn scenario_doji_then_up() {
        let blocks = vec![
            block("Doji", CandleType::Neutral, exact(1)),
            block("A", CandleType::Any, any_star()),
            block("U", CandleType::Up, exact(1)),
        ];
        // 平 D D U → row0=平(doji), Any@1-2, U@3
        let df = make_df(
            &[10.0, 11.0, 11.0, 10.0],
            &[10.0, 10.0, 10.0, 11.0], // 平 D D U
        );
        let matches = partition_matches_at(&blocks, exact(4), &df, 3);
        assert!(!matches.is_empty());
    }

    /// 大窗口多 Any*：window=20, pattern=[阴, 任意*, 阳, 任意*, 阳, 任意*, 阳]
    /// 四个固定块 + 三个 Any*，验证枚举不爆炸且能正确匹配。
    #[test]
    fn scenario_large_window_multi_any() {
        let blocks = vec![
            block("D1", CandleType::Down, exact(1)),
            block("A1", CandleType::Any, any_star()),
            block("U1", CandleType::Up, exact(1)),
            block("A2", CandleType::Any, any_star()),
            block("U2", CandleType::Up, exact(1)),
            block("A3", CandleType::Any, any_star()),
            block("U3", CandleType::Up, exact(1)),
        ];
        // 20 bars: all U except row 0 = D
        let n = 20;
        let mut open = vec![10.0; n];
        let mut close = vec![11.0; n];
        open[0] = 11.0; close[0] = 10.0; // row 0 = D
        let df = make_df(&open, &close);
        // window=20, anchor=19
        let matches = partition_matches_at(&blocks, exact(20), &df, 19);
        assert!(!matches.is_empty(), "D + 任意*×3 + U×3 window=20 should match");
        // Each match should have D at row 0 and U3 at row 19
        for m in &matches {
            assert_eq!(m.get("D1"), Some(&(0, 1)));
            assert_eq!(m.get("U3"), Some(&(19, 20)));
        }
    }
}
