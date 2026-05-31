# Screener Rule Engine Development Document

## 1. 目标

本文件定义的是“通用筛选规则引擎”的开发方案，不绑定某一个具体模型。

重点有三件事：

1. 系统必须支持你内部使用的“点命令/锚点命令”。
2. 系统必须支持你未来会不断扩展的复杂规则类型。
3. 系统必须以“惰性计算 + 短路求值”为核心执行原则。

你之前给出的那一大批规则，只作为“规则类型样本”，不是当前文档要锁死的固定策略。

## 2. 核心认识

### 2.1 `A / A0 / Bm / Rn` 不是脏命名

这些不是随便的代号，而是策略内部的“点命令”。

系统应该原生支持它们：

- 作为策略内部的锚点 ID
- 作为规则引用的目标点
- 作为调试输出中的定位标签

因此，不应该试图把它们从系统里移除。
正确做法是：

1. 引擎内部把它们视为稳定锚点标识符。
2. UI 层可以给它们附带中文解释或别名。
3. 不同策略可以定义不同的点命令集合。

### 2.2 规则样本不等于规则规范

你给的示例规则，真正传递的信息不是“实现这几百条文字”，而是“系统必须支持这些规则形态”。

系统必须支持的，不是某一条具体规则，而是下面这些规则类型：

- 日线价格/指标比较
- 分钟窗口时长判断
- 分钟窗口全程成立判断
- 大盘联动条件
- 涨停/封板事件条件
- 例外豁免条件
- K 线重标记条件
- 区间计数条件
- 分组结构条件
- 先否决后确认的阶段化流程

## 3. 系统分层

整个筛选系统建议拆成 4 层，而不是一个超长 DSL。

### 3.1 点命令层

负责定义和解析策略里的锚点。

例如：

- `A0`
- `A`
- `Bm`
- `C`
- `R2`
- `Rn`

这里的职责不是直接做买卖判断，而是先回答：

- 这个点存在不存在
- 对应的是哪一天/哪一组 K 线
- 和别的点之间是什么关系

建议抽象：

```rust
struct AnchorPoint {
    id: String,
    bar_index: usize,
    trade_date: String,
}
```

对“组”的支持：

```rust
struct AnchorGroup {
    id: String,
    start_bar: usize,
    end_bar: usize,
    kind: AnchorGroupKind,
}
```

### 3.2 表达式层

负责低层的数值/布尔表达式。

当前仓库里的 `rust/src/api/screener.rs` 就属于这一层。

它适合处理：

- `close > ma18`
- `high >= boll_upper`
- `count(close > open, 5) >= 3`
- `bars_since(cross_up(close, ma20)) <= 2`

但它不适合直接承载完整策略编排。

### 3.3 规则编排层

负责把表达式变成“规则”。

最少应支持：

- `reject`
- `accept`
- `waive`
- `relabel`
- `all_of`
- `any_of`

建议抽象：

```rust
enum RuleAction {
    Reject,
    Accept,
    Waive { target_rule_ids: Vec<String> },
    RelabelBullish,
    RelabelBearish,
}
```

### 3.4 执行规划层

负责惰性求值。

它要决定：

- 先算什么
- 后算什么
- 哪些数据根本不用读
- 哪条规则一旦命中就立刻停

这一层才是性能的核心。

## 4. 惰性执行模型

### 4.1 固定执行顺序

必须强制采用漏斗式流程：

1. 基础静态过滤
2. 日线窗口加载
3. 点命令解析
4. 日线预处理
5. 日线否决规则
6. 分钟数据按需加载
7. 分钟否决规则
8. 分钟通过规则
9. 输出结果与调试轨迹

### 4.2 一票否决

每只股票的执行过程必须满足：

- 命中任意否决规则，立刻停止
- 命中任意通过分支，且该阶段定义为 `any_of` 时，立刻通过
- 不再继续计算无关分钟窗口

### 4.3 分钟数据绝不能全量先读

必须按阶段按需读取：

1. 先只读日线
2. 日线过关后，再读必要的分钟日
3. 某条分钟规则只需要 `目标日`，就不要连 `前一日` 一起读
4. 某股票一旦被否决，立刻释放后续分钟计算机会

## 5. 引擎必须支持的规则类型

下面是系统能力清单，不是固定策略清单。

### 5.1 日线关系类

支持：

- 价格和均线比较
- 价格和布林带比较
- K 线实体/影线形态
- 区间最高/最低比较
- 连阳/连阴统计
- 区间 K 线数量限制

### 5.2 分钟窗口类

支持：

- 某状态在窗口内持续多少分钟
- 某状态在窗口内是否全程成立
- 某状态在窗口内是否出现过
- 某状态在窗口内出现了几段

推荐原子算子：

- `duration(day, from, to, state)`
- `all_minutes(day, from, to, state)`
- `any_minute(day, from, to, state)`
- `segment_count(day, from, to, state)`

### 5.3 联动类

支持：

- 个股和大盘同时判定
- 一个点的状态依赖另一个标的
- 同步比较个股分钟状态与指数分钟状态

### 5.4 事件类

支持：

- 涨停
- 跌停
- 封板
- 开板
- 封板时长
- 最后时刻是否封住

### 5.5 重标记类

支持把某根 K 线临时重判为：

- 阳线
- 阴线
- 特殊 K 线

这是规则系统的一等能力，不应写成零散补丁。

### 5.6 豁免类

支持：

- 某个条件成立后，跳过另一批规则
- 某个场景标签成立后，某条规则失效

### 5.7 分组结构类

支持：

- 一组阴线
- 多组阴线
- 阳线组 / 阴线组
- 某组之后的第一根阳线
- 某组内部/组间统计

这意味着引擎必须有“组解析器”，而不是只会看单根 K 线。

## 6. 数据契约

### 6.1 日线数据

最少需要：

- `trade_date`
- `open`
- `high`
- `low`
- `close`
- `volume`
- `amount`
- `ma5`
- `ma12`
- `ma18`
- `lma`
- `boll_upper`
- `boll_mid`
- `boll_lower`
- `is_limit_up_close`
- `listed_days`
- `is_st`
- `is_suspended`

### 6.2 分钟数据

最少需要：

- `trade_date`
- `minute`
- `price_line`
- `avg_line`
- `prev_close`
- `limit_up_price`
- `is_at_limit_up`
- `volume`
- `amount`

### 6.3 分钟派生状态

建议预先向量化生成：

- `price_positive`
- `avg_positive`
- `both_positive`
- `price_negative`
- `avg_negative`
- `both_negative`
- `price_above_avg`
- `price_below_avg`

后续所有分钟规则尽量只消费这些原子状态。

## 7. DSL 设计建议

### 7.1 不要只做一个 DSL

建议拆成 3 层：

1. 点命令声明层
2. 表达式层
3. 规则编排层

### 7.2 点命令声明层

专门描述某个策略如何找出锚点。

示意：

```yaml
anchors:
  - id: A
    kind: single_bar
    resolver: first_positive_after(group: Bm)

  - id: Rn
    kind: single_bar
    resolver: last_positive_in(range: analysis_window)

  - id: Bm
    kind: group
    resolver: negative_group(index: 1)
```

### 7.3 表达式层

保留当前 `screener.rs` 那套 DSL，用于原子布尔条件：

```text
close >= boll_upper
bars_since(cross_up(close, ma20)) <= 2
count(close > open, 5) >= 3
```

### 7.4 规则编排层

用结构化 YAML/JSON，而不是一整段自由文本。

示意：

```yaml
phases:
  - id: daily_veto
    mode: all
    rules:
      - id: veto_1
        target: A
        when: expr("close >= boll_upper")
        action: reject

  - id: minute_pass
    mode: any
    rules:
      - id: pass_1
        target: target_day
        when:
          minute_all:
            day: target_day
            from: "10:00"
            to: "15:00"
            state: both_positive
        action: accept
```

## 8. 调试与可视化

复杂策略没有可视化就等于不可维护。

系统必须输出：

- 命中的点命令结果
- 命中的规则 ID
- 被豁免的规则 ID
- 实际读取的分钟日期
- 每一步是否短路退出

图形调试至少要有：

1. 日线锚点标注
2. 分钟状态高亮
3. 规则命中时间窗口标注

## 9. 推荐的 Rust 模块拆分

建议不要把未来逻辑继续堆进单个 `rust/src/api/screener.rs`。

建议拆为：

- `rust/src/api/screener/expr.rs`
- `rust/src/api/screener/anchors.rs`
- `rust/src/api/screener/minute_status.rs`
- `rust/src/api/screener/ruleset.rs`
- `rust/src/api/screener/executor.rs`
- `rust/src/api/screener/debug.rs`

如果以后有具体策略，再单独放：

- `rust/src/api/screener/models/<strategy>.rs`

而不是把策略和引擎耦死。

## 10. 当前正确的开发顺序

### Milestone 1

先做通用能力：

- 分钟状态原子
- 点命令解析框架
- 规则编排结构
- `reject / accept / waive / relabel`

### Milestone 2

再做执行引擎：

- 日线先筛
- 分钟按需加载
- 短路退出
- trace 输出

### Milestone 3

最后才开始灌入具体策略。

具体策略无论叫：

- 模型 C-
- 模型 A
- 盘中半日版
- 尾盘版

都应该只是“规则配置 + 锚点定义”，不应该反向塑造底层引擎。

## 11. 明确不该做的事

不要做下面这些：

1. 不要把示例规则直接写死到引擎里。
2. 不要把点命令当成需要消灭的命名噪音。
3. 不要把整套策略塞成一个超长布尔字符串。
4. 不要先全量加载分钟数据再慢慢筛。
5. 不要把“豁免规则”写成散落在各处的补丁判断。

## 12. 结论

后续正确方向不是“继续补一批规则”，而是先把筛选系统正式升级为：

1. 支持点命令
2. 支持规则类型
3. 支持惰性执行
4. 支持短路求值
5. 支持 trace 与可视化验证

等这层打稳之后，你给任何一套新规则，系统都能接，而不是每来一套规则就重写一遍引擎。
