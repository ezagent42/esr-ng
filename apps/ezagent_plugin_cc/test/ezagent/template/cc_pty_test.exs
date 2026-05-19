defmodule Ezagent.PluginCc.TemplateTest do
  use ExUnit.Case, async: false

  alias Ezagent.PluginCc.Template

  describe "template_name/0" do
    test "returns stable id" do
      assert Template.template_name() == "cc.pty"
    end
  end

  describe "validate/1" do
    test "accepts well-formed template" do
      assert :ok =
               Template.validate(%{
                 "class" => "cc.pty",
                 "agent_uri" => "agent://cc-architect",
                 "cwd" => "/tmp"
               })
    end

    test "rejects missing class" do
      assert {:error, :missing_class_field} =
               Template.validate(%{"agent_uri" => "agent://x", "cwd" => "/tmp"})
    end

    test "rejects wrong class" do
      assert {:error, {:wrong_class, "other"}} =
               Template.validate(%{"class" => "other", "agent_uri" => "agent://x", "cwd" => "/tmp"})
    end

    test "rejects missing agent_uri" do
      assert {:error, :missing_agent_uri} =
               Template.validate(%{"class" => "cc.pty", "cwd" => "/tmp"})
    end

    test "rejects non-agent scheme URI" do
      assert {:error, {:bad_agent_uri, _}} =
               Template.validate(%{"class" => "cc.pty", "agent_uri" => "user://x", "cwd" => "/tmp"})
    end

    test "rejects missing cwd" do
      assert {:error, :missing_cwd} =
               Template.validate(%{"class" => "cc.pty", "agent_uri" => "agent://x"})
    end
  end

  describe "instantiate/3 (test_mode — no actual claude spawn)" do
    test "spawns a PtyServer for the declared agent" do
      agent_uri_str = "agent://test-#{System.unique_integer([:positive])}"

      tmpl = %{
        "class" => "cc.pty",
        "agent_uri" => agent_uri_str,
        "cwd" => "/tmp"
      }

      workspace_uri = URI.parse("workspace://test")

      assert {:ok, [returned_uri]} = Template.instantiate("test-tmpl", tmpl, workspace_uri)
      assert URI.to_string(returned_uri) == agent_uri_str
    end
  end

  describe "registry integration" do
    test "Template Class is registered at boot" do
      assert {:ok, Ezagent.PluginCc.Template} =
               Ezagent.TemplateRegistry.lookup("cc.pty")
    end
  end
end
