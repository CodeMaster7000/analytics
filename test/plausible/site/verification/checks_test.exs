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
      stub_installation()

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      assert result.diagnostics.body_fetched? == true
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache?
      assert result.diagnostics.scan_findings == []
      assert result.diagnostics.callback_status == 202
      refute result.diagnostics.proxy_likely?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []
      assert rating.recommendations == []
    end

    test "service error - 400" do
      stub_fetch_body(200, @normal_body)
      stub_installation(400, %{})

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == false
      assert result.diagnostics.body_fetched? == true
      assert result.diagnostics.service_error == 400
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)

      refute rating.ok?

      assert rating.errors == ["Your website is up, but we couldn't verify it"]

      assert rating.recommendations == [
               "Please try again in a few minutes",
               "Try visiting your website to help us register pageviews"
             ]
    end

    @tag :slow
    test "can't fetch body but headless reports ok" do
      stub_fetch_body(500, "")
      stub_installation()

      {result, log} =
        with_log(fn ->
          run_checks()
        end)

      assert log =~ "3 attempts left"
      assert log =~ "2 attempts left"
      assert log =~ "1 attempt left"

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true

      assert result.diagnostics.body_fetched? == false
      refute result.diagnostics.service_error

      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []
      assert rating.recommendations == []
    end

    test "fetching will follow 2 redirects" do
      ref = :counters.new(1, [:atomics])
      test = self()

      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        if :counters.get(ref, 1) < 2 do
          :counters.add(ref, 1, 1)
          send(test, :redirect_sent)

          conn
          |> Plug.Conn.put_resp_header("location", "https://example.com")
          |> Plug.Conn.send_resp(302, "redirecting to https://example.com")
        else
          conn
          |> Plug.Conn.put_resp_header("content-type", "text/html")
          |> Plug.Conn.send_resp(200, @normal_body)
        end
      end)

      stub_installation()

      result = run_checks()
      assert_receive :redirect_sent
      assert_receive :redirect_sent
      refute_receive _

      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      assert result.diagnostics.body_fetched? == true
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []
      assert rating.recommendations == []
    end

    test "fetching will not follow more than 2 redirect" do
      test = self()

      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        send(test, :redirect_sent)

        conn
        |> Plug.Conn.put_resp_header("location", "https://example.com")
        |> Plug.Conn.send_resp(302, "redirecting to https://example.com")
      end)

      stub_installation()

      result = run_checks()

      assert_receive :redirect_sent
      assert_receive :redirect_sent
      assert_receive :redirect_sent
      refute_receive _

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      assert result.diagnostics.body_fetched? == false
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []
      assert rating.recommendations == []
    end

    test "fetching body fails at non-2xx status" do
      stub_fetch_body(599, "boo")
      stub_installation()

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == true
      refute result.diagnostics.body_fetched?
      refute result.diagnostics.service_error
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []
      assert rating.recommendations == []
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

    test "detecting snippet in body" do
      stub_fetch_body(200, @snippet_in_body)
      stub_installation()

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 1
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []

      assert rating.recommendations ==
               [
                 "Hint: Place the snippet in <head> rather than <body>"
               ]
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
      stub_installation()

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 2
      assert result.diagnostics.snippets_found_in_body == 2
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []

      assert rating.recommendations == [
               "Hint: Place the snippet in <head> rather than <body>",
               {"Hint: Multiple snippets found on your website. Was that intentional?",
                "https://plausible.io/docs/script-extensions"}
             ]
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
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.send_resp(200, @normal_body)
        else
          conn
          |> Plug.Conn.put_resp_content_type("text/html")
          |> Plug.Conn.send_resp(200, @body_no_snippet)
        end
      end)

      Req.Test.stub(Plausible.Verification.Checks.Installation, fn conn ->
        {:ok, body, _} = Plug.Conn.read_body(conn)

        if String.contains?(body, "?plausible_verification") do
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(200, Jason.encode!(plausible_installed()))
        else
          raise "Should not get here even"
        end
      end)

      result = run_checks()

      assert result.diagnostics.snippet_found_after_busting_cache? == true
      assert result.diagnostics.snippets_found_in_head == 1
      assert result.diagnostics.snippets_found_in_body == 0

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []

      assert rating.recommendations == [
               "Hint: Purge your site's cache to ensure you're viewing the latest version of your website"
             ]
    end

    test "detecting no snippet" do
      stub_fetch_body(200, @body_no_snippet)
      stub_installation(200, plausible_installed(false))

      result = run_checks()

      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      refute result.diagnostics.snippet_found_after_busting_cache?

      rating = State.interpret_diagnostics(result)

      refute rating.ok?
      assert rating.errors == ["We found no snippet installed on your website"]

      assert rating.recommendations == [
               {"Hint: Place the snippet on your website and deploy it",
                "https://plausible.io/docs/plausible-script"}
             ]
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
      assert result.diagnostics.service_error == true
      assert result.diagnostics.body_fetched? == false
      assert result.diagnostics.snippet_found_after_busting_cache? == false

      assert log =~
               ~s|Error running check Faulty check on https://example.com: %RuntimeError{message: "boom"}|

      rating = State.interpret_diagnostics(result)

      refute rating.ok?
      assert rating.errors == ["We encountered a temporary problem verifying your website"]

      assert rating.recommendations == [
               "Please try again in a few minutes",
               "Try visiting your website to help us register pageviews"
             ]
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
      assert result.diagnostics.service_error == true
      assert result.diagnostics.body_fetched? == false
      assert result.diagnostics.snippet_found_after_busting_cache? == false

      assert log =~
               ~s|Error running check Faulty check on https://example.com: :boom|

      rating = State.interpret_diagnostics(result)
      refute rating.ok?
      assert rating.errors == ["We encountered a temporary problem verifying your website"]

      assert rating.recommendations == [
               "Please try again in a few minutes",
               "Try visiting your website to help us register pageviews"
             ]
    end

    test "disallowed via content-security-policy" do
      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-security-policy", "default-src 'self' foo.local")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @normal_body)
      end)

      installed? = Enum.random([true, false])
      stub_installation(200, plausible_installed(installed?))

      result = run_checks()

      assert result.diagnostics.disallowed_via_csp? == true

      rating = State.interpret_diagnostics(result)

      assert rating.ok? == installed?
      assert rating.errors == []

      assert rating.recommendations == [
               {"Make sure your Content-Security-Policy allows plausible.io",
                "https://plausible.io/docs/troubleshoot-integration"}
             ]
    end

    test "allowed via content-security-policy" do
      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        conn
        |> Plug.Conn.put_resp_header(
          "content-security-policy",
          Enum.random([
            "default-src 'self'; script-src plausible.io; connect-src plausible.io",
            "default-src 'self' *.plausible.io"
          ])
        )
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, @normal_body)
      end)

      stub_installation()
      result = run_checks()

      assert result.diagnostics.disallowed_via_csp? == false

      rating = State.interpret_diagnostics(result)

      assert rating.ok?
      assert rating.errors == []
      assert rating.recommendations == []
    end

    test "running checks sends progress messages" do
      stub_fetch_body(200, @normal_body)
      stub_installation()

      final_state = run_checks(report_to: self())

      assert_receive {:verification_check_start, {Checks.FetchBody, %State{}}}
      assert_receive {:verification_check_start, {Checks.CSP, %State{}}}
      assert_receive {:verification_check_start, {Checks.ScanBody, %State{}}}
      assert_receive {:verification_check_start, {Checks.Snippet, %State{}}}
      assert_receive {:verification_check_start, {Checks.SnippetCacheBust, %State{}}}
      assert_receive {:verification_check_start, {Checks.Installation, %State{}}}
      assert_receive {:verification_end, %State{} = ^final_state}
      refute_receive _
    end

    @gtm_body """
    <html>
    <head>
    </head>
    <body>
    Hello
     <noscript><iframe src="https://www.googletagmanager.com/ns.html?id=GTM-XXXX" height="0" width="0" style="display:none;visibility:hidden"></iframe></noscript>
    </body>
    </html>
    """

    test "detecting gtm" do
      stub_fetch_body(200, @gtm_body)
      stub_installation()

      result = run_checks()

      assert result.diagnostics.scan_findings == [:gtm]

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []

      assert rating.recommendations == [
               {"Using Google Tag Manager?", "https://plausible.io/docs/google-tag-manager"}
             ]
    end

    test "non-html body" do
      Req.Test.stub(Plausible.Verification.Checks.FetchBody, fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("image/png")
        |> Plug.Conn.send_resp(200, :binary.copy(<<0>>, 100))
      end)

      stub_installation(200, plausible_installed(false))

      result = run_checks()

      assert result.assigns == %{}
      assert result.diagnostics.snippets_found_in_head == 0
      assert result.diagnostics.snippets_found_in_body == 0
      assert result.diagnostics.plausible_installed? == false
      assert result.diagnostics.snippet_found_after_busting_cache? == false
      assert result.diagnostics.disallowed_via_csp? == false
      assert result.diagnostics.service_error == nil
      assert result.diagnostics.body_fetched? == false
      assert result.diagnostics.scan_findings == []

      rating = State.interpret_diagnostics(result)
      refute rating.ok?
      assert rating.errors == ["We could not reach your website. Is it up?"]

      assert rating.recommendations == [
               "Make sure the website is up and running at https://example.com",
               {"Note: if you host elsewhere, we can't verify it",
                "https://plausible.io/docs/subdomain-hostname-filter"}
             ]
    end

    @proxied_script_body """
    <html>
    <head>
    <script defer data-domain=\"example.com\" src=\"https://proxy.example.com/js/script.js\"></script>
    </head>
    <body>Hello</body>
    </html>
    """

    test "proxied setup working OK" do
      stub_fetch_body(200, @proxied_script_body)
      stub_installation()

      result = run_checks()

      assert result.diagnostics.callback_status == 202
      assert result.diagnostics.proxy_likely? == true

      rating = State.interpret_diagnostics(result)
      assert rating.ok?
      assert rating.errors == []

      assert rating.recommendations == [
               {"Using a proxy? Read our guide", "https://plausible.io/docs/proxy/introduction"}
             ]
    end

    test "proxied setup, function defined but callback won't fire" do
      stub_fetch_body(200, @proxied_script_body)
      stub_installation(200, plausible_installed(true, 0))

      result = run_checks()

      assert result.diagnostics.callback_status == 0
      assert result.diagnostics.proxy_likely? == true

      rating = State.interpret_diagnostics(result)
      refute rating.ok?
      assert rating.errors == ["Installation incomplete"]

      assert rating.recommendations ==
               [
                 "In case of proxies, don't forget to setup the /event route",
                 {"Using a proxy? Read our guide", "https://plausible.io/docs/proxy/introduction"}
               ]
    end

    test "proxied setup, function undefined, callback won't fire" do
      stub_fetch_body(200, @proxied_script_body)
      stub_installation(200, plausible_installed(false, 0))

      result = run_checks()

      assert result.diagnostics.callback_status == 0
      assert result.diagnostics.proxy_likely? == true

      rating = State.interpret_diagnostics(result)
      refute rating.ok?
      assert rating.errors == ["We could not verify your installation"]

      assert rating.recommendations ==
               [
                 {"Have you seen our troubleshooting guide?",
                  "https://plausible.io/docs/troubleshoot-integration"},
                 {"Using a proxy? Read our guide", "https://plausible.io/docs/proxy/introduction"}
               ]
    end

    test "callback fails to fire" do
      stub_fetch_body(200, @normal_body)
      stub_installation(200, plausible_installed(true, 0))

      result = run_checks()

      assert result.diagnostics.callback_status == 0

      rating = State.interpret_diagnostics(result)
      refute rating.ok?
      assert rating.errors == ["You're almost there"]
      assert rating.recommendations == [""]
    end
  end

  defp run_checks(extra_opts \\ []) do
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

  defp stub_installation(status \\ 200, json \\ plausible_installed()) do
    Req.Test.stub(Plausible.Verification.Checks.Installation, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(json))
    end)
  end

  defp plausible_installed(bool \\ true, callback_status \\ 202) do
    %{"data" => %{"plausibleInstalled" => bool, "callbackStatus" => callback_status}}
  end
end
