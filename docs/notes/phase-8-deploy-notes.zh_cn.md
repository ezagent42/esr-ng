# Phase 8 — 分支验证指南

**分支**：`feat/phase-8-ide-shell-liveview`
**状态**：未 merge 到 main；待 Allen 审阅 + 决定
**作者**：Claude Opus 4.7 (1M)
**日期**：2026-05-19

---

## 启动步骤

```bash
cd /Users/h2oslabs/Workspace/esr-ng
git checkout feat/phase-8-ide-shell-liveview
git pull origin feat/phase-8-ide-shell-liveview     # 远程已 push

# 1. DB 干净重启
ps aux | grep "ezagent_runtime" | grep "$(whoami)" | grep -v grep | awk '{print $2}' | xargs kill -9 2>/dev/null
sleep 3
mix ezagent.db.reset && mix ecto.migrate

# 2. 启动 phx
EZAGENT_HOME=$HOME/.ezagent EZAGENT_PROFILE=default \
  ELIXIR_ERL_OPTIONS="-name ezagent_runtime_phase8@127.0.0.1 -setcookie $(cat $HOME/.ezagent/default/runtime/cookie)" \
  mix phx.server

# 3. 在另一个 shell 设置 admin 密码
mix ezagent.user.set_password entity://user/admin --password <你选一个>

# 4. 浏览器访问
open http://127.0.0.1:10042/login
# Entity URI: entity://user/admin
# Password: <你刚设的>
```

---

## 应当看到的 IDE Shell（与旧版的对比）

### 旧版 (`main` branch)
- 顶部 5 个水平文本链接 (Workspaces / Routing / Users / Snapshots / Entities)
- 中间 3 列网格 (左 sessions / 中 chat / 右 members)
- 底部展开式 debug panel
- 每个其它页面自带独立的 page header + ← /admin 返回链接

### 新版 (`feat/phase-8-ide-shell-liveview`)
- **左侧 Activity Bar**: 7 个图标 (Sessions / Workspaces / Identities / Routing / Plugins / Observability / Settings)，hover 显示 tooltip，点击切换页面
- **Activity Bar 右侧 Resource Panel**: 200px 宽，显示当前 Activity 的上下文资源（如 Sessions Activity 显示 Direct/Group/Floating Sessions；Workspaces Activity 显示 workspace 列表；Routing Activity 显示 routing tables）
- **Top Command Bar**: 顶部 40px 高，包含
	- 左侧 ezagent 品牌 + workspace 名
	- 中央 CmdK 搜索按钮（⌘K 快捷键预留，Phase 9 接通后端）
	- 右侧 bell / help icon + 当前 Entity URI chip
- **Main Window**: 中央最大区域，展示当前页面主体（chat / table / form / 等）
- **Right Sidebar**: 默认隐藏（响应式 lg+ 显示），显示成员列表或上下文详情
- **Status Bar**: 底部 24px 高，显示
	- 当前 Entity URI
	- Workspace 名
	- Session URI（如有）
	- agents alive 数（绿点 + N）
	- bridges 连接数（status dot）
	- 🐞 events 数（链接到 /admin/observability）
	- 编译版本

---

## 7 个 IDE Shell 已接入的页面

| 路径 | LV | Activity Bar 高亮 | Resource Panel 内容 |
|---|---|---|---|
| `/admin` | AdminLive (Sessions) | Sessions | 现有 sessions_sidebar (Direct/Group/Floating) |
| `/admin/workspaces` | WorkspacesLive | Workspaces | workspace 名列表 |
| `/admin/workspaces/:name` | WorkspaceDetailLive | Workspaces | 当前 workspace + ← back |
| `/admin/entities` | EntitiesLive | Identities | filter chips (all/user/agent/session/...) |
| `/admin/routing` | RoutingLive | Routing | routing table 切换按钮 |
| `/admin/users` | UsersLive | Identities | (空，单页表格) |
| `/admin/settings` | SettingsLive | Settings | 5 个 section 切换 (Account/Preferences/Keyboard/Access/System) |
| `/admin/observability` | ObservabilityLive | Observability | 5 个 tab 切换 (Overview/Events/Audit/Bridges/Snapshots) |

---

## 仍保留旧布局的页面 (Phase 9 polish 完成)

这些页面通过 URL 直接访问可用，但**还没包裹进 IDE Shell**：

- `/admin/users/:uri/caps` — UserCapsLive
- `/admin/users/:uri/api-keys` — UserApiKeysLive
- `/admin/snapshots` — SnapshotsLive (替代品在 `/admin/observability` 的 Snapshots tab)
- `/admin/agents/:uri` — AgentDetailLive
- `/admin/agents/:uri/terminal` — PtyTerminalLive
- `/admin/auto/:kind`, `/admin/auto/:kind/:uri` — AutoDeriveLive
- `/admin/feishu/bindings` — FeishuBindingsLive (从 Plugins Activity 链接进入)

Phase 9 用同样的 2-line pattern 包裹（`alias EzagentDomainUi.IdeShell` + `<IdeShell.ide_shell ...>` 包裹 render 主体）。

---

## 已知限制 / 未完成的 spec 章节

| spec 章节 | 状态 | 备注 |
|---|---|---|
| §5 阶段 A (primitives + shell 组件) | ✓ done | 12 个 primitives + 7 个 shell 组件 + 15 单元测试 |
| §5 阶段 B (admin_live 接入) | ✓ done | render/1 全部用 IdeShell 包裹 |
| §5 阶段 C (4 个高优先级 LV 接入) | ✓ done | workspaces/entities/routing/workspace_detail 都接入 |
| §5 阶段 D (新 Settings + Observability) | ✓ done | 两个新 LV + router 路由 |
| §5 阶段 E (剩余 8 LV 浅迁移) | partial | 仅 users_live 接入；其余 7 个待 Phase 9 |
| §5 阶段 F (CmdK Command Palette) | deferred | UI 骨架已 ship；fuzzy 搜索后端 + ⌘K 快捷键绑定待 Phase 9 |
| §5 阶段 G (验证 + 截图) | ✓ done | 见 `/tmp/phase8-ide-shell-tour.webm` |
| §5 阶段 H (文档 + push) | ✓ done | 本文件 |

---

## 验收清单（spec §6）

按浏览器中逐项核对：

- [ ] 最左侧有 Activity Bar (7 个图标)
- [ ] Activity Bar 右侧是 Resource Panel
- [ ] 顶部有 Top Command Bar (含 CmdK 搜索框)
- [ ] 中央 Main Window 显示 chat (默认 Sessions Activity)
- [ ] Right Sidebar 默认窄栏 + 展开按钮 (lg+ breakpoint)
- [ ] 底部 Status Bar 显示 Entity / Workspace / Agents 计数 / Bridges 计数 / version
- [ ] ⌘K 打开 Command Palette modal **(deferred 到 Phase 9)**
- [ ] 切换 Activity 触发浏览器导航
- [ ] Settings, Observability 两个新 page 可用
- [ ] 不再有顶部水平 5 链接条
- [ ] 12 个 app 全 `mix test` 0 failures **(测试 infra SQLite 问题，单 app 跑都 pass；umbrella 多 app 跑有 DB pool 竞争 — pre-existing 问题)**
- [ ] Sessions, chat send, agent 反应 等 v1 行为完整保留

---

## 不变性测试

`apps/ezagent_domain_ui/test/ezagent_domain_ui/ide_shell_test.exs` 包含 15 个测试覆盖：

- 6 区域渲染完整
- activity_for_path/1 映射所有路径
- activity_items/0 返回 7 个 + 顺序
- status_bar 段都展示
- editor_tabs 按 key 标识
- command_palette open/hidden 切换

执行：`mix test apps/ezagent_domain_ui/test/ezagent_domain_ui/ide_shell_test.exs`

---

## 决定事项 (待 Allen 回来确认)

1. **CmdK Command Palette** — UI 骨架已 ship；要 Phase 9 单独 PR 接通 fuzzy 搜索后端 + ⌘K 快捷键？或者你期望本次就完整接通？
2. **剩余 7 个长尾 LV** — 当前可访问但无 IDE Shell。Phase 9 polish 完成？或者你想 merge 当前再说？
3. **是否 merge** — 当前分支 `feat/phase-8-ide-shell-liveview` 已稳定；浏览器 e2e 显示新 IDE Shell 工作；测试 infra 问题 pre-existing。你可以决定：
	- (A) 直接 merge 当前分支 + Phase 9 后续 polish
	- (B) 让我先把 Phase 9 (CmdK + 长尾 LV) 完成再 merge
	- (C) 你 review 一两个具体问题后定
4. **Right Sidebar 在 lg- 屏幕的策略** —— 当前 `hidden lg:block`；你 desktop 应当能看到。如果你想 mobile 也能用，改成 togglable button。
