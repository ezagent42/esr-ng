defmodule EzagentWeb.Plugs.LocaleTest do
  @moduledoc """
  i18n V1 (Allen 2026-05-21) — Plug.Locale resolves Gettext locale from
  (in priority order): `?locale=` query → session → Accept-Language →
  default "en".
  """
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias EzagentWeb.Plugs.Locale

  setup do
    # Each test runs in this process so process-dict locale doesn't
    # leak between tests. Reset to the default before each.
    Gettext.put_locale(EzagentWeb.Gettext, "en")
    :ok
  end

  describe "call/2 — locale resolution priority" do
    test "query param wins over session and header" do
      conn =
        :get
        |> conn("/?locale=zh_CN")
        |> put_req_header("accept-language", "en-US")
        |> init_test_session(%{locale: "en"})
        |> Locale.call([])

      assert conn.assigns.current_locale == "zh_CN"
      assert get_session(conn, :locale) == "zh_CN"
      assert Gettext.get_locale(EzagentWeb.Gettext) == "zh_CN"
    end

    test "unsupported query param is ignored (falls through to session)" do
      conn =
        :get
        |> conn("/?locale=fr")
        |> init_test_session(%{locale: "zh_CN"})
        |> Locale.call([])

      assert conn.assigns.current_locale == "zh_CN"
    end

    test "session locale wins over header when query absent" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "en-US,en;q=0.9")
        |> init_test_session(%{locale: "zh_CN"})
        |> Locale.call([])

      assert conn.assigns.current_locale == "zh_CN"
    end

    test "Accept-Language containing zh resolves to zh_CN" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "zh-CN,zh;q=0.9,en;q=0.8")
        |> init_test_session(%{})
        |> Locale.call([])

      assert conn.assigns.current_locale == "zh_CN"
    end

    test "Accept-Language without zh falls back to default en" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "en-US,en;q=0.9,fr;q=0.5")
        |> init_test_session(%{})
        |> Locale.call([])

      assert conn.assigns.current_locale == "en"
    end

    test "no headers and no session yield default en" do
      conn =
        :get
        |> conn("/")
        |> init_test_session(%{})
        |> Locale.call([])

      assert conn.assigns.current_locale == "en"
    end

    test "invalid session value falls through to header" do
      conn =
        :get
        |> conn("/")
        |> put_req_header("accept-language", "zh-CN")
        |> init_test_session(%{locale: "not-a-locale"})
        |> Locale.call([])

      assert conn.assigns.current_locale == "zh_CN"
    end

    test "supported_locales/0 returns the V1 set" do
      assert Locale.supported_locales() == ["en", "zh_CN"]
    end
  end
end
