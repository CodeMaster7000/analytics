defmodule PlausibleWeb.Live.VerificaionTest do
  use PlausibleWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Plausible.Test.Support.HTML

  setup [:create_user, :log_in, :create_site]

  @verify_button ~s|button#launch-verification-button[phx-click="launch-verification"]|
  @verification_modal ~s|div#verification-modal|

  describe "GET /:domain" do
    test "static verification screen renders", %{conn: conn, site: site} do
      conn = get(conn, "/#{site.domain}")
      resp = html_response(conn, 200)
      assert resp =~ "Verifying your installation"
      assert resp =~ "on #{site.domain}"

      assert resp =~ "Need to see the snippet again?"
      assert resp =~ "Run verification later and go to Site Settings?"
      assert resp =~ "Skip to the dashboard?"

      refute resp =~ "modal"
    end
  end

  describe "GET /settings/general" do
    test "verification elements render under the snippet", %{conn: conn, site: site} do
      conn = get(conn, "/#{site.domain}/settings/general")
      resp = html_response(conn, 200)

      assert element_exists?(resp, @verify_button)

      assert element_exists?(resp, @verification_modal)
    end
  end

  describe "LiveView: foo" do
    test "foo", %{conn: conn, site: site} do
      get_lv_standalone(conn, site)
      |> IO.inspect(label: :result)
    end
  end

  def get_lv_standalone(conn, site) do
    conn = assign(conn, :live_module, PlausibleWeb.Live.Verification)
    {:ok, lv, html} = live(conn, "/#{site.domain}")
    {lv, html}
  end
end
