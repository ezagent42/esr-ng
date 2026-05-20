# Phase 8b — Session LV 重设计 (设计规范)

**作者**：Claude Opus 4.7 (1M)
**日期**：2026-05-20
**分支**：`feat/phase-8-ide-shell-liveview` (同 Phase 8 主分支，分多个 commit)
**前置**：Phase 8 polish bundle subagent (#51) 完成后开始

---

## §0 目标 & 约束

### 目标

把 admin_live (Sessions Activity 的 `/sessions` 页面) 从 v1 "inline-style 三列硬塞" 重做为：

1. Session 是 IDE Shell Main Window 内的**第一公民概念**，有多种 view 呈现方式 (chat / PTY / 未来更多)
2. View-mode 是 **plugin 扩展点**，不是 admin_live 内部 if-else
3. Session settings (debug / feishu binding / routing) 集中到 setting dropdown
4. inline @ mention autocomplete 替代 dropdown select
5. Members 仍在 IDE Shell Right Sidebar (符合 IDE Shell 跨 page 上下文模型)

### 硬约束 (Allen 2026-05-20)

- 三层架构都触及，但每层职责清晰：
  - **core 完全不动** (Kind/Behavior/dispatch 跟 UI view 无关)
  - **domain_ui 加 SessionViewRegistry + SessionView behaviour** (新的 UI 扩展点)
  - **plugin 注册各自 view** (cc 注册 PtyView, liveview 注册 ConversationView)
- View 切换是**单一二选一** (chat OR PTY)，不做 split-view (per Allen "splitview 目前甚至没必要做")
- 路由不动 (业务路由由 polish subagent 改完了)
- 不动 SessionTemplate / Workspace / Routing 等业务逻辑

### 不在 Phase 8b 范围

- Split view (后续 Phase)
- 第三种 view (canvas / whiteboard / video)
- View 间状态共享 (PTY 高亮代码跳到 conversation 引用)
- View-mode 持久化用户偏好 (LocalStorage)
- Session-scoped routing rules 的 CRUD UI (setting dropdown 只 link 到 `/routing?session=...`)

---

## §1 架构改动

### 1.1 新加 `Ezagent.UI.SessionView` behaviour

`apps/ezagent_domain_ui/lib/ezagent_domain_ui/session_view.ex` (NEW):

```elixir
defmodule Ezagent.UI.SessionView do
  @moduledoc """
  Phase 8b — Session view extension point.

  A SessionView is a Phoenix.Component that renders ONE way of looking
  at a session in the Main Window's main area (between SessionEditor
  header and input). Each view declares which sessions it applies to
  via `applies_to/1`.

  Plugins register views in their Application.start/2 via
  `Ezagent.UI.SessionViewRegistry.register/3`.

  Default views shipped:
  - `:conversation` (in ezagent_plugin_liveview) — chat message stream
  - `:pty` (in ezagent_plugin_cc) — xterm.js terminal, only for cc.agent[local-pty]
  """

  @doc "Short identifier for the view (atom)."
  @callback id() :: atom()

  @doc "Display label for the view-switcher button."
  @callback label() :: String.t()

  @doc "Heroicon name for the view-switcher button."
  @callback icon() :: String.t()

  @doc """
  Does this view apply to the given session?
  Called once per session render to decide which view-switcher buttons
  show up. Should be cheap (e.g. lookup session members + check kind types).
  """
  @callback applies_to?(session_uri :: URI.t()) :: boolean()

  @doc """
  Phoenix.Component-style render. Receives assigns including
  session_uri + caller_uri + current_member_options + any view-specific
  state owned by the wrapping LV.

  The view is rendered INSIDE the SessionEditor's main area (between
  header and input). Views don't render their own header/input.
  """
  @callback render(assigns :: map()) :: Phoenix.LiveView.Rendered.t()

  @doc """
  Optional — extra assigns the view needs that the wrapping LV should
  prepare. Returns list of `{:assign_key, fn_or_value}` pairs.

  Example: PTY view needs the buffer subscription; declare it here so
  admin_live mount/3 sets up the subscription only if PTY view applies.
  """
  @callback prepare_assigns(session_uri :: URI.t(), socket :: Phoenix.LiveView.Socket.t()) ::
              Phoenix.LiveView.Socket.t()

  @optional_callbacks [prepare_assigns: 2]
end
```

### 1.2 新加 `Ezagent.UI.SessionViewRegistry`

`apps/ezagent_domain_ui/lib/ezagent_domain_ui/session_view_registry.ex` (NEW):

```elixir
defmodule Ezagent.UI.SessionViewRegistry do
  @moduledoc """
  ETS-backed registry of SessionView modules. Mirrors the
  BehaviorRegistry / SpawnRegistry / TemplateRegistry pattern —
  plugins register at boot, consumers (admin_live) query at render.

  Three operations:
  - register/1: plugin calls this in Application.start/2
  - applicable_views/1: admin_live calls this with session_uri to get the
    list of views the user can choose
  - lookup/1: admin_live calls this with the selected view id to get the
    module to render
  """

  @table :ezagent_session_view_registry

  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, read_concurrency: true])
    end
    :ok
  end

  @doc "Register a SessionView module."
  def register(view_module) when is_atom(view_module) do
    id = view_module.id()
    :ets.insert(@table, {id, view_module})
    :ok
  end

  @doc "Get all registered views that apply to the given session_uri."
  def applicable_views(session_uri) do
    @table
    |> :ets.tab2list()
    |> Enum.filter(fn {_id, mod} -> safe_applies_to(mod, session_uri) end)
    |> Enum.map(fn {_id, mod} -> %{id: mod.id(), label: mod.label(), icon: mod.icon(), module: mod} end)
    |> Enum.sort_by(& &1.id)
  end

  defp safe_applies_to(mod, session_uri) do
    try do
      mod.applies_to?(session_uri)
    catch
      _, _ -> false
    end
  end

  @doc "Look up a view module by id (atom). Returns {:ok, module} | :error."
  def lookup(id) do
    case :ets.lookup(@table, id) do
      [{^id, mod}] -> {:ok, mod}
      [] -> :error
    end
  end

  @doc "List all registered view ids (for tests / debug)."
  def all_ids do
    @table |> :ets.tab2list() |> Enum.map(fn {id, _} -> id end) |> Enum.sort()
  end
end
```

Register the ETS table in `EzagentCore.EtsOwner`:

```elixir
# Add :ezagent_session_view_registry to @tables
```

Init at `EzagentCore.Application.start/2`:

```elixir
:ok = Ezagent.UI.SessionViewRegistry.init()
```

### 1.3 Plugin registrations

**ezagent_plugin_liveview** (default view):

```elixir
# apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/application.ex (or boot module)
defp register_views do
  :ok = Ezagent.UI.SessionViewRegistry.register(EzagentPluginLiveview.Views.ConversationView)
end
```

NEW module `apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/views/conversation_view.ex`:

```elixir
defmodule EzagentPluginLiveview.Views.ConversationView do
  @behaviour Ezagent.UI.SessionView
  use Phoenix.Component
  alias EzagentDomainUi.Primitives

  @impl true
  def id, do: :conversation

  @impl true
  def label, do: "Chat"

  @impl true
  def icon, do: "message-square"

  @impl true
  def applies_to?(_session_uri), do: true  # all sessions have a conversation view

  @impl true
  def render(assigns) do
    ~H"""
    <div id="messages" phx-update="stream" phx-hook="ScrollOnUpdate"
         class="flex-1 overflow-y-auto p-4 space-y-3 bg-zinc-50">
      <div :for={{dom_id, row} <- @messages_stream} id={dom_id}
           class={["max-w-2xl rounded-lg px-3 py-2",
                   row.sender_kind == :user && "bg-blue-50 border border-blue-100 ml-auto",
                   row.sender_kind == :agent && "bg-emerald-50 border border-emerald-100 mr-auto",
                   row.sender_kind == :other && "bg-zinc-100 mx-auto"]}>
        <div class="flex items-center gap-2 text-[11px] text-zinc-500">
          <span class="font-mono">{row.sender}</span>
          <span>·</span>
          <span>{format_time(row.at)}</span>
        </div>
        <div :if={row.text != ""} class="mt-1 text-sm whitespace-pre-wrap">{row.text}</div>
        <div :if={attachments_of(row) != []} class="mt-2 flex gap-1 flex-wrap">
          <a :for={{name, href} <- attachments_of(row)} href={href} target="_blank"
             class="inline-flex items-center gap-1 px-2 py-1 bg-white border border-zinc-200 rounded text-xs text-blue-600 hover:bg-zinc-50">
            📎 {name}
          </a>
        </div>
      </div>
    </div>
    """
  end

  defp format_time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
  defp format_time(_), do: ""

  defp attachments_of(%{attachments: list}) when is_list(list), do: list
  defp attachments_of(_), do: []
end
```

**ezagent_plugin_cc** (PTY view):

```elixir
# apps/ezagent_plugin_cc/lib/ezagent/plugin_cc/application.ex
defp register_views do
  :ok = Ezagent.UI.SessionViewRegistry.register(EzagentPluginCc.Views.PtyView)
end
```

NEW module `apps/ezagent_plugin_cc/lib/ezagent/plugin_cc/views/pty_view.ex`:

```elixir
defmodule EzagentPluginCc.Views.PtyView do
  @behaviour Ezagent.UI.SessionView
  use Phoenix.Component
  alias EzagentDomainUi.Primitives

  @impl true
  def id, do: :pty

  @impl true
  def label, do: "Terminal"

  @impl true
  def icon, do: "terminal"

  @impl true
  def applies_to?(session_uri) do
    # Session has at least one entity://agent/cc_* member that's alive
    case :rpc.call(node(), Ezagent.KindRegistry, :lookup, [session_uri]) do
      {:ok, session_pid} ->
        try do
          state = :sys.get_state(session_pid, 200)
          members = Map.keys(state.state.chat.members)
          Enum.any?(members, fn uri ->
            URI.to_string(uri) =~ ~r{^entity://agent/cc_}
          end)
        catch
          _, _ -> false
        end
      _ -> false
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col bg-black text-zinc-200 font-mono">
      <div class="px-3 py-1 text-xs text-zinc-500 bg-zinc-900">
        Terminal — {@active_pty_agent_uri || "select an agent"}
      </div>
      <div id="pty-terminal" phx-hook="PtyTerminal"
           data-agent-uri={@active_pty_agent_uri}
           class="flex-1 overflow-hidden">
      </div>
    </div>
    """
  end
end
```

### 1.4 admin_live 重写

`apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/admin_live.ex` (REWRITE render/1 + mount/3):

主要变化：
- mount/3 assigns `:current_view` (默认 `:conversation`) + `:applicable_views`
- render/1 主区改为：`SessionEditor` 组件 包含 (header / view-switcher / view-render / input)
- view-switcher 调 `SessionViewRegistry.applicable_views/1` 拿可用 views
- view 切换 via `phx-click="switch_view"` event
- Members 仍在 IDE Shell Right Sidebar (用现有 member_panel)

### 1.5 NEW `EzagentPluginLiveview.Admin.SessionEditor` component

`apps/ezagent_plugin_liveview/lib/ezagent_plugin_liveview/admin/session_editor.ex` (NEW):

```elixir
defmodule EzagentPluginLiveview.Admin.SessionEditor do
  use Phoenix.Component
  alias EzagentDomainUi.Primitives
  alias EzagentDomainUi.Components

  attr :current_session_uri, URI, required: true
  attr :sessions, :list, required: true
  attr :applicable_views, :list, required: true
  attr :current_view, :atom, required: true
  attr :new_session_form, :map, required: true
  attr :compose_form, :map, required: true
  attr :member_options, :list, required: true
  attr :uploads, :map, default: nil
  attr :flash_error, :string, default: nil
  slot :main_view, required: true

  def session_editor(assigns) do
    ~H"""
    <div class="flex-1 flex flex-col min-h-0">
      <.session_header
        current_session_uri={@current_session_uri}
        sessions={@sessions}
        applicable_views={@applicable_views}
        current_view={@current_view}
        new_session_form={@new_session_form}
      />
      <div class="flex-1 flex flex-col min-h-0">
        {render_slot(@main_view)}
      </div>
      <.message_composer
        compose_form={@compose_form}
        member_options={@member_options}
        uploads={@uploads}
        flash_error={@flash_error}
      />
    </div>
    """
  end

  # Top bar: session dropdown + create + view switcher + setting dropdown
  defp session_header(assigns) do
    ~H"""
    <header class="flex items-center gap-2 px-3 py-2 border-b border-zinc-200 bg-white shrink-0">
      <.session_selector current_session_uri={@current_session_uri} sessions={@sessions} />
      <.create_button new_session_form={@new_session_form} />
      <div class="flex-1" />
      <.view_switcher applicable_views={@applicable_views} current_view={@current_view} />
      <.setting_dropdown current_session_uri={@current_session_uri} />
    </header>
    """
  end

  # Inline @ autocomplete message composer
  defp message_composer(assigns) do
    ~H"""
    <form for={@compose_form} phx-submit="chat_compose" phx-change="validate_compose"
          class="border-t border-zinc-200 bg-white p-3 space-y-2 shrink-0">
      <div id="mention-popover" class="hidden" />
      <div class="flex gap-2">
        <input type="text" name="chat[text]" placeholder="Type a message... use @ to mention"
               phx-hook="MentionAutocomplete" data-members={Jason.encode!(@member_options)}
               class="flex-1 px-3 py-2 border border-zinc-300 rounded-md text-sm" />
        <div :if={@uploads}>
          <label for={@uploads.attachments.ref}
                 class="inline-block px-3 py-2 border border-zinc-300 rounded-md text-sm cursor-pointer">
            📎
          </label>
          <.live_file_input upload={@uploads.attachments} class="hidden" />
        </div>
        <button type="submit" class="px-4 py-2 bg-emerald-600 text-white rounded-md text-sm font-medium">
          Send
        </button>
      </div>
      <p :if={@flash_error} class="text-xs text-rose-600">{@flash_error}</p>
    </form>
    """
  end

  # ... session_selector, create_button, view_switcher, setting_dropdown components ...
end
```

### 1.6 Setting dropdown contents

Per Allen 阶段 e:

- **Debug toggle**: 一个 toggle 把 raw event stream 显示在 Main Window 底部 (LV 内部 state, 默认 off)
- **Feishu binding**: 显示当前 session 绑定的 chat_id (via `SessionBinding.chat_ids_for/1`); 提供 "Unbind" 按钮 (dispatch to feishu_session_bindings table)
- **Routing**: link `/routing?session=session://X` (jump to routing page filtered to this session — requires routing_live to support `?session=` query)
- **Session info**: URI + members count + bound workspace + creation time

### 1.7 Inline @ autocomplete

NEW JS hook `apps/ezagent_web/assets/js/hooks/mention_autocomplete.js`:

```javascript
export const MentionAutocomplete = {
  mounted() {
    this.members = JSON.parse(this.el.dataset.members || "[]");
    this.popover = document.getElementById("mention-popover");
    this.el.addEventListener("input", (e) => this.handleInput(e));
  },

  handleInput(e) {
    const text = this.el.value;
    const caret = this.el.selectionStart;
    const match = /@(\S*)$/.exec(text.substring(0, caret));
    if (match) {
      const filter = match[1].toLowerCase();
      const matches = this.members.filter(uri => uri.toLowerCase().includes(filter)).slice(0, 5);
      this.renderPopover(matches);
    } else {
      this.popover.classList.add("hidden");
    }
  },

  renderPopover(matches) {
    if (matches.length === 0) {
      this.popover.classList.add("hidden");
      return;
    }
    // Position popover above the input
    const rect = this.el.getBoundingClientRect();
    this.popover.style.position = "absolute";
    this.popover.style.top = `${rect.top - this.popover.offsetHeight - 4}px`;
    this.popover.style.left = `${rect.left}px`;
    this.popover.innerHTML = matches.map(uri =>
      `<button type="button" class="block w-full text-left px-2 py-1 text-xs font-mono hover:bg-zinc-100" data-uri="${uri}">${uri}</button>`
    ).join("");
    matches.forEach((uri, i) => {
      this.popover.children[i].addEventListener("click", () => this.selectMention(uri));
    });
    this.popover.classList.remove("hidden");
  },

  selectMention(uri) {
    const text = this.el.value;
    const caret = this.el.selectionStart;
    const match = /@(\S*)$/.exec(text.substring(0, caret));
    if (match) {
      const before = text.substring(0, match.index);
      const after = text.substring(caret);
      this.el.value = `${before}@${uri} ${after}`;
      this.el.focus();
    }
    this.popover.classList.add("hidden");
  },
};
```

Register in `apps/ezagent_web/assets/js/app.js`.

### 1.8 Members PTY button

In `EzagentPluginLiveview.Admin.MemberPanel` (existing component), for each member row that is an `entity://agent/cc_*` URI:

- Add a small `🖥️` icon button next to the member URI
- `phx-click="switch_to_pty_for_agent"` `phx-value-agent={member_uri}`
- admin_live handle_event sets `:current_view = :pty` + `:active_pty_agent_uri = agent_uri`

### 1.9 Retire `/identities/agents/:uri/terminal`

The standalone PTY terminal page is removed. PTY is accessed via:
- Click Members panel agent's 🖥️ button (sets view to :pty)
- Click view-switcher Terminal button in SessionEditor header

The `pty_terminal_live.ex` file is **deleted**. Route `/identities/agents/:uri/terminal` removed from router. `EzagentPluginCc.Views.PtyView` is the new home for xterm.js integration (uses the same PtyTerminal JS hook).

### 1.10 CC Bridges (v2) panel relocation

Per Allen 注解 #1: CC Bridges 不再放 session, 搬到 agent detail page (`/identities/agents/:uri`).

`AgentDetailLive` 加一个 section "CC Bridges (v2)" 显示该 agent 的 BridgeRegistry 状态 (当前在 admin_live debug_panel 里的 `connected_bridges` 列表过滤到该 agent)。

---

## §2 测试

### 2.1 SessionViewRegistry unit tests

`apps/ezagent_domain_ui/test/ezagent_domain_ui/session_view_registry_test.exs`:

- `register/1` + `applicable_views/1` round trip
- `applies_to?` 返 false 时该 view 不出现
- `lookup/1` 找已注册 + 返 :error 未注册
- multiple views 按 id 排序

### 2.2 Plugin view applies_to tests

- `EzagentPluginLiveview.Views.ConversationView.applies_to?` always true
- `EzagentPluginCc.Views.PtyView.applies_to?` true only when session has cc_* member

### 2.3 admin_live integration

- mount/3 with empty session → `applicable_views == [:conversation]`
- mount/3 with cc agent in session → `applicable_views == [:conversation, :pty]`
- `phx-click="switch_view"` 切换 `current_view`
- Mention dropdown 替换为 @ autocomplete; LV test 难以测前端 hook, 改测 LV 服务端不再渲染 `<select>` 而是 `<input phx-hook="MentionAutocomplete">`

---

## §3 实施阶段

| 阶段 | 内容 | 文件 |
|---|---|---|
| a | SessionView behaviour + SessionViewRegistry + ETS init | `domain_ui` 2 files + EtsOwner + EzagentCore.Application |
| b | ConversationView (在 liveview plugin) + PtyView (在 cc plugin) | 2 new modules + 2 Application.start 调整 |
| c | admin_live render/1 重写 — 用 SessionViewRegistry + new SessionEditor | `admin_live.ex` 改写 |
| d | NEW SessionEditor component (header / view switcher / composer) | `admin/session_editor.ex` |
| e | Setting dropdown 内容 | session_editor.ex 内 |
| f | MentionAutocomplete JS hook + composer 改输入 | `assets/js/hooks/mention_autocomplete.js` + `app.js` + composer |
| g | Members panel PTY 按钮 + admin_live switch_to_pty_for_agent event | `member_panel.ex` + admin_live event handler |
| h | 删除 `pty_terminal_live.ex` + 路由 | 删 1 file + router |
| i | CC Bridges 搬到 agent_detail_live | agent_detail_live 加 section, admin_live 不再渲染 |
| j | 测试 | 3 new test files |

---

## §4 验收

浏览器访问 `/sessions`:

1. ✓ Main Window 内 SessionEditor 包含 header / view switcher / view content / input
2. ✓ Header 左：session dropdown 切换 + +create 按钮
3. ✓ Header 右：view switcher (💬 Chat / 🖥️ Terminal) + setting icon
4. ✓ View 切换：点 Terminal 主区切到 xterm.js，点 Chat 切回 conversation
5. ✓ session 没有 cc.agent member 时 Terminal 按钮不出现
6. ✓ Members 仍在 IDE Shell Right Sidebar (跟其它 page 一致)
7. ✓ Members 内 cc agent 行旁有 🖥️ 按钮，点击切到 PTY view
8. ✓ input 框输入 `@` 触发 autocomplete popover；点击候选填入
9. ✓ setting dropdown：Debug toggle / Feishu binding / Routing link / Session info
10. ✓ CC Bridges panel 从 admin_live 消失；在 `/identities/agents/<uri>` 出现
11. ✓ `/identities/agents/<uri>/terminal` 路由不存在 (404 或 redirect)
12. ✓ 全 12 app `mix test` 0 failures

---

## §5 风险

| 风险 | mitigation |
|---|---|
| MentionAutocomplete popover 定位在 fixed input 之上时 z-index 冲突 | hook 计算 fixed position; popover 放 body, 不嵌入 form |
| PtyView 的 `applies_to?` :sys.get_state 200ms 超时阻塞 LV 渲染 | 缓存 1s; `try/catch` 包裹; ETS-cached members list |
| 删除 `/identities/agents/:uri/terminal` 破坏老书签 | 添 redirect 到 `/sessions?view=pty&agent=X` |
| 退役 pty_terminal_live 后 hook 数据传递改变 | PtyView render 用同样的 PtyTerminal JS hook + data-agent-uri 属性 |
| SessionEditor 拆出后丢了某些原有事件 handler | 改写时逐个对照 admin_live 原 handlers, 全部保留 |

---

## §6 Phase 9+ 后续

- View-mode 持久化 (cookie 或 LocalStorage)
- Split view (两 view 并列)
- 更多 view 类型 (canvas / whiteboard / video chat)
- View 间状态共享 (selection sync)
- Session-scoped routing CRUD UI
- Multi-session tabs (Main Window 多 session 并存)
