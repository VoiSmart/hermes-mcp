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

    test "validate values dsl (enum) field as enum" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :status, :string, values: ["active", "inactive", "pending"], required: true
          end
        )

      assert {:ok, _} = tool_module.mcp_schema(%{status: "active"})
      assert {:ok, _} = tool_module.mcp_schema(%{status: "inactive"})

      assert {:error, errors} = tool_module.mcp_schema(%{status: "unknown"})
      assert [:status] in error_paths(errors)

      assert {:error, errors} = tool_module.mcp_schema(%{})
      assert [:status] in error_paths(errors)
    end

    test "still validates enum fields after values intro in dsl" do
      require Logger

      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :status, {:enum, ["active", "inactive", "pending"]}, type: :string, required: true

            field :nested_enum do
              field :level, {:enum, ["low", "medium", "high"]}, type: :string, required: true
            end
          end
        )

      assert {:ok, _} = tool_module.mcp_schema(%{status: "active"})
      assert {:ok, _} = tool_module.mcp_schema(%{status: "inactive"})

      assert {:error, errors} = tool_module.mcp_schema(%{status: "unknown"})
      assert [:status] in error_paths(errors)

      assert {:error, errors} = tool_module.mcp_schema(%{})
      assert [:status] in error_paths(errors)

      assert {:ok, _} = tool_module.mcp_schema(%{status: "active", nested_enum: %{level: "medium"}})
      assert {:error, errors} = tool_module.mcp_schema(%{status: "active", nested_enum: %{level: "extreme"}})
      assert [:nested_enum, :level] in error_paths(errors)
    end

    test "enforces type constraints and required fields" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :username, :string, required: true
            field :age, :integer, min: 0, max: 120
            field :email, :string, required: true
          end
        )

      assert {:ok, _} = tool_module.mcp_schema(%{username: "user-1", email: "user@example.com", age: 25})

      assert {:error, errors} = tool_module.mcp_schema(%{username: "user-1", age: -5})

      assert Enum.any?(errors, &match?(%{path: [:age]}, &1))
      assert Enum.any?(errors, &match?(%{path: [:email]}, &1))
    end

    test "enforces float range constraints" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :ratio, :float, min: 0.1, max: 0.9
          end
        )

      assert {:ok, _} = tool_module.mcp_schema(%{ratio: 0.5})

      assert {:error, errors} = tool_module.mcp_schema(%{ratio: 1.5})
      assert Enum.any?(errors, &match?(%{path: [:ratio]}, &1))

      assert {:error, errors} = tool_module.mcp_schema(%{ratio: 0.0})
      assert Enum.any?(errors, &match?(%{path: [:ratio]}, &1))
    end

    test "validates nested objects constrained plus required fields" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :profile, required: true do
              field :first_name, :string, required: true
              field :last_name, :string, max_length: 5
              field :age, :integer, min: 0
            end
          end
        )

      assert {:ok, _} = tool_module.mcp_schema(%{profile: %{first_name: "John"}})

      assert {:error, errors} = tool_module.mcp_schema(%{})
      paths = error_paths(errors)
      assert [:profile] in paths

      assert {:error, errors} = tool_module.mcp_schema(%{profile: %{}})
      paths = error_paths(errors)
      assert [:profile, :first_name] in paths

      assert {:error, errors} = tool_module.mcp_schema(%{profile: %{first_name: "Alice", age: -10}})
      assert [:profile, :age] in error_paths(errors)

      assert {:error, errors} = tool_module.mcp_schema(%{profile: %{first_name: "magnum", last_name: "magnums"}})
      paths = error_paths(errors)
      assert [:profile, :last_name] in paths
    end

    test "validates string length constraints" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :title, :string, min_length: 5, max_length: 20
            field :description, :string, max_length: 100

            field :nestings do
              field :tags, :string

              field :notes do
                field :comments, :string, min_length: 10
              end
            end
          end
        )

      assert {:ok, _} =
               tool_module.mcp_schema(%{
                 title: "A valid title",
                 description: "Some description",
                 nesting: %{notes: %{comment: "This is a valid comment"}}
               })

      assert {:error, errors} = tool_module.mcp_schema(%{title: "Shrt"})
      assert [:title] in error_paths(errors)

      assert {:error, errors} = tool_module.mcp_schema(%{title: "This title is way too long to be valid"})
      assert [:title] in error_paths(errors)

      assert {:error, errors} = tool_module.mcp_schema(%{nestings: %{notes: %{comments: "Too short"}}})
      assert [:nestings, :notes, :comments] in error_paths(errors)
    end

    test "ignores unknown fields in input data" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :user, required: true, description: "User information" do
              field :id, :string, format: "uuid", required: true

              field :profile do
                field :age, :integer, min: 0
                field :bio, :string, max_length: 160
              end
            end
          end
        )

      assert {:ok, _} =
               tool_module.mcp_schema(%{
                 user: %{
                   id: "550e8400-e29b-41d4-a716-446655440000",
                   profile: %{
                     age: 30,
                     bio: "Hello world!"
                   },
                   extra_field: "should be ignored"
                 },
                 another_extra: 123
               })

      assert {:error, errors} = tool_module.mcp_schema(%{user: %{profile: %{age: -5}}})
      paths = error_paths(errors)
      assert [:user, :id] in paths
      assert [:user, :profile, :age] in paths
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
