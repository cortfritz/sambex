defmodule Sambex.HotFolder.FileManager do
  @moduledoc """
  File management operations for HotFolder processing workflow.

  Handles moving files between different state folders (incoming, processing, success, errors)
  and ensures atomic operations where possible to prevent file loss or corruption.
  """

  require Logger

  alias Sambex.HotFolder.Config

  @type move_result :: :ok | {:error, any()}

  @doc """
  Moves a file from the incoming folder to the processing folder.

  This is the first step in the file processing workflow, ensuring that files
  are moved out of the incoming folder as quickly as possible to prevent
  duplicate processing.

  ## Examples

      iex> config = %Sambex.HotFolder.Config{base_path: "hot", folders: %{incoming: "in", processing: "proc"}}
      iex> Sambex.HotFolder.FileManager.move_to_processing(conn_pid, "test.pdf", config)
      :ok

  """
  @spec move_to_processing(pid(), String.t(), Config.t()) :: move_result()
  def move_to_processing(connection_pid, filename, config) do
    source_path = build_file_path(config, :incoming, filename)
    dest_path = build_file_path(config, :processing, filename)

    Logger.debug("Moving file to processing: #{source_path} -> #{dest_path}")

    move_file(connection_pid, source_path, dest_path)
  end

  @doc """
  Moves a file from the processing folder to the success folder.

  Called when a file has been successfully processed by the handler.

  ## Examples

      iex> config = %Sambex.HotFolder.Config{base_path: "hot", folders: %{processing: "proc", success: "done"}}
      iex> Sambex.HotFolder.FileManager.move_to_success(conn_pid, "test.pdf", config)
      :ok

  """
  @spec move_to_success(pid(), String.t(), Config.t()) :: move_result()
  def move_to_success(connection_pid, filename, config) do
    source_path = build_file_path(config, :processing, filename)
    dest_path = build_file_path(config, :success, filename)

    Logger.debug("Moving file to success: #{source_path} -> #{dest_path}")

    move_file(connection_pid, source_path, dest_path)
  end

  @doc """
  Moves a file from the processing folder to the errors folder.

  Called when a file processing has failed after all retries are exhausted.
  Optionally creates an error report alongside the file.

  ## Examples

      iex> config = %Sambex.HotFolder.Config{base_path: "hot", folders: %{processing: "proc", errors: "failed"}}
      iex> Sambex.HotFolder.FileManager.move_to_errors(conn_pid, "test.pdf", config)
      :ok

      iex> Sambex.HotFolder.FileManager.move_to_errors(conn_pid, "test.pdf", config, "Error details...")
      :ok

  """
  @spec move_to_errors(pid(), String.t(), Config.t(), String.t() | nil) :: move_result()
  def move_to_errors(connection_pid, filename, config, error_report \\ nil) do
    source_path = build_file_path(config, :processing, filename)
    dest_path = build_file_path(config, :errors, filename)

    Logger.debug("Moving file to errors: #{source_path} -> #{dest_path}")

    with :ok <- move_file(connection_pid, source_path, dest_path),
         :ok <- maybe_write_error_report(connection_pid, filename, config, error_report) do
      :ok
    end
  end

  @doc """
  Gets file information including size for stability checking.

  Used to determine if a file upload is complete by checking if the size
  remains stable across multiple polls.

  ## Examples

      iex> Sambex.HotFolder.FileManager.get_file_info(conn_pid, "inbox/test.pdf")
      {:ok, %{name: "test.pdf", path: "inbox/test.pdf", size: 2048, modified: ~U[2025-01-15 10:30:00Z]}}

  """
  @spec get_file_info(pid(), String.t()) :: {:ok, map()} | {:error, any()}
  def get_file_info(connection_pid, file_path) do
    case Sambex.Connection.get_file_stats(connection_pid, file_path) do
      {:ok, stat} ->
        file_info = %{
          name: Path.basename(file_path),
          path: file_path,
          size: stat.size,
          modified: stat.modification_time
        }

        {:ok, file_info}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a file exists at the given path.

  ## Examples

      iex> Sambex.HotFolder.FileManager.file_exists?(conn_pid, "inbox/test.pdf")
      true

      iex> Sambex.HotFolder.FileManager.file_exists?(conn_pid, "inbox/nonexistent.pdf")  
      false

  """
  @spec file_exists?(pid(), String.t()) :: boolean()
  def file_exists?(connection_pid, file_path) do
    case Sambex.Connection.get_file_stats(connection_pid, file_path) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Ensures that the required folders exist, creating them if necessary.

  Called during HotFolder initialization when `create_folders: true` is set.

  ## Examples

      iex> config = %Sambex.HotFolder.Config{base_path: "hot"}
      iex> Sambex.HotFolder.FileManager.ensure_folders_exist(conn_pid, config)
      :ok

  """
  @spec ensure_folders_exist(pid(), Config.t()) :: :ok | {:error, any()}
  def ensure_folders_exist(connection_pid, config) do
    folder_paths = Config.all_folder_paths(config)

    Enum.reduce_while(folder_paths, :ok, fn {folder_type, path}, _acc ->
      case ensure_folder_exists(connection_pid, path) do
        :ok ->
          Logger.debug("Folder #{folder_type} exists or created: #{path}")
          {:cont, :ok}

        {:error, reason} ->
          Logger.error("Failed to create folder #{folder_type} at #{path}: #{inspect(reason)}")
          {:halt, {:error, {folder_type, reason}}}
      end
    end)
  end

  ## Private Functions

  defp build_file_path(config, folder_type, filename) do
    folder_path = Config.folder_path(config, folder_type)
    Path.join(folder_path, filename)
  end

  defp move_file(connection_pid, source_path, dest_path) do
    # First, ensure the destination directory exists
    dest_dir = Path.dirname(dest_path)

    with :ok <- ensure_folder_exists(connection_pid, dest_dir),
         :ok <- Sambex.Connection.move_file(connection_pid, source_path, dest_path) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to move file #{source_path} -> #{dest_path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_folder_exists(connection_pid, folder_path) do
    case Sambex.Connection.list_dir(connection_pid, folder_path) do
      {:ok, _} ->
        # Folder exists
        :ok

      {:error, _} ->
        # Try to create the folder
        # Note: This is a simplified implementation. A full implementation
        # would need to create parent directories recursively if they don't exist.
        case Sambex.Connection.mkdir(connection_pid, folder_path) do
          :ok -> :ok
          # Folder was created by another process
          {:error, :file_exists} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp maybe_write_error_report(_connection_pid, _filename, _config, nil), do: :ok

  defp maybe_write_error_report(connection_pid, filename, config, error_report) do
    # Create an error report file alongside the failed file
    report_filename = "#{Path.rootname(filename)}_error.txt"
    report_path = build_file_path(config, :errors, report_filename)

    case Sambex.Connection.write_file(connection_pid, report_path, error_report) do
      :ok ->
        Logger.debug("Error report written: #{report_path}")
        :ok

      {:error, reason} ->
        Logger.warning("Failed to write error report for #{filename}: #{inspect(reason)}")
        # Don't fail the entire operation if error report fails
        :ok
    end
  end
end
