# GLOSSARY.md

ESR 项目的**单一真相源**(single source of truth)for:

1. **Decision Log** — 累积所有架构决策(v0.1 → v0.4,#1-#83;实施期持续 append)
2. **术语表** — ESR domain 词汇定义
3. **易混淆词表** — 跟外部世界同名概念的消歧 convention

本文件由 Allen + 工程师共同维护。实施期每产生新的架构决策 → append 到 Decision Log;每新增 domain 词汇 → 加进术语表;每发现跟外部世界的命名碰撞 → 加进易混淆词表。

---

## 0. 怎么用本文件

- **查决策为什么这么定** → §1 Decision Log,按编号或主题搜
- **不确定某个词在 ESR 里啥意思** → §2 术语表
- **写文档 / 代码碰到易混淆词** → §3 消歧表 + convention
- **实施期产生新决策** → append 到 §1,编号递增

每条 Decision 包含: 编号 / 决策内容 / 时期(v0.1/v0.2/v0.3/v0.4/impl)。具体论证回 `ARCHITECTURE.md` 对应章节,本文件只列简要表述方便快查。

---

## 1. Decision Log

按讨论顺序累积(v0.1 → v0.2 → v0.3 → v0.4 → 实施期):

| # | 决策 | 时期 |
|---|---|---|
| 1 | **Kind = Class** — 系统所有可寻址实体是 Kind 实例,Kind 跟 OO Class 等价;URI 是 instance ID;`Esr.<Category>.<KindType>` 模块定义 Kind | v0.1 |
| 2 | **Behavior** — Kind 上的能力切片,跨 Kind 复用;每个 Behavior 拥有 state slice + invoke/4 | v0.1 |
| 3 | **Invocation 中心化** — 一切 actor 间通信走 `%Invocation{target, action, args, mode, ctx}`,无第二条路径 | v0.1 |
| 4 | **CapBAC** — capability-based access control(struct,不是字符串);每个 Invocation 在 ctx 携带 caps;dispatch step 5.5 检查 | v0.1 |
| 5 | **5 个 mode** — `:call` / `:cast` / `:call_stream` / `:subscribe` / `:introspect`,有限集不可扩 | v0.1 |
| 6 | **URI scheme 集合** — `agent://` / `user://` / `session://` / `workspace://` / `resource://...` 等,scheme 决定 Kind 类型 | v0.1 |
| 7 | **3 个 Kind 子类** — Session(routing context owner)/ Entity(Principal, 持 cap)/ Resource(被操作,无 cap) | v0.2 |
| 8 | **@interface 是 SSOT** — Behavior 声明 `@interface` 含 args/returns/errors/modes;所有 UI(LiveView/CLI/HTTP/MCP)从它派生 | v0.2 |
| 9 | **不变量:Session 是 routing context owner** — chat/IM 系统的 channel,RoutingRules 挂在 Session 上 | v0.2 |
| 10 | **Phoenix as transport, not fullstack** — 用 Endpoint/Socket/Channel/PubSub/Presence/Plug;不用 Controller/View | v0.2 |
| 11 | **少发明多装配** — 判断标准:新人记多还是少;esr_core 是 thin convention layer + glue | v0.2 |
| 12 | **Cross-cutting Behavior** — 通过 attach 注入(audit、logging),不修改 Kind 模块 | v0.2 |
| 13 | **Adapter pattern** — 所有外部 transport(Feishu/Slack/CC/Web)是 Adapter;Adapter 不允许有业务语义 | v0.2 |
| 14 | **PubSub 用于不确定旁观者**(view 渲染、telemetry),dispatch 用于确定 receiver | v0.2 |
| 15 | **ctx.reply 路由表** — Invocation 结果按 ctx.reply 字段路由(phoenix_channel / webhook / mcp_response / none) | v0.2 |
| 16 | **state_slice 隔离** — 每个 Behavior 只能读写自己声明的 slice,不能越界 | v0.2 |
| 17 | **Plugin = OTP application** — no DSL,纯 convention;mix.exs 标准依赖管理 | v0.2 |
| 18 | **Kind 实例化策略** — Session 是 ephemeral GenServer(任务结束 terminate),Entity 是 long-lived,Resource 是 lazy GenServer | v0.2 |
| 19 | **Cap 三档 scope** — `:instance` / `:kind` / `:all` | v0.2 |
| 20 | **Plugin 注册自己的 Kind** — Plugin 启动时 `BehaviorRegistry.register/3`,无中心化配置 | v0.2 |
| 21 | **Behavior 是 plugin,不是 core** — `Esr.Behavior.*` 全是 plugin(标准 Behavior plugin 集合),core 只提供 behaviour 契约 | v0.3 |
| 22 | **具体 Kind 是 plugin** — `Esr.Entity.Agent` / `Esr.Resource.Workspace` / `Esr.Session.*` 都是 plugin,不是 core | v0.3 |
| 23 | **Cross-cutting 通过 attach API** — `Esr.BehaviorRegistry.attach(Kind, Behavior, slice)`,无 mixin | v0.3 |
| 24 | **Identity Behavior 标准化** — `Esr.Behavior.Identity` 是所有 Entity Kind 的基础 Behavior(handle/caps/inbox) | v0.3 |
| 25 | **Chat Behavior 标准化** — `Esr.Behavior.Chat` 处理 Message 收发,跨 Session/Agent 复用 | v0.3 |
| 26 | **Message 是 core 概念** — `%Esr.Message{}` 在 esr_core 定义,Message routing 不专属 chat plugin | v0.3 |
| 27 | **Snapshot 持久化策略 4 选** — `:on_change` / `:periodic` / `:on_terminate` / `:ephemeral` / `:external` | v0.3 |
| 28 | **RoutingRegistry plugin 自声明 tables** — core 不预定义任何 table,plugin 在 Application.start/2 里 `declare_table` | v0.3 |
| 29 | **CapBAC step 5.5 in dispatch flow** — 每次 invocation 必经 cap 检查,核心权限 gate | v0.3 |
| 30 | **三档 cap scope** — instance(`uri`)/ kind(`module`)/ all(`:*`) | v0.3 |
| 31 | **Behavior unit testing** — 纯函数 invoke/4 可直接测,无需 mock | v0.3 |
| 32 | **OSProcess Behavior** — pty / 外部进程通过 erlexec wrapped,统一 Behavior 接口 | v0.3 |
| 33 | **Webhook plug** — Plug 作为 webhook 入口,构造 Invocation,走标准 dispatch | v0.3 |
| 34 | **REST AdminAPI 走 Plug** — admin 操作不是 LiveView,是 Plug + JSON | v0.3 |
| 35 | **WebSocket adapter** — `Esr.Web.UserSocket` (公开)+ `Esr.Web.AdminSocket` (内部)分两 socket | v0.3 |
| 36 | **三种 transport 全 first-class** — WS / stdio / MCP via channel,没有"主"和"次" | v0.3 |
| 37 | **RoutingRegistry core 不预定义 table** — plugin 自声明 + 自维护 | v0.3 |
| 38 | **`Esr.Capability` struct, not string** — 老 esr 字符串 cap 撞 typo 事故;新版用 struct + 严格 matcher | v0.3 |
| 39 | **5 个 mode 是有限集** — 不允许新 mode,要扩展用 ctx 字段 | v0.3 |
| 40 | **Behavior state_slice 是 map** — 不是 struct;运行时灵活,持久化 JSON-friendly | v0.3 |
| 41 | **Routing rules additive** — 已加路径不会因新增 rule 被消除,除非显式 revoke;`always() → A` + `mention(B) → B` 时 @B → A 和 B 同时收到 | v0.3 |
| 42 | **Matcher AST 可序列化** — RoutingRegistry 存 matcher_data,运行时反序列化求值 | v0.3 |
| 43 | **Invocation flow 9 步标准化** — Appendix A 详述,plugin 作者不需要看 | v0.3 |
| 44 | **LOC budget 显式化** — esr_core target ~580 LOC(v0.3 数字,后被校准);每模块 hard ceiling;超 cap 触发设计 review | v0.3 |
| 45 | **持久化 F+G 全 Phoenix 原生** — Ecto + SQLite BLOB / S3 via `req_s3`;无新外部依赖 | v0.3 |
| 46 | **SQLite 是唯一数据库** — 不双轨;Postgres 不在 v0 spec | v0.3 |
| 47 | **`:oban` 移除** — snapshot / DLQ / drain 用 `Process.send_after/3`;~15 LOC Esr.Scheduler;BEAM 原生足够 | v0.3 |
| 48 | **Federation 形态 A 确认** — 独立节点 + cross-node 协议;v0 不实现,share-nothing 持久化 / URI / CapBAC 已留接口 | v0.3 |
| 49 | **LiveView IM dogfood + CLI 写入 spec**(Appendix D),让 spec 读者直观感受系统怎么用 | v0.3 |
| 50 | **ESR 不内置通用 MCP server** — 内嵌 BEAM agent 直接调 Elixir API,Python adapter 走 WS;唯一 MCP 集成是 CC Channel | v0.3 |
| 51 | **CC Channel = ESR ↔ CC 桥** — 反向 MCP push 模型(不是 LLM pull tools);双向 | v0.3 |
| 52 | **`esr_plugin_cc_channel` 单 plugin 含两侧组件**(Elixir adapter + Python channel server)统一发布 | v0.3 |
| 53 | **CC Channel 实现语言:Python 优先**(复用现有 esr),Bun 备选 | v0.3 |
| 54 | **Adapter driver 关系两种** — ESR-driven(Feishu/Slack,OSProcess 拉起)与 external-driven(CC Channel,CC 用 `--channels` 拉起) | v0.3 |
| 55 | **单层鉴权模型** — WS connect 验 token(身份)+ Invocation 验 cap(权限);Channels 协议的 sender allowlist / pairing 不使用 | v0.3 |
| 56 | **`esr_plugin_cc_pty` vs `esr_plugin_cc_channel` 独立 plugin** — 本地 pty vs 外部桥接,两者并存 | v0.3 |
| 57 | **LiveView IM 不限于 dogfood** — v0 期内部 IM 验证 spec,v0 之后作为产品 web 入口,跟 Feishu/Slack/CC channel 并列 | v0.3 |
| 58 | **LiveView ↔ CLI 同构映射** — 两侧 UI 都从 `@interface` 自动派生;`/agent:set-default A` ↔ `esr agent set-default A` 等价 | v0.3 |
| 59 | **`:on_change` 触发时机:slice 真变了才写**(`new_slice != old_slice`),不是 invoke 后都写;BEAM 不可变 + 值比较自然给出正确语义 | v0.3 |
| 60 | **Audit log 异步写入** — `:telemetry` handler 只 `GenServer.cast` 到 `Esr.Audit.Writer`;Writer 内 batch + 100ms flush;不用 Oban | v0.3 |
| 61 | **顶层加 "ESR 是 router 不是 req/resp app" framing** — 4 个 P1/P2 设计动作的共同根 | v0.4 |
| 62 | **"持久化层存了代码引用"为第二条 framing** — `type_name` 稳定 ID 间接层,模块改名时映射改一处 | v0.4 |
| 63 | **Resource Kind "shared referent needs identity"** — 任何被多方按身份引用的命名锚点都需要独立身份;Workspace 是示范 | v0.4 |
| 64 | **Template 升级双层模型** — Class(模块级,开发者写)+ Instance(运行时 Resource Kind,用户创建);Workspace 是 Template Instance 代表性例子 | v0.4 |
| 65 | **RoutingRegistry 加 `put_new` 语义**(unique-key only)+ duplicate-key 表用 `put` | v0.4 |
| 66 | **`use Esr.Kind` 宏强制生命周期** — register→subscribe→announce_ready 严格三步,plugin 作者无法绕过 | v0.4 |
| 67 | **`:call` to not-ready actor 必须 fail-fast,不能 buffer** — caller 同步阻塞,buffer 撞 deadline_ms | v0.4 |
| 68 | **零匹配路由 telemetry + DLQ unroutable** — 不能静默;ESR router 必须人工造可观测性 | v0.4 |
| 69 | **Idempotency ETS 模块** — bounded LRU,ctx 带 `idempotency_key`,dispatch step 2.7 自动检查 | v0.4 |
| 70 | **Matcher 边界按"读 core 数据"画线** — Message-field matcher 全在 core;读 plugin 专属 payload 才在 plugin | v0.4 |
| 71 | **Plugin 判定原则显式化(§2.2)** — 读 core 数据 → core;读 plugin 专属 → plugin;通用 invariants → core | v0.4 |
| 72 | **LOC 预算校准 595 → ~870** — dev review 实测扎实;invocation/matcher/kind 上调;新增 reliability 4 模块;red line 1100 | v0.4 |
| 73 | **feishu-cc 切片 3 张参考表入 spec(§10.7)** — ChatRouting / PrincipalMapping(unique, put_new)+ SessionRules(duplicate, put) | v0.4 |
| 74 | **Routing 迁移分诊规则**(§17.12) — 1722 行不一次性迁;偶然复杂度蒸发;真实业务重新表达;feishu-cc 切片优先 | v0.4 |
| 75 | **inbound 永远走 dispatch,绝不裸 `PubSub.broadcast`** — 升级为 §5.7.6 硬不变式;Phoenix.PubSub 不 buffer 没订阅者的 topic | v0.4 |
| 76 | **Idempotency v0 语义:收到即记,不是成功才记**(§5.7.3) — 失败走 DLQ;事务化"成功才记"超出 v0 复杂度预算 | v0.4 |
| 77 | **Event Sourcing 不做** — 从 deferred 改成已决不做;append-only Message stream 已具备 ES 真实好处 | v0.4 |
| 78 | **`SessionBindings` 作为 v0.4 第 4 张参考表**(duplicate-key)+ RoutingRegistry 加 `reverse_index` 可选反查 | v0.4 |
| 79 | **LOC cap 总和 > red line 是预期** — cap 是单模块异常天花板,red line 是实测合计触发器,两个独立信号 | v0.4 |
| 80 | **sub-step 是 /goal 内部 e2e gate,phase 才是 Allen review 单元** — 行为正确性自动化 + 架构判断人工拆开;VERIFICATION.md 先于 PLAN.md 写 | v0.4 |
| 81 | **`user://admin` bootstrap principal,持 all-caps 不可 revoke** — 结构性 invariant 集中在 `Esr.Capability.revoke/2`;Phase 1-3c LiveView/CLI 默认 `ctx.caller = user://admin` | v0.4 |
| 82 | **authz stub 带 `:stub_grant` telemetry 防"顺手简化"** — Phase 1 永远 grant + emit telemetry;Phase 3d in-place 替换为真实检查 + `:granted`/`:denied` | v0.4 |
| 83 | **§14 LOC budget round-2 校准** — `message_store.ex` 之前漏列;补进清单 ~50 LOC;target 870 → 920;red line 1100 → 1150 | v0.4 |
| 84 | **Phase 1 采用路径 B(`@behaviour Esr.Kind` + 共享 `Esr.Kind.Server`)** 不用宏 — register→subscribe→announce_ready property 等价 Decision #66 但 means 不同;共享 Server 把 Kind 隔离从 compile time 推到 runtime;`Esr.Kind.Runtime.handle_dispatch/3` 必须 defensive 处理多 Kind state shape;Phase 1 接受 trade-off 因为只有 Echo 一个业务 Kind;Phase 2+ 若 state shape 假设冲突再评估(详见 ARCHITECTURE.md §5.7.4) | impl |
| 85 | **`.claude/` 暂用 plain dir 不 vendor+submodule**(Phase 0 实施期决策)— 短期符合"少发明多装配"+ 镜像老 esr 实际结构;trigger 迁 vendor: (a) 出现 skill 需要 upstream 更新需求,或 (b) Phase 5 完成后整理 tech debt | impl |
| 86 | **CC channel 协议层简化:Channel = MCP server + 1 capability**(Phase 1b 实证)— v0.3 §12.8 之前假设 channel 是独立通信协议(独立 server 进程 + 类似 WebSocket 的 wire),Phase 1b 发现 Channels 是 MCP 协议扩展(`capabilities.experimental['claude/channel']` + `notifications/claude/channel` + 标准 MCP tools/call)。`esr_plugin_cc_bridge_v1_prototype` ~250 LOC Python。**LOC 对比的诚实表述**:老 esr `cc_channel_runner`(973 LOC)和 cc-openclaw `channel_server`(4164 LOC)包含 channel 之外功能(多 session / persistence / permission relay 等),直接拿 4164 vs 250 对比是**不公平的**;**协议层简化是真的**,LOC 简化幅度模糊。Phase 5 `esr_plugin_cc_channel` 走简化路径(详见 ARCHITECTURE.md §12.8) | impl |
| 87 | **`--dangerously-load-development-channels server:<name>` 需要项目根 `.mcp.json`**(per-operator,gitignored,通过 `git rev-parse --show-toplevel` 锚定)— 否则 claude 启动期 lookup 失败打印 warning;`--mcp-config <abs>` 只读 session-level,**不**满足 dev-channels lookup。`Esr.Bridge.V1Prototype.McpConfigWriter.write!/0` 同时写 session-level 和 project-level | impl |
| 88 | **K-path Behavior 模型**(Phase 2 落地 Decision #61)— 一个 Behavior 模块同时挂在多个 Kind 上,每个 Kind 通过 `BehaviorRegistry.register(kind, action, behavior)` 注册自己消费的 **action subset**(Chat: Session→send/join/leave, User+Agent→receive)。`Kind.behaviors/0` 从"action 路由权威"降级为"`init_slice` 用的列表",真正权威是 BehaviorRegistry per-Kind 表。User Kind 可以 `behaviors() = []` 但仍接收 `:receive` 分发(实现细节见 `apps/esr_plugin_chat/`)。这是 plugin isolation 北极星的核心原语:加新 Behavior(语音/file 等)不动 Kind 模块 | impl |
| 89 | **`Esr.Kind.Server.handle_info/2` 统一 Behavior 消息转发器**(新合约面)— 任何非 dispatch 入站(Process.monitor `:DOWN`, bridge `send/2` 回调, 未来 timer tick 等)都进 Kind.Server 单 mailbox,转发到每个 composing Behavior 的可选回调 `handle_kind_message(message, slice, ctx)`,返 `{:ok, new_slice}` 或 `:ignore`。Kind.Server 仍完全不感知任何业务 Behavior。Phase 2 Chat 用这个 hook 实现 offline 状态机(:DOWN→last_seen)和 bridge→Agent reply 回路。在 §5.7.4 Kind.Server 节增补合约 | impl |
| 90 | **`ctx.kind_module` + `ctx.self_uri` 在 Kind.Runtime 注入**(Invocation flow 增补)— Behavior 跨 Kind 时(Chat 的 :receive 要分支 User vs Agent / Session 的 :send 要 broadcast topic 含自己 URI)需要这两个值,Phase 1 没有。Kind.Runtime.handle_dispatch/4 在 `invoke_behavior` 前单点 `Map.put` 注入,plugin 作者永远不需要手 plumb。`Invocation.ctx` type spec 同步:这两 key 是 runtime-injected,Behavior 内可见,adapter 构造 Invocation 时不需要填 | impl |
| 91 | **MessageStore 为聊天历史的单一真相源**(Phase 2 P2-D3)— Session.Chat slice 只持 ephemeral 在线状态(members/monitors/last_seen),offline 期消息从不维护 pending queue;rejoin 时通过 `MessageStore.in_session_since(session_uri, last_seen[uri])` 派生 replay 集,SQL `LIMIT 1000` 兜底超长 backlog。理由跟 memory `feedback_converge_to_uri_list` 同源(可派生的不该独立维护)。详见 `apps/esr_core/lib/esr/message_store.ex` | impl |
| 92 | **`InterfaceValidator` 加 `:uri` primitive**(§6.2 type-spec 语法扩展)— Chat 的 `@interface` schema 声明 `sender: :uri, mentions: {:list, :uri}` 等典型 URI 字段,validator 在 dispatch 边界要求 `%URI{}` struct,**拒绝裸字符串**。配合 `Esr.Ecto.URI` 自定义 Ecto type 实现 URI 跨进程/跨持久化层都是 struct,序列化/反序列化由专门 type 处理 | impl |
| 93 | **`session://` URI scheme + 两条新 PubSub `:events` 通道**(§3.5 URI types + §5.7.6 topic taxonomy 扩展)— Phase 2 新增 `session://` 作为 Kind URI scheme(Session Kind 用)。`esr:session:<uri>:events` 用于 chat stream 订阅(消息/成员变更/online-offline)+ `esr:user:<uri>:events` 用于个人 inbox 通知。两个 topic 都是 §5.7.6 的 view fan-out 合法用法(已加入 `check_invariants` #1 allowlist) | impl |
| 94 | **Bridge↔Agent dual map**(v1_prototype 实现层模式,Phase 5 channel 重写时复用)— `Esr.Bridge.V1Prototype.Server` 同时维护 `bridge_to_agent: %{bridge_id => pid}` + `agent_to_bridge: %{agent_uri_str => bridge_id}`。出站(Agent.invoke(:receive) → claude)用 `bridge_for_agent/1`;入站(claude reply tool → Agent)用 `forward_reply_to_agent/2` 找 pid → `send/2`。模式本质:wire-id 和 business-URI 解耦,routing 层不感知 wire 协议。Phase 5 esr_plugin_cc_channel 重写时延续此模式 | impl |
| 95 | **RoutingRegistry 作第 3 个 Registry 家族 + owner-pid check**(Phase 3a 落地 Decision #28/#37/#65)— `Esr.RoutingRegistry` 跟 `KindRegistry`(URI→pid,boot 时 register)/`BehaviorRegistry`(boot-only 注册,last-writer-wins OK)并列;独有 **owner-pid check**(declare_table 时记 owner,只该 pid 能写)— 因为 admin 是**运行时**写 routing rules(`mix esr.routing.add_rule` / Phase 4 LV 表单),不像 BehaviorRegistry 是 boot-only。Plugin X 不能 stomp plugin Y 的 routing table。详见 `apps/esr_core/lib/esr/routing_registry.ex` moduledoc 三者对比表 | impl |
| 96 | **Matcher AST 5 leaf + JSON serde**(Decision #41/#42/#70 落地)— `Esr.Routing.Matcher` 5 个 leaf(`mention/from/text_contains/text_matches/always`);plain tuple 形态(`{:mention, "agent://X"}`)无 macro;`to_json/1` + `from_json/1` 让 matcher 进 SQLite `routing_rules.matcher_data` 列。组合子(and/or/not)Phase 4+(P3-D3 决定单层规则 + 多条规则 additive 已覆盖 demo 场景)| impl |
| 97 | **Resolver 双层 fan-out:cross-session 走规则 + in-session 走 members fall-through**(P3-D impl 决策 b)— `Chat.invoke(:send)` 先调 `Esr.Routing.Resolver.resolve/2` 拿 cross-session targets,再 always 加上 in-session members(`Map.keys(slice.members)`)— 同一条 message 同时落本 session 成员 + 走规则到其他 session。Recursion guard:不 re-dispatch 到 current session。这是 router 真正能让"在 main 发的 urgent 消息**同时** 落 oncall"工作的关键 | impl |
| 98 | **`message_routings` 关联表保 Decision #40 identity invariant + 多 session 持久化**(#P1-4 spec review 修复)— Phase 2 `messages.uri` 是 PK,Phase 3 D8 reply 可同时 target N 个 session → PK 冲突。新 `message_routings` 复合 PK `(message_uri, session_uri)`:`messages` 保 1 行/uri(identity invariant 不破),per-session 路由信息走 routings 表。`MessageStore.write/2` 内 transaction upsert messages + insert message_routings。新加 `MessageStore.sessions_for_message/1` 给 ref/session_uris 一致性 soft warn 用 | impl |
| 99 | **Identity Behavior in slice + admin_caps 注入 init_slice**(Phase 3d step 1 / Decision #24 落地)— Phase 1-2 admin_caps 是 `Esr.Entity.User.admin_caps/0` module function 硬编码常量。Phase 3d 加 `Esr.Behavior.Identity`(`@callback init_slice/1` 读 `args[:initial_caps]`,默认空 MapSet)+ User Kind.behaviors 加 Identity。chat plugin Application spawn admin User 时传 `kind_server_spec(:user_admin, User, admin_uri, %{initial_caps: User.admin_caps()})`(per #B1 — kind_server_spec/4 加 extra_args 参数)。caps 现在在 `:sys.get_state(admin_user_pid).state.identity.caps` 可观测 | impl |
| 100 | **`Esr.Capability.cap_for_action/3` helper**(#P1-8)— dispatch step 5.5 需要的 "action → cap_needed" 反查,签名加 `target_uri`(必填)以从中提取 `instance`(via `Esr.URI.instance/1`)。返 `%{kind, behavior, instance}` 喂 `matches?/2`。`behavior` 从 `BehaviorRegistry.lookup(kind_module, action)` 拿,缺失则返 `:unknown`(caller 决定 deny vs skip)| impl |
| 101 | **Phase 3d hard flip:`:stub_grant` 永久死亡 + check_invariants #9 #10 invariant test gate**(P3-D6 落地)— `Esr.Kind.Runtime.handle_dispatch` step 5.5 的 `authz_stub/4` 函数**整个删除**,替换为 `authz_check/4`(真 `Capability.matches?` + `[:esr, :authz, :granted]` / `:denied` telemetry)。`:stub_grant` atom 全 codebase 清空(per #B5:audit.ex/telemetry.ex/admin_live.ex 的字符串/atom 用法全改为 `granted/denied`)。**runtime invariant test**(`runtime_phase3d_test.exs`)真正构造 deny ctx → dispatch → 断言 `{:error, :unauthorized}` + `:denied` telemetry — 这是 invariant #10 的**语义 gate**(grep 只是 tripwire,per memory `feedback_completion_requires_invariant_test`)| impl |
| 102 | **Reply 契约 D8:`{session_uris: [URI], text, ref?}`** — Python bridge `reply` MCP tool 三字段;`session_uris` 是 list(claude 可一次回 N session,典型场景:跨 session 转发);`ref` optional(支持 proactive reply,无 inbound 触发也能 reply)。Agent.handle_kind_message 用同一 `%Esr.Message{}` envelope dispatch chat/send per session_uri(identity invariant — 配合 #98 message_routings)。ref + session_uris 不一致 emit `[:esr, :chat, :reply_session_mismatch]` telemetry 但**仍按 session_uris 路由**(soft warn,信任 claude 显式决定)| impl |
| 103 | **Bridge↔Agent floating (P3-D9 contract change) + LV @-dropdown 只列 session 成员**(real-claude e2e exposed)— Phase 2 bridge announce auto-join `session://main`;Phase 3 改为 spawn Agent Kind 但**不 join 任何 session**(floating),admin 通过 LV "Add to session..." dropdown 显式拉入。配合 LV 修复:compose 区 `@ agent` dropdown 只列 current_session_uri 的 members(不再列所有 KindRegistry agent://),空时显 hint "(no agents in this session — add one via Floating list)"。multi-agent demo 暴露的 UX 问题(@ floating agent 后 message 静默 drop)的根本修复 | impl |
| 104 | **push_to_claude meta 必含 `"session"` 字段 + reply dispatch failure 可见**(real-claude e2e hotfix)— `Chat.invoke(:receive)` Agent 分支构造 push_to_claude 的 meta 时**必须**包含 `"session" => URI.to_string(ctx.caller)`(`ctx.caller` 是 Session.dispatch_receive 设的源 session URI),claude 才能正确填 reply 的 `session_uris`。配合:`Chat.handle_kind_message` 在 dispatch chat/send 返 `{:error, _}` 时 emit `[:esr, :chat, :reply_dispatch_failed]` telemetry(以前静默 drop,real-claude 测试时把 reply 发到 `session://admin` 这种瞎猜的不存在 session,完全丢失) | impl |

实施期决策(impl)将持续从 #105 起 append →

---

## 2. 术语表

ESR domain 词汇,按字母顺序。

### Adapter

外部 transport 接入点。**Adapter 不允许有业务语义**——它只做两件事:解析外部输入 → 构造 `%Invocation{}`;渲染结果回外部协议。

例:`esr_plugin_feishu` 是 Feishu adapter;`esr_adapter_cli` 是 CLI adapter;`esr_plugin_cc_channel` 是 CC channel adapter(双侧组件)。

参考: ARCHITECTURE.md §12

### Adapter Driver 关系

Adapter subprocess 由谁拉起:

- **ESR-driven**: ESR 通过 `Esr.Behavior.OSProcess` 拉起 subprocess(Feishu/Slack)
- **External-driven**: subprocess 由外部 host 拉起,主动连入 ESR(CC Channel 由 `claude --channels` 拉起)

参考: ARCHITECTURE.md §12.4,Decision #54

### Audit Log

每条 Invocation 的执行记录,异步写入 SQLite `invocations` 表。**通过 `:telemetry` event 触发,`Esr.Audit.Writer` GenServer 异步 cast batch + 100ms flush**;不阻塞 invoke 路径。

参考: ARCHITECTURE.md §10.2,Decision #60

### Behavior

Kind 上的能力切片,跨 Kind 复用。每个 Behavior 模块定义 `actions/0`、`state_slice/0`、`init_slice/1`、`invoke/4`。Behavior 是 plugin,不是 core(core 只有 behaviour 契约)。

```elixir
defmodule Esr.Behavior.Chat do
  use Esr.Behavior
  @interface [
    receive: %{args: %{message: Esr.Message}, ...},
    send: ...
  ]
  def actions, do: [:receive, :send]
  def state_slice, do: :chat_state
  def init_slice(_), do: %{...}
  def invoke(:receive, slice, args, ctx), do: ...
end
```

参考: ARCHITECTURE.md §6,Decision #2

### BehaviorRegistry

`{Kind, action}` → Behavior module 的运行时映射。Plugin 通过 `Esr.BehaviorRegistry.register/3` 在 Application.start/2 时注册。

参考: ARCHITECTURE.md §6.4

### CapBAC

Capability-based access control。ESR 的权限模型——每个 Invocation 在 `ctx.caps` 携带 capabilities;dispatch step 5.5 检查 caller 持有的 caps 是否允许该 action。

参考: ARCHITECTURE.md §7,Decision #4

### Capability(`%Esr.Capability{}`)

权限 token,struct(不是字符串)。字段:

```elixir
%Esr.Capability{
  kind: module() | :all,           # 哪种 Kind 类型
  behavior: module() | :all,       # 哪个 Behavior
  instance: URI.t() | module() | :all  # 哪个 instance (or scope)
}
```

参考: ARCHITECTURE.md §7,Decision #38

### Channel(Claude Code Channel)

Anthropic 给 Claude Code 的"外部事件 push to TUI"机制。**MCP 协议的一个扩展 capability**(不是独立通信协议,Decision #86 Phase 1b 实证)——一个 channel 就是个普通 MCP server,多三件事:`capabilities.experimental['claude/channel']` + `notifications/claude/channel` notification(server → claude,渲染 `<channel source="...">`)+ 标准 MCP tool(如 `reply`,claude → server)。

ESR 通过 `esr_plugin_cc_channel`(Elixir HTTP/SSE + Python MCP server)桥接外部 CC 实例。Python 侧是普通 MCP server,走 stdio 跟 CC 通信;Elixir 侧通过 HTTP/SSE 跟 Python 通信。**不需要独立 channel-server 进程,不需要 WebSocket** — 这是 v0.3 §12.8 的认知错误,Phase 1b 纠正。

⚠️ 易混淆 — Phoenix.Channel 是 Phoenix 框架的 WebSocket 抽象,跟 CC Channel 完全是两件事(碰巧同名)。见 §3 易混淆词表。

参考: ARCHITECTURE.md §12.8(Phase 1b 后已重写),Decision #86

### ctx(Invocation context)

`%Invocation{}.ctx` 字段。包含:

```elixir
%{
  caller: URI.t(),                  # 发起者 principal
  caps: [Esr.Capability.t()],       # caller 持有的 caps
  reply: reply_target(),            # 结果路由(见 ctx.reply)
  idempotency_key: String.t() | nil,
  trace_id: String.t(),
  invocation_id: String.t(),
  ...
}
```

参考: ARCHITECTURE.md §4

### Dispatch

`Esr.Invocation.dispatch/1` — 中心化 invocation 路由入口。所有 actor 间通信都走这条路径,**没有第二条**。9 步标准 flow 见 Appendix A。

参考: ARCHITECTURE.md §5,Decision #3 #43

⚠️ 不要跟 `Phoenix.Router.dispatch`(HTTP path 路由)混。

### DLQ(Dead Letter Queue)

存放失败 invocation + unroutable message 的 SQLite 表。**`unroutable`** 子类:零匹配路由的 message。

参考: ARCHITECTURE.md §5.5.5,Decision #68

### Entity

Kind 三子类之一。**Principal**——发起 Invocation,持有 caps。例:`agent://...` / `user://...`。

参考: ARCHITECTURE.md §3.1,Decision #7

### `@interface`

Behavior 声明的 action schema(args / returns / errors / modes)。**Single Source of Truth**:所有 UI(LiveView slash command / CLI / HTTP / MCP)从 `@interface` 自动派生,**不写两遍**。

参考: ARCHITECTURE.md §6.2,Decision #8

### Idempotency

`Esr.Idempotency` 模块 — bounded ETS LRU,去重重复 invocation(webhook 重试场景)。`ctx.idempotency_key` 设置后,dispatch step 2.7 自动检查 + record。

**v0 语义:收到即记,不是成功才记**(Decision #76)。失败 invocation 走 DLQ 兜底。

参考: ARCHITECTURE.md §5.7.3

### Invocation(`%Esr.Invocation{}`)

ESR actor 间通信的 envelope:

```elixir
%Esr.Invocation{
  target: URI.t(),         # 谁来处理(Kind 实例 URI + behavior/action 后缀)
  args: map(),
  mode: :call | :cast | :call_stream | :subscribe | :introspect,
  ctx: map()
}
```

参考: ARCHITECTURE.md §4,Decision #3 #5

### Kind

ESR 所有可寻址实体的"class"。每个 Kind 在 `Esr.<Category>.<KindType>` 模块定义。Kind 实例由 URI 标识。

三子类:**Session** / **Entity** / **Resource**(Decision #7)。

参考: ARCHITECTURE.md §3,Decision #1

### KindRegistry

URI → pid 的运行时映射 + type_name → module 的间接层。`Esr.KindRegistry.put_new/2` 保证唯一性(撞 key reject)。

参考: ARCHITECTURE.md §5.4

### Matcher

Routing rule 的 predicate AST。组合子(`always` / `and` / `or` / `not`)+ Message-field matchers(`mention` / `from` / `text_contains` 等)。

Matcher 在 core,**因为读 core 数据 `%Message{}`**(Decision #70)。

参考: ARCHITECTURE.md §5.5

### Message(`%Esr.Message{}`)

ESR Entity-Entity 通信的 envelope(Chat 业务层):

```elixir
%Esr.Message{
  sender: URI.t(),
  mentions: [URI.t()],
  body: term(),
  ref: URI.t() | nil,
  inserted_at: DateTime.t()
}
```

5 字段最小集。Message 是 core 概念(Decision #26),不是 chat plugin 专属。

参考: ARCHITECTURE.md §3.5

### MessageStore

`Esr.MessageStore` — Message 持久化 + query。`append/2` + `query/1`(7 维度:session_uri / mentioning / from / ref_chain / after_ts / before_ts / limit + order)。

参考: ARCHITECTURE.md §10.4

### Mode

Invocation 的 5 个 mode(Decision #5 #39):

| Mode | 语义 |
|---|---|
| `:call` | 同步,caller 等结果;to not-ready 必须 fail-fast |
| `:cast` | 异步 fire-and-forget;to not-ready 进 PendingDelivery buffer |
| `:call_stream` | 同步流式,caller 收 Stream.t() |
| `:subscribe` | 订阅 PubSub topic |
| `:introspect` | 读 Kind 内部状态,read-only |

### PendingDelivery

`Esr.PendingDelivery` — actor not-ready 窗口的 buffer。`:cast` to not-ready 进 buffer,ready 时 flush;`:call` to not-ready fail-fast 不 buffer(Decision #67)。

参考: ARCHITECTURE.md §5.7

### Phoenix.PubSub

actor 间 broadcast 总线。用于**不确定旁观者**(view 渲染、telemetry),**不是 inbound message 投递**(Decision #75 硬不变式)。

⚠️ Inbound message 永远走 `dispatch/1`,绝不裸 `PubSub.broadcast` 到 inbound topic。

参考: ARCHITECTURE.md §5.7.6

### Plugin

OTP application 形式的 ESR 扩展(Decision #17)。Plugin 注册自己的 Kind / Behavior / RoutingRegistry table。

判定原则(Decision #71):
- 读 core 数据 → core
- 读 plugin 专属 payload → plugin
- 业务概念(Chat / Workspace / Identity) → plugin
- 外部协议绑定 → plugin

参考: ARCHITECTURE.md §2.2 / §8

### Plugin 命名形态

- `:esr_behavior_<name>` — 单 Behavior plugin
- `:esr_adapter_<name>` — 单侧 transport adapter
- `:esr_plugin_<name>` — 复合 plugin
- `:esr_web_<name>` — Phoenix 入口 plugin

参考: ARCHITECTURE.md §13

### Principal

发起 Invocation 的主体。在 ESR 里 = Entity Kind 的实例(`agent://...` / `user://...`)。

### ReadyGate

`Esr.ReadyGate` — ETS 三态 ready 表(`:ready` / `:not_ready` / `:unknown`)。`use Esr.Kind` 宏在 GenServer init 完成后 announce_ready;`dispatch/1` 检查 ReadyGate 状态决定走哪条路径(直送 vs PendingDelivery vs fail-fast)。

参考: ARCHITECTURE.md §5.7,Decision #66

### Resource

Kind 三子类之一。**被操作,无 cap**。例:`workspace://...` / `resource://folder/...`。

"Shared referent needs identity"(Decision #63)— 被多方按身份引用的命名锚点需要独立身份,是 Resource 存在的根。

参考: ARCHITECTURE.md §3.1

### RoutingRegistry

外部 key → URI(s) 的运行时映射。Plugin 自声明 table(`declare_table/3`,含 `duplicate_keys: boolean` + 可选 `reverse_index`)。

- Unique-key table 用 `put_new`(撞 key reject)
- Duplicate-key table 用 `put`(append 语义)

参考: ARCHITECTURE.md §5.4,Decision #65

### Session

Kind 三子类之一。**Routing context owner**——IRC 的 channel 类比;RoutingRules 挂在 Session 上;消息 dispatch 时 Session 决定 N 个 receiver。

⚠️ 不是 Phoenix session(cookie / web session)。

参考: ARCHITECTURE.md §3.1,Decision #9

### Slice(state_slice)

每个 Behavior 拥有的 state 切片,在 Kind 模块的 state map 里独立 key。Behavior 只能读写自己声明的 slice(Decision #16)。

```elixir
# Kind GenServer state:
%{
  uri: ...,
  caps: ...,        # Identity Behavior slice
  chat_state: ...,  # Chat Behavior slice  
  routing: ...,     # SessionRouting Behavior slice
}
```

### Snapshot

Kind state 的 SQLite 持久化(`kind_snapshots` 表)。4 种策略(Decision #27):

- `:on_change` — slice 真变了才写(Decision #59)
- `:periodic` — 定时
- `:on_terminate` — Session 类适合
- `:ephemeral` — 不持久化(测试用)
- `:external` — state 在外部系统

参考: ARCHITECTURE.md §10.1

### Stub(authz stub)

Phase 1-3c 的 `authz_check/2` 显式 permissive 实现:**永远 grant,emit `:stub_grant` telemetry**。带 `PHASE-3D-STUB: DO NOT REMOVE` 注释。Phase 3d 起 in-place 替换为真实 cap 检查 + `:granted`/`:denied` telemetry(Decision #82)。

### Template — Class

模块级 Template,开发者写。实现 `@behaviour Esr.Kind.Template`(`validate/1` + `instantiate/2` 等 callback)。决定"这类东西如何 instantiate"。

例:`Esr.Session.Feishu2CC.Template` 是 Feishu↔CC session 的 Template Class。

参考: ARCHITECTURE.md §9.1,Decision #64

### Template — Instance

运行时 Resource Kind 实例,**用户创建**(不是开发者写)。携带具体预设值(folder/agent/settings/env)。被 `/session:new` 引用,merge 进 instantiate 流程。

例:`workspace://esr-dev` 是 Workspace Template Instance 实例;`esr-dev` 是用户起的名字。

`/session:new` 走流程:拿 Workspace state → 调 `TargetSessionClass.validate/1` 检查 → 调 `TargetSessionClass.instantiate/2` 起 session。

参考: ARCHITECTURE.md §9.2,Decision #64

### Type Name(`type_name` / `kind_type`)

Kind 类型的稳定 ID(不是模块名字符串)。`use Esr.Kind, type_name: :agent` 声明;`kind_snapshots.kind_type` 字段存这个;`Esr.KindRegistry` 维护 `type_name → module` 映射。

模块改名时 mapping 改一处,snapshot 不动。

参考: ARCHITECTURE.md §1.2 差异 2,Decision #62

### Unroutable

零匹配路由的 message — routing 算出 0 个 receiver。**必须 telemetry + DLQ unroutable**,不能静默(Decision #68)。

### URI

ESR 寻址 scheme。格式: `<scheme>://<segment>/<...>/behavior/<behavior_name>/<action>`(后半段可选,仅 Invocation target 用)。

例:
- `agent://allen-小满` — Entity 实例
- `session://feishu-cc/cc-7f3a` — Session 实例
- `workspace://esr-dev` — Resource 实例
- `agent://arch-a/behavior/chat/receive` — Invocation target

参考: ARCHITECTURE.md §3.4,Decision #6

### `user://admin`

Bootstrap principal,系统首次启动自动创建,持 all-caps。**不可 revoke**(结构性 invariant 在 `Esr.Capability.revoke/2` 集中检查)。Phase 1-3c LiveView/CLI 默认 `ctx.caller = user://admin`(authz stub 期占位);Phase 3d 起仍持 all-caps。

参考: ARCHITECTURE.md §7.6,Decision #81

### View

`Esr.View` behaviour — outbound 渲染抽象。每个 transport(LiveView / CLI / Feishu / Slack)实现自己的 `Esr.View.render/2`,把 Invocation 渲染成本 transport 的输出格式。

参考: ARCHITECTURE.md §12.7

### Workspace

Template Instance 的代表性例子。**薄 Resource Kind**——state 是 folder/agent/settings/env 预设 bundle;持有命名身份(`workspace://esr-dev`);被 session/user/repo/plugin-config 多方按 URI 引用。

参考: ARCHITECTURE.md §3.1.1,Decision #63

---

## 3. 易混淆词消歧

ESR domain 词跟外部世界(Phoenix / Elixir / 通用计算机科学)同名碰撞。**写文档/代码碰到这些词,必须按 convention 消歧**。

### 消歧 convention

1. **首次出现必须明确**:第一次提到易混淆词时,写全(例:"CC Channel(MCP 协议)"或"Phoenix.Channel(WS 抽象)")
2. **代码 module name 跟着区分**:`Esr.Channel` 是 ESR 内部概念,`Phoenix.Channel` 永远带 namespace
3. **如果上下文已经明确,可以省 prefix**:在 `lib/esr_plugin_cc_channel/` 目录下 "channel" 默认指 CC Channel,这时不需要 disambiguate

### 易混淆词表

| 词 | ESR 意义 | 外部世界意义 | 消歧写法 |
|---|---|---|---|
| **channel** | Claude Code Channel(MCP 协议扩展:`claude/channel` capability + 一个 notification method + tools) | Phoenix.Channel(Phoenix WS 框架抽象) / OTP channel(无此概念) | "CC Channel" / "Phoenix.Channel";两个完全无关,碰巧同名 |
| **session** | ESR Session(routing context owner,Kind 子类) | Phoenix session(cookie/web session) / HTTP session | "ESR Session" / "Phoenix session" |
| **registry** | KindRegistry(URI→pid) / RoutingRegistry(external_key→URI) | Elixir Registry(底层 module) | 显式指 "KindRegistry" 或 "RoutingRegistry";"Elixir Registry" |
| **behavior** | Esr.Behavior(action 处理者,自定义概念) | Elixir behaviour(callback 契约,语言级) | ESR 用 "Behavior" 大写 B;Elixir 用 "behaviour" 小写 b(British spelling) |
| **template** | Template Class(模块级)/ Template Instance(运行时 Resource) | Phoenix template(.heex 文件) | "Template Class" / "Template Instance" / "Phoenix template" |
| **plugin** | OTP app 形式的 ESR 扩展 | Mix.Project plugin(`mix archive`)/ Elixir plugin(完全不同) | ESR 用 `esr_plugin_*` namespace 前缀 |
| **dispatch** | `Esr.Invocation.dispatch/1`(消息分发) | `Phoenix.Router.dispatch`(HTTP 路由) | "Invocation dispatch" / "Phoenix.Router.dispatch" |
| **broadcast** | `Phoenix.PubSub.broadcast`(只用于 view/telemetry,**不用于 inbound message**) | 通用术语 | ESR 写代码时 `PubSub.broadcast` 出现在 inbound 路径 = bug;严格按 Decision #75 |
| **router** | ESR 是 message router(全局架构定位) | Phoenix.Router(HTTP path 路由) | "ESR(message router)" / "Phoenix.Router(HTTP path)" |
| **kind** | ESR Kind(可寻址实体的 class) | (Elixir 无此概念;OO 语言里类似 Class) | 全文用 "Kind",首字母大写 |
| **principal** | 发起 Invocation 的主体(Entity Kind 实例) | (Web 安全/auth 通用术语) | 含义大致一致,不太需要消歧 |
| **transport** | ESR Adapter 的 wire 形态(WS/HTTP/stdio/MCP) | (网络栈 layer 4) | 上下文明确 |
| **scope** | Cap 的三档(`:instance` / `:kind` / `:all`) | 通用术语(变量作用域 / 项目范围 / 等等) | 写 "cap scope" 明确 |

### 命名 convention 总结

- ESR 自定义概念用**大写首字母** + **Esr.* 模块前缀**:`Esr.Kind` / `Esr.Behavior` / `Esr.Channel`(如果有)
- 外部库 / Elixir 语言级概念用**官方拼写**:`Phoenix.Channel` / `Elixir behaviour`(小写)
- 写代码命名变量时避免单词裸用:不要 `channel = ...`,写 `cc_channel = ...` 或 `phoenix_channel = ...`

---

## 4. 维护流程

### 实施期新增 Decision

1. 实施期产生新架构决策(brainstorm 阶段 / dev review / Allen 指示)
2. Append 到 §1 Decision Log,编号递增(下一条 #88)
3. Period 字段标 `impl`(区别 v0.1-v0.4 的"设计期"决策)
4. 决策正文要简洁:**一句话核心 + 关键 link**(到 ARCHITECTURE.md 章节或 phase-specs/)
5. 同步:如果决策影响 ARCHITECTURE.md,Allen 决定要不要 patch 主文档(小决策可能只在 GLOSSARY 记录)

### 新增术语

1. 实施期发现一个**没在 §2 列出但需要 Claude Code / 新人快速理解**的概念
2. Append 到 §2(按字母顺序插入)
3. 包含简要定义 + ARCHITECTURE.md 参考章节
4. 如果该词易混淆,同时加 §3 易混淆词表

### 新增易混淆词

1. 实施期碰到 ESR 跟外部世界的命名碰撞(代码 review 时容易看到)
2. Append 到 §3 易混淆词表
3. 给出消歧 convention(怎么写以区分)
4. 全 repo grep 一遍现有代码 / 文档,确保已有使用都遵循 convention

---

## End

本文件是 ESR 项目的**单一真相源**,跟 ARCHITECTURE.md 平级。实施期任何疑问优先查这里。

**Maintainers**: Allen + Claude(顶层文档维护)+ 工程师(实施期 phase-specs)
**Last updated**: Phase 1 完成(2026-05-15)+ impl 期 #84-#87 入账;Channel 术语 + 易混淆词表同步 Decision #86 后简化定义
**Decision Log status**: #87(下一条 #88,实施期持续 append)
