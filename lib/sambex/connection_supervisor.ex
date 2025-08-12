defmodule Sambex.ConnectionSupervisor do
  @moduledoc """
  Supervisor for managing SMB connections.

  This supervisor manages connection processes and the registry
  for named connections. It ensures connections are properly
  supervised and can be restarted if they crash.

  ## Examples

      # Start the supervisor (usually done in application.ex)
      {:ok, _pid} = Sambex.ConnectionSupervisor.start_link()

      # Start a supervised connection
      {:ok, conn} = Sambex.ConnectionSupervisor.start_connection(
        url: "smb://server/share",
        username: "user", 
        password: "pass",
        name: :my_share
      )
  """

  use Supervisor

  @doc """
  Start the connection supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @doc """
  Start a new supervised connection.

  ## Options
    - `:url` - SMB URL (required)
    - `:username` - Username for authentication (required)
    - `:password` - Password for authentication (required) 
    - `:name` - Optional name for the connection

  ## Examples
      {:ok, conn} = Sambex.ConnectionSupervisor.start_connection(
        url: "smb://server/share",
        username: "user",
        password: "pass"
      )

      {:ok, _pid} = Sambex.ConnectionSupervisor.start_connection(
        url: "smb://server/docs", 
        username: "user",
        password: "pass",
        name: :docs
      )
  """
  def start_connection(opts) do
    DynamicSupervisor.start_child(
      Sambex.DynamicConnectionSupervisor,
      {Sambex.Connection, opts}
    )
  end

  @doc """
  Stop a supervised connection.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name

  ## Examples
      :ok = Sambex.ConnectionSupervisor.stop_connection(conn)
      :ok = Sambex.ConnectionSupervisor.stop_connection(:my_share)
  """
  def stop_connection(conn_or_name) do
    pid = case conn_or_name do
      pid when is_pid(pid) -> pid
      name when is_atom(name) ->
        case Registry.lookup(Sambex.Registry, name) do
          [{pid, _}] -> pid
          [] -> raise ArgumentError, "No connection found with name #{inspect(name)}"
        end
    end

    DynamicSupervisor.terminate_child(Sambex.DynamicConnectionSupervisor, pid)
  end

  @doc """
  List all active connections.

  Returns a list of `{name_or_pid, pid}` tuples for all active connections.

  ## Examples
      connections = Sambex.ConnectionSupervisor.list_connections()
      # => [{:my_share, #PID<0.123.0>}, {#PID<0.124.0>, #PID<0.124.0>}]
  """
  def list_connections do
    # Get all children from the dynamic supervisor
    children = DynamicSupervisor.which_children(Sambex.DynamicConnectionSupervisor)
    
    # Get all named connections from registry
    named_connections = Registry.select(Sambex.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    named_map = Map.new(named_connections, fn {name, pid} -> {pid, name} end)

    # Build result list
    for {_, pid, _, _} <- children, is_pid(pid) do
      case Map.get(named_map, pid) do
        nil -> {pid, pid}  # Unnamed connection
        name -> {name, pid}  # Named connection
      end
    end
  end

  @impl true
  def init(:ok) do
    children = [
      # Registry for named connections
      {Registry, keys: :unique, name: Sambex.Registry},
      # Dynamic supervisor for connection processes
      {DynamicSupervisor, name: Sambex.DynamicConnectionSupervisor, strategy: :one_for_one}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end