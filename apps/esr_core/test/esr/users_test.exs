defmodule Esr.UsersTest do
  use EsrCore.DataCase, async: false

  alias Esr.Users

  describe "create/3" do
    test "inserts a user with bcrypt password + caps" do
      uri = "user://test-#{System.unique_integer([:positive])}"

      {:ok, decoded} = Users.create(uri, "secret", [])

      assert URI.to_string(decoded.uri) == uri
      assert is_binary(decoded.password_hash)
      assert decoded.password_hash != "secret"
      assert decoded.caps == []
    end

    test "nil password leaves password_hash nil" do
      uri = "user://nopw-#{System.unique_integer([:positive])}"

      {:ok, decoded} = Users.create(uri, nil, [])
      assert decoded.password_hash == nil
    end

    test "caps round-trip through JSON" do
      uri = "user://caps-#{System.unique_integer([:positive])}"

      cap = %Esr.Capability{
        kind: :workspace,
        behavior: Esr.Behavior.Workspace,
        instance: :any,
        granted_by: URI.parse("user://admin"),
        granted_at: ~U[2026-05-16 00:00:00.000000Z]
      }

      {:ok, decoded} = Users.create(uri, "x", [cap])
      assert [%Esr.Capability{kind: :workspace, behavior: Esr.Behavior.Workspace, instance: :any}] = decoded.caps
    end

    test "duplicate uri returns error" do
      uri = "user://dup-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, "x", [])
      assert {:error, _changeset} = Users.create(uri, "y", [])
    end
  end

  describe "verify_password/2" do
    test "true for correct password" do
      uri = "user://verify-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, "right-pw", [])

      assert Users.verify_password(uri, "right-pw")
    end

    test "false for wrong password" do
      uri = "user://wrong-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, "right-pw", [])

      refute Users.verify_password(uri, "WRONG")
    end

    test "false for nonexistent user (no timing leak)" do
      refute Users.verify_password("user://does-not-exist", "anything")
    end

    test "false for user with NULL password_hash (must set_password first)" do
      uri = "user://nopw-vp-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, nil, [])

      refute Users.verify_password(uri, "anything")
    end
  end

  describe "set_password/2" do
    test "updates an existing user's hash" do
      uri = "user://setpw-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, "old", [])

      assert {:ok, _} = Users.set_password(uri, "new")
      refute Users.verify_password(uri, "old")
      assert Users.verify_password(uri, "new")
    end

    test "set_password on NULL-hash row enables login" do
      uri = "user://enable-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, nil, [])
      refute Users.verify_password(uri, "anything")

      {:ok, _} = Users.set_password(uri, "now-set")
      assert Users.verify_password(uri, "now-set")
    end

    test "returns :not_found for unknown uri" do
      assert {:error, :not_found} =
               Users.set_password("user://never-existed-#{System.unique_integer()}", "x")
    end
  end

  describe "list_all/0 + get_by_uri/1" do
    test "lists every row + lookup roundtrip" do
      uri = "user://list-#{System.unique_integer([:positive])}"
      {:ok, _} = Users.create(uri, "x", [])

      uris = Users.list_all() |> Enum.map(fn d -> URI.to_string(d.uri) end)
      assert uri in uris

      assert %{uri: %URI{}} = Users.get_by_uri(uri)
    end

    test "get_by_uri returns nil for unknown" do
      assert nil ==
               Users.get_by_uri("user://no-such-#{System.unique_integer([:positive])}")
    end
  end
end
