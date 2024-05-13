defmodule Plausible.Verification.ChecksTest do
  use Plausible.DataCase, async: true

  alias Plausible.Verification.Checks
  alias Plausible.Verification.State
  import ExUnit.CaptureLog

  @normal_body """
  <html>
  <head>
  <script defer data-domain=\"example.com\" src=\"https://plausible.io/js/plausible.js\"></script>
  </head>
  <body>Hello</body>
  </html>
  """

  describe "running checks" do
    test "success" do
      stub_fetch_body(200, @normal_body)
      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      result = run_checks()

      assert result.diagnostics.document_content_type == "text/html; charset=utf-8"
      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      assert result.diagnostics.body_fetched? == true
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    test "service error - 400" do
      stub_fetch_body(200, @normal_body)
      stub_installation(400, %{})

      result = run_checks()

      assert result.diagnostics.document_content_type == "text/html; charset=utf-8"
      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == false
      assert result.diagnostics.body_fetched? == true
      assert result.diagnostics.service_error == 400
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    @tag :slow
    test "can't fetch body but headless reports ok" do
      stub_fetch_body(500, "")
      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      {result, log} =
        with_log(fn ->
          run_checks()
        end)

      assert log =~ "3 attempts left"
      assert log =~ "2 attempts left"
      assert log =~ "1 attempt left"

      assert result.diagnostics.document_content_type == ""
      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true

      assert result.diagnostics.body_fetched? == false
      refute result.diagnostics.service_error

      refute result.diagnostics.snippet_found_after_busting_cache
    end

    test "fetching will follow 1 redirect" do
      ref = :counters.new(1, [:atomics])
      test = self()

      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        if :counters.get(ref, 1) < 1 do
          :counters.add(ref, 1, 1)
          send(test, :redirect_sent)

          conn
          |> Plug.Conn.put_resp_header("location", "https://example.com")
          |> Plug.Conn.send_resp(302, "redirecting to https://example.com")
        else
          conn
          |> Plug.Conn.send_resp(200, @normal_body)
        end
      end)

      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      result = run_checks()
      assert_receive :redirect_sent

      assert result.diagnostics.document_content_type == ""
      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      assert result.diagnostics.body_fetched? == true
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    test "fetching will not follow more than 1 redirect" do
      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "https://example.com")
        |> Plug.Conn.send_resp(302, "redirecting to https://example.com")
      end)

      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      result = run_checks()

      assert result.diagnostics.document_content_type == ""
      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      assert result.diagnostics.body_fetched? == false
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    test "fetching body fails at non-2xx status" do
      stub_fetch_body(599, "boo")
      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      result = run_checks()

      assert result.diagnostics.document_content_type == ""
      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      refute result.diagnostics.body_fetched?
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    @snippet_in_body """
    <html>
    <head>
    </head>
    <body>
    Hello
    <script defer data-domain=\"example.com\" src=\"https://plausible.io/js/plausible.js\"></script>
    </body>
    </html>
    """

    test "detecting snippet in head" do
      stub_fetch_body(200, @snippet_in_body)
      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 1
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    @many_snippets """
    <html>
    <head>
    <script defer data-domain=\"example.com\" src=\"https://plausible.io/js/plausible.js\"></script>
    <script defer data-domain=\"example.com\" src=\"https://plausible.io/js/plausible.js\"></script>
    </head>
    <body>
    Hello
    <script defer data-domain=\"example.com\" src=\"https://plausible.io/js/plausible.js\"></script>
    <script defer data-domain=\"example.com\" src=\"https://plausible.io/js/plausible.js\"></script>
    </body>
    </html>
    """

    test "detecting many snippets" do
      stub_fetch_body(200, @many_snippets)
      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 2
      assert result.diagnostics.snippets_found_in_body == 2
      refute result.diagnostics.snippet_found_after_busting_cache
    end

    @body_no_snippet """
    <html>
    <head>
    </head>
    <body>
    Hello
    </body>
    </html>
    """

    test "detecting snippet after busting cache" do
      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        if conn.query_params["plausible_verification"] do
          conn
          |> Plug.Conn.send_resp(200, @normal_body)
        else
          Plug.Conn.send_resp(conn, 200, @body_no_snippet)
        end
      end)

      Req.Test.stub(Plausible.Verification.Checks.Installation, fn conn ->
        conn = Plug.Conn.fetch_query_params(conn)

        if conn.query_params["plausible_verification"] do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"plausibleInstalled" => true}))
        else
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(%{"plausibleInstalled" => false}))
        end
      end)

      result = run_checks()
      assert result.diagnostics.snippet_found_after_busting_cache == true
      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
    end

    test "a check that raises" do
      defmodule FaultyCheckRaise do
        use Plausible.Verification.Check

        @impl true
        def friendly_name, do: "Faulty check"

        @impl true
        def perform(_), do: raise("boom")
      end

      {result, log} =
        with_log(fn ->
          run_checks(checks: [FaultyCheckRaise])
        end)

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == false
      assert result.diagnostics.document_content_type == ""
      assert result.diagnostics.service_error == nil
      assert result.diagnostics.body_fetched? == false
      assert result.diagnostics.snippet_found_after_busting_cache == false

      assert log =~
               ~s|Error running check Faulty check on https://example.com: %RuntimeError{message: "boom"}|
    end

    test "a check that throws" do
      defmodule FaultyCheckThrow do
        use Plausible.Verification.Check

        @impl true
        def friendly_name, do: "Faulty check"

        @impl true
        def perform(_), do: :erlang.throw(:boom)
      end

      {result, log} =
        with_log(fn ->
          run_checks(checks: [FaultyCheckThrow])
        end)

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == false
      assert result.diagnostics.document_content_type == ""
      assert result.diagnostics.service_error == nil
      assert result.diagnostics.body_fetched? == false
      assert result.diagnostics.snippet_found_after_busting_cache == false

      assert log =~
               ~s|Error running check Faulty check on https://example.com: :boom|
    end

    test "running checks sends progress messages" do
      stub_fetch_body(200, @normal_body)
      stub_installation(200, %{"data" => %{"plausibleInstalled" => true}})

      final_state = run_checks(report_to: self())

      assert_receive {:verification_check_start, {Checks.FetchBody, %State{}}}
      assert_receive {:verification_check_start, {Checks.Snippet, %State{}}}
      assert_receive {:verification_check_start, {Checks.Installation, %State{}}}
      assert_receive {:verification_end, %State{} = ^final_state}
    end
  end

  def run_checks(extra_opts \\ []) do
    Checks.run(
      "https://example.com",
      "example.com",
      Keyword.merge([async?: false, report_to: nil, slowdown: 0], extra_opts)
    )
  end

  defp stub_fetch_body(status, body) do
    Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("text/html")
      |> Plug.Conn.send_resp(status, body)
    end)
  end

  defp stub_installation(status, json) do
    Req.Test.stub(Plausible.Verification.Checks.Installation, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(json))
    end)
  end
end
