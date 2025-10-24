defmodule Hermes.Server.SchemaMacroDSLTest do
  use ExUnit.Case, async: true

  alias Hermes.Server.Component.Schema

  describe "Schema.normalize/1 parse the schema DSL correctly" do
    test "empty schema" do
      tool_module =
        build_tool(
          quote do
          end
        )

      schema = tool_module.__mcp_raw_schema__()
      normalized = Schema.normalize(schema)

      assert normalized == %{}
    end

    test "field macro with no constraints or metadata" do
      tool_module =
        build_tool(
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
        build_tool(
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

    test "field macro with min constraint only" do
      tool_module =
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
        build_tool(
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
  end

  defp build_tool(schema_ast) do
    module_name = Module.concat(__MODULE__, "Generated#{System.unique_integer([:positive])}")

    quoted =
      quote do
        use Hermes.Server.Component, type: :tool

        schema do
          unquote(schema_ast)
        end

        @impl true
        def execute(params, _ctx), do: {:ok, params}
      end

    {:module, module, _binary, _warnings} =
      Module.create(module_name, quoted, Macro.Env.location(__ENV__))

    module
  end

  describe "Component.input_schema/0 with DSL macros generates correct JSON Schema" do
    test "complex schema with various fields and constraints" do
      tool_module =
        build_tool(
          quote do
            field :username, :string, required: true, description: "User's login name"
            field :age, :integer, min: 0, description: "User's age"
            field :email, :string, format: "email", required: true

            field :preferences do
              field :newsletter, :boolean
              field :notifications, :string
            end
          end
        )

      expected_json_schema = %{
        "type" => "object",
        "properties" => %{
          "username" => %{
            "type" => "string",
            "description" => "User's login name"
          },
          "age" => %{
            "type" => "integer",
            "minimum" => 0,
            "description" => "User's age"
          },
          "email" => %{
            "type" => "string",
            "format" => "email"
          },
          "preferences" => %{
            "type" => "object",
            "properties" => %{
              "newsletter" => %{
                "type" => "boolean"
              },
              "notifications" => %{
                "type" => "string"
              }
            }
          }
        },
        "required" => ["email", "username"]
      }

      assert tool_module.input_schema() == expected_json_schema
    end
  end
end
