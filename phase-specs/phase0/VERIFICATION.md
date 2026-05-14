# Phase 0 — VERIFICATION

> **先于 PLAN.md 写**(M1 / Decision #80)。VERIFICATION 是 phase 完成的验收契约。
> Phase 0 是单块 phase(无 sub-step),所以这是 **phase 级验收 gate**。
> 配套:`SPEC.md` / `PLAN.md` / `DECISIONS.md`

## Phase 0 验收 checklist

全绿才能 tag `phase0`:

### 结构
- [ ] esr-ng 是 Mix umbrella;`apps/esr_core/` + `apps/esr_web/` 存在
- [ ] `esr_core` app 的 `mix.exs` deps **不含 `:phoenix`(框架)** 也不含 `:phoenix_live_view` / `:bandit` / `:plug` 这些 web-transport 依赖。**允许**含 `:phoenix_pubsub` / `:telemetry*` / `:ecto_sql` / `:ecto_sqlite3` / `:jason` 等独立 OTP 生态库(它们不需要 Phoenix 框架)
- [ ] phx.new 默认的 `esr_core_web` 已重命名为 `esr_web`(目录 + mix.exs app name + `EsrWeb` 模块前缀 + config 引用全部同步)
- [ ] 奠基提交的 5 个文档在根:`ARCHITECTURE.md` / `GLOSSARY.md` / `IMPLEMENTATION_ROADMAP.md` / `CLAUDE.md` / `ARCHITECTURE_GRILL_v0.3.md`
- [ ] `AGENTS.md` 存在(phx.new 生成,未被重写)
- [ ] `phase-specs/phase0/` 4 文件在版本控制里

### 编译 + 测试
- [ ] `mix deps.get` 成功
- [ ] `mix compile` 无 error、无 warning
- [ ] `mix test` 绿(只有 phoenix 自带 test)
- [ ] `mix format --check-formatted` 通过

### 运行(从 tailnet IP 验,不是 localhost)
- [ ] `mix phx.server` 起得来,dev endpoint 绑 `0.0.0.0:4000`(不是 `127.0.0.1`)
- [ ] 从 tailnet `curl http://<tailnet-ip>:4000/_health` 返回 200 + `{"status":"ok"}`
- [ ] 浏览器从 `http://<tailnet-ip>:4000` 打开 → 看到「ESR v0.4 — phase 0 complete」首页
- [ ] 从 tailnet IP 访问时 **LiveView WS 连得上**(`check_origin` 已放行 tailnet IP / dev 期 `check_origin: false`)—— 页面不是静态的,LiveView socket 真连上
- [ ] `mix ecto.create && mix ecto.migrate` 跑通,SQLite 文件生成

### 工具链
- [ ] `.claude/skills/` 有迁移过来的 5 个 skill(elixir-phoenix-helper / erlexec-elixir / commit-work / grill-me / grill-with-docs),spot-check 一个能正常 invoke
- [ ] `.claude/settings.json` 是 esr-ng **全新写**的 —— 没有指向不存在的老 esr 脚本(grep 确认无 `pre-merge-dev-gate.sh` / `openclaw-channel-postcheck.sh` / `replay-guide-reminder.sh` 死引用)
- [ ] `mix esr.check_invariants` 能跑,输出「Phase 0: no invariants apply yet」,exit 0
- [ ] B git-hook:`scripts/hooks/sub-step-gate.sh` 存在 + 可执行;`.claude/settings.json` 的 PreToolUse hook 配好;手动触发能跑 `mix test` + `mix format --check-formatted`

### 不变式 grep checklist
Phase 0 **无 dispatch 路径,8 条硬不变式都不适用**。本 phase 的 `check_invariants` 是骨架。
8 条不变式的真实 grep 检查从 **Phase 1** 起建立(那时有 dispatch / Kind / Behavior / 路由)。

### e2e flow
Phase 0 **无 e2e flow**(没有 dispatch,`FLOWS.md` 的 F1-F8 一条都跑不了)。e2e flow track 从 **Phase 1** 起(F1 — 文本往返,LiveView + Echo)。

## 人 review 关键点(Allen)

- 空首页从 tailnet IP 可访问?LiveView WS 连得上?
- `mix test` 绿?
- 迁过来的 5 个 skill 在新 repo 工作?
- esr-ng 的 `settings.json` 没有残留 esr-specific 的死引用?
- `esr_core` 的 `mix.exs` 没有 `:phoenix`(框架)依赖?(架构纯度的第一道关 —— 见下)

## 为什么「esr_core 不依赖 `:phoenix` 框架」是第一道关

1. **依赖方向**:ARCHITECTURE.md §2.3/§12 把 Phoenix 定为 **transport**,transport 可插拔(Feishu/CC/CLI/LiveView 都是 adapter)。依赖箭头必须 `transport → core`,绝不 `core → transport`。core 一旦依赖 `:phoenix`,箭头就反了。
2. **结构性强制**:依赖物理上不在,就**不可能**手滑把 transport 代码塞进 core —— 编译器替你守架构,比纪律可靠。
3. **core 可纯 OTP 单测**:dispatch / Kind / registry 应该不起 web 栈就能测。core 依赖 `:phoenix` 的话,每个 core 测试都拖着 Endpoint/Bandit。
4. **plugin 隔离北极星的前提**:core 必须 transport-agnostic;跟某一个 transport 的框架绑死,正好是反面。
5. **federation 留口**(§17.3):节点是「SQLite + 单 BEAM」,core 是纯 OTP 才可能跑 headless relay。

**为什么是「第一道」**:这是最容易手滑犯(phx.new umbrella 脚手架可能把 `:phoenix` 接到错的 app)、又最难回头的违规 —— Phase 0 没接住,后面每个 phase 都建在错的依赖图上。Phase 0 验收接住 = 在任何上层代码写之前接住。

**精度**:守的是不依赖 `:phoenix`(**框架**),不是「不沾 Phoenix 任何东西」。`:phoenix_pubsub` 是独立 hex 包(无 `:phoenix` 依赖),esr_core 的 `:subscribe` mode 合法用它;`:telemetry` / `:ecto` 同理。
