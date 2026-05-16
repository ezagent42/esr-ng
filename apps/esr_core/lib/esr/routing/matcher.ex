defmodule Esr.Routing.Matcher do
  @moduledoc """
  Routing matchers — predicates over `%Esr.Message{}` used by
  `Esr.Routing.Resolver` to derive recipients (Phase 3 落地 Decision
  #41 / #42 / #70).

  Per Decision #70 (boundary "reads core data → core"): all 5 leaf
  matchers read `%Esr.Message{}` fields, so they live in `esr_core`.
  Plugin-payload matchers (e.g. `feishu_card_type`) belong in the
  plugin that owns that payload.

  ## 5 leaf matchers (Phase 3 scope, Decision P3-D3)

  - `mention(URI.t())` — `URI` in `message.mentions`
  - `from(URI.t())` — `message.sender == URI`
  - `text_contains(String.t())` — body text contains substring
  - `text_matches(regex_string)` — body text matches Elixir-regex string
  - `always()` — unconditional true (catchall rule use)

  Combinators (and/or/not) intentionally deferred to Phase 4+ — most
  Phase 3 routing scenarios are covered by additive single-matcher
  rules (multiple rules each matching different criteria; Decision
  #41 additive semantics).

  ## Shape

  Matchers are plain Elixir tuples (Decision #42 JSON-serializable):
  - `{:mention, "user://admin"}` (URI as string for JSON round-trip)
  - `{:from, "agent://cc-builder"}`
  - `{:text_contains, "urgent"}`
  - `{:text_matches, "^/help"}`
  - `{:always}`

  ## Why string URIs in matcher tuples (not %URI{})

  Matchers persist to SQLite via Jason; URI struct doesn't round-trip
  through JSON cleanly (Jason serializes %URI{} as string via the
  `defimpl Jason.Encoder, for: URI` from `Esr.Message`, but
  deserializes to plain string). Storing as string in the matcher
  tuple makes the JSON round-trip explicit + symmetric.
  """

  @type matcher ::
          {:mention, String.t()}
          | {:from, String.t()}
          | {:text_contains, String.t()}
          | {:text_matches, String.t()}
          | {:always}

  # --- Constructors (accept URI struct OR string) -----------------------

  @doc "Match if `uri` is in message.mentions."
  @spec mention(URI.t() | String.t()) :: matcher()
  def mention(%URI{} = uri), do: {:mention, URI.to_string(uri)}
  def mention(uri) when is_binary(uri), do: {:mention, uri}

  @doc "Match if message.sender == uri."
  @spec from(URI.t() | String.t()) :: matcher()
  def from(%URI{} = uri), do: {:from, URI.to_string(uri)}
  def from(uri) when is_binary(uri), do: {:from, uri}

  @doc "Match if message.body.text contains substring."
  @spec text_contains(String.t()) :: matcher()
  def text_contains(s) when is_binary(s), do: {:text_contains, s}

  @doc "Match if message.body.text matches Elixir regex (string form)."
  @spec text_matches(String.t()) :: matcher()
  def text_matches(re) when is_binary(re) do
    # Validate at construction so bad regex fails fast, not at first match.
    {:ok, _} = Regex.compile(re)
    {:text_matches, re}
  end

  @doc "Always match — catchall rule constructor."
  @spec always() :: matcher()
  def always, do: {:always}

  # --- Predicate ---------------------------------------------------------

  @doc """
  Evaluate a matcher against a Message. Returns `true` / `false`.

  `:text_matches` recompiles the regex per call — Phase 3 acceptable
  (rules are <100; eval is microsecond). Phase 4+ can memoize compiled
  regex if profiling shows.
  """
  @spec match?(matcher(), Esr.Message.t()) :: boolean()
  def match?({:mention, uri_str}, %Esr.Message{mentions: mentions}) do
    Enum.any?(mentions, fn
      %URI{} = u -> URI.to_string(u) == uri_str
      s when is_binary(s) -> s == uri_str
    end)
  end

  def match?({:from, uri_str}, %Esr.Message{sender: sender}) do
    case sender do
      %URI{} = u -> URI.to_string(u) == uri_str
      s when is_binary(s) -> s == uri_str
    end
  end

  def match?({:text_contains, sub}, %Esr.Message{body: body}) do
    case extract_text(body) do
      text when is_binary(text) -> String.contains?(text, sub)
      _ -> false
    end
  end

  def match?({:text_matches, re_str}, %Esr.Message{body: body}) do
    case extract_text(body) do
      text when is_binary(text) ->
        {:ok, re} = Regex.compile(re_str)
        Regex.match?(re, text)

      _ ->
        false
    end
  end

  def match?({:always}, _msg), do: true

  # --- JSON serde (Decision #42 / DECISIONS P3-D impl Matcher AST) ------

  @doc """
  Serialize matcher to JSON-friendly map for `RuleStore` persistence.

  Format: `%{"type" => "<atom_name>", "arg" => <string>}`.
  `:always` has no arg.
  """
  @spec to_json(matcher()) :: map()
  def to_json({:mention, uri_str}), do: %{"type" => "mention", "arg" => uri_str}
  def to_json({:from, uri_str}), do: %{"type" => "from", "arg" => uri_str}
  def to_json({:text_contains, sub}), do: %{"type" => "text_contains", "arg" => sub}
  def to_json({:text_matches, re}), do: %{"type" => "text_matches", "arg" => re}
  def to_json({:always}), do: %{"type" => "always"}

  @doc """
  Deserialize from JSON map back to matcher tuple.

  Returns `{:ok, matcher}` or `{:error, reason}` — caller validates.
  """
  @spec from_json(map()) :: {:ok, matcher()} | {:error, term()}
  def from_json(%{"type" => "mention", "arg" => uri}) when is_binary(uri),
    do: {:ok, mention(uri)}

  def from_json(%{"type" => "from", "arg" => uri}) when is_binary(uri),
    do: {:ok, from(uri)}

  def from_json(%{"type" => "text_contains", "arg" => sub}) when is_binary(sub),
    do: {:ok, text_contains(sub)}

  def from_json(%{"type" => "text_matches", "arg" => re}) when is_binary(re) do
    try do
      {:ok, text_matches(re)}
    rescue
      e -> {:error, {:invalid_regex, Exception.message(e)}}
    end
  end

  def from_json(%{"type" => "always"}), do: {:ok, always()}
  def from_json(other), do: {:error, {:invalid_matcher_json, other}}

  # --- Internals --------------------------------------------------------

  # Body can have atom OR string keys (in-flight vs loaded from MessageStore).
  defp extract_text(%{text: t}) when is_binary(t), do: t
  defp extract_text(%{"text" => t}) when is_binary(t), do: t
  defp extract_text(_), do: nil
end
