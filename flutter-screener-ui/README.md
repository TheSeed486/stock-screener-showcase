# Flutter 筛选器 UI（源码展示）

此目录包含筛选器 UI 的 Flutter/Dart 源码，从完整私有股票交易终端中提取。

## 为什么仅源码展示？

这些文件依赖 `flutter_rust_bridge` 生成的绑定代码（`lib/src/rust/api/screener.dart`），该代码与私有 Rust 宿主 crate 绑定。没有 Rust 后端和 FRB 代码生成，Flutter 代码无法独立构建运行。

此处包含源码用于**代码审查**——展示 Flutter/Dart 能力。

## 目录内容

### `features/screener_v2/`（13 个文件）
- **`widgets/expr_builder.dart`** — 递归公式树编辑器，支持拖拽参数绑定。将可视化树节点转为 `ExprNode` AST，再编译为 JSON 供 Rust 执行。
- **`widgets/custom_indicator_editor.dart`** — 自定义指标定义界面，公式组合编辑。
- **`widgets/condition_card.dart`** — 单个条件展示/编辑卡片，带状态指示。
- **`compiler/pipeline_compiler.dart`** — 将 `StageModel`（Flutter 端模型）编译为 Rust 消费的 Pipeline JSON。
- **`compiler/expr_compiler.dart`** — 将 `ExprNode` 树编译为表达式 JSON。
- **`models/`** — 与 Rust DSL 类型对应的 Dart 模型（`ExprNode`、`PathRef`、`IndicatorModel`、`StageModel`、`PatternModel`）。

### `features/screener/`（7 个文件）
- 初版 V1 筛选器：条件编辑器、结果表格。

### `widgets/`（8 个文件）
- **`kline_chart/animated_kline_chart_painters.dart`** — 自定义 Canvas 蜡烛图绘制，支持缩放、拖拽、十字光标。
- **`kline_chart/animated_kline_chart_models.dart`** — K 线渲染数据模型。
- **`minute_chart/minute_time_chart_painters.dart`** — 自定义 Canvas 分时图绘制。
- **`minute_chart/minute_time_chart_models.dart`** — 分时图渲染数据模型。
- **`animated_kline_chart.dart`** / **`minute_time_chart.dart`** — 图表组件入口。
- **`stock_list.dart`** / **`stock_table.dart`** — 通用股票列表/表格组件。

## 截图

运行效果见仓库根目录 `docs/screenshots/`。
