defmodule EsrDomainPython.JsonRpc do
  @moduledoc """
  JSON-RPC 2.0 frame + envelope helpers — placeholder contract for
  Phase 7+ Python plugin host.

  ## Framing

  Wire format is LSP-style:

      Content-Length: 123\\r\\n
      \\r\\n
      {"jsonrpc": "2.0", ...}

  No newline-delimited form, no msgpack — JSON only, length-prefixed.

  ## Envelopes

  Request, response (ok), response (error), notification — JSON-RPC 2.0.
  Validated by the helpers below; no extra fields allowed in v1 of the
  contract.

  ## Why no implementation here

  Phase 7+ delivers the port + supervisor + message loop. PR 11 lands
  the envelope shapes and parsers so:
  - Phase 6 design discussions reference a concrete contract.
  - Future Phase 7 PR can plug in port logic against the same encoder.
  """

  @typedoc "JSON-RPC request id (integer or string per the spec)."
  @type id :: integer() | String.t()

  @typedoc "Decoded envelope — one of these four shapes."
  @type envelope ::
          {:request, id(), method :: String.t(), params :: map()}
          | {:notification, method :: String.t(), params :: map()}
          | {:result, id(), result :: term()}
          | {:error, id() | nil, code :: integer(), message :: String.t(), data :: term() | nil}

  @doc """
  Encode an envelope into the wire bytes (length-prefixed JSON).
  """
  @spec encode_frame(envelope()) :: iodata()
  def encode_frame(env) do
    body = env |> envelope_to_map() |> Jason.encode!()
    ["Content-Length: ", Integer.to_string(byte_size(body)), "\r\n\r\n", body]
  end

  @doc """
  Parse a single frame body (JSON string, already de-framed) into an
  envelope.

  Returns `{:ok, envelope}` or `{:error, reason}`. The framing layer
  (length header) is handled by the I/O loop in Phase 7+, not here.
  """
  @spec decode_body(String.t()) :: {:ok, envelope()} | {:error, term()}
  def decode_body(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{"jsonrpc" => "2.0"} = m} -> classify(m)
      {:ok, _} -> {:error, :missing_jsonrpc_version}
      {:error, reason} -> {:error, {:json_decode_failed, reason}}
    end
  end

  # --- Internals -------------------------------------------------------

  defp classify(%{"id" => id, "method" => method} = m) when not is_nil(method) do
    {:ok, {:request, id, method, Map.get(m, "params", %{})}}
  end

  defp classify(%{"method" => method} = m) when is_binary(method) do
    {:ok, {:notification, method, Map.get(m, "params", %{})}}
  end

  defp classify(%{"id" => id, "result" => result}) do
    {:ok, {:result, id, result}}
  end

  defp classify(%{"id" => id, "error" => %{"code" => code, "message" => msg} = err})
       when is_integer(code) and is_binary(msg) do
    {:ok, {:error, id, code, msg, Map.get(err, "data")}}
  end

  defp classify(_), do: {:error, :unrecognized_envelope_shape}

  defp envelope_to_map({:request, id, method, params}) do
    %{"jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params}
  end

  defp envelope_to_map({:notification, method, params}) do
    %{"jsonrpc" => "2.0", "method" => method, "params" => params}
  end

  defp envelope_to_map({:result, id, result}) do
    %{"jsonrpc" => "2.0", "id" => id, "result" => result}
  end

  defp envelope_to_map({:error, id, code, message, data}) do
    err = %{"code" => code, "message" => message}
    err = if is_nil(data), do: err, else: Map.put(err, "data", data)
    %{"jsonrpc" => "2.0", "id" => id, "error" => err}
  end
end
