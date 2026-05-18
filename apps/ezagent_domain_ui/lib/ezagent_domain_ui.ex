defmodule EzagentDomainUi do
  @moduledoc """
  UI domain — small shadcn-like HEEx component primitives.

  Plugin LV pages (`ezagent_plugin_liveview` and future 3rd-party plugins)
  import these via `use EzagentDomainUi.Components` to get consistent
  styling without each page reinventing button / card / badge styles.

  Phase 6 PR 3: extracted alongside `ezagent_plugin_liveview`. Validates
  the "UI as plugin" path — a plugin author writes pages on top of
  this library + Phoenix.LiveView without touching ezagent or core.
  """
end
