defmodule CallAssistant.CallE.CliTest do
  use ExUnit.Case, async: true

  alias CallAssistant.CallE.Cli

  describe "parse_cli_failure/2" do
    test "call_started: false means the call definitely never started" do
      output =
        Jason.encode!(%{
          "ok" => false,
          "stage" => "plan_call",
          "call_started" => false,
          "retry_safe" => true,
          "error" => %{"code" => "plan_call_error", "message" => "plan_call failed: fetch failed"}
        })

      assert Cli.parse_cli_failure(output, 1) ==
               {:call_failure,
                %{
                  message: "plan_call failed: fetch failed",
                  call_uncertain: false,
                  recovery_id: nil
                }}
    end

    test "call_started: \"unknown\" is treated as uncertain, and keeps the recovery_id" do
      output =
        Jason.encode!(%{
          "ok" => false,
          "stage" => "run_call",
          "call_started" => "unknown",
          "retry_safe" => false,
          "recovery_id" => "PKCarVFXk7xdUh3cbwU8qJRD",
          "error" => %{"code" => "run_call_error", "message" => "run_call failed: fetch failed"}
        })

      assert Cli.parse_cli_failure(output, 1) ==
               {:call_failure,
                %{
                  message: "run_call failed: fetch failed",
                  call_uncertain: true,
                  recovery_id: "PKCarVFXk7xdUh3cbwU8qJRD"
                }}
    end

    test "call_started: true is treated as uncertain" do
      output =
        Jason.encode!(%{
          "ok" => false,
          "stage" => "get_call_run",
          "call_started" => true,
          "retry_safe" => true,
          "error" => %{"code" => "get_call_run_timeout", "message" => "get_call_run timed out"}
        })

      assert {:call_failure, %{call_uncertain: true}} = Cli.parse_cli_failure(output, 1)
    end

    test "falls back to a plain :cli_exit when the output isn't the expected JSON shape" do
      assert Cli.parse_cli_failure("segfault, core dumped", 139) ==
               {:cli_exit, 139, "segfault, core dumped"}
    end

    test "falls back to :cli_exit for valid JSON that isn't an \"ok\": false failure body" do
      assert Cli.parse_cli_failure(Jason.encode!(%{"unexpected" => "shape"}), 1) ==
               {:cli_exit, 1, Jason.encode!(%{"unexpected" => "shape"})}
    end

    test "missing error.message falls back to a generic message" do
      output = Jason.encode!(%{"ok" => false, "call_started" => false})

      assert Cli.parse_cli_failure(output, 1) ==
               {:call_failure, %{message: "call failed", call_uncertain: false, recovery_id: nil}}
    end
  end
end
