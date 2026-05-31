# Stock Screener DSL & Engine

[English](#english) | [中文](#chinese)

---

<a name="english"></a>
## English

A **domain-specific language (DSL)** and **Polars-based execution engine** for stock screening strategies, with a **Flutter formula-tree editor** for interactive strategy building.

This is a curated subset of a larger private stock trading terminal. The full application includes real-time market data, K-line charts, watchlists, and backtesting — powered by a proprietary data source. This public repo showcases the screener subsystem: the DSL, the engine, and the Flutter UI.

### What's Inside

| Component | Description | Runnable |
|-----------|-------------|----------|
| **`kline-dsl`** (Rust) | Typed AST: 25+ expression types, candlestick patterns, indicators, intraday conditions | `cargo build` |
| **`kline-engine`** (Rust) | Polars-based batch execution, multi-threaded runner, pattern matcher, compiler/evaluator dual-path | `cargo build` |
| **CLI Demo** | 4 screening strategies run against sample data | `cargo run --example cli_demo` |
| **Flutter UI** (Dart) | Recursive formula tree editor, K-line/minute chart canvas painters, results table | source showcase only |

### Quick Start (Rust CLI)

```bash
git clone https://github.com/<user>/stock-screener-showcase.git
cd stock-screener-showcase

# Run the CLI demo (uses included sample data)
STOCK_DB_DIR=./sample_data cargo run --example cli_demo

# Run all tests
cargo test --workspace
```

### Example: SMA Crossover Strategy

Define a screening pipeline in Rust:

```rust
let stage = Stage {
    name: "above_sma20".into(),
    indicators: vec![IndicatorCall::new("sma", params! {"period" => 20})],
    conditions: vec![(
        "above_sma20".into(),
        Expr::Gt(Box::new(col("close", 0)), Box::new(col("sma_20", 0))),
    )],
    // ...
};
let pipeline = Pipeline { stages: vec![stage] };
let df = run_pipeline_df(&pipeline, &registry, &provider, &symbols, from, to, None);
```

Or define the same strategy as JSON (the Flutter UI compiles to this):

```json
{
  "stages": [{
    "name": "above_sma20",
    "prepare": { "indicators": [{ "module_id": "sma", "params": { "period": 20 } }] },
    "conditions": {
      "above_sma20": { "Gt": [{ "Path": { "field": "close" } }, { "Path": { "field": "sma_20" } }] }
    }
  }]
}
```

### Architecture

```
┌──────────────────────────────────────┐
│  Flutter UI (formula tree editor)    │  ── source showcase
├──────────────────────────────────────┤
│  kline-dsl (AST: Expr, Pipeline)     │  ── public crate
├──────────────────────────────────────┤
│  kline-engine (compiler, runner)     │  ── public crate
│  ┌────────────────────────────────┐  │
│  │ DataProvider trait (abstract)  │  │
│  │ ParquetDataProvider (concrete) │  │
│  └────────────────────────────────┘  │
├──────────────────────────────────────┤
│  Private: TDX data source, FRB host  │  ── not in this repo
└──────────────────────────────────────┘
```

### Screenshots (from the private full application)

<p align="center">
  <img src="docs/screenshots/筛选条件.png" width="30%" alt="Screener Builder" />
  <img src="docs/screenshots/筛选结果.png" width="30%" alt="Results" />
  <img src="docs/screenshots/市场页.png" width="30%" alt="Market" />
</p>
<p align="center">
  <img src="docs/screenshots/个股页.png" width="30%" alt="K-line Chart" />
  <img src="docs/screenshots/分时页.png" width="30%" alt="Minute Chart" />
  <img src="docs/screenshots/自选页.png" width="30%" alt="Watchlist" />
</p>

### Key Design Decisions

See [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md) for detailed rationale on:

- **Polars over iterative evaluation** — vectorized batch execution processes 5000+ stocks in seconds
- **Typed AST over string DSL** — compile-time safety, IDE support, serializable to JSON
- **Dual-path evaluation** — Polars path for numeric conditions, interpreter fallback for complex pattern matching
- **`DataProvider` trait** — separates strategy logic from data sourcing (Parquet in this repo, TDX protocol in private)
- **Batch-first, per-symbol fallback** — fastest path for most conditions, graceful degradation for edge cases

### What's NOT in This Repo

The private repository additionally contains:

- **TDX protocol implementation** (`tdx_api/`) — low-level TCP binary protocol for Chinese A-share market data
- **FRB host crate** (`rust/`) — Flutter-Rust bridge, data fetching, caching, storage
- **Full Flutter app** — market overview, stock detail with K-line charts, watchlist management, backtesting
- **Real market data** — 35 years of A-share daily/minute/tick data

See [ARCHITECTURE.md](ARCHITECTURE.md) for the full system design.

### Flutter UI (Source Showcase)

The `flutter-screener-ui/` directory contains the Flutter source for:

- **Recursive formula tree editor** (`expr_builder.dart`) — visual editor for nested `Expr` AST nodes with drag-drop parameter binding
- **K-line chart painters** (`animated_kline_chart_painters.dart`) — custom Canvas renderer with zoom, pan, crosshair
- **Minute chart painters** (`minute_time_chart_painters.dart`) — time-series chart with bid/ask visualization
- **Pipeline compiler** — compiles the visual formula tree to JSON for Rust execution

These files demonstrate Flutter proficiency but cannot be built standalone (they depend on `flutter_rust_bridge` codegen from the private Rust host crate).

### Tech Stack

- **Rust**: Polars 0.53, Rayon, serde, chrono, rusqlite
- **Flutter/Dart**: Custom Canvas painters, Riverpod-like ViewModels, `data_table_2`
- **Bridge**: `flutter_rust_bridge` v2.11 (private repo)
- **Data**: Parquet (via Polars), SQLite metadata catalog

---

<a name="chinese"></a>
## 中文

一个用于股票筛选策略的**领域特定语言（DSL）**和**基于 Polars 的执行引擎**，配备 **Flutter 公式树编辑器**进行交互式策略构建。

这是完整私有股票交易终端的精选子集。完整应用包含实时行情、K线图、自选股、回测等功能——由专有数据源驱动。本公开仓库展示筛选器子系统：DSL、引擎、Flutter UI。

### 内容概览

| 组件 | 说明 | 可运行 |
|------|------|--------|
| **`kline-dsl`** (Rust) | 类型化 AST：25+ 表达式类型、K线形态、指标、分时条件 | `cargo build` |
| **`kline-engine`** (Rust) | Polars 批量执行、多线程运行器、形态匹配、编译器/解释器双路径 | `cargo build` |
| **CLI Demo** | 4 个筛选策略对示例数据运行 | `cargo run --example cli_demo` |
| **Flutter UI** (Dart) | 递归公式树编辑器、K线/分时图 Canvas 绘制、结果表格 | 仅源码展示 |

### 快速开始

```bash
git clone https://github.com/<user>/stock-screener-showcase.git
cd stock-screener-showcase
STOCK_DB_DIR=./sample_data cargo run --example cli_demo
cargo test --workspace
```

### 架构

公开仓库包含 DSL 和引擎层。数据源（通达信协议）和完整 Flutter 应用保留在私有仓库中。详见 [ARCHITECTURE.md](ARCHITECTURE.md)。

### 工程设计决策

核心设计权衡见 [DESIGN_DECISIONS.md](DESIGN_DECISIONS.md)：
- 为什么选择 Polars 批量执行而非逐股迭代
- 为什么选择类型化 AST 而非字符串 DSL
- 为什么采用编译器+解释器双路径
- `DataProvider` trait 如何实现数据源解耦
- 批量优先、逐股回退的执行策略

### 许可证

MIT — 详见 [LICENSE](LICENSE)
