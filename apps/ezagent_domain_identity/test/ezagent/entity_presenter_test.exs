defmodule Ezagent.EntityPresenterTest do
  use EzagentCore.DataCase, async: false

  alias Ezagent.Entity.Profile
  alias Ezagent.EntityPresenter

  test "display/1 returns the profile name when present" do
    {:ok, _} = Profile.upsert(%{entity_uri: "entity://user/default/allen", display_name: "Allen Woods"})
    assert EntityPresenter.display("entity://user/default/allen") == "Allen Woods"
  end

  test "display/1 falls back to the URI path segment when no profile" do
    assert EntityPresenter.display("entity://user/default/admin") == "admin"
    assert EntityPresenter.display("entity://agent/default/echo") == "echo"
  end

  test "display/1 falls back to the raw string for an unparseable URI" do
    assert EntityPresenter.display("not a uri") == "not a uri"
  end

  test "display_many/1 batch-resolves, keyed by string, with fallbacks" do
    {:ok, _} = Profile.upsert(%{entity_uri: "entity://user/default/a", display_name: "Ay"})

    result = EntityPresenter.display_many(["entity://user/default/a", URI.parse("entity://agent/default/echo")])

    assert result == %{
             "entity://user/default/a" => "Ay",
             "entity://agent/default/echo" => "echo"
           }
  end
end
