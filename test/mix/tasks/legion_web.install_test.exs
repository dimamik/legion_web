defmodule Mix.Tasks.LegionWeb.InstallTest do
  use ExUnit.Case, async: true

  import Igniter.Test

  @router """
  defmodule TestWeb.Router do
    use TestWeb, :router
  end
  """

  @web_module """
  defmodule TestWeb do
    defmacro __using__(:router) do
      quote do
        use Phoenix.Router
      end
    end
  end
  """

  defp project_with_router do
    test_project(
      files: %{
        "lib/test_web.ex" => @web_module,
        "lib/test_web/router.ex" => @router
      }
    )
  end

  describe "igniter/1 against a Phoenix-style project" do
    test "imports LegionWeb.Router into the router module" do
      project_with_router()
      |> Igniter.compose_task("legion_web.install", [])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |  import LegionWeb.Router
      """)
    end

    test "adds a scope mounting legion_dashboard at /legion" do
      project_with_router()
      |> Igniter.compose_task("legion_web.install", [])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |    legion_dashboard("/legion")
      """)
    end

    test "adds a browser-piped scope around the dashboard route" do
      project_with_router()
      |> Igniter.compose_task("legion_web.install", [])
      |> assert_has_patch("lib/test_web/router.ex", """
      + |  scope "/" do
      + |    pipe_through(:browser)
      """)
    end

    test "emits no router-related warnings" do
      igniter =
        project_with_router()
        |> Igniter.compose_task("legion_web.install", [])

      refute Enum.any?(igniter.warnings, &String.contains?(&1, "No Phoenix router"))
      refute Enum.any?(igniter.warnings, &String.contains?(&1, "Could not automatically update"))
    end
  end

  describe "igniter/1 without a Phoenix router" do
    test "emits a warning explaining the requirement" do
      test_project()
      |> Igniter.compose_task("legion_web.install", [])
      |> assert_has_warning(&String.contains?(&1, "No Phoenix router found"))
    end

    test "does not patch any files" do
      test_project()
      |> Igniter.compose_task("legion_web.install", [])
      |> assert_unchanged()
    end
  end
end
