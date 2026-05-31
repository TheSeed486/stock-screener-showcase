# Screener DSL

## Scope

This document describes the current expression-layer DSL only.

It does **not** define the full future screener system.

The full architecture is split into:

1. point-command / anchor resolution
2. expression compilation
3. structured ruleset orchestration
4. lazy execution and short-circuit rejection

See `SCREENER_RULE_ENGINE.md` for the full engine design.

## Goal

Build the current expression layer as:

1. `DSL source`
2. `Rust parser + validator`
3. `Polars LazyFrame plan`
4. `Collect ranked matches`

The backend is Polars-based. Flutter should only edit/view screen definitions and render results.

At this layer, the job is:

- parse reusable numeric/boolean expressions
- validate fields and builtins
- compile expressions into Polars expressions
- support plan inspection and later execution

At this layer, the job is **not**:

- define point commands like `A / A0 / Bm / Rn`
- express multi-phase `reject / accept / waive / relabel` rule flows
- encode daily-first / minute-lazy orchestration
- model strategy-specific anchor semantics

## Execution Model

### Data flow

1. Resolve `universe` and `timeframe`
2. Load the required snapshot/window from DuckDB into a Polars `DataFrame`
3. Add derived columns from `let`
4. Combine every `filter` into one final predicate
5. Apply `sort` and `limit`
6. Collect final matches

### Important semantic rule

All `filter` clauses must be evaluated against the same original series state.

Do **not** apply filters one by one to the already-filtered rows when the expression uses:

- rolling windows
- shifted references like `close[1]`
- cross conditions
- window functions like `count(...)`

The implementation in `rust/src/api/screener.rs` therefore combines filter expressions first and runs a single final `LazyFrame::filter(...)`.

## DSL Shape

```text
screen breakout_scan {
  universe all_a;
  timeframe daily;
  let ma20 = sma(close, 20);
  let ma60 = sma(close, 60);
  filter cross_up(close, ma20);
  filter ma20 > ma60;
  filter volume > sma(volume, 5) * 1.8;
  sort by close desc;
  limit 100;
}
```

## Expression Features

### Core

- arithmetic: `+ - * /`
- comparison: `> >= < <= == !=`
- logic: `and or not`
- series offset: `close[1]`
- reusable bindings: `let`

### Builtins backed by Polars today

- `abs`
- `shift`
- `sma`
- `ema`
- `highest`
- `lowest`
- `stddev`
- `sum`
- `count`
- `every`
- `any`
- `bars_since`
- `cross_up`
- `cross_down`
- `rank`
- `bullish_engulfing`
- `bearish_engulfing`
- `gap_up`
- `gap_down`

### V1 semantics worth locking in

- `ema(series, window)`
  - implemented with Polars `ewm_mean`
  - uses `adjust = false`
  - uses `min_periods = window` for consistency with the other window indicators
- `sum(series, window)`
  - rolling window sum
- `bars_since(condition)`
  - returns the number of bars since the last `true`
  - rows before the first `true` are treated as not-ready and will not accidentally pass small-threshold filters
- `rank(series)`
  - dense descending rank over the current frame
  - for inverse ranking, use arithmetic such as `rank(-turnover)`

### Builtin fields today

- `open`
- `high`
- `low`
- `close`
- `volume`
- `amount`
- `pct_change`
- `amplitude`
- `turnover`

## Why Polars

Polars is the right execution layer for the screener module because it gives us:

- vectorized column expressions
- rolling/window operators
- lazy optimization before execution
- a clean bridge from DuckDB snapshots into in-memory factor calculations

DuckDB remains the storage layer. Polars becomes the calculation and screening layer.

## Near-Term Next Steps

1. Add the anchor resolver layer so internal point commands become first-class engine objects.
2. Add a structured ruleset schema for `reject / accept / waive / relabel` and phased execution.
3. Add DuckDB -> Arrow -> Polars loaders for daily and minute screener datasets.
4. Add result payload types and execution APIs so Flutter can fetch actual matches, not only validate/explain the DSL.
5. Add more indicators:
   `rsi`, `macd`, `atr`, `boll`
6. Add watchlist/custom-universe support.
7. Add cached compiled screen definitions and execution benchmarks.
