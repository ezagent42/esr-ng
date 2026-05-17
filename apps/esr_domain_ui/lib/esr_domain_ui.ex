defmodule EsrDomainUi do
  @moduledoc """
  UI domain — small shadcn-like HEEx component primitives.

  Plugin LV pages (`esr_plugin_ezagent` and future 3rd-party plugins)
  import these via `use EsrDomainUi.Components` to get consistent
  styling without each page reinventing button / card / badge styles.

  Phase 6 PR 3: extracted alongside `esr_plugin_ezagent`. Validates
  the "UI as plugin" path — a plugin author writes pages on top of
  this library + Phoenix.LiveView without touching ezagent or core.
  """
end
