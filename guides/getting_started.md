# Getting Started with Sambex

Sambex is an Elixir library for working with SMB/CIFS file shares. This guide will help you get up and running quickly.

## Installation

Add `sambex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sambex, "~> 0.2.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## System Requirements

Sambex uses `libsmbclient` under the hood, which should be available on most systems:

- **macOS**: Install with `brew install samba`
- **Ubuntu/Debian**: Install with `apt-get install libsmbclient-dev`
- **CentOS/RHEL**: Install with `yum install libsmbclient-devel`

## Quick Start Example

Here's a complete example showing how to connect to an SMB share and perform basic operations:

```elixir
# Start a connection to your SMB share
{:ok, conn} = Sambex.Connection.connect(
  "smb://192.168.1.100/shared_folder",
  "your_username",
  "your_password"
)

# List files in the root directory
{:ok, files} = Sambex.Connection.list_dir(conn, "/")
IO.inspect(files)
# Output: [{"document.pdf", :file}, {"photos", :directory}, {"readme.txt", :file}]

# Read a small text file
{:ok, content} = Sambex.Connection.read_file(conn, "/readme.txt")
IO.puts("File content: #{content}")

# Create a new file
message = "Hello from Elixir!"
{:ok, bytes_written} = Sambex.Connection.write_file(conn, "/greeting.txt", message)
IO.puts("Wrote #{bytes_written} bytes")

# Get file information
{:ok, stats} = Sambex.Connection.get_file_stats(conn, "/greeting.txt")
IO.inspect(stats)
# Output: %{size: 18, type: :file, mode: 644, ...}

# Clean up the connection
Sambex.Connection.disconnect(conn)
```

## Working with Multiple Shares

For applications that need to work with multiple SMB shares, use named connections:

```elixir
# Connect to different shares with meaningful names
{:ok, _} = Sambex.Connection.start_link([
  url: "smb://fileserver/documents", 
  username: "user", 
  password: "pass",
  name: :documents
])

{:ok, _} = Sambex.Connection.start_link([
  url: "smb://fileserver/backups",
  username: "user", 
  password: "pass", 
  name: :backups
])

# Use the named connections
Sambex.Connection.list_dir(:documents, "/reports")
Sambex.Connection.upload_file(:backups, "/local/data.json", "/daily/data.json")
```

## Error Handling

All Sambex functions return tagged tuples, making error handling straightforward:

```elixir
case Sambex.Connection.read_file(conn, "/might_not_exist.txt") do
  {:ok, content} -> 
    process_file(content)
  
  {:error, :enoent} -> 
    IO.puts("File not found - creating default")
    create_default_file(conn)
    
  {:error, :eacces} ->
    IO.puts("Permission denied")
    
  {:error, reason} ->
    IO.puts("Unexpected error: #{inspect(reason)}")
end
```

## Common Use Cases

### Backup Files to SMB Share

```elixir
defmodule BackupService do
  def backup_file(local_path, remote_path) do
    {:ok, conn} = Sambex.Connection.connect(
      "smb://backup-server/backups",
      System.get_env("BACKUP_USER"),
      System.get_env("BACKUP_PASS")
    )
    
    result = Sambex.Connection.upload_file(conn, local_path, remote_path)
    Sambex.Connection.disconnect(conn)
    
    case result do
      {:ok, _} -> {:ok, "Backup successful"}
      error -> error
    end
  end
end

# Usage
BackupService.backup_file("/important/data.db", "/daily/#{Date.utc_today()}/data.db")
```

### Process Files from SMB Directory

```elixir
defmodule FileProcessor do
  def process_directory(conn, directory) do
    case Sambex.Connection.list_dir(conn, directory) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn {_name, type} -> type == :file end)
        |> Enum.each(fn {filename, _type} ->
          process_file(conn, "#{directory}/#{filename}")
        end)
        
      {:error, reason} ->
        IO.puts("Failed to list directory: #{reason}")
    end
  end
  
  defp process_file(conn, filepath) do
    case Sambex.Connection.read_file(conn, filepath) do
      {:ok, content} ->
        # Process the file content
        IO.puts("Processing #{filepath}: #{byte_size(content)} bytes")
        
      {:error, reason} ->
        IO.puts("Failed to read #{filepath}: #{reason}")
    end
  end
end
```

### Sync Local Directory to SMB Share

```elixir
defmodule DirectorySync do
  def sync_to_smb(local_dir, conn, remote_dir) do
    local_dir
    |> File.ls!()
    |> Enum.each(fn filename ->
      local_path = Path.join(local_dir, filename)
      remote_path = "#{remote_dir}/#{filename}"
      
      if File.regular?(local_path) do
        case Sambex.Connection.upload_file(conn, local_path, remote_path) do
          {:ok, _} -> IO.puts("✓ Synced #{filename}")
          {:error, reason} -> IO.puts("✗ Failed to sync #{filename}: #{reason}")
        end
      end
    end)
  end
end

# Usage
{:ok, conn} = Sambex.Connection.connect("smb://server/share", "user", "pass")
DirectorySync.sync_to_smb("/local/documents", conn, "/backup/documents")
```

## Production Deployment

For production applications, integrate Sambex connections into your supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Your other children...
      
      # SMB connections
      {Sambex.Connection, [
        url: "smb://production-fileserver/app-data",
        username: System.get_env("SMB_USERNAME"),
        password: System.get_env("SMB_PASSWORD"),
        name: :app_data
      ]},
      
      {Sambex.Connection, [
        url: "smb://backup-server/backups",
        username: System.get_env("BACKUP_USERNAME"), 
        password: System.get_env("BACKUP_PASSWORD"),
        name: :backups
      ]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Then use the connections throughout your application:

```elixir
defmodule MyApp.DataService do
  def save_report(report_data) do
    filename = "/reports/#{Date.utc_today()}_report.json"
    
    case Sambex.Connection.write_file(:app_data, filename, Jason.encode!(report_data)) do
      {:ok, _} -> 
        # Also backup the report
        Sambex.Connection.write_file(:backups, filename, Jason.encode!(report_data))
        {:ok, "Report saved successfully"}
        
      {:error, reason} -> 
        {:error, "Failed to save report: #{reason}"}
    end
  end
end
```

## Next Steps

- Read the [API documentation](Sambex.html) for detailed function information
- Learn about [connection management](Sambex.Connection.html) 
- Explore [supervisor patterns](Sambex.ConnectionSupervisor.html)
- Check out the [examples repository](https://github.com/wearecococo/sambex/tree/main/examples) for more use cases

## Troubleshooting

### Connection Issues

If you're having trouble connecting:

1. Verify the SMB share is accessible: `smbclient //server/share -U username`
2. Check firewall settings (SMB typically uses ports 139 and 445)
3. Ensure your credentials are correct
4. Try different SMB URL formats: `smb://server/share` vs `smb://ip_address/share`

### Permission Errors

If you get permission errors:

1. Verify your user has the necessary permissions on the share
2. Check that the share allows the specific operations you're trying
3. Some shares may be read-only

### Performance Considerations

- Use the connection API for better performance (avoids reconnecting)
- Consider connection pooling for high-throughput applications
- Large files are handled efficiently by the underlying libsmbclient
- Be mindful of network latency when working with remote shares