# 筛选引擎

## 概念

筛选引擎的核心是一个**管线（Pipeline）**：股票依次经过若干个**阶段（Stage）**，每个阶段做一轮判断，任一阶段不通过则淘汰。

```
股票池 → Stage 1 → Stage 2 → ... → Stage N → 通过
              ↓         ↓              ↓
           淘汰      淘汰           淘汰
```

## Stage 结构

每个 Stage 包含：

| 字段 | 说明 |
|------|------|
| `name` | 阶段名，用于结果追踪 |
| `timeframe` | 时间粒度（日线 / 分钟） |
| `start_date` | 扫描目标日期 |
| `windowsize` | 窗口大小（从目标日期往回看多少根 K 线） |
| `prepare` | 预计算指标（SMA、BOLL 等） |
| `conditions` | 判断条件列表，**全部 AND 关系** |
| `kline_pattern` | K 线形态匹配（如连续阳线、吞没形态等） |
| `vars` | 中间变量定义 |
| `points` | 命名锚点定义 |
| `marks` | K 线重标记 |
| `extra_stocks` | 需要跨股票数据的目标 |

## 表达式类型

条件、变量、锚点都用 `Expr` 表示。当前支持 25+ 种表达式节点：

### 字面量与引用

| 节点 | 说明 |
|------|------|
| `Num(f64)` | 数值字面量 |
| `Bool(bool)` | 布尔字面量 |
| `Path(PathExpr)` | 路径引用，如 `stock.point.offset.field` |
| `Var(String)` | 变量引用 |

### 算术

`Neg` `Add` `Sub` `Mul` `Div` `Abs` `PctChange`

### 比较

`Gt` `Lt` `Gte` `Lte` `Eq` `Between`

### 布尔

`And` `Or` `Not` `Implies`（A → B）

### 范围聚合

| 节点 | 说明 |
|------|------|
| `All(from, to, pred)` | 区间内所有 K 线满足 pred |
| `Any(from, to, pred)` | 区间内任意 K 线满足 pred |
| `CountBars(from, to, pred, op, n)` | 区间内满足 pred 的 K 线数量比较 |
| `RangeVal(stock, from, to, col, func)` | 区间内某列的最值/均值等 |
| `CrossUp / CrossDown` | 均线金叉/死叉检测 |
| `Monotone` | 单调性判断 |

### K 线形态

| 节点 | 说明 |
|------|------|
| `CandleIs(stock, at, candle)` | 判断某根 K 线类型（阳线/阴线/十字星等） |

### 其他

| 节点 | 说明 |
|------|------|
| `SyncWithMarket` | 与大盘同步比较 |
| `Intraday` | 分时条件引用 |
| `IntradayDuration` | 分时持续时长判断 |

## 指标系统

指标通过 `ModuleRegistry` 注册，在 Stage 的 `prepare.indicators` 中引用。引擎自动计算指标列并附加到 DataFrame 上。

内置指标示例：
- `sma(period)` — 收盘价简单移动平均
- `boll(period, k)` — 布林带（上轨/中轨/下轨）
- `vol_ma(period)` — 成交量移动平均
- `high_n(period)` / `low_n(period)` — N 日最高/最低

自定义指标通过 JSON 定义公式，支持 `RollingMean`、`RollingStd`、`RollingMax`、`RollingMin`、`Ewma`、`Add`、`Sub`、`Mul`、`Div` 等组合。

## 执行流程

### 三级执行策略

```
Tier 1: try_run_batch_grouped()
  所有股票加载到一个 DataFrame，group_by 后一次性执行。
  最快路径，适用于简单指标 + 条件。

  ↓ 失败（复杂形态、跨股引用等场景）

Tier 2: try_run_batch_df()
  每只股票独立 DataFrame，但条件仍编译为 Polars 向量化表达式。
  适用于 group_by 有问题但条件可编译的场景。

  ↓ 失败（Polars 无法表达的条件）

Tier 3: run_pipeline()
  逐股逐行解释执行。最慢但最通用。
  适用于 Polars 无法表达的有状态形态匹配和复杂逻辑。
```

### 短路求值

- 每个 Stage 的条件是 AND 关系，任意一个失败即停止该 Stage 的后续计算
- 一个 Stage 失败，后续 Stage 不再执行
- 分钟数据仅在日线条件全部通过后才按需加载

### 多日扫描

`run_screener_scan_rs` 使用 `std::thread::scope` 多线程并行扫描多个交易日。每天独立运行完整管线，线程间无共享状态。

## 数据抽象

引擎通过 `DataProvider` trait 解耦数据源：

```rust
pub trait DataProvider: Send + Sync {
    fn kline(&self, symbol: &str, tf: Timeframe, from: NaiveDate, to: NaiveDate) -> LazyFrame;
    fn intraday(&self, symbol: &str, date: NaiveDate) -> LazyFrame;
    fn market_index(&self, symbol: &str) -> String;
}
```

目前唯一实现是 `ParquetDataProvider`——从按年分区的 Parquet 文件读取历史 K 线数据，预计算 OHLCV 价格转换。替换数据源只需实现这个 trait。

## 结果输出

管线输出为 Polars DataFrame，包含列：

| 列名 | 说明 |
|------|------|
| `market` | 市场代码（0=SZ, 1=SH, 2=BJ） |
| `code` | 6 位股票代码 |
| `passed` | 是否通过全部阶段 |
| `eliminated_reason` | 淘汰原因（首个失败的条件名） |
| `eliminated_stage` | 在哪个阶段被淘汰 |
| `stage_trace` | 各阶段执行追踪（如 `daily✓(cond1,cond2) → minute✗(intraday_veto=cond3)`） |
| `date` | 扫描日期 |

## 与 Flutter 的交互

Flutter 端通过 JSON 定义管线结构（Pipeline → Stage → Condition），经 `flutter_rust_bridge` 传给 Rust 执行。Rust 端运行完毕后返回 JSON 结果给 Flutter 展示。

JSON 格式与 Rust 结构体一一对应（通过 serde 序列化），无需额外转换层。Flutter 端有对应的 Dart 模型类（`ExprNode`、`StageModel` 等）和编译器（将 Dart 模型编译为 Pipeline JSON）。
