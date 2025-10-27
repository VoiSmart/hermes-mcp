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

  describe "Component.input_schema/0 with DSL macros generates correct JSON Schema" do
    test "complex schema with various fields and constraints" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :username, :string, required: true, description: "User's login name", min_length: 3, max_length: 12
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
            "description" => "User's login name",
            "minLength" => 3,
            "maxLength" => 12
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
        "required" => ["username", "email"]
      }

      input_schema = tool_module.input_schema()

      assert input_schema["type"] == expected_json_schema["type"]
      assert input_schema["properties"] == expected_json_schema["properties"]

      assert MapSet.new(input_schema["required"]) ==
               MapSet.new(expected_json_schema["required"])
    end

    test "nested objects with required and default fields" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :profile, required: true do
              field :first_name, :string, required: true
              field :last_name, :string

              field :settings do
                field :theme, :string, default: "light"
                field :language, :string, required: true
              end
            end
          end
        )

      expected_json_schema = %{
        "type" => "object",
        "properties" => %{
          "profile" => %{
            "type" => "object",
            "properties" => %{
              "first_name" => %{
                "type" => "string"
              },
              "last_name" => %{
                "type" => "string"
              },
              "settings" => %{
                "type" => "object",
                "properties" => %{
                  "theme" => %{
                    "type" => "string",
                    "default" => "light"
                  },
                  "language" => %{
                    "type" => "string"
                  }
                },
                "required" => ["language"]
              }
            },
            "required" => ["first_name"]
          }
        },
        "required" => ["profile"]
      }

      assert tool_module.input_schema() == expected_json_schema
    end

    test "string base and nested fields with length constraints" do
      tool_module =
        SchemaDSLHelpers.build_tool(
          quote do
            field :title, :string, min_length: 5, max_length: 100
            field :script, :string, max_length: 500

            field :summary do
              field :notes, :string
              field :comments, :string, min_length: 3
            end
          end
        )

      expected_json_schema = %{
        "type" => "object",
        "properties" => %{
          "title" => %{
            "type" => "string",
            "minLength" => 5,
            "maxLength" => 100
          },
          "script" => %{
            "type" => "string",
            "maxLength" => 500
          },
          "summary" => %{
            "type" => "object",
            "properties" => %{
              "notes" => %{
                "type" => "string"
              },
              "comments" => %{
                "type" => "string",
                "minLength" => 3
              }
            }
          }
        }
      }

      assert tool_module.input_schema() == expected_json_schema
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

      expected_json_schema = %{
        "type" => "object",
        "properties" => %{
          "user" => %{
            "type" => "object",
            "description" => "User information",
            "properties" => %{
              "id" => %{
                "type" => "string",
                "format" => "uuid"
              },
              "profile" => %{
                "type" => "object",
                "properties" => %{
                  "age" => %{
                    "type" => "integer",
                    "minimum" => 0
                  },
                  "bio" => %{
                    "type" => "string",
                    "maxLength" => 160
                  }
                }
              }
            },
            "required" => ["id"]
          }
        },
        "required" => ["user"]
      }

      assert tool_module.input_schema() == expected_json_schema
    end
  end

  describe "runtime validation via mcp_schema/1" do
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
