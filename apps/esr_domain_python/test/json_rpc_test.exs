defmodule EsrDomainPython.JsonRpcTest do
  use ExUnit.Case, async: true

  alias EsrDomainPython.JsonRpc

  test "encode + decode roundtrip — request" do
    env = {:request, 1, "behavior.invoke", %{"action" => "send"}}
    body = env |> JsonRpc.encode_frame() |> IO.iodata_to_binary()

    [_header, json] = String.split(body, "\r\n\r\n", parts: 2)
    assert {:ok, ^env} = JsonRpc.decode_body(json)
  end

  test "encode + decode roundtrip — notification" do
    env = {:notification, "audit.log", %{"level" => "info", "event" => "x"}}
    body = env |> JsonRpc.encode_frame() |> IO.iodata_to_binary()

    [_, json] = String.split(body, "\r\n\r\n", parts: 2)
    assert {:ok, ^env} = JsonRpc.decode_body(json)
  end

  test "encode + decode roundtrip — result" do
    env = {:result, 42, %{"ok" => true}}
    body = env |> JsonRpc.encode_frame() |> IO.iodata_to_binary()

    [_, json] = String.split(body, "\r\n\r\n", parts: 2)
    assert {:ok, ^env} = JsonRpc.decode_body(json)
  end

  test "encode + decode roundtrip — error" do
    env = {:error, 7, -32601, "method not found", %{"method" => "garbage"}}
    body = env |> JsonRpc.encode_frame() |> IO.iodata_to_binary()

    [_, json] = String.split(body, "\r\n\r\n", parts: 2)
    assert {:ok, ^env} = JsonRpc.decode_body(json)
  end

  test "decode rejects missing jsonrpc field" do
    assert {:error, :missing_jsonrpc_version} =
             JsonRpc.decode_body(~s|{"method": "foo"}|)
  end

  test "decode rejects garbage JSON" do
    assert {:error, {:json_decode_failed, _}} =
             JsonRpc.decode_body("{not json")
  end

  test "Content-Length header carries correct byte count" do
    env = {:notification, "ping", %{}}
    body = env |> JsonRpc.encode_frame() |> IO.iodata_to_binary()

    [header, json] = String.split(body, "\r\n\r\n", parts: 2)
    [len_str] = Regex.run(~r/Content-Length:\s*(\d+)/, header, capture: :all_but_first)
    assert String.to_integer(len_str) == byte_size(json)
  end
end
