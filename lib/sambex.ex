defmodule Sambex do
  @moduledoc """
  Elixir wrapper for SMB/CIFS file sharing using libsmbclient.

  Sambex provides both direct and connection-based APIs for working with SMB shares.
  The connection-based API is recommended for production use as it provides better
  security, performance, and follows Elixir/OTP patterns.

  ## Quick Start

  ### Setup
  Add to your `mix.exs`:

      def deps do
        [
          {:sambex, "~> 0.2.0"}
        ]
      end

  ### Simple Usage (Connection API - Recommended)

      # Start a connection to an SMB share
      {:ok, conn} = Sambex.Connection.connect(
        "smb://192.168.1.100/shared_folder", 
        "username", 
        "password"
      )

      # List files in the root directory
      {:ok, files} = Sambex.Connection.list_dir(conn, "/")
      IO.inspect(files)
      # [{"document.pdf", :file}, {"photos", :directory}]

      # Read a file
      {:ok, content} = Sambex.Connection.read_file(conn, "/document.pdf")

      # Write a file
      {:ok, _bytes} = Sambex.Connection.write_file(conn, "/new_file.txt", "Hello, SMB!")

      # Clean up
      Sambex.Connection.disconnect(conn)

  ## Two Usage Patterns

  ### 1. Connection API (Recommended)
  Create persistent connections that store credentials and provide better performance:

      # Named connections for multiple shares
      {:ok, _} = Sambex.Connection.start_link(
        url: "smb://server/documents",
        username: "user", 
        password: "pass",
        name: :documents
      )

      {:ok, _} = Sambex.Connection.start_link(
        url: "smb://server/photos",
        username: "user",
        password: "pass", 
        name: :photos
      )

      # Use named connections
      Sambex.Connection.list_dir(:documents, "/")
      Sambex.Connection.list_dir(:photos, "/")

  ### 2. Direct API (Legacy)
  Pass credentials on every operation:

      Sambex.init()  # Initialize the library
      Sambex.list_dir("smb://server/share", "user", "pass")
      Sambex.read_file("smb://server/share/file.txt", "user", "pass")

  ## Error Handling

  All functions return tagged tuples for easy pattern matching:

      case Sambex.Connection.read_file(conn, "/important.txt") do
        {:ok, content} -> 
          IO.puts("File content: \#{content}")
        {:error, :enoent} -> 
          IO.puts("File not found")
        {:error, reason} -> 
          IO.puts("Error: \#{reason}")
      end

  ## Common Operations

  ### Working with Directories

      # List directory contents
      {:ok, entries} = Sambex.Connection.list_dir(conn, "/projects")
      
      # Filter only files
      files = Enum.filter(entries, fn {_name, type} -> type == :file end)

  ### File Operations

      # Check if file exists by getting stats
      case Sambex.Connection.get_file_stats(conn, "/report.pdf") do
        {:ok, %{size: size, type: :file}} -> 
          IO.puts("File exists, size: \#{size} bytes")
        {:error, :enoent} -> 
          IO.puts("File does not exist")
      end

      # Copy local file to SMB share
      {:ok, _} = Sambex.Connection.upload_file(conn, "/local/file.txt", "/remote/file.txt")
      
      # Download from SMB share to local file
      {:ok, _} = Sambex.Connection.download_file(conn, "/remote/data.csv", "/local/data.csv")

  ### Large File Handling

      # Sambex handles large files efficiently
      {:ok, large_content} = File.read("/path/to/large_file.bin")
      {:ok, bytes_written} = Sambex.Connection.write_file(conn, "/backup/large_file.bin", large_content)
      IO.puts("Wrote \#{bytes_written} bytes")

  ## Production Usage

  For production applications, use the supervised connection API:

      # In your application.ex
      children = [
        # Sambex will start automatically with the application
        # Add your connections
        {Sambex.Connection, [
          url: "smb://fileserver/documents",
          username: System.get_env("SMB_USERNAME"),
          password: System.get_env("SMB_PASSWORD"),
          name: :fileserver
        ]}
      ]

      # In your business logic
      def save_report(report_data) do
        case Sambex.Connection.write_file(:fileserver, "/reports/\#{Date.utc_today()}.json", report_data) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, "Failed to save report: \#{reason}"}
        end
      end

  ## Security Notes

  - Use environment variables for credentials in production
  - The connection API stores credentials in GenServer state (more secure than passing them around)
  - Consider using SMB3 for better security
  - Always validate and sanitize file paths from user input

  ## Performance Tips

  - Use the connection API for better performance (avoids reconnecting on each operation)
  - Consider connection pooling for high-throughput applications
  - Large file operations are handled efficiently by the underlying libsmbclient

  ## HotFolder - Automated File Processing

  Sambex includes a powerful HotFolder feature that implements the "hot folder" pattern
  common in printing and document processing industries. HotFolders monitor SMB directories
  for new files and automatically process them through configurable workflows.

  ### Basic HotFolder Usage

      # Simple HotFolder that processes PDF files
      {:ok, pid} = Sambex.HotFolder.start_link(%{
        url: "smb://printserver/queue",
        username: "processor",
        password: "secret",
        handler: fn file_info ->
          IO.puts("Processing: \#{file_info.name}")
          # Your processing logic here
          {:ok, :processed}
        end,
        filters: %{
          name_patterns: [~r/\\.pdf$/i],
          min_size: 1024
        }
      })

  ### Advanced HotFolder Configuration

      config = %Sambex.HotFolder.Config{
        # Connection (reuse existing named connection)
        connection: :print_server,
        
        # File processing handler
        handler: {MyApp.PDFProcessor, :process, [:high_quality]},
        
        # Base path within the SMB share
        base_path: "hot-folders/pdf-processor",
        
        # Configurable folder names
        folders: %{
          incoming: "inbox",      # Files are dropped here
          processing: "working",  # Files move here during processing
          success: "completed",   # Successfully processed files
          errors: "failed"        # Failed files with error reports
        },
        
        # Rich filtering options
        filters: %{
          name_patterns: [~r/\\.pdf$/i, ~r/job_\\d+\\.txt$/],
          exclude_patterns: [~r/^\\./],  # Skip hidden files
          min_size: 1024,               # 1KB minimum
          max_size: 100_000_000,        # 100MB maximum
          mime_types: ["application/pdf"]
        },
        
        # Polling configuration with smart backoff
        poll_interval: %{
          initial: 1_000,    # Start at 1 second
          max: 30_000,       # Cap at 30 seconds
          backoff_factor: 2.0
        },
        
        # Error handling
        handler_timeout: 300_000,  # 5 minutes per file
        max_retries: 5,
        create_folders: true       # Auto-create folder structure
      }
      
      {:ok, pid} = Sambex.HotFolder.start_link(config, name: :pdf_processor)

  ### HotFolder File Processing Workflow

  1. **Discovery**: Files are found in the incoming folder during polling
  2. **Stability Check**: Files must have stable size across polls (ensures complete upload)
  3. **Filtering**: Files are checked against configured patterns, sizes, and MIME types
  4. **Processing**: File is moved to processing folder and handler is executed
  5. **Success**: On success, file is moved to success folder
  6. **Error**: On failure, file is moved to errors folder with detailed error report

  ### Handler Interface

  HotFolder handlers receive file information and return success/error tuples:

      def process_document(file_info) do
        # file_info: %{path: "inbox/document.pdf", name: "document.pdf", size: 2048}
        case convert_to_images(file_info.path) do
          {:ok, images} -> 
            save_thumbnails(images)
            {:ok, %{thumbnails_created: length(images)}}
          {:error, reason} -> 
            {:error, reason}
        end
      end

  ### Monitoring HotFolders

      # Get current statistics
      stats = Sambex.HotFolder.stats(pid)
      # => %{
      #   files_processed: 150,
      #   files_failed: 3,
      #   current_status: :polling,
      #   uptime: 3600,
      #   last_poll: ~U[2025-01-15 10:30:00Z],
      #   current_interval: 5000
      # }

      # Get current status
      status = Sambex.HotFolder.status(pid)
      # => :polling | {:processing, "filename.pdf"} | :error

      # Force immediate poll
      :ok = Sambex.HotFolder.poll_now(pid)

  ### Production HotFolder Setup

      # In your application.ex
      children = [
        # SMB connection
        {Sambex.Connection, [
          url: "smb://fileserver/print-queue",
          username: System.get_env("SMB_USERNAME"),
          password: System.get_env("SMB_PASSWORD"),
          name: :print_server
        ]},
        
        # HotFolder processor
        {Sambex.HotFolder, [
          %{
            connection: :print_server,
            handler: {MyApp.PrintProcessor, :process_job, []},
            base_path: "production/pdf-workflow",
            filters: %{
              name_patterns: [~r/\\.pdf$/i],
              min_size: 1024,
              max_size: 50_000_000
            },
            handler_timeout: 600_000,  # 10 minutes
            max_retries: 3
          },
          [name: :pdf_hotfolder]
        ]}
      ]

  ### Telemetry and Monitoring

  HotFolders emit comprehensive telemetry events for monitoring:

      # Attach telemetry handler
      :telemetry.attach_many(
        "hot-folder-metrics",
        [
          [:sambex, :hot_folder, :started],
          [:sambex, :hot_folder, :file_discovered],
          [:sambex, :hot_folder, :file_processed],
          [:sambex, :hot_folder, :file_failed],
          [:sambex, :hot_folder, :poll_completed]
        ],
        &MyApp.Telemetry.handle_hot_folder_event/4,
        nil
      )

  ### Error Handling and Recovery

  HotFolders provide robust error handling:

  - **Retry Logic**: Failed files are retried with exponential backoff
  - **Error Reports**: Detailed error reports are generated for failed files
  - **File Stability**: Files are checked for stable size to prevent processing partial uploads
  - **Connection Recovery**: Automatic recovery from connection failures

  Example error report:
  ```
  Error processing file: document.pdf
  Timestamp: 2025-01-15T10:30:00Z
  File Path: inbox/document.pdf
  File Size: 2048 bytes
  Attempts: 3
  Final Error: {:error, :invalid_format}
  Handler: MyApp.PDFProcessor.process/1

  Error History:
  Attempt 1 (2025-01-15T10:29:30Z): {:error, :network_timeout}
  Attempt 2 (2025-01-15T10:29:45Z): {:error, :invalid_format}
  Attempt 3 (2025-01-15T10:30:00Z): {:error, :invalid_format}
  ```

  ### Use Cases

  HotFolders are perfect for:
  - Document processing workflows
  - Image thumbnail generation
  - File format conversions
  - Data import pipelines
  - Print queue automation
  - Backup and archival systems
  """

  alias Sambex.Nif

  @doc """
  Initialize the SMB client library.

  This function must be called before using any other direct API functions.
  The connection API (`Sambex.Connection`) handles initialization automatically.

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      Sambex.init()
      # => :ok
      
  ## See Also

  - `Sambex.Connection` for the connection-based API that handles initialization automatically
  """
  def init do
    Nif.init_smb()
  end

  @doc """
  Connect to an SMB share using the direct API.

  This function establishes a connection for a single operation. For persistent 
  connections, consider using `Sambex.Connection.connect/3` instead.

  ## Parameters

  - `url` - SMB URL (e.g., "smb://server/share")
  - `username` - Username for authentication  
  - `password` - Password for authentication

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  ## Examples

      Sambex.init()
      Sambex.connect("smb://192.168.1.100/share", "user", "pass")
      # => :ok
      
  ## See Also

  - `Sambex.Connection.connect/3` for persistent connections
  - `Sambex.init/0` must be called before using this function
  """
  def connect(url, username, password) when is_binary(url) do
    Nif.connect(url, username, password)
  end

  @doc """
  List files and directories in an SMB directory using the direct API.

  Returns a list of tuples containing the filename and type (`:file` or `:directory`).

  ## Parameters

  - `url` - SMB URL to the directory (e.g., "smb://server/share/directory")
  - `username` - Username for authentication
  - `password` - Password for authentication

  ## Returns

  - `{:ok, [{filename, :file | :directory}, ...]}` on success
  - `{:error, reason}` on failure

  ## Examples

      Sambex.init()
      Sambex.list_dir("smb://192.168.1.100/share", "user", "pass")
      # => {:ok, [{"file.txt", :file}, {"folder", :directory}]}

      # Filter only files
      {:ok, entries} = Sambex.list_dir("smb://server/share", "user", "pass")
      files = Enum.filter(entries, fn {_name, type} -> type == :file end)
      
  ## See Also

  - `Sambex.Connection.list_dir/2` for the connection-based API
  - `Sambex.get_file_stats/3` to get detailed file information
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

  - `{:ok, binary_content}` on success
  - `{:error, reason}` on failure
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

  - `{:ok, bytes_written}` on success where `bytes_written` is an integer
  - `{:error, reason}` on failure
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

  - `:ok` on success
  - `{:error, reason}` on failure
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

  - `:ok` on success
  - `{:error, reason}` on failure

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
  Get file statistics/metadata from an SMB share.

  ## Parameters
    - url: SMB URL to the file (e.g., "smb://server/share/file.txt")
    - username: Username for authentication
    - password: Password for authentication

  ## Returns

  - `{:ok, stats_map}` on success
  - `{:error, reason}` on failure

  The `stats_map` contains:
    - `:size` - File size in bytes
    - `:type` - File type (`:file`, `:directory`, `:symlink`, `:other`)
    - `:mode` - File permissions (octal mode)
    - `:access_time` - Last access time (Unix timestamp)
    - `:modification_time` - Last modification time (Unix timestamp)
    - `:change_time` - Last status change time (Unix timestamp)
    - `:uid` - User ID of owner
    - `:gid` - Group ID of owner
    - `:links` - Number of hard links

  ## Examples
      Sambex.get_file_stats("smb://192.168.1.100/share/file.txt", "user", "pass")
      # => {:ok, %{size: 1024, type: :file, mode: 644, ...}}
  """
  def get_file_stats(url, username, password) when is_binary(url) do
    case Nif.get_file_stats(url, username, password) do
      {:ok, flat_list} ->
        {:ok, flat_list_to_map(flat_list)}

      error ->
        error
    end
  end

  # Helper function to convert flat list [:key1, val1, :key2, val2, ...] to map
  defp flat_list_to_map(flat_list) do
    flat_list
    |> Enum.chunk_every(2)
    |> Enum.into(%{}, fn [key, value] -> {key, value} end)
  end

  @doc """
  High-level function to copy a local file to an SMB share.

  This is a convenience function that reads a local file and writes it to the SMB share.

  ## Parameters

  - `local_path` - Path to the local file to upload
  - `smb_url` - SMB URL where the file should be written
  - `username` - Username for authentication
  - `password` - Password for authentication

  ## Returns

  - `{:ok, bytes_written}` on success
  - `{:error, reason}` on failure (could be from file read or SMB write)

  ## Examples

      Sambex.init()
      Sambex.upload_file("/local/document.pdf", "smb://server/share/document.pdf", "user", "pass")
      # => {:ok, 1024}
      
  ## See Also

  - `Sambex.Connection.upload_file/3` for the connection-based API
  - `Sambex.download_file/4` for the reverse operation
  - `Sambex.write_file/4` for writing binary content directly
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
  High-level function to download a file from an SMB share to local filesystem.

  This is a convenience function that reads a file from the SMB share and writes it locally.

  ## Parameters

  - `smb_url` - SMB URL of the file to download
  - `local_path` - Local path where the file should be saved
  - `username` - Username for authentication
  - `password` - Password for authentication

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure (could be from SMB read or local file write)

  ## Examples

      Sambex.init()
      Sambex.download_file("smb://server/share/report.pdf", "/local/report.pdf", "user", "pass")
      # => :ok
      
  ## See Also

  - `Sambex.Connection.download_file/3` for the connection-based API
  - `Sambex.upload_file/4` for the reverse operation
  - `Sambex.read_file/3` for reading content into memory
  """
  def download_file(smb_url, local_path, username, password) do
    case read_file(smb_url, username, password) do
      {:ok, content} ->
        File.write(local_path, content)

      error ->
        error
    end
  end

  @doc """
  Create a directory on an SMB share.

  ## Parameters

  - `url` - SMB URL to the directory to create (e.g., "smb://server/share/new_folder")
  - `username` - Username for authentication
  - `password` - Password for authentication

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure

  Possible error reasons:
  - `:file_exists` - Directory already exists
  - `:path_not_found` - Parent directory doesn't exist
  - `:permission_denied` - Insufficient permissions
  - `:not_directory` - Path component is not a directory

  ## Examples

      Sambex.init()
      Sambex.mkdir("smb://server/share/new_folder", "user", "pass")
      # => :ok

      # Create nested directories (parent must exist first)
      Sambex.mkdir("smb://server/share/reports", "user", "pass")
      Sambex.mkdir("smb://server/share/reports/2025", "user", "pass")
      # => :ok
      
  ## See Also

  - `Sambex.Connection.mkdir/2` for the connection-based API
  - `Sambex.list_dir/3` to verify directory creation
  """
  def mkdir(url, username, password) when is_binary(url) do
    Nif.mkdir(url, username, password)
  end
end
