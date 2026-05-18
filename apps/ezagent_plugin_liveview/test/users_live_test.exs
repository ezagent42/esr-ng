defmodule EzagentPluginLiveview.UsersLiveTest do
  use ExUnit.Case
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest

  @endpoint EsrWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(EsrCore.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(EsrCore.Repo, {:shared, self()})

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Test.init_test_session(%{
        "current_user_uri" => URI.to_string(Esr.Entity.User.admin_uri())
      })

    {:ok, conn: conn}
  end

  test "GET /admin/users renders existing admin row + create form", %{conn: conn} do
    {:ok, _lv, html} = live(conn, "/admin/users")
    assert html =~ "Users"
    assert html =~ "user://admin"
    assert html =~ "Create user"
  end

  test "create_user persists + appears in list", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/users")
    uri = "user://lv-create-#{System.unique_integer([:positive])}"

    lv
    |> form("#create-user form",
      user: %{
        uri: uri,
        password: "pw",
        caps: "workspace.workspace"
      }
    )
    |> render_submit()

    html = render(lv)
    assert html =~ uri
    assert %{} = Esr.Users.get_by_uri(uri)
  end

  test "create_user refuses '*' caps via UI (must use mix --allow-allcaps)", %{conn: conn} do
    {:ok, lv, _html} = live(conn, "/admin/users")
    uri = "user://lv-allcaps-#{System.unique_integer([:positive])}"

    lv
    |> form("#create-user form",
      user: %{
        uri: uri,
        password: "pw",
        caps: "*"
      }
    )
    |> render_submit()

    html = render(lv)
    assert html =~ "allow-allcaps"
    assert nil == Esr.Users.get_by_uri(uri)
  end

  test "set_password updates an existing user (PR 4 path)" do
    # Direct facade test — UI form submission with hidden field is
    # awkward in Phoenix.LiveViewTest; the facade is exercised in
    # PR 4 unit tests + the LV button is plain HTML POST.
    uri = "user://lv-setpw-#{System.unique_integer([:positive])}"
    {:ok, _} = Esr.Users.create(uri, nil, [])
    refute Esr.Users.verify_password(uri, "anything")

    assert {:ok, _} = Esr.Users.set_password(uri, "new-pw")
    assert Esr.Users.verify_password(uri, "new-pw")
  end
end
