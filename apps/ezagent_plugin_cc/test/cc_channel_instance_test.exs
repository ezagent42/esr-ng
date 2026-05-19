defmodule Ezagent.Template.CcChannelInstanceTest do
  @moduledoc """
  Phase 5 PR 5 invariant — operator can register a CC instance via
  the cc.channel_instance Template Class, token persists to
  $EZAGENT_HOME/credentials/cc-channels.yaml, idempotent re-instantiate
  returns the same token, lookup_by_token round-trips.
  """
  use ExUnit.Case, async: false

  setup do
    tmp = Path.join(System.tmp_dir!(), "esr-cc-ch-test-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "default/credentials"))
    File.chmod!(Path.join(tmp, "default/credentials"), 0o700)
    System.put_env("EZAGENT_HOME", tmp)

    on_exit(fn ->
      System.delete_env("EZAGENT_HOME")
      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "validate/1 enforces agent://cc/<name> shape (PR #131 strict)" do
    assert :ok =
             Ezagent.Template.CcChannelInstance.validate(%{
               "class" => "cc.channel_instance",
               "agent_uri" => "agent://cc/instance-x"
             })

    assert {:error, {:bad_agent_uri, _}} =
             Ezagent.Template.CcChannelInstance.validate(%{
               "class" => "cc.channel_instance",
               "agent_uri" => "user://x"
             })

    # PR #131: un-typed legacy agent:// is rejected
    assert {:error, {:missing_type_segment, _, _}} =
             Ezagent.Template.CcChannelInstance.validate(%{
               "class" => "cc.channel_instance",
               "agent_uri" => "agent://just-a-name"
             })

    # Wrong type segment is rejected
    assert {:error, {:wrong_agent_type, "curl", expected: "cc"}} =
             Ezagent.Template.CcChannelInstance.validate(%{
               "class" => "cc.channel_instance",
               "agent_uri" => "agent://curl/wrong"
             })

    assert {:error, :missing_agent_uri} =
             Ezagent.Template.CcChannelInstance.validate(%{"class" => "cc.channel_instance"})
  end

  test "instantiate mints + persists token + idempotent re-instantiate", %{tmp: tmp} do
    uri = URI.parse("agent://cc/cc-instance-test")

    assert {:ok, [^uri]} =
             Ezagent.Template.CcChannelInstance.instantiate(
               "main",
               %{"agent_uri" => URI.to_string(uri)},
               URI.parse("workspace://test")
             )

    file = Path.join([tmp, "default/credentials/cc-channels.yaml"])
    assert File.exists?(file)
    body = File.read!(file)
    assert body =~ "agent://cc/cc-instance-test"
    assert body =~ "token: \"tok_"

    # Re-instantiate → same token
    [{_uri, %{"token" => t1}}] = EzagentPluginCc.TokenStore.list_all()

    assert {:ok, [^uri]} =
             Ezagent.Template.CcChannelInstance.instantiate(
               "main",
               %{"agent_uri" => URI.to_string(uri)},
               URI.parse("workspace://test")
             )

    [{_uri, %{"token" => t2}}] = EzagentPluginCc.TokenStore.list_all()
    assert t1 == t2
  end

  test "lookup_by_token round-trips" do
    uri = URI.parse("agent://lookup-test")
    {:ok, token} = EzagentPluginCc.TokenStore.mint(uri)

    assert {:ok, ^uri} = EzagentPluginCc.TokenStore.lookup_by_token(token)
    assert :error = EzagentPluginCc.TokenStore.lookup_by_token("tok_nonexistent")
  end

  test "form_fields/0 declares agent_uri" do
    [field] = Ezagent.Template.CcChannelInstance.form_fields()
    assert field.name == "agent_uri"
    assert field.type == :uri
    assert field.required == true
  end
end
