# Sambex Examples

This guide provides practical examples for common Sambex use cases.

## Basic File Operations

### Reading and Writing Files

```elixir
# Connect to SMB share
{:ok, conn} = Sambex.Connection.connect(
  "smb://fileserver/documents", 
  "username", 
  "password"
)

# Read a configuration file
case Sambex.Connection.read_file(conn, "/config/app.json") do
  {:ok, json_content} ->
    config = Jason.decode!(json_content)
    IO.inspect(config)
    
  {:error, :enoent} ->
    IO.puts("Config file not found, using defaults")
    
  {:error, reason} ->
    IO.puts("Failed to read config: #{reason}")
end

# Write a log file
log_entry = "#{DateTime.utc_now()} - Application started\n"
{:ok, _} = Sambex.Connection.write_file(conn, "/logs/app.log", log_entry)

# Clean up
Sambex.Connection.disconnect(conn)
```

### Working with Binary Files

```elixir
defmodule ImageProcessor do
  def backup_and_resize_image(conn, image_path) do
    with {:ok, image_data} <- Sambex.Connection.read_file(conn, image_path),
         {:ok, resized_data} <- resize_image(image_data),
         {:ok, _} <- Sambex.Connection.write_file(conn, "/backups" <> image_path, image_data),
         {:ok, _} <- Sambex.Connection.write_file(conn, "/thumbnails" <> image_path, resized_data) do
      {:ok, "Image processed successfully"}
    else
      {:error, reason} -> {:error, "Failed to process image: #{reason}"}
    end
  end
  
  defp resize_image(image_data) do
    # Your image resizing logic here
    # This example just returns the original data
    {:ok, image_data}
  end
end

# Usage
{:ok, conn} = Sambex.Connection.connect("smb://server/images", "user", "pass")
ImageProcessor.backup_and_resize_image(conn, "/photos/vacation.jpg")
```

## Directory Operations

### Listing and Filtering Files

```elixir
defmodule FileManager do
  def list_files_by_extension(conn, directory, extension) do
    case Sambex.Connection.list_dir(conn, directory) do
      {:ok, entries} ->
        files = entries
        |> Enum.filter(fn {_name, type} -> type == :file end)
        |> Enum.map(fn {name, _type} -> name end)
        |> Enum.filter(fn name -> String.ends_with?(name, extension) end)
        
        {:ok, files}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  def get_directory_size(conn, directory) do
    case Sambex.Connection.list_dir(conn, directory) do
      {:ok, entries} ->
        total_size = entries
        |> Enum.filter(fn {_name, type} -> type == :file end)
        |> Enum.map(fn {name, _type} -> 
          case Sambex.Connection.get_file_stats(conn, "#{directory}/#{name}") do
            {:ok, %{size: size}} -> size
            _ -> 0
          end
        end)
        |> Enum.sum()
        
        {:ok, total_size}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end

# Usage
{:ok, conn} = Sambex.Connection.connect("smb://server/files", "user", "pass")

# List all PDF files
{:ok, pdf_files} = FileManager.list_files_by_extension(conn, "/documents", ".pdf")
IO.inspect(pdf_files)

# Get total size of directory
{:ok, total_bytes} = FileManager.get_directory_size(conn, "/documents")
IO.puts("Directory size: #{total_bytes} bytes")
```

### Recursive Directory Processing

```elixir
defmodule RecursiveProcessor do
  def process_directory_tree(conn, directory, processor_fn) do
    case Sambex.Connection.list_dir(conn, directory) do
      {:ok, entries} ->
        Enum.each(entries, fn {name, type} ->
          full_path = Path.join(directory, name)
          
          case type do
            :file ->
              processor_fn.(conn, full_path, :file)
              
            :directory ->
              processor_fn.(conn, full_path, :directory)
              # Recursively process subdirectory
              process_directory_tree(conn, full_path, processor_fn)
          end
        end)
        
      {:error, reason} ->
        IO.puts("Error processing #{directory}: #{reason}")
    end
  end
end

# Example: Count files and directories
defmodule FileCounter do
  def count_items(conn, root_directory) do
    counts = %{files: 0, directories: 0}
    agent = Agent.start_link(fn -> counts end)
    
    processor = fn _conn, _path, type ->
      Agent.update(agent, fn counts ->
        Map.update(counts, type == :file && :files || :directories, 0, &(&1 + 1))
      end)
    end
    
    RecursiveProcessor.process_directory_tree(conn, root_directory, processor)
    
    final_counts = Agent.get(agent, & &1)
    Agent.stop(agent)
    final_counts
  end
end

# Usage
{:ok, conn} = Sambex.Connection.connect("smb://server/archive", "user", "pass")
counts = FileCounter.count_items(conn, "/")
IO.puts("Found #{counts.files} files and #{counts.directories} directories")
```

## File Synchronization

### One-way Sync from Local to SMB

```elixir
defmodule SyncManager do
  def sync_local_to_smb(local_dir, conn, remote_dir) do
    case File.ls(local_dir) do
      {:ok, local_files} ->
        # Get remote files for comparison
        {:ok, remote_entries} = Sambex.Connection.list_dir(conn, remote_dir)
        remote_files = remote_entries
        |> Enum.filter(fn {_name, type} -> type == :file end)
        |> Enum.map(fn {name, _type} -> name end)
        |> MapSet.new()
        
        # Sync each local file
        Enum.each(local_files, fn filename ->
          local_path = Path.join(local_dir, filename)
          remote_path = "#{remote_dir}/#{filename}"
          
          if File.regular?(local_path) do
            should_sync = cond do
              not MapSet.member?(remote_files, filename) ->
                IO.puts("New file: #{filename}")
                true
                
              file_newer?(local_path, conn, remote_path) ->
                IO.puts("Updated file: #{filename}")
                true
                
              true ->
                false
            end
            
            if should_sync do
              case Sambex.Connection.upload_file(conn, local_path, remote_path) do
                {:ok, _} -> IO.puts("✓ Synced #{filename}")
                {:error, reason} -> IO.puts("✗ Failed to sync #{filename}: #{reason}")
              end
            end
          end
        end)
        
      {:error, reason} ->
        IO.puts("Failed to read local directory: #{reason}")
    end
  end
  
  defp file_newer?(local_path, conn, remote_path) do
    with {:ok, local_stat} <- File.stat(local_path),
         {:ok, remote_stat} <- Sambex.Connection.get_file_stats(conn, remote_path) do
      local_mtime = local_stat.mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
      remote_mtime = DateTime.from_unix!(remote_stat.modification_time)
      DateTime.compare(local_mtime, remote_mtime) == :gt
    else
      _ -> true  # If we can't compare, assume local is newer
    end
  end
end

# Usage
{:ok, conn} = Sambex.Connection.connect("smb://backup-server/sync", "user", "pass")
SyncManager.sync_local_to_smb("/home/user/documents", conn, "/backup/documents")
```

## Production Patterns

### Connection Pool for High Throughput

```elixir
defmodule SMBConnectionPool do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_connection() do
    GenServer.call(__MODULE__, :get_connection)
  end
  
  def return_connection(conn) do
    GenServer.cast(__MODULE__, {:return_connection, conn})
  end
  
  def init(opts) do
    url = Keyword.fetch!(opts, :url)
    username = Keyword.fetch!(opts, :username)
    password = Keyword.fetch!(opts, :password)
    pool_size = Keyword.get(opts, :pool_size, 5)
    
    connections = for _ <- 1..pool_size do
      {:ok, conn} = Sambex.Connection.connect(url, username, password)
      conn
    end
    
    {:ok, %{available: connections, in_use: MapSet.new()}}
  end
  
  def handle_call(:get_connection, _from, %{available: [conn | rest], in_use: in_use}) do
    {:reply, {:ok, conn}, %{available: rest, in_use: MapSet.put(in_use, conn)}}
  end
  
  def handle_call(:get_connection, _from, %{available: []} = state) do
    {:reply, {:error, :no_connections_available}, state}
  end
  
  def handle_cast({:return_connection, conn}, %{available: available, in_use: in_use}) do
    if MapSet.member?(in_use, conn) do
      new_state = %{
        available: [conn | available], 
        in_use: MapSet.delete(in_use, conn)
      }
      {:noreply, new_state}
    else
      {:noreply, %{available: available, in_use: in_use}}
    end
  end
end

# High-throughput file processor
defmodule HighThroughputProcessor do
  def process_files(file_list) do
    tasks = Enum.map(file_list, fn file_path ->
      Task.async(fn ->
        case SMBConnectionPool.get_connection() do
          {:ok, conn} ->
            try do
              process_single_file(conn, file_path)
            after
              SMBConnectionPool.return_connection(conn)
            end
            
          {:error, :no_connections_available} ->
            {:error, "No connections available"}
        end
      end)
    end)
    
    Task.await_many(tasks, 30_000)
  end
  
  defp process_single_file(conn, file_path) do
    with {:ok, content} <- Sambex.Connection.read_file(conn, file_path),
         processed_content <- transform_content(content),
         {:ok, _} <- Sambex.Connection.write_file(conn, "/processed" <> file_path, processed_content) do
      {:ok, "Processed #{file_path}"}
    else
      {:error, reason} -> {:error, "Failed to process #{file_path}: #{reason}"}
    end
  end
  
  defp transform_content(content) do
    # Your transformation logic here
    String.upcase(content)
  end
end

# Usage
SMBConnectionPool.start_link([
  url: "smb://processing-server/data",
  username: "processor",
  password: "secret",
  pool_size: 10
])

files_to_process = ["/input/file1.txt", "/input/file2.txt", "/input/file3.txt"]
results = HighThroughputProcessor.process_files(files_to_process)
IO.inspect(results)
```

### Supervised Production Service

```elixir
defmodule DocumentService do
  use GenServer
  
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end
  
  def save_document(content, filename) do
    GenServer.call(__MODULE__, {:save_document, content, filename})
  end
  
  def get_document(filename) do
    GenServer.call(__MODULE__, {:get_document, filename})
  end
  
  def list_documents() do
    GenServer.call(__MODULE__, :list_documents)
  end
  
  def init(:ok) do
    # Start our SMB connection
    {:ok, _} = Sambex.Connection.start_link([
      url: Application.get_env(:my_app, :documents_smb_url),
      username: Application.get_env(:my_app, :documents_smb_user),
      password: Application.get_env(:my_app, :documents_smb_pass),
      name: :documents
    ])
    
    {:ok, %{}}
  end
  
  def handle_call({:save_document, content, filename}, _from, state) do
    result = case Sambex.Connection.write_file(:documents, "/#{filename}", content) do
      {:ok, _} -> 
        # Also create metadata
        metadata = %{
          filename: filename,
          size: byte_size(content),
          created_at: DateTime.utc_now(),
          checksum: :crypto.hash(:sha256, content) |> Base.encode16()
        }
        
        Sambex.Connection.write_file(
          :documents, 
          "/metadata/#{filename}.json", 
          Jason.encode!(metadata)
        )
        
        {:ok, "Document saved successfully"}
        
      {:error, reason} -> 
        {:error, "Failed to save document: #{reason}"}
    end
    
    {:reply, result, state}
  end
  
  def handle_call({:get_document, filename}, _from, state) do
    result = Sambex.Connection.read_file(:documents, "/#{filename}")
    {:reply, result, state}
  end
  
  def handle_call(:list_documents, _from, state) do
    result = case Sambex.Connection.list_dir(:documents, "/") do
      {:ok, entries} ->
        documents = entries
        |> Enum.filter(fn {name, type} -> 
          type == :file and not String.starts_with?(name, ".")
        end)
        |> Enum.map(fn {name, _type} -> name end)
        |> Enum.reject(fn name -> String.ends_with?(name, ".json") end)
        
        {:ok, documents}
        
      error -> error
    end
    
    {:reply, result, state}
  end
end

# In your application.ex
children = [
  DocumentService,
  # Your other services...
]

# Usage in your application
DocumentService.save_document("Hello, World!", "greeting.txt")
{:ok, content} = DocumentService.get_document("greeting.txt")
{:ok, files} = DocumentService.list_documents()
```

## Error Handling Patterns

### Retry Logic with Backoff

```elixir
defmodule ReliableFileOperations do
  def read_file_with_retry(conn, path, max_retries \\ 3) do
    do_with_retry(fn -> Sambex.Connection.read_file(conn, path) end, max_retries)
  end
  
  def write_file_with_retry(conn, path, content, max_retries \\ 3) do
    do_with_retry(fn -> Sambex.Connection.write_file(conn, path, content) end, max_retries)
  end
  
  defp do_with_retry(operation, retries_left, delay \\ 1000)
  
  defp do_with_retry(operation, retries_left, delay) when retries_left > 0 do
    case operation.() do
      {:ok, result} -> 
        {:ok, result}
        
      {:error, reason} when reason in [:etimedout, :econnrefused, :ehostunreach] ->
        IO.puts("Operation failed (#{reason}), retrying in #{delay}ms... (#{retries_left} retries left)")
        Process.sleep(delay)
        do_with_retry(operation, retries_left - 1, min(delay * 2, 10_000))
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp do_with_retry(_operation, 0, _delay) do
    {:error, :max_retries_exceeded}
  end
end

# Usage
{:ok, conn} = Sambex.Connection.connect("smb://unreliable-server/files", "user", "pass")

case ReliableFileOperations.read_file_with_retry(conn, "/important.txt") do
  {:ok, content} -> IO.puts("Successfully read file: #{content}")
  {:error, :max_retries_exceeded} -> IO.puts("Failed after all retries")
  {:error, reason} -> IO.puts("Failed with error: #{reason}")
end
```

This collection of examples demonstrates real-world usage patterns for Sambex, from simple file operations to production-ready services with error handling and connection management.