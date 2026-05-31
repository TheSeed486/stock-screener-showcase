# Flutter Screener UI (Source Showcase)

This directory contains the Flutter/Dart source code for the screener UI, extracted from the private stock trading terminal.

## Why Source-Only?

These files depend on `flutter_rust_bridge` codegen output (`lib/src/rust/api/screener.dart`) which binds to the private Rust host crate. Without the Rust backend and FRB codegen, the Flutter code cannot build or run independently.

The source code is included here for **code review purposes** — to demonstrate Flutter/Dart proficiency.

## What's Here

### `features/screener_v2/` (13 files)
- **`widgets/expr_builder.dart`** — Recursive formula tree editor with drag-drop parameter binding. Converts visual tree nodes to `ExprNode` AST, then compiles to JSON for Rust execution.
- **`widgets/custom_indicator_editor.dart`** — Custom indicator definition UI with formula composition.
- **`widgets/condition_card.dart`** — Individual condition display/edit card with status indicators.
- **`compiler/pipeline_compiler.dart`** — Compiles `StageModel` (Flutter-side model) to Pipeline JSON consumed by Rust.
- **`compiler/expr_compiler.dart`** — Compiles `ExprNode` tree to expression JSON.
- **`models/`** — Dart model classes mirroring the Rust DSL types (`ExprNode`, `PathRef`, `IndicatorModel`, `StageModel`, `PatternModel`).

### `features/screener/` (7 files)
- Original V1 screener with condition editor and results table.

### `widgets/` (4 files)
- **`kline_chart/animated_kline_chart_painters.dart`** — Custom Canvas painter for candlestick charts with MA overlays.
- **`kline_chart/animated_kline_chart_models.dart`** — Data models for K-line rendering.
- **`minute_chart/minute_time_chart_painters.dart`** — Custom Canvas painter for minute-by-minute time-series.
- **`minute_chart/minute_time_chart_models.dart`** — Data models for minute chart rendering.

## Screenshots

See `docs/screenshots/` in the repository root for screenshots of the running application.
