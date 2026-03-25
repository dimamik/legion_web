defmodule Mix.Tasks.LegionWeb.Install.Docs do
  @moduledoc false

  def short_doc do
    "Installs Legion Web dashboard into your Phoenix application"
  end

  def example do
    "mix legion_web.install"
  end

  def long_doc do
    """
    #{short_doc()}

    This task configures your Phoenix application to use the Legion Web dashboard:

    * Adds the required `LegionWeb.Router` import to your router
    * Sets up the dashboard route at "/legion"

    ## Example

    ```bash
    #{example()}
    ```
    """
  end
end

if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.LegionWeb.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()}"

    @moduledoc __MODULE__.Docs.long_doc()
    use Igniter.Mix.Task

    alias Igniter.Code.Common
    alias Igniter.Code.Module, as: CodeModule
    alias Igniter.Libs.Phoenix, as: PhoenixLib
    alias Igniter.Project.Module, as: ProjectModule

    @impl Igniter.Mix.Task
    def info(_argv, _composing_task) do
      %Igniter.Mix.Task.Info{
        group: :legion,
        example: __MODULE__.Docs.example()
      }
    end

    @impl Igniter.Mix.Task
    def igniter(igniter) do
      case PhoenixLib.select_router(igniter) do
        {igniter, nil} ->
          Igniter.add_warning(igniter, """
          No Phoenix router found. Phoenix LiveView is required for Legion Web.
          """)

        {igniter, router} ->
          update_router(igniter, router)
      end
    end

    defp update_router(igniter, router) do
      case ProjectModule.find_and_update_module(
             igniter,
             router,
             &do_update_router(igniter, &1)
           ) do
        {:ok, igniter} ->
          igniter

        {:error, igniter} ->
          Igniter.add_warning(igniter, """
          Could not automatically update the router. Please add manually:

              import LegionWeb.Router

              scope "/" do
                pipe_through :browser
                legion_dashboard "/legion"
              end
          """)
      end
    end

    defp do_update_router(igniter, zipper) do
      web_module = PhoenixLib.web_module(igniter)

      with {:ok, zipper} <- CodeModule.move_to_use(zipper, web_module),
           {:ok, zipper} <-
             {:ok, Common.add_code(zipper, "\nimport LegionWeb.Router")} do
        add_route(zipper)
      end
    end

    defp add_route(zipper) do
      {:ok,
       Common.add_code(zipper, """
       scope "/" do
         pipe_through :browser

         legion_dashboard "/legion"
       end
       """)}
    end
  end
else
  defmodule Mix.Tasks.LegionWeb.Install do
    @shortdoc "#{__MODULE__.Docs.short_doc()} | Install `igniter` to use"

    @moduledoc __MODULE__.Docs.long_doc()

    use Mix.Task

    def run(_argv) do
      Mix.shell().error("""
      The task 'legion_web.install' requires igniter. Please install igniter and try again.

      For more information, see: https://hexdocs.pm/igniter/readme.html#installation
      """)

      exit({:shutdown, 1})
    end
  end
end
