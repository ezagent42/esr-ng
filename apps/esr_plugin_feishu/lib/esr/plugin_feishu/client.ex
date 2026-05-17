defmodule EsrPluginFeishu.Client do
  @moduledoc """
  Phase 5 PR 6 — Lark/Feishu HTTP client.

  Two operations needed for the demo:
  1. `tenant_access_token/0` — mint short-lived (~2h) access token from
     `app_id` + `app_secret` (cached in this GenServer; auto-refreshes)
  2. `send_text/2` — POST a text message to a `chat_id`

  Uses :httpc to avoid adding new deps (Req/Tesla would also work but
  this plugin is the only HTTP client in the codebase and zero-dep is
  cleaner per memory feedback_let_it_crash_no_workarounds).

  Credentials read from `Esr.Home.read_credentials("feishu")` at boot.
  If the feishu.yaml is the empty template (`app_id: cli_REPLACE_ME`),
  the plugin still starts but client calls return `{:error,
  :credentials_not_configured}` — operator gets a clear error rather
  than crash-on-load (this matters for dev: operator may run the
  server before filling creds).
  """
  use GenServer
  require Logger

  @lark_base "https://open.feishu.cn/open-apis"

  defstruct [:app_id, :app_secret, token: nil, expires_at: nil]

  # --- public API ---------------------------------------------------------

  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @doc """
  Send a text message to a Feishu chat. Returns `:ok` on success,
  `{:error, reason}` on any failure (token mint or send).
  """
  @spec send_text(String.t(), String.t()) :: :ok | {:error, term()}
  def send_text(chat_id, text) when is_binary(chat_id) and is_binary(text) do
    GenServer.call(__MODULE__, {:send_text, chat_id, text}, 10_000)
  end

  @doc "Returns `{:ok, status}` describing the client's credential state."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # --- callbacks ----------------------------------------------------------

  @impl true
  def init(_) do
    state =
      case Esr.Home.read_credentials("feishu") do
        {:ok, %{"app_id" => app_id, "app_secret" => app_secret} = creds}
        when is_binary(app_id) and is_binary(app_secret) ->
          # Template-stubs have `cli_REPLACE_ME` — flag as un-configured so
          # send_text returns a clear error rather than calling Lark with
          # garbage credentials.
          if String.contains?(app_id, "REPLACE_ME") or String.contains?(app_secret, "REPLACE_ME") do
            Logger.warning(
              "EsrPluginFeishu.Client: credentials file present but unfilled (cli_REPLACE_ME). " <>
                "Edit #{Path.join(Esr.Home.path(:credentials), "feishu.yaml")} to enable."
            )

            %__MODULE__{app_id: nil, app_secret: nil}
          else
            Logger.info("EsrPluginFeishu.Client: credentials loaded (app_id=#{String.slice(app_id, 0..14)}…)")
            _ = creds
            %__MODULE__{app_id: app_id, app_secret: app_secret}
          end

        {:error, :not_found} ->
          Logger.warning(
            "EsrPluginFeishu.Client: no feishu.yaml at #{Path.join(Esr.Home.path(:credentials), "feishu.yaml")}. " <>
              "Run `mix esr.home.init` then fill credentials."
          )

          %__MODULE__{app_id: nil, app_secret: nil}

        err ->
          Logger.error("EsrPluginFeishu.Client: credential read failed: #{inspect(err)}")
          %__MODULE__{app_id: nil, app_secret: nil}
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:send_text, _chat, _text}, _from, %__MODULE__{app_id: nil} = state),
    do: {:reply, {:error, :credentials_not_configured}, state}

  def handle_call({:send_text, chat_id, text}, _from, state) do
    case ensure_token(state) do
      {:ok, token, new_state} ->
        body = %{
          receive_id: chat_id,
          msg_type: "text",
          content: Jason.encode!(%{text: text})
        }

        case http_post_json(
               "#{@lark_base}/im/v1/messages?receive_id_type=chat_id",
               body,
               [{~c"Authorization", String.to_charlist("Bearer #{token}")}]
             ) do
          {:ok, %{"code" => 0}} ->
            {:reply, :ok, new_state}

          {:ok, %{"code" => code, "msg" => msg}} ->
            {:reply, {:error, {:lark_error, code, msg}}, new_state}

          err ->
            {:reply, err, new_state}
        end

      err ->
        {:reply, err, state}
    end
  end

  def handle_call(:status, _from, state) do
    s = %{
      configured: state.app_id != nil,
      app_id_prefix: state.app_id && String.slice(state.app_id, 0..14),
      token_minted: state.token != nil
    }

    {:reply, s, state}
  end

  # --- token mint + caching ------------------------------------------------

  defp ensure_token(%__MODULE__{token: token, expires_at: exp} = state)
       when is_binary(token) do
    if exp && DateTime.compare(DateTime.utc_now(), exp) == :lt do
      {:ok, token, state}
    else
      mint_token(state)
    end
  end

  defp ensure_token(state), do: mint_token(state)

  defp mint_token(%__MODULE__{app_id: app_id, app_secret: app_secret} = state) do
    case http_post_json(
           "#{@lark_base}/auth/v3/tenant_access_token/internal",
           %{app_id: app_id, app_secret: app_secret},
           []
         ) do
      {:ok, %{"code" => 0, "tenant_access_token" => token, "expire" => seconds_left}} ->
        # Cache 5 minutes shy of expiry to avoid edge-of-validity sends.
        expires_at = DateTime.add(DateTime.utc_now(), seconds_left - 300, :second)
        {:ok, token, %{state | token: token, expires_at: expires_at}}

      {:ok, %{"code" => code, "msg" => msg}} ->
        {:error, {:lark_auth_error, code, msg}}

      err ->
        err
    end
  end

  # --- :httpc helper -------------------------------------------------------

  defp http_post_json(url, payload, extra_headers) do
    body = Jason.encode!(payload)

    headers =
      [
        {~c"Content-Type", ~c"application/json; charset=utf-8"}
        | extra_headers
      ]

    request = {String.to_charlist(url), headers, ~c"application/json", body}

    case :httpc.request(:post, request, [{:timeout, 5000}, {:connect_timeout, 5000}], []) do
      {:ok, {{_, 200, _}, _resp_headers, resp_body}} ->
        case Jason.decode(to_string(resp_body)) do
          {:ok, decoded} -> {:ok, decoded}
          err -> err
        end

      {:ok, {{_, status, _}, _, resp_body}} ->
        {:error, {:http_status, status, to_string(resp_body)}}

      {:error, reason} ->
        {:error, {:http_error, reason}}
    end
  end
end
