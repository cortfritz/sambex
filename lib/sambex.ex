defmodule Sambex do
  @moduledoc """
  Elixir wrapper for Sambex using Zigler.

  Provides functionality to connect to SMB shares and perform file operations.
  """

  alias Sambex.Nif

  @doc """
  Initialize the SMB client library.
  Must be called before using other functions.
  """
  def init do
    Nif.init_smb()
  end

  @doc """
  Connect to an SMB share.

  ## Parameters
    - url: SMB URL (e.g., "smb://server/share")
    - username: Username for authentication
    - password: Password for authentication

  ## Examples
      Sambex.connect("smb://192.168.1.100/share", "user", "pass")
      # => :ok
  """
  def connect(url, username, password) when is_binary(url) do
    Nif.connect(url, username, password)
  end

  @doc """
  List files and directories in an SMB directory.

  ## Parameters
    - url: SMB URL (e.g., "smb://server/share/directory")
    - username: Username for authentication
    - password: Password for authentication

  ## Returns
    {:ok, [{filename, :file | :directory}, ...]} or {:error, reason}

  ## Examples
      Sambex.list_dir("smb://192.168.1.100/share", "user", "pass")
      # => {:ok, [{"file.txt", :file}, {"folder", :directory}]}
  """
  def list_dir(url, username, password) when is_binary(url) do
    Nif.list_dir(url, username, password)
  end

  @doc """
  Read a file from an SMB share.

  ## Parameters
    - url: SMB URL to the file (e.g., "smb://server/share/file.txt")
    - username: Username for authentication
    - password: Password for authentication

  ## Returns
    {:ok, binary_content} or {:error, reason}
  """
  def read_file(url, username, password) when is_binary(url) do
    Nif.read_file(url, username, password)
  end

  @doc """
  Write a file to an SMB share.

  ## Parameters
    - url: SMB URL to the file (e.g., "smb://server/share/file.txt")
    - content: Binary content to write
    - username: Username for authentication
    - password: Password for authentication

  ## Returns
    {:ok, bytes_written} or {:error, reason}
  """
  def write_file(url, content, username, password)
      when is_binary(url) and is_binary(content) do
    Nif.write_file(url, content, username, password)
  end

  @doc """
  Delete a file from an SMB share.

  ## Parameters
    - url: SMB URL to the file (e.g., "smb://server/share/file.txt")
    - username: Username for authentication
    - password: Password for authentication

  ## Returns
    :ok or {:error, reason}
  """
  def delete_file(url, username, password) when is_binary(url) do
    Nif.delete_file(url, username, password)
  end

  @doc """
  Move/rename a file on an SMB share.

  ## Parameters
    - source_url: SMB URL to the source file (e.g., "smb://server/share/old_file.txt")
    - dest_url: SMB URL to the destination file (e.g., "smb://server/share/new_file.txt")
    - username: Username for authentication
    - password: Password for authentication

  ## Returns
    :ok or {:error, reason}

  ## Examples
      # Rename a file in the same directory
      Sambex.move_file("smb://192.168.1.100/share/old.txt", "smb://192.168.1.100/share/new.txt", "user", "pass")
      # => :ok

      # Move a file to a different directory
      Sambex.move_file("smb://192.168.1.100/share/file.txt", "smb://192.168.1.100/share/folder/file.txt", "user", "pass")
      # => :ok
  """
  def move_file(source_url, dest_url, username, password)
      when is_binary(source_url) and is_binary(dest_url) do
    Nif.move_file(source_url, dest_url, username, password)
  end

  @doc """
  High-level function to copy a local file to an SMB share.
  """
  def upload_file(local_path, smb_url, username, password) do
    case File.read(local_path) do
      {:ok, content} ->
        write_file(smb_url, content, username, password)

      error ->
        error
    end
  end

  @doc """
  High-level function to download a file from an SMB share.
  """
  def download_file(smb_url, local_path, username, password) do
    case read_file(smb_url, username, password) do
      {:ok, content} ->
        File.write(local_path, content)

      error ->
        error
    end
  end
end
