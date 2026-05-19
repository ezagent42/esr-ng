defmodule EzagentDomainUi.Primitives do
  @moduledoc """
  Phase 8 — additional primitives for the IDE Shell.

  Extends the shadcn-inspired set in `EzagentDomainUi.Components`
  with the building blocks that IDE-Shell layouts need: status dots,
  avatars, tabs, modals, toasts, tree lists, empty states, form
  fields, URI chips, toolbars, tooltips, icons.

  `use EzagentDomainUi.Primitives` imports every component below so
  templates can call `<.status_dot>`, `<.uri_chip>` etc. directly.

  Visual identity matches Components — neutral zinc palette, tight
  border-radius, subtle shadows.
  """

  use Phoenix.Component
  alias Phoenix.LiveView.JS

  defmacro __using__(_opts) do
    quote do
      import EzagentDomainUi.Primitives
    end
  end

  # --- status_dot ------------------------------------------------------------

  @doc """
  Small colored dot for online/offline/connecting/error states.

      <.status_dot color="green" />
      <.status_dot color="amber" pulse />
  """
  attr :color, :string, default: "gray", values: ~w(green gray amber red)
  attr :pulse, :boolean, default: false
  attr :class, :string, default: ""

  def status_dot(assigns) do
    ~H"""
    <span
      class={[
        "inline-block w-2 h-2 rounded-full",
        @color == "green" && "bg-emerald-500",
        @color == "gray" && "bg-zinc-400",
        @color == "amber" && "bg-amber-500",
        @color == "red" && "bg-rose-500",
        @pulse && "animate-pulse",
        @class
      ]}
    />
    """
  end

  # --- avatar ----------------------------------------------------------------

  @doc """
  Monogram or icon avatar for an Entity URI.

      <.avatar uri="entity://user/admin" />
      <.avatar uri="entity://agent/cc_demo" size="md" />
  """
  attr :uri, :any, required: true
  attr :size, :string, default: "sm", values: ~w(xs sm md)
  attr :class, :string, default: ""

  def avatar(assigns) do
    {label, bg} = avatar_label_and_color(assigns.uri)
    assigns = assign(assigns, :label, label) |> assign(:bg, bg)

    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center rounded-full font-medium text-white shrink-0",
        @size == "xs" && "w-4 h-4 text-[8px]",
        @size == "sm" && "w-6 h-6 text-[10px]",
        @size == "md" && "w-8 h-8 text-xs",
        @bg,
        @class
      ]}
    >
      {@label}
    </span>
    """
  end

  defp avatar_label_and_color(uri) do
    str = uri_to_string(uri)

    {label, color_seed} =
      case URI.new(str) do
        {:ok, %URI{scheme: "entity", host: "user", path: "/" <> name}} ->
          {String.upcase(String.first(name) || "?"), name}

        {:ok, %URI{scheme: "entity", host: "agent", path: "/" <> name}} ->
          flavor = name |> String.split("_", parts: 2) |> List.first()
          {flavor |> String.first() |> String.upcase(), flavor}

        {:ok, %URI{host: host}} when is_binary(host) ->
          {String.upcase(String.first(host) || "?"), host}

        _ ->
          {"?", "fallback"}
      end

    {label, avatar_bg(color_seed)}
  end

  defp avatar_bg(seed) when is_binary(seed) do
    case :erlang.phash2(seed, 6) do
      0 -> "bg-blue-500"
      1 -> "bg-emerald-500"
      2 -> "bg-amber-500"
      3 -> "bg-rose-500"
      4 -> "bg-violet-500"
      _ -> "bg-zinc-500"
    end
  end

  defp avatar_bg(_), do: "bg-zinc-500"

  defp uri_to_string(%URI{} = uri), do: URI.to_string(uri)
  defp uri_to_string(s) when is_binary(s), do: s
  defp uri_to_string(_), do: ""

  # --- tabs ------------------------------------------------------------------

  @doc """
  Horizontal tab strip.

      <.tabs
        items={[{:overview, "Overview"}, {:members, "Members"}]}
        selected={:overview}
        on_select="select_tab"
      />
  """
  attr :items, :list, required: true
  attr :selected, :any, required: true
  attr :on_select, :string, default: nil
  attr :class, :string, default: ""

  def tabs(assigns) do
    ~H"""
    <div class={["flex items-center gap-px border-b border-zinc-200 bg-zinc-50", @class]}>
      <button
        :for={{key, label} <- @items}
        type="button"
        phx-click={@on_select}
        phx-value-key={inspect(key)}
        class={[
          "px-3 py-1.5 text-xs font-medium transition-colors border-b-2",
          to_string(key) == to_string(@selected)
            && "border-zinc-900 text-zinc-900 bg-white"
            || "border-transparent text-zinc-500 hover:text-zinc-700 hover:bg-zinc-100"
        ]}
      >
        {label}
      </button>
    </div>
    """
  end

  # --- modal -----------------------------------------------------------------

  @doc """
  Modal with optional header/body/footer slots.

      <.modal id="confirm-delete" open={@show_modal}>
        <:header>Delete user?</:header>
        <:body>This is irreversible.</:body>
        <:footer>
          <.button variant="danger" phx-click="confirm">Delete</.button>
        </:footer>
      </.modal>
  """
  attr :id, :string, required: true
  attr :open, :boolean, default: false
  attr :on_close, :string, default: nil
  slot :header
  slot :body
  slot :footer

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        "fixed inset-0 z-50 flex items-center justify-center",
        not @open && "hidden"
      ]}
      phx-window-keydown={if @on_close, do: JS.push(@on_close)}
      phx-key="escape"
    >
      <div
        class="absolute inset-0 bg-zinc-900/40 backdrop-blur-sm"
        phx-click={if @on_close, do: @on_close}
      />
      <div class="relative z-10 w-full max-w-md mx-4 bg-white rounded-lg shadow-2xl overflow-hidden">
        <div :if={@header != []} class="px-4 py-3 border-b border-zinc-200 font-medium text-sm">
          {render_slot(@header)}
        </div>
        <div :if={@body != []} class="px-4 py-3 text-sm text-zinc-700">
          {render_slot(@body)}
        </div>
        <div :if={@footer != []} class="px-4 py-3 border-t border-zinc-200 bg-zinc-50 flex justify-end gap-2">
          {render_slot(@footer)}
        </div>
      </div>
    </div>
    """
  end

  # --- toast -----------------------------------------------------------------

  @doc """
  Toast notification at the bottom-right corner.

      <.toast kind="success">Saved</.toast>
  """
  attr :kind, :string, default: "info", values: ~w(info success error)
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def toast(assigns) do
    ~H"""
    <div
      class={[
        "fixed bottom-4 right-4 z-40 px-3 py-2 rounded-md shadow-lg text-sm font-medium",
        @kind == "info" && "bg-zinc-800 text-white",
        @kind == "success" && "bg-emerald-600 text-white",
        @kind == "error" && "bg-rose-600 text-white",
        @class
      ]}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  # --- tree_list -------------------------------------------------------------

  @doc """
  Hierarchical list for resource panels.

      <.tree_list>
        <:section title="Direct Sessions">
          <:item>session://default/dm-1</:item>
        </:section>
      </.tree_list>

  Use the `section` slot for groups; pass plain children for ungrouped items.
  """
  attr :class, :string, default: ""

  slot :section do
    attr :title, :string, required: true
    attr :count, :integer
  end

  slot :inner_block

  def tree_list(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1 text-xs", @class]}>
      <div :for={section <- @section} class="mb-2">
        <div class="px-2 py-1 text-[10px] uppercase tracking-wide text-zinc-500 font-medium flex items-center justify-between">
          <span>{section.title}</span>
          <span :if={Map.get(section, :count)} class="text-zinc-400 normal-case tracking-normal">
            {section.count}
          </span>
        </div>
        <div class="flex flex-col gap-px">
          {render_slot(section)}
        </div>
      </div>
      <div :if={@inner_block != []}>
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # --- empty_state -----------------------------------------------------------

  @doc """
  Placeholder for empty lists / unconfigured surfaces.

      <.empty_state title="No sessions" description="Create one to start chatting">
        <:action>
          <.button variant="primary">+ New session</.button>
        </:action>
      </.empty_state>
  """
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :icon, :string, default: "📭"
  slot :action

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 px-4 text-center">
      <div class="text-3xl mb-3 opacity-50">{@icon}</div>
      <div class="text-sm font-medium text-zinc-700">{@title}</div>
      <div :if={@description} class="text-xs text-zinc-500 mt-1 max-w-xs">{@description}</div>
      <div :if={@action != []} class="mt-4">
        {render_slot(@action)}
      </div>
    </div>
    """
  end

  # --- form_field ------------------------------------------------------------

  @doc """
  Wrapped form input with label + help + error slot.

      <.form_field name="email" type="text" label="Email" required>
        <:help>We never share your email.</:help>
      </.form_field>
  """
  attr :name, :string, required: true
  attr :type, :string, default: "text"
  attr :label, :string, required: true
  attr :value, :any, default: nil
  attr :placeholder, :string, default: nil
  attr :required, :boolean, default: false
  attr :error, :string, default: nil
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(autocomplete pattern)
  slot :help

  def form_field(assigns) do
    ~H"""
    <div class={["flex flex-col gap-1", @class]}>
      <label class="text-xs font-medium text-zinc-700">
        {@label}
        <span :if={@required} class="text-rose-600">*</span>
      </label>
      <input
        type={@type}
        name={@name}
        value={@value}
        placeholder={@placeholder}
        required={@required}
        class={[
          "px-2 py-1.5 text-xs border rounded-md font-mono",
          @error && "border-rose-400" || "border-zinc-300"
        ]}
        {@rest}
      />
      <div :if={@help != []} class="text-[11px] text-zinc-500">{render_slot(@help)}</div>
      <div :if={@error} class="text-[11px] text-rose-600">{@error}</div>
    </div>
    """
  end

  # --- uri_chip --------------------------------------------------------------

  @doc """
  Monospaced pill displaying a URI.

      <.uri_chip uri={@current_entity_uri} />
      <.uri_chip uri="entity://user/admin" copyable />
  """
  attr :uri, :any, required: true
  attr :copyable, :boolean, default: false
  attr :class, :string, default: ""

  def uri_chip(assigns) do
    str = uri_to_string(assigns.uri)
    assigns = assign(assigns, :str, str)

    ~H"""
    <span
      class={[
        "inline-flex items-center gap-1 px-2 py-0.5 rounded-md text-[11px] font-mono",
        "bg-zinc-100 text-zinc-700 border border-zinc-200",
        @class
      ]}
      title={if @copyable, do: "Click to copy"}
    >
      {@str}
    </span>
    """
  end

  # --- toolbar ---------------------------------------------------------------

  @doc """
  Small button cluster for editor-tab actions.

      <.toolbar>
        <.button size="sm" variant="ghost">↻</.button>
        <.button size="sm" variant="ghost">⚙</.button>
      </.toolbar>
  """
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def toolbar(assigns) do
    ~H"""
    <div class={["inline-flex items-center gap-px", @class]}>
      {render_slot(@inner_block)}
    </div>
    """
  end

  # --- tooltip ---------------------------------------------------------------

  @doc """
  Hover tooltip wrapper.

      <.tooltip text="Open Sessions">
        <.icon name="message-square" />
      </.tooltip>
  """
  attr :text, :string, required: true
  attr :class, :string, default: ""
  slot :inner_block, required: true

  def tooltip(assigns) do
    ~H"""
    <span class={["group relative inline-flex", @class]}>
      {render_slot(@inner_block)}
      <span class="absolute left-full ml-2 top-1/2 -translate-y-1/2 px-2 py-1 bg-zinc-900 text-white text-[11px] rounded whitespace-nowrap opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none z-50">
        {@text}
      </span>
    </span>
    """
  end

  # --- icon ------------------------------------------------------------------

  @doc """
  Icon stub — uses emoji or short text fallback. Phase 9 swaps for
  lucide-icons SVG sprite.

      <.icon name="message-square" />
      <.icon name="settings" size="md" />
  """
  attr :name, :string, required: true
  attr :size, :string, default: "sm", values: ~w(xs sm md lg)
  attr :class, :string, default: ""

  def icon(assigns) do
    emoji = icon_emoji(assigns.name)
    assigns = assign(assigns, :emoji, emoji)

    ~H"""
    <span
      class={[
        "inline-flex items-center justify-center leading-none select-none",
        @size == "xs" && "text-xs",
        @size == "sm" && "text-sm",
        @size == "md" && "text-base",
        @size == "lg" && "text-xl",
        @class
      ]}
      aria-label={@name}
    >
      {@emoji}
    </span>
    """
  end

  defp icon_emoji("message-square"), do: "💬"
  defp icon_emoji("folder"), do: "📁"
  defp icon_emoji("users"), do: "👥"
  defp icon_emoji("route"), do: "🔀"
  defp icon_emoji("puzzle"), do: "🧩"
  defp icon_emoji("activity"), do: "📈"
  defp icon_emoji("settings"), do: "⚙️"
  defp icon_emoji("search"), do: "🔍"
  defp icon_emoji("bell"), do: "🔔"
  defp icon_emoji("help"), do: "❓"
  defp icon_emoji("terminal"), do: "🖥️"
  defp icon_emoji("chevron-right"), do: "›"
  defp icon_emoji("chevron-left"), do: "‹"
  defp icon_emoji("chevron-down"), do: "⌄"
  defp icon_emoji("x"), do: "✕"
  defp icon_emoji("plus"), do: "+"
  defp icon_emoji("dot"), do: "•"
  defp icon_emoji("bug"), do: "🐞"
  defp icon_emoji("dashboard"), do: "📊"
  defp icon_emoji(_), do: "◇"
end
