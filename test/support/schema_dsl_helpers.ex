defmodule Hermes.Test.SchemaDSLHelpers do
  @moduledoc false

  def build_tool(schema_ast) do
    module_name =
      Module.concat(__MODULE__, "Generated#{System.unique_integer([:positive])}")

    quoted =
      quote do
        use Hermes.Server.Component, type: :tool

        alias Hermes.Server.Response

        schema do
          unquote(schema_ast)
        end

        @impl true
        def execute(params, frame), do: {:reply, Response.text(Response.tool(), "ok"), frame}
      end

    {:module, module, _binary, _warnings} =
      Module.create(module_name, quoted, Macro.Env.location(__ENV__))

    module
  end
end
