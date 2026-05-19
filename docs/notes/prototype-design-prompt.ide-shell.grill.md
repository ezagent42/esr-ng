# Grill report — `prototype-design-prompt.ide-shell.zh_cn.md`

Reviewer: opus-1m subagent
Date: 2026-05-19
Inputs: ide-shell variant (692 lines) vs baseline zh/en prompt (~542 lines), SPEC v2 (`docs/notes/uri-design.md` §5+§6), entity-agnostic reflection (10 proposals S-1..S-10), ARCHITECTURE Decision Log, GLOSSARY.

Verdict legend: **ACCEPT** | **REJECT** (with reason) | **REFINE** (suggested rewrite).

---

## §1 Summary

1. **The IDE-shell IA reorganisation is mostly sound** — Activity Bar / Left Panel / Main Window / Right Sidebar / Status Bar maps the existing 14 routes cleanly without inventing new entities, and the "Main Window largest, everything else small" rule is a defensible response to the v1 noisy three-column layout.
2. **CRITICAL — the variant ships with stale URI examples.** The top header asserts "post-SPEC alignment 2026-05-19" and adopts §5.1 (2-segment authority) + §5.2 (query string action), but every URI in the body still uses `user://default/...` / `agent://cc/...` / `session://default/...`. SPEC v2 §5.12 collapsed `user://` and `agent://` into `entity://user/<name>` and `entity://agent/<flavor>_<name>`. SPEC v2 §5.13 deleted `message://`. SPEC v2 §5.6 closed the allowlist at **6** schemes — but §330 of the variant says **8** schemes and lists `message` + `agent` + `user` which no longer exist. This is a self-inconsistency the variant must fix before it can ship to a designer.
3. **The Activity-Bar item `Users` demoted to `Settings → Access & Identity` is an entity-agnostic regression** — it doubles down on §3.5 of the entity-agnostic reflection (admin has no symmetric "what's alive?" surface across both Entity sub-types). Recommend renaming Users → `Identities` / `Access` and keeping it Activity-Bar-level OR (better) building S-5 from the reflection: a unified `/admin/live` "Entities" surface.
4. **`<UriChip>` validation rule in §3a is wrong post-SPEC** — line 330 enumerates 8 schemes including `agent` + `user` + `message`. Under SPEC v2 the 6 schemes are `entity / workspace / session / template / resource / system`. Validator must match SPEC §5.6, not the variant's enumeration.
5. **Agent-as-IDE-user is acceptable in principle but the variant lets the IDE metaphor leak.** Phrases like "Workspaces 列表", "editor tabs", "split panes" transfer cleanly. But "Recent Agents", "Running Agents", "Agent Templates" sub-tree in the Agents Activity duplicates `/admin/agents`+ `/admin/snapshots`+ `WorkspaceDetail.templates`; the variant doesn't say which is canonical. Recommend the Left Panel Agents tree be views of single backing concepts, not new ones.

---

## §2 Per-change verdicts

### 2.1 IDE-shell IA replacing left-sidebar shell — ACCEPT

> "本轮设计方向更新（2026-05-19）：Web Admin 不再按 Slack-clone 方式组织，而按 Agent IDE Shell 组织." (variant §0)

vs baseline §2 "导航模型 —— 请替换掉当前的顶部导航" which proposed a **left sidebar shell** with collapsible nav groups.

ACCEPT. The IDE-shell metaphor is *strictly more expressive* than the sidebar metaphor for ezagent's actual workload (multiple concurrent agents + sessions + workspaces + observability, all viewed at once). Activity Bar + Main Window with multi-tab + split panes is exactly what the existing PTY/Chat toggle + DebugDrawer want to grow into. The baseline's flat left-sidebar would have re-introduced the same noise problem in 6 months.

Caveat: the metaphor must not import implicit IDE assumptions that don't transfer (see 2.7 below — Recent Agents, File Tree absent, etc.).

### 2.2 7 top-level Activity-Bar items — REFINE

> "默认保持 7 个顶级功能...: Sessions, Workspaces, Agents, Routing, Plugins, Observability, Settings." (variant §1.5)

vs baseline left-sidebar groups: Chat, Workspaces, Agents, Users, Routing, Observability, Integrations (= 7 entries, same count).

REFINE. Two issues:

- **`Users` was demoted to Settings → Access & Identity.** This is wrong per entity-agnostic principle. Users are Entity-sub-type-1; demoting them while keeping Agents Activity-Bar-level reinforces the §3.5 reflection bug ("the operator has no symmetric 'what's alive?' surface"). Recommended fix: rename the Activity-Bar item to `Identities` or `Entities`, host both Users and Agents under it, and demote `Agents` from its own slot. OR keep Users at top-level and rename to `Access`. Either way, **don't bury identity management 2 clicks deeper than agent management**.

- **`Plugins` as a top-level item.** ezagent has 4 plugins today (`cc`, `curl_agent`, `feishu`, `echo`) + `liveview` itself. Surfacing them as Activity-Bar-level real-estate inflates a runtime concern that operators touch monthly into the same prominence as Sessions (touched constantly). Recommend demoting Plugins to Settings → Plugins or to Observability → Plugins. Use the freed slot for Identities (per the previous point).

Suggested final list of 7: **Sessions, Workspaces, Identities (was Users + Agents merged), Routing, Observability, Settings, _slot-for-future_**. Or 6 + a CmdK that's the actual escape hatch (it already is per §1.7 of the variant).

### 2.3 CmdK Command Palette at top — ACCEPT

> "顶部常驻一个 CmdK 命令入口... 搜索 sessions、entities、actions、workspaces、plugins、routes、recent." (variant §1.7)

baseline: no equivalent.

ACCEPT. CmdK is the right answer to "I want every Entity to reach every action without me having to design 7 nested trees." It also fixes the entity-agnostic problem (an agent driving agent-browser can `?action=` URI directly; a human types in CmdK). Both routes go through one resolver.

Refine note (small): the variant's grouping list says "Sessions, Entities, Actions, Workspaces, Plugins, Routes, Recent" — 7 groups. SPEC v2 has 6 schemes. The CmdK groups should mirror the schemes 1:1 (Entities / Workspaces / Sessions / Templates / Resources / System) + (Actions, Recent). Designer wouldn't know without being told.

### 2.4 Main Window with editor tabs + split panes — ACCEPT

> "Main Window 中央最大区域... 支持多 tab、split panes、Chat / Terminal / Workspace / Routing 等 editor tab." (variant §1.5)

baseline §1.3: "主面板内的标签条 (tab strip)、页头里的分屏切换按钮 (split-pane toggle)、或一个滑出抽屉 (slide-over drawer) 都可以."

ACCEPT. This is a *concretisation* of the baseline's "designer chooses one of three" → "use tabs + splits". Clean, removes ambiguity. The "default single pane, user opens Split View explicitly" rule is correct.

### 2.5 Right Sidebar default-collapsed — ACCEPT

> "Right Sidebar 默认窄或收起；根据 Main Window 当前 tab 显示 Members、Inspector、Rule Details、Quick Actions." (variant §1.5)

baseline: member panel always-on as a third column.

ACCEPT. Saves Main Window real estate. Aligns with how IDEs (VS Code, JetBrains) handle the inspector — opt-in.

### 2.6 Status Bar with Debug entry — ACCEPT

> "底部 Status Bar 展示系统状态并启动 Debug / Observability 工具." (variant §0, §1.5)

baseline: `<DebugDrawer>` as collapsible bottom region in admin_live.

ACCEPT. Status Bar is the right home — it's persistent across all admin pages (matching the Observability Activity), low-noise default, expandable on click. Better than a per-page collapsible drawer.

### 2.7 Left Panel = "current Activity's resources only" rule — REFINE

> "Left Panel 只显示该功能区内部的资源... 不要在 Left Panel 里再次列出 Sessions / Workspaces / Agents / Routing / Plugins / Observability / Settings." (variant §1.6)

baseline: sidebar held all top-level entries.

ACCEPT the *rule*. REFINE the *content of each tree*:

- **Sessions Activity → Direct Sessions / Group Sessions / Unassigned Agents.** Fine.
- **Agents Activity → Running Agents / Agent Templates / Recent Agents.** Issue: "Recent Agents" is a new concept the codebase doesn't have. Is it MRU-by-operator? Globally-MRU? Persisted? Either spec the storage (UI-only cookie? per-Entity preference Kind?) or drop it. "Agent Templates" overlaps with WorkspaceDetail.templates — say *which* is canonical (recommendation: Templates live under Workspace; the Agents Activity reads them as a view, not a writable surface).
- **Routing Activity → Rules / Targets / Transforms / Registry.** "Transforms" doesn't exist in the codebase (no Transform Kind, no transform table; routing matchers + receivers is the model). Drop or rename. "Targets" is ambiguous — is this Receiver Targets? KindRegistry instances by URI? Be explicit.
- **Plugins Activity → Installed Plugins / Bindings / Generated UI.** "Generated UI" — what is this? Is it `/admin/auto/:kind`? If so, that's a *cross-Activity* concept, not a Plugin sub-section.
- **Observability Activity → Overview / Events / Audit Log / Bridges / Snapshots / Debug Streams.** Solid.
- **Settings Activity → Account / Preferences / Keyboard / Access & Identity / System.** "Access & Identity" being a Settings sub-section is the §2.2 problem above.

REFINE: each Left Panel sub-tree must cite the backing concept by URI scheme + Kind, not invent new vocabulary. The variant introduces ~6 new words ("Recent Agents", "Transforms", "Targets", "Generated UI", "Bindings" as distinct from feishu_bindings, "Registry" as distinct from KindRegistry) — each one is a future-bug if engineers and designers disagree on what it means.

### 2.8 Naming corrections — ACCEPT (mostly)

> "顶级入口使用 Sessions, 不要用 Chat... Group Sessions, 不要用 Channels... Integrations 改为 Plugins... Floating agents 改为 Unassigned Agents." (variant §1.8)

ACCEPT all four. Specifically:

- **"Chat" → "Sessions"**: correct. Chat is a Behavior on the Session Kind, not a domain concept.
- **"Channels" → "Group Sessions"**: correct. Avoids Slack-import (also collides with the now-removed `channel://` scheme that was briefly in the codebase).
- **"Integrations" → "Plugins"**: correct, matches `apps/ezagent_plugin_*` directory naming.
- **"Floating agents" → "Unassigned Agents"**: arguable. "Floating" is the established term in ARCHITECTURE Decision #103 ("Bridge↔Agent floating"). Changing it forces a doc update. ACCEPT but with note: ARCHITECTURE.md must be updated alongside the prototype, otherwise future contributors will read two terms for one concept.

### 2.9 URI examples — `user://default/<name>` etc. — REJECT, MUST REWRITE

> "`user://default/allen`, `agent://cc/cc-architect`, `session://default/review-room`, `workspace://default/research`." (variant §1.1 vocabulary table; appears ~20 times throughout)

vs SPEC v2 §5.12: "user:// and agent:// schemes are deleted. The merged shape: User: `entity://user/<name>`; Agent: `entity://agent/<flavor>_<name>` (e.g. `entity://agent/cc_demo-builder`, `entity://agent/curl_my-deepseek`, `entity://agent/echo_default`)."

vs SPEC v2 §5.6 scheme allowlist: **6** schemes = `entity / workspace / session / template / resource / system`. **No** `user`, **no** `agent`, **no** `message`, **no** `feishu`.

**REJECT** the URI examples in the current form. The variant's top header claims SPEC alignment but the body doesn't honour §5.12. Required rewrites:

| Variant (wrong) | SPEC v2 canonical |
|---|---|
| `user://default/allen` | `entity://user/allen` |
| `agent://cc/cc-architect` | `entity://agent/cc_cc-architect` |
| `agent://curl/deepseek-coder` | `entity://agent/curl_deepseek-coder` |
| `agent://cc/customer-bot` (line 73 example) | `entity://agent/cc_customer-bot` |
| `session://default/review-room` | `session://<template-name>/review-room` (per §5.6 free-form type axis = source template name; if ad-hoc, `session://adhoc/review-room`) |
| `workspace://default/research` | `workspace://default/research` ✓ (already correct) |
| `session://default/allen-cc-architect-dm` | `session://dm/allen-cc-architect` (or whatever DM template name is chosen) |

Also **REJECT** the §3a `<UriChip>` validation enumeration:

> "docs/notes/uri-design.md §5.6 注册的 8 个 scheme 为: agent, user, session, workspace, template, resource, message, system."

This sentence is **factually wrong against the spec it cites**. The real §5.6 lists 6 schemes: `entity, workspace, session, template, resource, system`. The variant's "8 schemes including agent + user + message" is the pre-SPEC-v2 set (v1). Designer using this list will validate canonical URIs as invalid.

**Required rewrite:** replace the enumeration with: "docs/notes/uri-design.md §5.6 注册的 6 个 scheme: `entity`, `workspace`, `session`, `template`, `resource`, `system`. Entity URIs are `entity://user/<name>` or `entity://agent/<flavor>_<name>`."

### 2.10 Feishu treatment — ACCEPT (the prose), REFINE (the placement)

> "feishu 侧通道 (不是 Kind)... 不再有 `feishu://` URI (见 §5.8)。出站 dispatch 走 `user://default/X?action=chat.send`... Invocation 参数里携带 `feishu_id`... 在 WorkspaceDetail / TemplateClassPicker UI 上以飞书绑定表单出现, 不是 Template Class 行" (variant §1.2)

ACCEPT the structural model — this matches SPEC v2 §5.8 exactly. The variant has *correctly* internalised the "plugins don't own schemes" rule for the prose.

REFINE: the URI examples in this same paragraph use `user://default/X?action=chat.send` instead of `entity://user/X?action=chat.send`. Same §2.9 issue.

REFINE further: the variant also retains `/admin/feishu/bindings` as a route AND puts Bindings under Plugins Activity AND has `<FeishuBindingsPage>` as a top-level LV page. The baseline had the same. Recommended: keep the route (it's existing code) but explicitly note in §2 that this route is a *thin admin page* over a join table (`feishu_user_bindings`), not a Kind. Otherwise readers (designer + engineers) will assume `feishu` is a first-class concept the way `Workspace` is.

### 2.11 cc.agent[remote-channel] as sub-row of local-pty — REFINE

> "把它当作同一个 `cc.agent` Template 的另一个 mode 呈现 (PR-D2, 2026-05-19)。很少作为焦点行；通常作为同名 agent 的 local-pty 行的子项呈现." (variant §1.2)

baseline §1.2 said the same.

REFINE. "As a sub-item of the same-named agent's local-pty row" presumes a 1:1 pairing — that for every `remote-channel` agent there's a same-named `local-pty` agent. Per ARCHITECTURE Decision #103 and PR-D2, the two modes are independent: a `cc.agent[remote-channel]` can exist *without* a paired `local-pty`. So "sub-row of local-pty" is misleading visually.

Suggested rewrite: "When a `cc.agent[remote-channel]` agent exists, render it as a separate row in the same list as `local-pty` agents, with a visually distinct mode badge. If both modes happen to share a name (operator convention, not enforced), group them visually under the shared name with the mode as a secondary identifier."

### 2.12 `<MessageComposer>` mention dropdown — ACCEPT

> "Mention 下拉应列出当前 Session 的每一个成员 URI, 不论 Entity 子类型 (`user://default/*`, `agent://*/*`, `system://*/*`)." (variant §3 domain components table)

baseline §3 said similar.

ACCEPT — this is exactly entity-agnostic reflection S-4. Both human members and agent members should be mention-able.

REFINE the URI examples per §2.9: replace `user://default/*` with `entity://user/*` and `agent://*/*` with `entity://agent/*`. And remove `system://*/*` — system URIs are not Session members (they're cap-bearing sentinels, not dispatchable participants).

### 2.13 Sessions Activity Left Panel grouping — ACCEPT

> "Sessions Activity → Direct Sessions, Group Sessions, Unassigned Agents." (variant §1.6)

baseline §1.4 said: `<SessionList>` with "Direct messages" + "Channels" groups + `<FloatingAgentList>` at bottom.

ACCEPT with the renames already accepted in §2.8.

### 2.14 Workspace = Deployment Unit — ACCEPT

> "Workspace (工作区) — 一个**部署单元 (Deployment Unit)** —— 声明开机后应当存活的 entity + session_templates + routing_rules (类比 Kubernetes Namespace; 见 §5.5)" (variant §1.1 vocabulary)

baseline §1.1: "Workspace — 持久化的集群配置: 成员 + session_templates + routing_rules."

ACCEPT — this is a strict improvement, matching SPEC v2 §5.5 framing. The variant teaches the designer the K8s mental model, which is the right one.

### 2.15 `<TemplateClassPicker>` enumerating `cc.agent` / `curl.agent` / `echo` — REFINE

> "横向按钮行, 列出已注册的 Template Class (`cc.agent`, `curl.agent`, `echo` 等), 外加一个 JSON custom 逃生出口. 对 `cc.agent`, 表单包含 `mode` 字段." (variant §3 domain components table)

baseline §3: same enumeration plus `feishu.chat_binding`.

ACCEPT the removal of `feishu.chat_binding` (matches SPEC v2 §5.8).

REFINE: the variant hardcodes the Template Class list (`cc.agent`, `curl.agent`, `echo`). Per **plugin isolation north star** (CLAUDE.md / global memory line "North Star: plugin isolation"), the picker should be a *registry-driven enumeration*, not a hardcoded list. The designer should be told: "render whatever Template Classes the backend registers; do not hardcode names — render them as data."

Suggested rewrite: "横向按钮行, 由后端 TemplateClassRegistry 提供 (`cc.agent`, `curl.agent`, `echo` 是当前已注册的, 但 UI 必须从注册表枚举而非硬编码). JSON 自定义为高级逃生出口."

### 2.16 §3a `<AutoForm>` schema description — ACCEPT (logic), REJECT (the placeholder examples)

> Placeholder shows `placeholder: "agent://cc/cc-architect"` (variant §3a JSON example, line 297)

REJECT this specific placeholder. Per §2.9 it must be `entity://agent/cc_cc-architect`.

ACCEPT the rest of §3a — the field-type-locked-to-4 (`text/path/uri/select`) rule is correct, the auto-derive-from-schema concept is the plugin-isolation enabler, the cap-grant + workspace-add + feishu-binding all reusing AutoForm is correct.

### 2.17 Settings → Access & Identity — REJECT

> "Settings 是'当前操作者和系统显示/访问偏好'的地方... Access & Identity — 入口链接到 Users, Capabilities, API Keys. 具体页面仍使用 `/admin/users`, `/admin/users/:uri/caps`, `/admin/users/:uri/api-keys`." (variant §1.5 settings section)

REJECT placing identity management under Settings. Two reasons:

1. **Entity-agnostic principle violation.** Settings should be operator preferences (theme, density, defaults). Identity (who exists, who can do what, what credentials they hold) is a *system* concern, not an *operator preference* concern. Burying it under Settings reinforces the §3.5 reflection problem: there's no first-class "what entities exist?" surface, only fragmented per-sub-type pages.

2. **`/admin/users` is the *only* place to see who can log in** — and the variant's CmdK lists it as a deep link, not a discoverable nav location. New operators won't find it.

Suggested fix: keep an Activity-Bar item for `Identities` (or rename it `Access` if "Identities" reads weird). Under it: Users (list of `entity://user/*`), Agents (list of `entity://agent/*`), Capabilities (cross-Entity cap matrix), API Keys (per-Entity key vault). Settings then has *only* operator preferences (theme, density, shortcuts, defaults, time format). System version + health goes to Observability → Overview, not Settings → System.

This also closes entity-agnostic reflection S-5 (a unified `/admin/live` surface).

### 2.18 Observability page consolidation — ACCEPT

> "Observability 是'系统发生了什么、为什么这样、哪里出问题'的地方... Overview, Events, Audit Log, Bridges, Snapshots, Debug Panel." (variant §1.5 observability section)

baseline had Snapshots + DebugDrawer as separate concepts in different pages.

ACCEPT. Consolidating into one Observability surface is correct. The existing `/admin/snapshots` becomes one tab; the `<DebugDrawer>` becomes Debug Panel under it; CC Bridges and CC Events get their own tabs.

REFINE: add a note that Health Overview (line 283: `LiveView connected, agents running, bridges connected, failed dispatches, recent errors, snapshot freshness`) is a *derived* view — the data lives in KindRegistry + KindRunner + telemetry. Tell the designer this is an aggregator card, not a new store.

### 2.19 Routing Activity Wizard — ACCEPT

> "Main Window 默认显示 Rule Table 或 Rule Flow. Right Sidebar 显示 Rule Wizard 或 Rule Inspector. Wizard 步骤: When? → What's it about? → Who receives it? → Preview & save." (variant §1.5 routing section)

baseline §UX-polish: "Step 1 — When? ... Step 4 — Preview & save" — wizard already there.

ACCEPT. The variant moves it from a modal/page-action to a Right Sidebar permanent fixture, which is better — operators see the wizard *and* the existing rules at once.

REFINE: per SPEC v2 §5.4 + §5.7, the wizard's Scope picker (global / workspace / session) is missing from the variant. Add a Step 0: "Scope — at what level should this rule apply? Global / Workspace://X / Session://Y." This makes Scope a first-class wizard input, matching the unified `/admin/routing` model that S-9 envisages and SPEC v2 §5.4 normalises.

### 2.20 Light theme only — ACCEPT

> "本轮原型统一采用 light theme. 不要再额外生成 dark theme 页面." (variant §4.4)

baseline §4.4: "暗色模式通过 `data-theme='dark'` 启用. 请为原语同时设计明色与暗色两套变体."

ACCEPT. Light-only is a *prototype scope reduction*, not a product decision. The variant says "不要分散评审注意力" — correct. Dark theme can be added once the light theme is approved. (Real engineering note: Tailwind v4 + daisyUI handle both off one config; deferring is genuinely cheap.)

### 2.21 Dev-mode admin login button — REFINE

> "考虑一键 dev 模式 admin 登入按钮 —— 由一条横幅守门: 'Dev mode only; disable in production'." (variant §UX-polish login)

baseline had same.

ACCEPT the button. REFINE the URI: per SPEC v2 §5.12, the button should pre-fill `entity://user/admin`, not `user://admin`. ARCHITECTURE Decision #81 ("`user://admin` is bootstrap principal, all-caps not revocable") still holds — only the URI shape changes.

Implication: ARCHITECTURE.md Decision #81 needs a SPEC-v2 rewrite (`user://admin` → `entity://user/admin`). Note this for the doc-PR but it's out of the variant's scope.

### 2.22 PtyViewer integration — ACCEPT

> "PtyViewer ... 一个黑盒子, 工程师将通过 JS hook 把 xterm.js 挂进去. 尺寸撑满容器. WebSocket 建立中显示 Connecting 状态." (variant §3)

baseline §3: identical.

ACCEPT. Unchanged from baseline. Cross-reference: ARCHITECTURE PtyTerminal hook contract (line 374 of the variant) is correctly preserved.

### 2.23 Definition-of-done items — ACCEPT

> "Activity Bar, Left Panel, Top Command Bar, Main Window, Right Sidebar, Status Bar 都必须出现; 至少展示 session 单 pane / Chat+PTY split / routing+wizard / workspace editor / observability / settings 六类页面." (variant §DoD)

baseline §DoD: each route → one HTML file + component library + light+dark variants.

ACCEPT. The variant's DoD is more specific (names the 6 must-show layouts) and is achievable.

REFINE: baseline asked for "明色与暗色两套变体". Variant dropped dark — consistent with §2.20 ACCEPT — good. But the variant adds "CmdK Command Palette: 顶部常驻搜索入口 + 浮层状态都要展示" which the baseline didn't require. This is good ADD, not a regression.

---

## §3 SPEC v2 compliance findings

| SPEC § | Rule | Variant compliance |
|---|---|---|
| §5.1 | 2-segment authority `<scheme>://<type>/<name>` | **PARTIAL** — header asserts compliance, but body URIs use 1-segment (`session://main` is gone but `session://default/X` is right; the bug is `user://default/X` should be `entity://user/X` — that's §5.12, not §5.1) |
| §5.2 | Query-string action (`?action=behavior.action`) | **COMPLIANT** — examples like `?action=chat.send`, `?action=pty.write` used throughout |
| §5.3 | `@hash` content addressing on templates only | **NOT MENTIONED** — variant doesn't discuss template versioning; OK because designer doesn't need it for prototype |
| §5.4 | 3-tier scope (global / workspace / session) | **MISSING** — Routing Wizard doesn't include Scope as Step 0 (see §2.19) |
| §5.5 | Workspace = Deployment Unit | **COMPLIANT** — §1.1 vocabulary table calls this out explicitly |
| §5.6 | 6-scheme allowlist | **VIOLATED** — variant §3a line 330 says 8 schemes including `agent`, `user`, `message`; should be 6 (`entity`, `workspace`, `session`, `template`, `resource`, `system`) |
| §5.7 | Synthetic singletons dissolved (no `routing-admin://`, no `pty-input://`) | **COMPLIANT** — variant uses `agent://cc/X?action=pty.write` and doesn't reference `routing-admin://` (line 71 example shows the right shape — just the scheme is `agent://` instead of `entity://agent/`) |
| §5.8 | Plugins don't own schemes (Feishu side-channel) | **COMPLIANT IN PROSE** — variant explicitly says Feishu is *not* a Kind; uses the `user://X?action=chat.send` with `feishu_id` in args (right shape, wrong scheme name per §5.12) |
| §5.10 | Singleton naming = `default` | **COMPLIANT** — `workspace://default/research`, `session://default/main` |
| §5.11 | No backward compatibility | **COMPLIANT** — header explicitly states "没有任何向后兼容的简写" |
| §5.12 | `entity://` merger | **VIOLATED** — every `user://` and `agent://` URI in the variant should be `entity://user/` and `entity://agent/<flavor>_`. Mechanical sed-like replacement; ~20 occurrences |
| §5.13 | Messages have no URI | **NOT VIOLATED** but **NOT MENTIONED** — variant doesn't display message URIs, so the breakage is silent. Suggest a line: "Messages are not URIs — chat-stream items show timestamp + sender Entity URI, never a `message://...` value." |
| §5.14 | Agent flavor in name, not URI type axis | **VIOLATED** — variant says `agent://<类型>/<名称>` (typed; line 32) where SPEC says `entity://agent/<flavor>_<name>` (flavor free-form in name) |

**Bottom line on §3**: the variant's text body is built on the pre-SPEC-v2 (v1) URI vocabulary. The top-of-file SPEC-alignment note is *aspirational, not realised*. To ship to a designer, the variant needs a global URI rewrite pass: ~20 substitutions, all mechanical, no semantic rework required.

---

## §4 Entity-agnostic compliance findings

| Reflection § | Rule | Variant compliance |
|---|---|---|
| §3.1 | `/login` must accept any Entity URI | **COMPLIANT** — variant §UX-polish login: "接受纯标识符 (`allen`) — 服务器默认构建 `user://default/allen`... 完整 URI 字段为高级回退" (right shape; wrong scheme per §5.12). Also: "agent://curl/myself" mentioned as the agent-login example. |
| §3.2 | CLI tokens issuable to any Entity | **NOT DESIGNER-FACING** — covered in `<KeyVault>` for API keys, but this is a different concept. OK to leave out. |
| §3.3 | `current_user_uri` → `current_entity_uri` rename | **NOT DESIGNER-FACING** — but the variant says "当前 Entity" (current Entity) in the Settings → Account section, which is the right vocabulary. ACCEPT. |
| §3.4 | Mention dropdown lists every member | **COMPLIANT** — see §2.12 |
| §3.5 | Unified `/admin/live` or "Entities" page | **VIOLATED** — see §2.17 above. Variant *demotes* Users to Settings sub-section instead of *promoting* Users + Agents to a unified Identities Activity. This is the most important entity-agnostic regression. |
| §3.7 | `mix ezagent.agent.create` parity with `user.create` | **NOT DESIGNER-FACING** |
| §3.8 | Lexicon — "the user" leaks | **MOSTLY OK** — variant says "Entity" throughout, "operator" once. Acceptable. |
| §3.9 | Docstring split-language | **NOT DESIGNER-FACING** |

**Bottom line on §4**: the variant is entity-agnostic in vocabulary but commits one structural violation (§3.5 / Activity-Bar demotion of Users). Easy fix: rename `Users` Activity slot to `Identities` and host both sub-types.

---

## §5 Pushback questions for Allen

1. **"Did you intend SPEC v2 §5.12 (entity:// merger) for this variant, or are you keeping the v1 `user://` / `agent://` shape for designer-readability reasons?"** If the latter, the top-of-file SPEC-alignment header should say "SPEC v2 §5.1, §5.2, §5.6 (partial), §5.10 — NOT §5.12 (kept v1 split for human-readability of designer brief)." If the former, the whole body needs the §2.9 rewrite.

2. **"Why is Users demoted to Settings while Agents has its own Activity?"** This contradicts §3.5 of the entity-agnostic reflection. Recommend the Activity-Bar item become `Identities` (or `Access`) and hold both. Plugins demotes to Settings or Observability to free the slot.

3. **"Recent Agents — is this a persisted concept or UI-only?"** Variant introduces it without specifying. Pick one: (a) per-Entity preference Kind that stores last-N opened agent URIs, (b) UI cookie, (c) drop the line.

4. **"Routing Activity → `Transforms`, `Targets`, `Registry` — these aren't in the codebase. What do they mean?"** Either spec the backing concepts or remove from the Left Panel tree.

5. **"`<TemplateClassPicker>` enumerates `cc.agent` / `curl.agent` / `echo` — should this list be hardcoded or registry-driven?"** Plugin isolation north star says registry-driven. Confirm.

6. **"Scope in Routing Wizard — global / workspace / session — should be Step 0. Did you mean to omit it?"** SPEC v2 §5.4 makes this a first-class concept.

7. **"Activity-Bar item `Plugins` — what does an operator do there 1×/month vs Sessions 100×/day? Should Plugins move to Settings/Observability to free top-level real estate?"**

8. **"For `cc.agent[remote-channel]` rendered as a sub-row of `local-pty` — does the variant assume 1:1 pairing of remote-channel + local-pty agents of the same name? PR-D2 made them independent."** See §2.11.

---

## Appendix — minimum patch set if you want to ship this variant today

If Allen wants the variant ready for designer hand-off this week, the smallest viable patch is:

1. **Global URI rewrite** (mechanical, ~20 substitutions): `user://default/X` → `entity://user/X`; `agent://<type>/<name>` → `entity://agent/<type>_<name>`; `session://default/X` keeps `default` only where it really is the default template. **Fix §3a line 330's 8-scheme enumeration → 6 schemes.**
2. **Rename Activity-Bar `Users` slot to `Identities`** and move Users + Agents under it; or **rename Activity-Bar `Settings` to keep Users at top-level**. Drop "Plugins" Activity (move to Observability or Settings).
3. **Routing Wizard Step 0 = Scope** (global / workspace / session).
4. **Drop or spec** the four undefined Left Panel sub-items: Recent Agents, Transforms, Targets, Generated UI.
5. **Add SPEC v2 §5.13 note**: "Messages don't have URIs; chat-stream items show timestamp + sender Entity URI, never a `message://` value."

Everything else can ship as-is.
