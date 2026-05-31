# Design Decisions

This document explains the key engineering choices behind the screener DSL and engine. Written for internship reviewers who want to understand the *why*, not just the *what*.

## 1. Why Polars over Iterative Evaluation?

**Problem**: Screening 5000+ stocks through multi-condition pipelines is compute-intensive. Per-symbol, row-by-row evaluation in Rust would require nested loops and kill cache locality.

**Decision**: Compile DSL conditions to Polars lazy expressions and execute them as vectorized column operations.

**Tradeoffs**:

| Approach | 5000 stocks, 250 days | Memory | Code complexity |
|----------|----------------------|--------|-----------------|
| Iterative (per-row) | ~30s | Low | Simple |
| Polars batch | ~0.5s | Moderate (DataFrame per stock) | Compiler needed |
| Polars grouped | ~0.1s | Higher (single giant DataFrame) | Complex join logic |

We chose **batch-first with grouped optimization**. The engine first attempts a fully vectorized path (all stocks in one DataFrame with group_by). When that fails (complex patterns, cross-stock references), it falls back to per-symbol Polars execution. When even that fails, it falls back to the row-by-row interpreter.

**Result**: Common screening strategies (SMA crossover, volume spikes, Bollinger Bands) process 5000 stocks in under 200ms on a laptop.

## 2. Why a Typed AST over a String DSL?

**Problem**: Stock screening strategies have deeply nested logic (if A then B, and for all candles in range C, D holds). String-based DSLs require parser maintenance, have cryptic error messages, and lack IDE support.

**Decision**: Define the strategy language as Rust types (`Expr` enum with 25+ variants) that serialize to/from JSON.

**Tradeoffs**:

| Approach | Type safety | IDE support | Serialization | Human readability |
|----------|------------|-------------|---------------|-------------------|
| String DSL | None | None | Manual parser | Best |
| Typed AST (Rust) | Full | Full (rust-analyzer) | Free (serde) | Good (builder API) |
| JSON-only | None | None | Free | Verbose |

We chose the typed AST because:
- **serde** gives us JSON serialization for free — the Flutter UI sends JSON, Rust deserializes it
- **Builder patterns** (`Expr::gt()`, `PathExpr::window_end(0).col("close")`) make Rust-side construction ergonomic
- **Exhaustive matching** catches missing condition handlers at compile time
- The Flutter side parses JSON into identical Dart model classes, so the JSON format serves as the wire protocol

The JSON format is intentionally verbose to be self-documenting. A strategy editor UI in Flutter produces it; humans rarely write it by hand.

## 3. Why Dual-Path Evaluation (Compiler + Interpreter)?

**Problem**: Polars expressions can handle 90% of screening conditions efficiently (numeric comparisons, rolling windows, boolean logic). But 10% of conditions need state-machine evaluation that Polars can't express: sequential pattern matching ("3 consecutive up days where each close is higher than the previous"), cross-stock references ("current stock up, market index down"), or intraday minute-by-minute predicates.

**Decision**: Compile what we can to Polars; interpret the rest.

The compiler path (`expr_compiler.rs`):
```
DSL Expr → Polars Expr (lazy) → with_column → filter mask
```

The interpreter path (`evaluator/`):
```
DSL Expr → EvalCtx { df, date_index, window } → row-by-row bool
```

The engine tries compilation first. If `try_compile_condition()` returns `None` (unsupported expression), the condition runs through the evaluator. This is transparent to the pipeline author.

**Key insight**: The compiler and interpreter share the same AST. No translation layer needed. A condition either compiles or it doesn't, and the engine handles both paths.

## 4. Why a `DataProvider` Trait?

**Problem**: The engine needs historical K-line data to evaluate conditions. But data sources vary: Parquet files (this repo), TDX protocol (private repo), databases, CSV files.

**Decision**: Define an abstract `DataProvider` trait that the engine depends on, with concrete implementations provided by the host application.

```rust
pub trait DataProvider: Send + Sync {
    fn kline(&self, symbol: &str, tf: Timeframe, from: NaiveDate, to: NaiveDate) -> LazyFrame;
    fn intraday(&self, symbol: &str, date: NaiveDate) -> LazyFrame;
    fn market_index(&self, symbol: &str) -> String;
}
```

**Benefits**:
- The engine crate has **zero dependencies on any specific data source**
- Testing is trivial: inject a provider backed by sample Parquet files
- The private repo swaps in a TDX-backed provider without changing a line of engine code
- Users of this public repo can implement their own provider (CSV, database, web API)

This is standard dependency inversion — the kind of abstraction that separates a library from a script.

## 5. Why Batch-First, Per-Symbol Fallback?

**Problem**: The fastest execution path (single DataFrame with `group_by`) doesn't work for all pipelines. Complex patterns with variable-length windows or cross-stock references need per-symbol processing.

**Decision**: Three-tier execution strategy:

```
Tier 1: try_run_batch_grouped()     ← all stocks in one LazyFrame, group_by market+code
  ↓ fails
Tier 2: try_run_batch_df()          ← per-symbol LazyFrame, Polars compilation
  ↓ fails
Tier 3: run_pipeline()              ← per-symbol row-by-row interpreter
```

**Tier 1** is the fastest path. It loads all stocks into a single DataFrame, adds indicator columns, compiles conditions to boolean masks, and filters. With Polars lazy evaluation, the entire pipeline is a single optimized query plan. This works for ~80% of practical screening strategies.

**Tier 2** handles pipelines where group_by is problematic (certain windowing patterns, complex joins). Each stock gets its own DataFrame, but conditions still compile to vectorized Polars expressions.

**Tier 3** is the escape hatch. Row-by-row evaluation for conditions that Polars can't express (stateful patterns, cross-stock references). Slow but correct.

The engine tries tiers in order and falls back transparently. The pipeline author doesn't need to know which tier will execute their strategy.

## 6. Why `std::thread::scope` for Multi-Day Scans?

The screener scan runs the same pipeline across hundreds of trading days. This is embarrassingly parallel — each day is independent.

**Decision**: Use `std::thread::scope` (safe scoped threads) instead of `rayon` or `tokio`.

**Why not rayon?** Rayon is great for data parallelism (parallel iterators) but less ergonomic for task parallelism where each task has different setup (JSON deserialization, date parsing, provider initialization).

**Why not tokio?** The engine is CPU-bound, not I/O-bound. Async adds complexity without benefit here.

**Why scoped threads?** The child threads can safely reference the parent's stack (date strings, pipeline template, registry JSON) without `Arc` cloning. The `scope` call blocks until all threads complete, which is exactly what we want for a CLI tool.

## 7. Why Parquet for Historical Data?

The private repo stores 35 years of daily K-line data. Storage format matters at this scale.

**Why Parquet?**
- **Columnar**: screening queries typically read 3-4 columns (close, volume, date) out of 9 — Parquet reads only those columns
- **Compression**: zstd compression reduces 322MB of raw data to ~160MB
- **Predicate pushdown**: Polars pushes date range filters into the Parquet reader, skipping entire row groups
- **Zero-copy with Polars**: Parquet → Polars DataFrame is a direct path, no intermediate format

The `ParquetDataProvider` in this repo organizes data as `klines/YYYY.parquet` — one file per year. This is a deliberate tradeoff: per-year partitioning balances file count (36 files for 35 years) with query efficiency (a typical screening scans 1-3 years).

## 8. Why Not Use an Off-the-Shelf Expression Language?

Alternatives considered:

| Tool | Why not |
|------|---------|
| CEL (Common Expression Language) | No Polars integration; designed for protobuf/services, not dataframes |
| PRQL | Compiles to SQL, not Polars; no pattern matching primitives |
| Python `eval()` | Not type-safe; slow; dependency nightmare for a Rust library |
| Custom PEG parser | Maintenance burden; the AST is the right abstraction level |

The DSL is genuinely domain-specific — candlestick patterns, rolling windows with named anchors, intraday minute predicates, cross-stock references. These concepts don't exist in general-purpose expression languages. Building a typed AST was less code than shimming a general tool into a domain it wasn't designed for.

## 9. Flutter: Why Custom Canvas Painters?

The K-line and minute charts in `flutter-screener-ui/lib/widgets/` use Flutter's `CustomPainter` API rather than a charting library.

**Why not `fl_chart` or `syncfusion`?**
- K-line charts (candlestick + volume + MA overlays) are not standard chart types
- Performance: 500+ visible candles need efficient incremental repaint during zoom/pan
- Crosshair synchronization between price and volume panes needs custom hit testing
- Existing libraries don't support the specific interaction model (drag to pan, scroll to zoom, tap for crosshair)

The tradeoff is more code (~500 lines per chart) but full control over rendering and interaction. For a financial terminal, this control is worth the cost.
