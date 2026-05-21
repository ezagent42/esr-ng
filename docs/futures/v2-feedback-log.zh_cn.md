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

## Workflow gap — UI "create agent" 动词隐藏了 instantiate step

### 原始反馈

> [Feishu 2026-05-21 15:59 (GMT+9), msg `om_x100b6fde9bf484a8c4afee8c48a8120`]
> 我刚创建了 Agent: entity://agent/default/cc_demo，但看起来还是显示not running, 请检查是否已经启动？如果没有，为什么？如果启动了，为什么显示not running?

### 本质原因

V1 的 user-facing 动词 **"create agent"** **不等于** **"agent 准备好接收消息"**。UI 流程把 "create" 拆成 3 个内部步骤（spawn Kind 进 supervisor + 把 cc.agent template 加进 workspace.session_templates JSON + 通过 `cc.agent.instantiate/3` 启 PtyServer），但 `AgentNewLive.handle_event("create_agent")` 只做了 1+2 步。第 3 步（启 PtyServer）只在 `Workspace.Loader.load_all/0` 在 phx boot 时跑 — 所以新建的 cc agent 要等到 phx 重启才会真正 running。

这跟 **Phase 8c bare-handle bounce** bug 是同一类抽象漏出（auth 动词的表面效果跟实际存进 session 的内容不一致）。共同模式：user-facing 动词的 dispatch 路径在结构上**不完整**, 比动词的表面意思**少做了事**。

### V2 影响

- **Scope**: structural — V1 的 `AgentNewLive` "create" 动词有误导性，不是一行能修的
- **Affects**: `EzagentPluginLiveview.AgentNewLive`, `Ezagent.Workspace.Loader`, `Ezagent.PluginCc.PtyServer` 生命周期，可能还有 "agent kind 生命周期阶段" 抽象本身
- **Blocks**: Allen 的 V1 cc agent 测试（workaround: phx 重启）—— 不硬阻塞其它测试
- **相关 Phase 9 PR/SPEC**: 无直接关联；这是 Phase 8c 的表面 bug 被 V1 测试 surface 出来
- **相关 memory**: 形态类似 Phase 8c bare-handle bounce 触发 `SessionPrincipal.put/2` invariant 的 bug

### 候选方案

- **A — AgentNewLive 战术修复**: `add_template` 之后加一个 `Workspace.invoke_template(workspace_uri, tmpl_name)` step。一个额外 dispatch 调用。Trade-off: 保留了 "spawn Kind + register template + instantiate template" 三步分裂；只有 LV 这条路径知道要串起来。其它 create 路径（CLI, API）要重复这个串接。
- **B — agent 生命周期重构为显式阶段**: UI 显示 `registered → instantiated → running` 带显式转换。"Not running" 变成 "Registered but not instantiated"。Trade-off: UI 更复杂但没隐藏 gap；user 看得到当前在哪个阶段。
- **C — 把 "create + instantiate" 合成单个 dispatch action**（推荐 V2）: 在 Behavior 层统一 workflow。`Ezagent.Behavior.AgentLifecycle.create_and_start` 是一个 cap-gated dispatch；AgentNewLive / CLI / API 都 invoke 同一个 action。Trade-off: 需要新 Behavior；最干净的抽象；符合 Phase 9 "dispatch 是唯一路径" invariant（Decision #3，invariant 1）。

### 链接

- Bug-fix candidate（如果 Allen 想在 V2 之前修）: `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/agent_new_live.ex` 大约 handle_event("create_agent") 行，在 `add_template` 之后插入 `Ezagent.Workspace.Loader.invoke_template(workspace_uri, tmpl_name)`（或等价）调用
- 测试 gap: 没有 test 断言 "AgentNewLive create_agent 之后, agent 实际能收消息" — invariant_completion_requires_test pattern 在这个 flow 没应用



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
