defmodule EzagentDomainUi.Components do
  @moduledoc """
  shadcn-inspired HEEx primitives for ESR admin/plugin UIs.

  `use EzagentDomainUi.Components` imports every component below so
  templates can call `<.button>`, `<.card>`, `<.badge>` etc. directly.

  Visual identity:
  - neutral zinc palette (slate-grey backgrounds, soft borders)
  - tight border-radius (rounded-md, not rounded-2xl)
  - subtle shadows (shadow-sm)
  - semantic color use for variant accents (primary, success, danger)
  - consistent spacing (4 / 6 / 8 px scale)

  Each component takes a `:class` attr that's appended after the
  default classes (shadcn pattern), so callers can override or extend
  without rewriting the primitive.
  """

  use Phoenix.Component

  defmacro __using__(_opts) do
    quote do
      import EzagentDomainUi.Components
    end
  end

  @doc """
  Button.

      <.button>Click me</.button>
      <.button variant="primary" phx-click="save">Save</.button>
      <.button variant="ghost" size="sm">Cancel</.button>
  """
  attr :variant, :string,
    default: "default",
    values: ~w(default primary success danger ghost outline)

  attr :size, :string, default: "md", values: ~w(sm md lg)
  attr :class, :string, default: ""
  attr :rest, :global, include: ~w(type disabled phx-click phx-disable-with phx-value-name name)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      class={[
        "inline-flex items-center justify-center font-medium rounded-md transition-colors",
        "focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-zinc-500 focus-visible:ring-offset-1",
        "disabled:opacity-50 disabled:cursor-not-allowed",
        size_class(@size),
        variant_class(@variant),
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp size_class("sm"), do: "h-8 px-3 text-xs"
  defp size_class("md"), do: "h-9 px-4 text-sm"
  defp size_class("lg"), do: "h-10 px-6 text-sm"

  defp variant_class("default"), do: "bg-zinc-100 dark:bg-zinc-900 text-zinc-900 dark:text-zinc-100 hover:bg-zinc-200 dark:hover:bg-zinc-700 border border-zinc-200 dark:border-zinc-800"
  defp variant_class("primary"), do: "bg-zinc-900 dark:bg-zinc-100 text-zinc-50 dark:text-zinc-900 hover:bg-zinc-800 dark:hover:bg-zinc-200 shadow-sm"
  defp variant_class("success"), do: "bg-emerald-600 text-emerald-50 hover:bg-emerald-700 dark:hover:bg-emerald-500 shadow-sm"
  defp variant_class("danger"), do: "bg-red-600 text-red-50 hover:bg-red-700 dark:hover:bg-red-500 shadow-sm"
  defp variant_class("ghost"), do: "text-zinc-700 dark:text-zinc-300 hover:bg-zinc-100 dark:hover:bg-zinc-800"
  defp variant_class("outline"), do: "bg-transparent border border-zinc-300 dark:border-zinc-700 text-zinc-700 dark:text-zinc-300 hover:bg-zinc-50 dark:hover:bg-zinc-900"

  @doc """
  Card — container with subtle border + shadow.

      <.card>
        <:header>Recent activity</:header>
        <p>body content</p>
      </.card>
  """
  attr :class, :string, default: ""
  attr :rest, :global
  slot :header
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["bg-white dark:bg-zinc-900 rounded-md border border-zinc-200 dark:border-zinc-800 shadow-sm", @class]} {@rest}>
      <div :if={@header != []} class="px-4 py-3 border-b border-zinc-200 dark:border-zinc-800">
        <h3 class="text-sm font-semibold text-zinc-900 dark:text-zinc-100">{render_slot(@header)}</h3>
      </div>
      <div class="p-4 text-sm text-zinc-700 dark:text-zinc-300">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  @doc """
  Badge — small inline tag (status chips, counts).

      <.badge>main</.badge>
      <.badge variant="success">online</.badge>
      <.badge variant="danger">offline</.badge>
  """
  attr :variant, :string,
    default: "default",
    values: ~w(default primary success warning danger info)

  attr :class, :string, default: ""
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 text-xs font-medium rounded-md border",
      badge_class(@variant),
      @class
    ]}>
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_class("default"), do: "bg-zinc-100 dark:bg-zinc-900 text-zinc-700 dark:text-zinc-300 border-zinc-200 dark:border-zinc-800"
  defp badge_class("primary"), do: "bg-zinc-900 dark:bg-zinc-100 text-zinc-50 dark:text-zinc-900 border-zinc-900 dark:border-zinc-100"
  defp badge_class("success"), do: "bg-emerald-50 dark:bg-emerald-950 text-emerald-700 dark:text-emerald-300 border-emerald-200 dark:border-emerald-800"
  defp badge_class("warning"), do: "bg-amber-50 dark:bg-amber-950 text-amber-700 dark:text-amber-300 border-amber-200 dark:border-amber-800"
  defp badge_class("danger"), do: "bg-red-50 dark:bg-red-950 text-red-700 dark:text-red-300 border-red-200 dark:border-red-800"
  defp badge_class("info"), do: "bg-sky-50 dark:bg-sky-950 text-sky-700 dark:text-sky-300 border-sky-200 dark:border-sky-800"

  @doc """
  Page header — title + optional subtitle + actions slot.

      <.page_header title="Workspaces">
        <:subtitle>Persisted Session + Member declarations</:subtitle>
        <:actions>
          <.button variant="primary">New workspace</.button>
        </:actions>
      </.page_header>
  """
  attr :title, :string, required: true
  attr :class, :string, default: ""
  slot :subtitle
  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class={["flex items-end justify-between mb-6 pb-4 border-b border-zinc-200 dark:border-zinc-800", @class]}>
      <div>
        <h1 class="text-xl font-semibold text-zinc-900 dark:text-zinc-100">{@title}</h1>
        <p :if={@subtitle != []} class="mt-1 text-sm text-zinc-500">{render_slot(@subtitle)}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-2">{render_slot(@actions)}</div>
    </div>
    """
  end

  @doc """
  Stat — single key/value pair used in summary rows.

      <.stat label="Sessions" value={5} />
      <.stat label="Online" value={3} variant="success" />
  """
  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :variant, :string, default: "default", values: ~w(default success warning danger)
  attr :class, :string, default: ""

  def stat(assigns) do
    ~H"""
    <div class={["flex flex-col gap-0.5", @class]}>
      <span class="text-xs uppercase tracking-wide text-zinc-500">{@label}</span>
      <span class={["text-lg font-semibold tabular-nums", stat_value_class(@variant)]}>
        {@value}
      </span>
    </div>
    """
  end

  defp stat_value_class("default"), do: "text-zinc-900 dark:text-zinc-100"
  defp stat_value_class("success"), do: "text-emerald-700 dark:text-emerald-300"
  defp stat_value_class("warning"), do: "text-amber-700 dark:text-amber-300"
  defp stat_value_class("danger"), do: "text-red-700 dark:text-red-300"
end
