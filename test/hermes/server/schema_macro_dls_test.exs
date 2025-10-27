defmodule Hermes.Server.SchemaMacroDSLTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Component.Schema
  alias Hermes.Test.SchemaDSLHelpers

  describe "Schema.normalize/1 parse the schema DSL correctly" do
    test "empty schema" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{}
    end

    test "field macro with no constraints or metadata" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :name, :string
            field :age, :integer
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               name: {:mcp_field, :string, []},
               age: {:mcp_field, :integer, []}
             }
    end

    test "field macro with metadata" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :language, :string, description: "Programming language", default: "elixir"
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               language: {:mcp_field, :string, [description: "Programming language", default: "elixir"]}
             }
    end

    test "field macro with min_length constraint" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :username, :string, min_length: 3
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               username: {:mcp_field, {:string, {:min, 3}}, []}
             }
    end

    test "field macro with max_length constraint" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :username, :string, max_length: 12
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               username: {:mcp_field, {:string, {:max, 12}}, []}
             }
    end

    test "field macro with range via min_length and max_length" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :username, :string, min_length: 3, max_length: 12
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               username: {:mcp_field, {:string, [min: 3, max: 12]}, []}
             }
    end

    test "field macro with min constraint only" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :threshold, :integer, min: 5
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               threshold: {:mcp_field, {:integer, {:gte, 5}}, []}
             }
    end

    test "field macro with max constraint only" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :ceiling, :integer, max: 10
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               ceiling: {:mcp_field, {:integer, {:lte, 10}}, []}
             }
    end

    test "field macro converts min and max into range constraint" do
      tool_module_int =
        SchemaDSLHelpers.build_tool(
          quote do
            field :limit, :integer, min: 1, max: 10
          end
        )

      schema_int = tool_module_int.__mcp_raw_schema__()
      normalized = Schema.normalize(schema_int)

      assert normalized == %{
               limit: {:mcp_field, {:integer, {:range, {1, 10}}}, []}
             }

      tool_module_float =
        SchemaDSLHelpers.build_tool(
          quote do
            field :ratio, :float, min: 0.0, max: 1.0
          end
        )

      schema_float = tool_module_float.__mcp_raw_schema__()
      normalized_float = Schema.normalize(schema_float)

      assert normalized_float == %{
               ratio: {:mcp_field, {:float, {:range, {0.0, 1.0}}}, []}
             }
    end

    test "field macro with required constraint only" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field(:email, :string, description: "User email", required: true)
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               email: {:mcp_field, {:required, :string}, [description: "User email"]}
             }

      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field(:email, :string, required: true, description: "User email")
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               email: {:mcp_field, {:required, :string}, [description: "User email"]}
             }
    end

    test "field macro required with other constraints and metadata" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field(:some_int, :integer, min: 5, required: true, description: "Some integer")
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               some_int: {:mcp_field, {:required, {:integer, {:gte, 5}}}, [description: "Some integer"]}
             }

      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field(:some_float, :float, required: true, max: 30, description: "Some float")
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               some_float: {:mcp_field, {:required, {:float, {:lte, 30}}}, [description: "Some float"]}
             }
    end

    test "field macro handles required option on nested object" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :event, required: true do
              field :name, :string, required: true
              field :count, :integer
            end
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               event:
                 {:mcp_field,
                  {:required,
                   %{
                     name: {:mcp_field, {:required, :string}, []},
                     count: {:mcp_field, :integer, []}
                   }}, []}
             }
    end

    test "field macro with nonexisting constraints/metadata are ignored" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field(:unknown, :string, foo: 123, bar: "test", required: true, description: "Unknown fields")
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               unknown: {:mcp_field, {:required, :string}, [description: "Unknown fields"]}
             }

      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field(:another_unknown, :integer, baz: 3.14, qux: false)
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               another_unknown: {:mcp_field, :integer, []}
             }
    end

    test "field macro values is correctly parsed as enum" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :status, :string, values: ["active", "inactive", "pending"]
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               status: {:mcp_field, {:enum, ["active", "inactive", "pending"]}, [type: :string]}
             }
    end

    test "field macro enum is still correctly parsed as enum after values introduction" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :status, {:enum, ["active", "inactive", "pending"]}, type: :string
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               status: {:mcp_field, {:enum, ["active", "inactive", "pending"]}, [type: :string]}
             }
    end

    test "nested field macro values is correctly parsed as enum" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :config do
              field :mode, :string, required: true, values: ["auto", "manual"]
            end
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               config:
                 {:mcp_field,
                  %{
                    mode: {:mcp_field, {:required, {:enum, ["auto", "manual"]}}, [type: :string]}
                  }, []}
             }
    end

    test "nested field macro with notexisting constraints/metadata are ignored" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :config, required: true, description: "config" do
              field :settings, description: "settings" do
                field :option, :string, foo: "bar", required: true
              end

              field :level, :integer, baz: 42
            end
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               config:
                 {:mcp_field,
                  {:required,
                   %{
                     settings:
                       {:mcp_field,
                        %{
                          option: {:mcp_field, {:required, :string}, []}
                        }, [description: "settings"]},
                     level: {:mcp_field, :integer, []}
                   }}, [description: "config"]}
             }
    end

    test "complex nested schema with various constraints and metadata" do
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

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{
               user:
                 {:mcp_field,
                  {:required,
                   %{
                     id: {:mcp_field, {:required, :string}, [format: "uuid"]},
                     profile:
                       {:mcp_field,
                        %{
                          age: {:mcp_field, {:integer, {:gte, 0}}, []},
                          bio: {:mcp_field, {:string, {:max, 160}}, []}
                        }, []}
                   }}, [description: "User information"]}
             }
    end
  end
end
