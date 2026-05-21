# V2 反馈日志

> **状态**: 进行中 — V1 验收阶段从 2026-05-21 开始。Allen 手动测试
> ezagent V1（Phase 9 已关闭）；Claude 把每条反馈原话记录在这里 +
> 抽象其本质原因。
>
> V2 规划开始时，这份文档是输入源。记录期间**不实施**。

## 记录协议

每条反馈一个条目，**4 个字段**:

1. **原始反馈 (Raw quote)** — Allen 从 Feishu 发的原话（中文保留，
   不释义，不"Allen 的意思是"）。包括时间戳 + Feishu message_id 当
   可得。
2. **本质原因 (Abstracted root cause)** — 这暴露了系统或交互的什么
   一般属性？要比具体 bug 高一层抽象。"哪类设计错了？"而不是
   "哪行代码错了？"
3. **V2 影响 (V2 implication)** — 需要 SPEC 改动、架构调整、新抽象、
   删抽象，还是仅 per-feature fix？标 scope: structural / tactical /
   ergonomic。
4. **候选方案 (Candidate solutions)** — 1-3 个方向，带 trade-off。
   **不**是决定；那是 V2 规划期的事。

按**主题**分组（顶级 `##` 区段）。主题从反馈内容派生，不预设。
新模式涌现时加新主题。

## 可能出现的主题（初步猜测，可调整）

- **URI ergonomics**（3 段 URI 啰嗦；用户感受到成本吗？）
- **Workspace 切换 UX**（Keycloak 模型有原则但够直观吗？）
- **Auth flow surface**（workspace 参数繁琐；bare-handle vs 完整 URI 的 ergonomics）
- **Admin 工具 gap**（手动 mix task vs LV CRUD；缺什么）
- **Session 生命周期**（session 何时持久化；rehydration 语义）
- **Plugin authoring 摩擦**（参考 `feedback_north_star_plugin_isolation`）
- **Multi-agent orchestration UX**（Phase 7 orchestrator 在 V1 怎么呈现）
- **Demo / first-run 体验**（新 dev 跑 `mix phx.server` —— 撞见什么）
- **可观测性 gap**（出问题时，能不能看出原因？）

---

## V2 规划触发

当 Allen 说"开始 V2 规划"（或等价）时，本文档变成
`superpowers:brainstorming` 会话的输入，产出:

1. `docs/superpowers/specs/<YYYY-MM-DD>-ezagent-v2-charter.md` ——
   按主题综合 + V2 目标 + 非目标
2. 每主题的 SPEC draft（按 Phase 9 模式）
3. 修订的 PR 序列（可能是 V2 的多个 phase）

在此之前：**记录，不实施**。

---

## 条目

（空 —— V1 验收刚开始）

### 条目模板

```markdown
## <主题> — <一句话摘要>

### 原始反馈

> [Feishu 2026-MM-DD HH:MM, msg `om_xxx`]
> <Allen 原话，中文保留>

### 本质原因

<1-3 句。不是"按钮坏了"而是"反馈 X 暴露缺失抽象：系统没有
Y 概念，所以用户得手动做 Z"。抽高一层。>

### V2 影响

- **Scope**: structural | tactical | ergonomic
- **Affects**: <影响的子系统 / SPEC 章节 / invariant>
- **Blocks**: <依赖的其它反馈，如有>

### 候选方案

- **A**: <方向>；trade-off: <代价>
- **B**: <方向>；trade-off: <代价>
- **C**（如适用）: <方向>；trade-off: <代价>

### 链接

- 相关 Phase 9 PR/SPEC: <ref 如有>
- 相关 memory: <feedback_xxx 如有>
- 相关 Decision Log 条目: #<number> 如有
```

---

## 约定

- **按 memory `feedback_bilingual_docs_convention`**: 本文档有
  `.md` 平行英文版，两个文件同步更新。
- **按 memory `feedback_subagent_review_plans`**: V2 规划开始时，
  SPEC subagent 要读**两份**: 本文档 + Phase 9 SPEC + amendments +
  demo doc。
- **按 memory `feedback_completion_requires_invariant_test`**: V2
  feature 需要 invariant test；本文档识别**应该**是 invariant 的
  东西。
- **不提前实施**: 即使 fix 是一行，先记录在这里。Allen + Claude
  review 抽象 pass 然后再 implementation pass。重点是发现跨反馈的
  模式，不是追个别症状。
