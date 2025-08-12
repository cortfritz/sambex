defmodule Sambex.Connection do
  @moduledoc """
  GenServer for maintaining persistent SMB connections.

  Provides a connection-based API that avoids passing credentials
  on every operation. Connections can be started with or without names
  for easy reference.

  ## Examples

      # Start an anonymous connection
      {:ok, conn} = Sambex.Connection.start_link(
        url: "smb://192.168.1.100/share",
        username: "user",
        password: "pass"
      )

      # Start a named connection
      {:ok, _pid} = Sambex.Connection.start_link(
        url: "smb://192.168.1.100/docs",
        username: "user", 
        password: "pass",
        name: :docs_share
      )

      # Use the connections
      Sambex.Connection.list_dir(conn, "/")
      Sambex.Connection.list_dir(:docs_share, "/reports")

      # Convenience function
      {:ok, conn} = Sambex.Connection.connect("smb://server/share", "user", "pass")
  """

  use GenServer
  require Logger

  @doc """
  Start a connection GenServer.

  ## Options
    - `:url` - SMB URL (required)
    - `:username` - Username for authentication (required) 
    - `:password` - Password for authentication (required)
    - `:name` - Optional name for the connection process

  ## Examples
      # Anonymous connection
      {:ok, pid} = Sambex.Connection.start_link(
        url: "smb://server/share",
        username: "user",
        password: "pass"
      )

      # Named connection
      {:ok, pid} = Sambex.Connection.start_link(
        url: "smb://server/share", 
        username: "user",
        password: "pass",
        name: :my_share
      )
  """
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    
    case name do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Sambex.Registry, name}})
    end
  end

  @doc """
  Convenience function to start a connection and return the PID.

  ## Examples
      {:ok, conn} = Sambex.Connection.connect("smb://server/share", "user", "pass")
      Sambex.Connection.list_dir(conn, "/")
  """
  def connect(url, username, password) do
    start_link(url: url, username: username, password: password)
  end

  @doc """
  List files and directories in an SMB directory.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `path` - Path relative to the share root

  ## Examples
      Sambex.Connection.list_dir(conn, "/")
      Sambex.Connection.list_dir(:my_share, "/documents")
  """
  def list_dir(conn_or_name, path) do
    GenServer.call(resolve_connection(conn_or_name), {:list_dir, path})
  end

  @doc """
  Read a file from the SMB share.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `path` - Path to the file relative to share root

  ## Examples
      {:ok, content} = Sambex.Connection.read_file(conn, "/readme.txt")
  """
  def read_file(conn_or_name, path) do
    GenServer.call(resolve_connection(conn_or_name), {:read_file, path})
  end

  @doc """
  Write a file to the SMB share.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `path` - Path to the file relative to share root
    - `content` - Binary content to write

  ## Examples
      :ok = Sambex.Connection.write_file(conn, "/output.txt", "Hello World")
  """
  def write_file(conn_or_name, path, content) do
    GenServer.call(resolve_connection(conn_or_name), {:write_file, path, content})
  end

  @doc """
  Delete a file from the SMB share.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `path` - Path to the file relative to share root

  ## Examples
      :ok = Sambex.Connection.delete_file(conn, "/temp.txt")
  """
  def delete_file(conn_or_name, path) do
    GenServer.call(resolve_connection(conn_or_name), {:delete_file, path})
  end

  @doc """
  Move/rename a file on the SMB share.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `source_path` - Source path relative to share root
    - `dest_path` - Destination path relative to share root

  ## Examples
      :ok = Sambex.Connection.move_file(conn, "/old.txt", "/new.txt")
  """
  def move_file(conn_or_name, source_path, dest_path) do
    GenServer.call(resolve_connection(conn_or_name), {:move_file, source_path, dest_path})
  end

  @doc """
  Get file statistics/metadata from the SMB share.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `path` - Path to the file relative to share root

  ## Examples
      {:ok, stats} = Sambex.Connection.get_file_stats(conn, "/file.txt")
  """
  def get_file_stats(conn_or_name, path) do
    GenServer.call(resolve_connection(conn_or_name), {:get_file_stats, path})
  end

  @doc """
  Upload a local file to the SMB share.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `local_path` - Local file path
    - `remote_path` - Remote path relative to share root

  ## Examples
      :ok = Sambex.Connection.upload_file(conn, "/local/file.txt", "/remote/file.txt")
  """
  def upload_file(conn_or_name, local_path, remote_path) do
    GenServer.call(resolve_connection(conn_or_name), {:upload_file, local_path, remote_path})
  end

  @doc """
  Download a file from the SMB share to local filesystem.

  ## Parameters
    - `conn_or_name` - Connection PID or registered name
    - `remote_path` - Remote path relative to share root
    - `local_path` - Local file path

  ## Examples
      :ok = Sambex.Connection.download_file(conn, "/remote/file.txt", "/local/file.txt")
  """
  def download_file(conn_or_name, remote_path, local_path) do
    GenServer.call(resolve_connection(conn_or_name), {:download_file, remote_path, local_path})
  end

  @doc """
  Stop a connection.

  ## Examples
      :ok = Sambex.Connection.disconnect(conn)
      :ok = Sambex.Connection.disconnect(:my_share)
  """
  def disconnect(conn_or_name) do
    GenServer.stop(resolve_connection(conn_or_name))
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)

    state = %{
      url: url,
      username: username,
      password: password
    }

    Logger.debug("Started SMB connection to #{url}")
    {:ok, state}
  end

  @impl true
  def handle_call({:list_dir, path}, _from, state) do
    url = build_url(state.url, path)
    result = Sambex.list_dir(url, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:read_file, path}, _from, state) do
    url = build_url(state.url, path)
    result = Sambex.read_file(url, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:write_file, path, content}, _from, state) do
    url = build_url(state.url, path)
    result = Sambex.write_file(url, content, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:delete_file, path}, _from, state) do
    url = build_url(state.url, path)
    result = Sambex.delete_file(url, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:move_file, source_path, dest_path}, _from, state) do
    source_url = build_url(state.url, source_path)
    dest_url = build_url(state.url, dest_path)
    result = Sambex.move_file(source_url, dest_url, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:get_file_stats, path}, _from, state) do
    url = build_url(state.url, path)
    result = Sambex.get_file_stats(url, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:upload_file, local_path, remote_path}, _from, state) do
    url = build_url(state.url, remote_path)
    result = Sambex.upload_file(local_path, url, state.username, state.password)
    {:reply, result, state}
  end

  def handle_call({:download_file, remote_path, local_path}, _from, state) do
    url = build_url(state.url, remote_path)
    result = Sambex.download_file(url, local_path, state.username, state.password)
    {:reply, result, state}
  end

  # Private functions

  defp resolve_connection(pid) when is_pid(pid), do: pid
  defp resolve_connection(name) when is_atom(name) do
    case Registry.lookup(Sambex.Registry, name) do
      [{pid, _}] -> pid
      [] -> raise ArgumentError, "No connection found with name #{inspect(name)}"
    end
  end

  defp build_url(base_url, path) do
    # Remove trailing slash from base_url and leading slash from path if present
    base = String.trim_trailing(base_url, "/")
    path = String.trim_leading(path, "/")
    
    case path do
      "" -> base
      _ -> "#{base}/#{path}"
    end
  end
end