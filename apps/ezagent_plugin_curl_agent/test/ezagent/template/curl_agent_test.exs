defmodule Ezagent.PluginCurlAgent.TemplateTest do
  use ExUnit.Case, async: true

  alias Ezagent.PluginCurlAgent.Template

  describe "validate/1 — PR #131 strict agent://curl/<name> shape" do
    test "happy path" do
      assert :ok =
               Template.validate(%{
                 "class" => "curl.agent",
                 "agent_uri" => "agent://curl/my-deepseek",
                 "provider" => "deepseek",
                 "api_url" => "https://api.deepseek.com/chat/completions",
                 "model" => "deepseek-chat"
               })
    end

    test "rejects wrong class" do
      assert {:error, {:wrong_class, "cc.pty"}} =
               Template.validate(%{
                 "class" => "cc.pty",
                 "agent_uri" => "agent://curl/x",
                 "provider" => "deepseek",
                 "api_url" => "https://x.test/chat",
                 "model" => "x"
               })
    end

    test "rejects un-typed legacy agent:// URI" do
      assert {:error, {:missing_type_segment, _, _}} =
               Template.validate(%{
                 "class" => "curl.agent",
                 "agent_uri" => "agent://just-a-name",
                 "provider" => "deepseek",
                 "api_url" => "https://x.test/chat",
                 "model" => "x"
               })
    end

    test "rejects legacy curl-agent:// scheme (PR #131 strict mode)" do
      assert {:error, {:bad_agent_uri, _}} =
               Template.validate(%{
                 "class" => "curl.agent",
                 "agent_uri" => "curl-agent://legacy",
                 "provider" => "deepseek",
                 "api_url" => "https://x.test/chat",
                 "model" => "x"
               })
    end

    test "rejects agent:// with wrong type" do
      assert {:error, {:wrong_agent_type, "cc", expected: "curl"}} =
               Template.validate(%{
                 "class" => "curl.agent",
                 "agent_uri" => "agent://cc/wrong-type",
                 "provider" => "deepseek",
                 "api_url" => "https://x.test/chat",
                 "model" => "x"
               })
    end

    test "rejects non-http(s) api_url" do
      assert {:error, {:bad_api_url, "ftp://nope"}} =
               Template.validate(%{
                 "class" => "curl.agent",
                 "agent_uri" => "agent://curl/x",
                 "provider" => "deepseek",
                 "api_url" => "ftp://nope",
                 "model" => "x"
               })
    end

    test "rejects missing model" do
      assert {:error, :missing_model} =
               Template.validate(%{
                 "class" => "curl.agent",
                 "agent_uri" => "agent://curl/x",
                 "provider" => "deepseek",
                 "api_url" => "https://x.test/chat"
               })
    end
  end

  describe "form_fields/0 — auto-derived UI surface" do
    test "all required fields present + ordered for sensible left-to-right reading" do
      names = Template.form_fields() |> Enum.map(& &1.name)

      assert names == [
               "agent_uri",
               "provider",
               "api_url",
               "model",
               "system_prompt",
               "max_history",
               "owner_uri"
             ]
    end

    test "required fields marked correctly" do
      required =
        Template.form_fields()
        |> Enum.filter(& &1.required)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      assert required == ["agent_uri", "api_url", "model", "provider"]
    end
  end

  describe "template_name/0" do
    test "is curl.agent" do
      assert Template.template_name() == "curl.agent"
    end
  end
end
