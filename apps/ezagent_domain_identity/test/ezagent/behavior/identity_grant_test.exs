defmodule Ezagent.Behavior.IdentityGrantTest do
  @moduledoc """
  Phase 6 PR 6 — grant_cap / revoke_cap behavior actions.
  """
  use EzagentCore.DataCase, async: false

  alias Ezagent.Behavior.Identity
  alias Ezagent.Capability

  test "grant_cap adds to slice + returns updated list" do
    slice = %{caps: MapSet.new()}

    new_cap = %Capability{
      kind: :echo,
      behavior: :any,
      instance: :any,
      granted_by: URI.parse("entity://user/default/admin"),
      granted_at: DateTime.utc_now()
    }

    {:ok, new_slice, %{caps: caps}} =
      Identity.invoke(:grant_cap, slice, %{cap: new_cap}, %{})

    assert MapSet.size(new_slice.caps) == 1
    assert new_cap in caps
  end

  test "revoke_cap removes from slice" do
    cap = %Capability{
      kind: :echo,
      behavior: :any,
      instance: :any,
      granted_by: URI.parse("entity://user/default/admin"),
      granted_at: DateTime.utc_now()
    }

    slice = %{caps: MapSet.new([cap])}

    {:ok, new_slice, %{caps: caps}} =
      Identity.invoke(:revoke_cap, slice, %{cap: cap}, %{})

    assert MapSet.size(new_slice.caps) == 0
    assert caps == []
  end

  test "grant_cap is idempotent (MapSet semantics)" do
    cap = %Capability{
      kind: :echo,
      behavior: :any,
      instance: :any,
      granted_by: URI.parse("entity://user/default/admin"),
      granted_at: DateTime.utc_now()
    }

    slice = %{caps: MapSet.new([cap])}

    {:ok, new_slice, _} = Identity.invoke(:grant_cap, slice, %{cap: cap}, %{})
    assert MapSet.size(new_slice.caps) == 1
  end

  test "interface declares grant_cap + revoke_cap" do
    iface = Identity.interface()
    assert Map.has_key?(iface, :grant_cap)
    assert Map.has_key?(iface, :revoke_cap)
    assert iface.grant_cap.modes == [:call]
  end
end
