# 工程设计决策

本文档解释筛选器 DSL 和引擎背后的核心工程选择，面向想了解"为什么这样做"而非仅仅"做了什么"的面试官。

## 1. 为什么选择 Polars 而非逐行迭代？

**问题**：对 5000+ 只股票执行多条件筛选管线，计算量很大。逐股、逐行的 Rust 求值需要嵌套循环，缓存局部性差。

**决策**：将 DSL 条件编译为 Polars 惰性表达式，以向量化列操作执行。

**对比**：

| 方式 | 5000 只股票 × 250 天 | 内存 | 代码复杂度 |
|------|---------------------|------|-----------|
| 逐行迭代 | ~30s | 低 | 简单 |
| Polars 按股批处理 | ~0.5s | 中（每只一个 DataFrame） | 需要编译器 |
| Polars 分组批处理 | ~0.1s | 高（单个巨型 DataFrame） | 复杂 join 逻辑 |

我们选择**分组批处理优先，逐股回退**。引擎先尝试全向量化路径（所有股票在一个 DataFrame 中 `group_by`），失败时回退到逐股 Polars 执行，再失败时回退到逐行解释器。

**结果**：常见筛选策略（均线交叉、成交量放量、布林带）在笔记本上处理 5000 只股票只需 200ms 以内。

## 2. 为什么选择类型化 AST 而非字符串 DSL？

**问题**：股票筛选策略有深度嵌套逻辑（如果 A 则 B，并在区间 C 内所有 K 线满足 D）。字符串 DSL 需要维护解析器，错误信息晦涩，缺乏 IDE 支持。

**决策**：将策略语言定义为 Rust 类型（`Expr` 枚举，25+ 变体），通过 serde 与 JSON 互转。

**对比**：

| 方式 | 类型安全 | IDE 支持 | 序列化 | 可读性 |
|------|---------|---------|--------|--------|
| 字符串 DSL | 无 | 无 | 需手写解析器 | 最好 |
| 类型化 AST (Rust) | 完整 | 完整（rust-analyzer） | 免费（serde） | 良好（Builder API） |
| 纯 JSON | 无 | 无 | 免费 | 冗长 |

选择类型化 AST 的原因：
- **serde** 免费提供 JSON 序列化 — Flutter UI 发 JSON，Rust 反序列化
- **Builder 模式**（`Expr::gt()`、`PathExpr::window_end(0).col("close")`）让 Rust 端构造更顺手
- **穷尽匹配**在编译期捕获遗漏的条件处理
- Flutter 端用相同的 JSON 格式解析为 Dart 模型类，JSON 作为通信协议

## 3. 为什么采用编译器 + 解释器双路径？

**问题**：Polars 表达式可以高效处理 90% 的筛选条件（数值比较、滚动窗口、布尔逻辑）。但 10% 的条件需要 Polars 表达不了的状态机求值：序列形态匹配（"连续 3 天收阳且收盘价逐步抬升"）、跨股引用（"当前股票涨，大盘指数跌"）、分钟级分时谓词。

**决策**：能编译为 Polars 的走编译器；编译不了的走解释器。

编译器路径（`expr_compiler.rs`）：
```
DSL Expr → Polars Expr（惰性）→ with_column → filter mask
```

解释器路径（`evaluator/`）：
```
DSL Expr → EvalCtx { df, date_index, window } → 逐行 bool
```

引擎优先尝试编译。如果 `try_compile_condition()` 返回 `None`（不支持的表达式），条件走解释器。对管线作者完全透明。

**关键洞察**：编译器和解释器共享同一份 AST。不需要翻译层。一个条件要么能编译要么不能，引擎自动处理两条路径。

## 4. 为什么抽象 DataProvider trait？

**问题**：引擎需要历史 K 线数据来求值条件。但数据源多种多样：Parquet 文件（本仓库）、数据库、CSV、网络 API。

**决策**：定义抽象的 `DataProvider` trait，引擎依赖 trait 而非具体实现。

```rust
pub trait DataProvider: Send + Sync {
    fn kline(&self, symbol: &str, tf: Timeframe, from: NaiveDate, to: NaiveDate) -> LazyFrame;
    fn intraday(&self, symbol: &str, date: NaiveDate) -> LazyFrame;
    fn market_index(&self, symbol: &str) -> String;
}
```

**好处**：
- 引擎 crate **零依赖任何具体数据源**
- 测试极其简单：注入 Parquet 示例数据即可
- 换入其他数据源（数据库、Web API），引擎代码一行不改
- 使用本仓库的用户可实现自己的 provider（CSV、数据库）

这就是标准的依赖反转——区分 library 和 script 的关键抽象。

## 5. 为什么批量优先、逐股回退？

**问题**：最快的执行路径（单 DataFrame + `group_by`）不适用所有管线。复杂形态匹配、可变长度窗口、跨股引用需要逐股处理。

**决策**：三级执行策略。

```
Tier 1: try_run_batch_grouped()     ← 所有股票一个 LazyFrame，group_by market+code
  ↓ 失败
Tier 2: try_run_batch_df()          ← 逐股 LazyFrame，Polars 编译
  ↓ 失败
Tier 3: run_pipeline()              ← 逐股逐行解释器
```

**Tier 1** 最快。所有股票加载到一个 DataFrame，加指标列，条件编译为布尔掩码，过滤。Polars 惰性求值将整个管线优化为单次查询。约 80% 的实用策略在此路径完成。

**Tier 2** 处理 group_by 有问题的情况（特定窗口模式、复杂 join）。每只股票独立 DataFrame，但条件仍编译为向量化 Polars 表达式。

**Tier 3** 是兜底。逐行求值 Polars 无法表达的条件（有状态形态、跨股引用）。慢但正确。

引擎按顺序尝试，透明回退。管线作者无需关心用哪条路径执行。

## 6. 为什么用 std::thread::scope 做多日扫描？

筛选器扫描需要在数百个交易日上运行相同管线。这是典型的 embarrassingly parallel — 每天相互独立。

**决策**：使用 `std::thread::scope`（安全有作用域线程）而非 `rayon` 或 `tokio`。

**为什么不用 rayon？** Rayon 擅长数据并行（并行迭代器），但在每个任务有不同初始化（JSON 反序列化、日期解析、provider 初始化）的任务并行场景不够顺手。

**为什么不用 tokio？** 引擎是 CPU 密集型，不是 I/O 密集型。引入 async 只会增加复杂度。

**为什么用 scoped threads？** 子线程安全引用父线程栈上的数据（日期字符串、管线模板、registry JSON），无需 `Arc` 克隆。`scope` 调用阻塞直到所有线程完成，正是 CLI 工具需要的。

## 7. 为什么选择 Parquet 存储历史数据？

历史 K 线数据量级很大（数十年、数千只股票）。存储格式的选择很重要。

**为什么是 Parquet？**
- **列式**：筛选查询通常只读 3-4 列（close、volume、date），Parquet 只读这些列
- **压缩**：zstd 压缩将 322MB 原始数据降到 ~160MB
- **谓词下推**：Polars 将日期范围过滤推入 Parquet 读取层，跳过整个 row group
- **零拷贝对接 Polars**：Parquet → Polars DataFrame 是直达路径，无中间格式

`ParquetDataProvider` 按 `klines/YYYY.parquet` 组织 — 每年一个文件。这是在文件数量（36 个文件覆盖 35 年）和查询效率（典型筛选扫描 1-3 年）之间的权衡。

## 8. 为什么不用现成的表达式语言？

| 方案 | 不用的原因 |
|------|-----------|
| CEL (Common Expression Language) | 不支持 Polars；为 protobuf/服务设计，非 DataFrame |
| PRQL | 编译到 SQL 而非 Polars；无形态匹配原语 |
| Python `eval()` | 无类型安全；慢；引入 Python 依赖 |
| 自定义 PEG 解析器 | 维护负担重；AST 是正确的抽象层级 |

DSL 是真正的领域特定 — K线形态、带命名锚点的滚动窗口、分钟级分时谓词、跨股引用。这些概念不存在于通用表达式语言中。构建类型化 AST 的代码量比将通用工具硬塞进不属于它的领域更少。

## 9. Flutter：为什么自定义 Canvas 绘制？

K 线图和分时图使用 Flutter `CustomPainter` API 而非图表库。

**为什么不用 `fl_chart` 或 `syncfusion`？**
- K 线图（蜡烛 + 成交量 + 均线叠加）不是标准图表类型
- 性能：500+ 可见蜡烛需要在缩放拖拽时高效增量重绘
- 价格区与成交量区的十字光标同步需要自定义命中测试
- 现有库不支持所需的交互模型（拖拽平移、滚轮缩放、点击出十字光标）

代价是更多代码（每张图约 500 行），但换来了对渲染和交互的完全控制。对金融终端而言，这个控制权值得付出。
