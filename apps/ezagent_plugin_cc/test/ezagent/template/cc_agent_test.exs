defmodule Ezagent.PluginCc.Template.CcAgentTest do
  @moduledoc """
  PR-D2 — unified `cc.agent` Template Class. Replaces the previous
  cc.pty / cc.channel_instance split.
  """
  use ExUnit.Case, async: false

  alias Ezagent.PluginCc.Template.CcAgent

  describe "template_name/0" do
    test "returns 'cc.agent'" do
      assert CcAgent.template_name() == "cc.agent"
    end
  end

  describe "validate/1" do
    test "accepts a well-formed local-pty template" do
      assert :ok =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://cc/cc-architect",
                 "mode" => "local-pty",
                 "cwd" => "/tmp"
               })
    end

    test "accepts back-compat missing-mode (defaults to local-pty, cwd still required)" do
      assert :ok =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://cc/no-mode",
                 "cwd" => "/tmp"
               })
    end

    test "accepts remote-channel without cwd (placeholder mode)" do
      assert :ok =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://cc/remote",
                 "mode" => "remote-channel"
               })
    end

    test "rejects missing class" do
      assert {:error, :missing_class_field} =
               CcAgent.validate(%{"agent_uri" => "agent://cc/x", "cwd" => "/tmp"})
    end

    test "rejects wrong class" do
      assert {:error, {:wrong_class, "cc.pty"}} =
               CcAgent.validate(%{
                 "class" => "cc.pty",
                 "agent_uri" => "agent://cc/x",
                 "cwd" => "/tmp"
               })
    end

    test "rejects missing agent_uri" do
      assert {:error, :missing_agent_uri} =
               CcAgent.validate(%{"class" => "cc.agent", "cwd" => "/tmp"})
    end

    test "rejects non-agent scheme" do
      assert {:error, {:bad_agent_uri, _}} =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "user://x",
                 "cwd" => "/tmp"
               })
    end

    test "rejects un-typed legacy agent:// URI (PR #131 strict)" do
      assert {:error, {:missing_type_segment, _, _}} =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://just-a-name",
                 "cwd" => "/tmp"
               })
    end

    test "rejects wrong type segment" do
      assert {:error, {:wrong_agent_type, "curl", expected: "cc"}} =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://curl/my-deepseek",
                 "cwd" => "/tmp"
               })
    end

    test "rejects missing cwd for local-pty" do
      assert {:error, :missing_cwd} =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://cc/x",
                 "mode" => "local-pty"
               })
    end

    test "rejects unsupported mode" do
      assert {:error, {:unsupported_mode, "bogus"}} =
               CcAgent.validate(%{
                 "class" => "cc.agent",
                 "agent_uri" => "agent://cc/x",
                 "mode" => "bogus",
                 "cwd" => "/tmp"
               })
    end
  end

  describe "instantiate/3 — local-pty mode" do
    test "spawns a PtyServer for the declared agent" do
      agent_uri_str = "agent://cc/test-#{System.unique_integer([:positive])}"

      tmpl = %{
        "class" => "cc.agent",
        "agent_uri" => agent_uri_str,
        "mode" => "local-pty",
        "cwd" => "/tmp"
      }

      workspace_uri = URI.parse("workspace://test")

      assert {:ok, [returned_uri]} = CcAgent.instantiate("test-tmpl", tmpl, workspace_uri)
      assert URI.to_string(returned_uri) == agent_uri_str
    end

    test "is idempotent — second call returns same URI without spawning a second PtyServer" do
      agent_uri_str = "agent://cc/idem-#{System.unique_integer([:positive])}"
      uri = URI.parse(agent_uri_str)

      tmpl = %{
        "class" => "cc.agent",
        "agent_uri" => agent_uri_str,
        "mode" => "local-pty",
        "cwd" => "/tmp"
      }

      workspace_uri = URI.parse("workspace://test")

      assert {:ok, [^uri]} = CcAgent.instantiate("t", tmpl, workspace_uri)

      pids_before = list_pty_pids_for(agent_uri_str)
      assert length(pids_before) == 1

      assert {:ok, [^uri]} = CcAgent.instantiate("t", tmpl, workspace_uri)

      pids_after = list_pty_pids_for(agent_uri_str)
      assert pids_after == pids_before
    end
  end

  describe "instantiate/3 — remote-channel mode (placeholder)" do
    test "returns :not_implemented" do
      assert {:error, :remote_mode_not_implemented} =
               CcAgent.instantiate(
                 "t",
                 %{
                   "class" => "cc.agent",
                   "agent_uri" => "agent://cc/remote-x",
                   "mode" => "remote-channel"
                 },
                 URI.parse("workspace://test")
               )
    end
  end

  describe "registry integration" do
    test "Template Class is registered at boot" do
      assert {:ok, Ezagent.PluginCc.Template.CcAgent} =
               Ezagent.TemplateRegistry.lookup("cc.agent")
    end
  end

  defp list_pty_pids_for(agent_uri_str) do
    Ezagent.PluginCc.PtyServer.list_agents()
    |> Enum.filter(fn a -> URI.to_string(a.agent_uri) == agent_uri_str end)
    |> Enum.map(& &1.pid)
  end
end
