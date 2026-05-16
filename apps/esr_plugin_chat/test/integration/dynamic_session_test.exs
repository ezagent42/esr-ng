defmodule EsrPluginChat.Integration.DynamicSessionTest do
  @moduledoc """
  Phase 3b-step 1: dynamic non-main Session create flow.
  """

  use ExUnit.Case
  alias Esr.{KindRegistry, Entity.User}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})
    :ok
  end

  test "create_session spawns Session Kind + joins creator" do
    short = "dyn-#{System.unique_integer([:positive])}"
    assert {:ok, session_uri} = EsrPluginChat.create_session(short)
    assert URI.to_string(session_uri) == "session://#{short}"

    # KindRegistry has it
    assert {:ok, pid} = KindRegistry.lookup(session_uri)
    assert Process.alive?(pid)

    # admin in members (poll briefly for cast to land)
    admin_uri = User.admin_uri()

    assert wait_until(fn ->
             %{state: %{chat: slice}} = :sys.get_state(pid)
             Map.has_key?(slice.members, admin_uri)
           end)
  end

  test "create_session is idempotent — re-call returns same URI" do
    short = "idemp-#{System.unique_integer([:positive])}"
    assert {:ok, uri1} = EsrPluginChat.create_session(short)
    assert {:ok, uri2} = EsrPluginChat.create_session(short)
    assert uri1 == uri2
  end

  test "main short-name is rejected (static child only)" do
    assert {:error, :main_is_static} = EsrPluginChat.create_session("main")
  end

  test "list_sessions includes main + any dynamic sessions" do
    short = "listed-#{System.unique_integer([:positive])}"
    {:ok, _} = EsrPluginChat.create_session(short)

    uris = EsrPluginChat.list_sessions() |> Enum.map(&URI.to_string/1)
    assert "session://main" in uris
    assert "session://#{short}" in uris
  end

  defp wait_until(fun, retries \\ 50) do
    case fun.() do
      false when retries > 0 ->
        Process.sleep(10)
        wait_until(fun, retries - 1)

      result ->
        result
    end
  end
end
