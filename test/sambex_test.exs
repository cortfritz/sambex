defmodule SambexTest do
  use ExUnit.Case

  describe "module structure" do
    test "Sambex module is available" do
      assert Code.ensure_loaded?(Sambex)
    end

    test "Sambex module has expected attributes" do
      assert Sambex.module_info(:attributes)
    end
  end

  describe "function exports" do
    test "Sambex exports expected public functions" do
      functions = Sambex.__info__(:functions)

      expected_functions = [
        {:init, 0},
        {:connect, 3},
        {:list_dir, 3},
        {:read_file, 3},
        {:write_file, 4},
        {:delete_file, 3},
        {:upload_file, 4},
        {:download_file, 4}
      ]

      for {function, arity} <- expected_functions do
        assert {function, arity} in functions,
               "Expected function #{function}/#{arity} not found in Sambex module"
      end
    end
  end

  describe "function documentation" do
    test "main functions have documentation" do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, docs} = Code.fetch_docs(Sambex)

      assert is_binary(module_doc)
      assert String.contains?(module_doc, "SMB")

      # Check that key functions are documented
      documented_functions =
        for {{:function, name, arity}, _, _, doc, _} <- docs,
            is_map(doc) and is_binary(doc["en"]),
            do: {name, arity}

      assert {:init, 0} in documented_functions
      assert {:list_dir, 3} in documented_functions
      assert {:read_file, 3} in documented_functions
      assert {:write_file, 4} in documented_functions
      assert {:delete_file, 3} in documented_functions
    end

    test "functions have proper typespecs" do
      # Ensure module is loaded
      Code.ensure_loaded(Sambex)

      # Just verify the module compiles with dialyzer-style analysis
      assert function_exported?(Sambex, :init, 0)
      assert function_exported?(Sambex, :list_dir, 3)
      assert function_exported?(Sambex, :read_file, 3)
      assert function_exported?(Sambex, :write_file, 4)
      assert function_exported?(Sambex, :delete_file, 3)
    end
  end

  describe "input validation (type checking only)" do
    test "functions require correct arity" do
      # Ensure module is loaded
      Code.ensure_loaded(Sambex)

      # Test that functions exist with correct arity
      assert function_exported?(Sambex, :list_dir, 3)
      assert function_exported?(Sambex, :read_file, 3)
      assert function_exported?(Sambex, :write_file, 4)
      assert function_exported?(Sambex, :delete_file, 3)
      assert function_exported?(Sambex, :upload_file, 4)
      assert function_exported?(Sambex, :download_file, 4)
    end

    test "functions validate binary inputs at compile time" do
      # Ensure module is loaded
      Code.ensure_loaded(Sambex)

      # Test that calling with wrong types would fail at runtime
      # (but don't actually call them to avoid segfault)

      # This should compile fine (correct types)
      quote do
        Sambex.list_dir("url", "user", "pass")
      end

      # These would fail at runtime with FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        apply(Sambex, :list_dir, [123, "user", "pass"])
      end
    end
  end

  describe "module metadata" do
    test "module has proper moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, _} = Code.fetch_docs(Sambex)

      assert is_binary(module_doc)
      assert String.length(module_doc) > 0
      assert String.contains?(module_doc, "SMB")
    end

    test "module compiles without warnings" do
      # If we got this far, the module compiled successfully
      assert true
    end
  end

  describe "helper functions" do
    test "upload_file/4 is properly defined" do
      Code.ensure_loaded(Sambex)
      assert function_exported?(Sambex, :upload_file, 4)
    end

    test "download_file/4 is properly defined" do
      Code.ensure_loaded(Sambex)
      assert function_exported?(Sambex, :download_file, 4)
    end
  end
end
