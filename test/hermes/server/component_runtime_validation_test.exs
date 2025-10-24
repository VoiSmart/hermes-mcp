defmodule Hermes.Server.ComponentRuntimeValidationTest do
  use ExUnit.Case, async: true

  alias Hermes.Test.SchemaDSLHelpers

  test "tool validator accepts params within constraints" do
    tool_module =
      SchemaDSLHelpers.build_tool(
        quote do
          field :count, :integer, min: 10, max: 100
        end
      )

    [tool] = Hermes.Server.parse_components({:tool, "count_tool", tool_module})

    assert {:ok, validated} =
             tool.validate_input.(%{
               "count" => 50
             })

    assert validated[:count] == 50
  end

  test "tool validator rejects params outside constraints" do
    tool_module =
      SchemaDSLHelpers.build_tool(
        quote do
          field :limit, :integer, min: 1, max: 5
          field :ratio, :float, min: 0.1, max: 0.9
        end
      )

    [tool] = Hermes.Server.parse_components({:tool, "constrained", tool_module})

    assert {:ok, _} =
             tool.validate_input.(%{
               "limit" => 3,
               "ratio" => 0.5
             })

    assert {:error, errors} =
             tool.validate_input.(%{
               "limit" => 0,
               "ratio" => 1.1
             })

    assert Enum.any?(errors, fn
             %Peri.Error{path: [:limit]} -> true
             _ -> false
           end)

    assert Enum.any?(errors, fn
             %Peri.Error{path: [:ratio]} -> true
             _ -> false
           end)
  end
end
