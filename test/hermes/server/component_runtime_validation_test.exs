defmodule Hermes.Server.ComponentRuntimeValidationTest do
  use ExUnit.Case, async: true

  alias Hermes.Test.SchemaDSLHelpers

  describe "validate_input/1 using schema DSL" do
    test "accepts params within constraints" do
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

    test "rejects params outside constraints" do
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

    test "correctly handle nested required fields" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :user, required: true do
              field :profile, required: true do
                field :email, :string, format: :email, required: true
                field :age, :integer, min: 0
              end

              field :settings do
                field :notifications, :boolean, required: true
              end
            end
          end
        )

      [tool] = Hermes.Server.parse_components({:tool, "nested_tool", tool_module})

      assert {:ok, _} =
               tool.validate_input.(%{
                 "user" => %{
                   "profile" => %{
                     "email" => "mail"
                   },
                   "settings" => %{
                     "notifications" => true
                   }
                 }
               })

      assert {:error, errors} =
               tool.validate_input.(%{
                 "user" => %{
                   "profile" => %{
                     "age" => -5
                   },
                   "settings" => %{}
                 }
               })

      error_paths = error_paths(errors)
      assert Enum.member?(error_paths, [:user, :profile, :email])

      assert {:ok, _} =
               tool.validate_input.(%{
                 "user" => %{
                   "profile" => %{
                     "email" => "magnum"
                   }
                 }
               })
    end
  end

  describe "mcp_schema/1 using schema DSL" do
    test "validates output against schema" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :result, :integer
          end
        )

      assert {:ok, _} =
               tool_module.mcp_schema(%{
                 "result" => 42
               })

      assert {:error, errors} =
               tool_module.mcp_schema(%{
                 "result" => "not an integer"
               })

      error_paths = error_paths(errors)
      assert Enum.member?(error_paths, [:result])
    end

    test "correctly handle nested required fields" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :user, required: true do
              field :profile, required: true do
                field :email, :string, format: :email, required: true
                field :age, :integer, min: 0
              end

              field :settings do
                field :notifications, :boolean, required: true
              end
            end
          end
        )

      assert {:ok, _} =
               tool_module.mcp_schema(%{
                 "user" => %{
                   "profile" => %{
                     "email" => "mail"
                   },
                   "settings" => %{
                     "notifications" => true
                   }
                 }
               })

      assert {:error, errors} =
               tool_module.mcp_schema(%{
                 "user" => %{
                   "profile" => %{
                     "age" => -5
                   },
                   "settings" => %{}
                 }
               })

      error_paths = error_paths(errors)
      assert Enum.member?(error_paths, [:user, :profile, :email])
    end
  end

  defp error_paths(errors) do
    Enum.flat_map(errors, fn
      %Peri.Error{path: path, errors: nil} ->
        [List.wrap(path)]

      %Peri.Error{path: path, errors: nested} when is_list(nested) ->
        [List.wrap(path)] ++ error_paths(nested)
    end)
  end
end
