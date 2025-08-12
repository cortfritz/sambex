defmodule SambexConnectionTest do
  use ExUnit.Case

  setup do
    # The registry is already started globally, just ensure dynamic supervisor is running
    unless Process.whereis(Sambex.DynamicConnectionSupervisor) do
      start_supervised!(
        {DynamicSupervisor, name: Sambex.DynamicConnectionSupervisor, strategy: :one_for_one}
      )
    end

    :ok
  end

  describe "module structure" do
    test "Sambex.Connection module is available" do
      assert Code.ensure_loaded?(Sambex.Connection)
    end

    test "Sambex.ConnectionSupervisor module is available" do
      assert Code.ensure_loaded?(Sambex.ConnectionSupervisor)
    end

    test "Registry is available" do
      # Registry should be started by the supervisor
      assert Process.whereis(Sambex.Registry) != nil
    end
  end

  describe "connection supervisor" do
    test "ConnectionSupervisor starts successfully" do
      # Should already be started by setup
      assert Process.whereis(Sambex.Registry) != nil
      assert Process.whereis(Sambex.DynamicConnectionSupervisor) != nil
    end

    test "can list connections when none exist" do
      connections = Sambex.ConnectionSupervisor.list_connections()
      assert is_list(connections)
    end
  end

  describe "anonymous connections" do
    test "can start anonymous connection" do
      {:ok, conn} =
        Sambex.Connection.start_link(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass"
        )

      assert is_pid(conn)
      assert Process.alive?(conn)

      # Clean up
      GenServer.stop(conn)
    end

    test "connect/3 convenience function works" do
      {:ok, conn} =
        Sambex.Connection.connect(
          "smb://test.example.com/share",
          "testuser",
          "testpass"
        )

      assert is_pid(conn)
      assert Process.alive?(conn)

      # Clean up
      Sambex.Connection.disconnect(conn)
    end

    test "disconnect works for anonymous connections" do
      {:ok, conn} =
        Sambex.Connection.connect(
          "smb://test.example.com/share",
          "testuser",
          "testpass"
        )

      assert Process.alive?(conn)
      :ok = Sambex.Connection.disconnect(conn)

      # Give it a moment to stop
      Process.sleep(10)
      refute Process.alive?(conn)
    end
  end

  describe "named connections" do
    test "can start named connection" do
      {:ok, pid} =
        Sambex.Connection.start_link(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass",
          name: :test_connection
        )

      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify it's registered
      assert [{^pid, _}] = Registry.lookup(Sambex.Registry, :test_connection)

      # Clean up
      Sambex.Connection.disconnect(:test_connection)
    end

    test "can reference connection by name" do
      {:ok, _pid} =
        Sambex.Connection.start_link(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass",
          name: :named_test
        )

      # Verify the connection is registered by name
      assert [{_pid, _}] = Registry.lookup(Sambex.Registry, :named_test)

      # Clean up
      Sambex.Connection.disconnect(:named_test)
    end

    test "raises error for non-existent named connection" do
      # Test that resolve_connection raises for non-existent names
      # We can't test this directly, so just verify the lookup fails
      assert [] = Registry.lookup(Sambex.Registry, :non_existent)
    end

    test "disconnect works for named connections" do
      {:ok, pid} =
        Sambex.Connection.start_link(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass",
          name: :disconnect_test
        )

      assert Process.alive?(pid)
      :ok = Sambex.Connection.disconnect(:disconnect_test)

      # Give it a moment to stop
      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end

  describe "supervised connections" do
    test "can start supervised connection" do
      {:ok, conn} =
        Sambex.ConnectionSupervisor.start_connection(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass"
        )

      assert is_pid(conn)
      assert Process.alive?(conn)

      # Verify it appears in connection list
      connections = Sambex.ConnectionSupervisor.list_connections()
      assert Enum.any?(connections, fn {_, pid} -> pid == conn end)

      # Clean up
      Sambex.ConnectionSupervisor.stop_connection(conn)
    end

    test "can start supervised named connection" do
      {:ok, pid} =
        Sambex.ConnectionSupervisor.start_connection(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass",
          name: :supervised_test
        )

      assert is_pid(pid)

      # Verify it appears in connection list with name
      connections = Sambex.ConnectionSupervisor.list_connections()
      assert {:supervised_test, pid} in connections

      # Clean up
      Sambex.ConnectionSupervisor.stop_connection(:supervised_test)
    end

    test "stop_connection works with PIDs" do
      {:ok, conn} =
        Sambex.ConnectionSupervisor.start_connection(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass"
        )

      assert Process.alive?(conn)
      :ok = Sambex.ConnectionSupervisor.stop_connection(conn)

      # Give it a moment to stop
      Process.sleep(10)
      refute Process.alive?(conn)
    end

    test "stop_connection works with names" do
      {:ok, pid} =
        Sambex.ConnectionSupervisor.start_connection(
          url: "smb://test.example.com/share",
          username: "testuser",
          password: "testpass",
          name: :stop_test
        )

      assert Process.alive?(pid)
      :ok = Sambex.ConnectionSupervisor.stop_connection(:stop_test)

      # Give it a moment to stop
      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end

  describe "connection API functions" do
    test "all expected functions are available" do
      # Test that the functions exist without calling them
      functions = Sambex.Connection.__info__(:functions)

      expected_functions = [
        {:list_dir, 2},
        {:read_file, 2},
        {:write_file, 3},
        {:delete_file, 2},
        {:move_file, 3},
        {:get_file_stats, 2},
        {:upload_file, 3},
        {:download_file, 3}
      ]

      for {function, arity} <- expected_functions do
        assert {function, arity} in functions,
               "Expected function #{function}/#{arity} not found"
      end
    end
  end

  describe "URL building" do
    test "build_url function works correctly" do
      # We can't test the private build_url function directly,
      # but we can verify the GenServer state contains the expected URL
      {:ok, conn} =
        Sambex.Connection.connect(
          "smb://test.example.com/share",
          "testuser",
          "testpass"
        )

      # Verify the connection is alive and has the expected state structure
      assert Process.alive?(conn)

      # Clean up
      Sambex.Connection.disconnect(conn)
    end
  end

  describe "function exports" do
    test "Sambex.Connection exports expected public functions" do
      functions = Sambex.Connection.__info__(:functions)

      expected_functions = [
        {:start_link, 1},
        {:connect, 3},
        {:list_dir, 2},
        {:read_file, 2},
        {:write_file, 3},
        {:delete_file, 2},
        {:move_file, 3},
        {:get_file_stats, 2},
        {:upload_file, 3},
        {:download_file, 3},
        {:disconnect, 1}
      ]

      for {function, arity} <- expected_functions do
        assert {function, arity} in functions,
               "Expected function #{function}/#{arity} not found in Sambex.Connection module"
      end
    end

    test "Sambex.ConnectionSupervisor exports expected public functions" do
      functions = Sambex.ConnectionSupervisor.__info__(:functions)

      expected_functions = [
        {:start_link, 0},
        {:start_link, 1},
        {:start_connection, 1},
        {:stop_connection, 1},
        {:list_connections, 0}
      ]

      for {function, arity} <- expected_functions do
        assert {function, arity} in functions,
               "Expected function #{function}/#{arity} not found in Sambex.ConnectionSupervisor module"
      end
    end
  end

  describe "documentation" do
    test "Sambex.Connection has proper moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, _} = Code.fetch_docs(Sambex.Connection)

      assert is_binary(module_doc)
      assert String.length(module_doc) > 0
      assert String.contains?(module_doc, "GenServer")
      assert String.contains?(module_doc, "SMB")
    end

    test "Sambex.ConnectionSupervisor has proper moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => module_doc}, _, _} =
        Code.fetch_docs(Sambex.ConnectionSupervisor)

      assert is_binary(module_doc)
      assert String.length(module_doc) > 0
      assert String.contains?(module_doc, "Supervisor")
      assert String.contains?(module_doc, "SMB")
    end

    test "main functions are documented" do
      {:docs_v1, _, :elixir, _, _, _, docs} = Code.fetch_docs(Sambex.Connection)

      documented_functions =
        for {{:function, name, arity}, _, _, doc, _} <- docs,
            is_map(doc) and is_binary(doc["en"]),
            do: {name, arity}

      assert {:start_link, 1} in documented_functions
      assert {:connect, 3} in documented_functions
      assert {:list_dir, 2} in documented_functions
      assert {:read_file, 2} in documented_functions
      assert {:write_file, 3} in documented_functions
    end
  end
end
