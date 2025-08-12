# HotFolders Guide

HotFolders in Sambex provide automated file processing workflows by monitoring SMB share directories for new files and triggering custom processing functions when files are detected. This pattern is commonly used in document processing, print workflows, data ingestion, and other file-based automation scenarios.

## What are HotFolders?

A HotFolder is a monitored directory where files can be "dropped" to trigger automated processing. When a file appears in the monitored directory, the HotFolder system:

1. **Detects** the new file through periodic polling
2. **Validates** the file against configured filters
3. **Moves** the file to a processing directory
4. **Processes** the file using your custom handler function
5. **Routes** the file to success or error directories based on the result

This pattern enables robust, unattended file processing workflows that can handle various scenarios like document conversion, data validation, backup operations, and more.

## How HotFolders Work

The Sambex HotFolder implementation provides a complete file processing pipeline:

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Incoming  │───▶│ Processing  │───▶│   Success   │
│   Directory │    │  Directory  │    │  Directory  │
└─────────────┘    └─────────────┘    └─────────────┘
                           │
                           │ (on error)
                           ▼
                   ┌─────────────┐
                   │    Error    │
                   │  Directory  │
                   └─────────────┘
```

### Key Components

1. **Polling Engine**: Efficiently monitors the incoming directory with intelligent backoff
2. **File Stability Checking**: Ensures files are completely uploaded before processing
3. **Filter System**: Allows selective processing based on filename patterns, size, and MIME types
4. **Handler Execution**: Safely runs your processing logic with timeout and retry protection
5. **File Management**: Automatically organizes files into appropriate directories
6. **Error Handling**: Comprehensive retry logic and error reporting

## Basic Usage

### Simple File Processing

Start with a basic HotFolder that processes all files in a directory:

```elixir
# Define your processing function
defmodule MyApp.FileProcessor do
  def process_file(file_info) do
    # file_info contains: %{name: "file.txt", path: "incoming/file.txt", size: 1024}
    IO.puts("Processing file: #{file_info.name}")
    
    # Simulate processing
    Process.sleep(1000)
    
    {:ok, %{processed_at: DateTime.utc_now()}}
  end
end

# Start the HotFolder
{:ok, pid} = Sambex.HotFolder.start_link(%{
  url: "smb://fileserver/processing",
  username: "processor",
  password: "secret",
  handler: &MyApp.FileProcessor.process_file/1
})
```

### Using Existing Connections

For better resource management, use existing SMB connections:

```elixir
# Start a named connection
{:ok, _} = Sambex.Connection.start_link([
  url: "smb://fileserver/documents",
  username: "user",
  password: "pass",
  name: :document_processor
])

# Use the connection in your HotFolder
{:ok, pid} = Sambex.HotFolder.start_link(%{
  connection: :document_processor,
  handler: &MyApp.DocumentProcessor.process/1
})
```

## Advanced Configuration

### Complete Configuration Example

```elixir
alias Sambex.HotFolder

config = %HotFolder.Config{
  # Connection settings
  connection: :pdf_processor,
  
  # Folder structure within the SMB share
  base_path: "pdf-workflow",
  folders: %{
    incoming: "inbox",
    processing: "working", 
    success: "completed",
    errors: "failed"
  },

  # File filtering
  filters: %{
    # Only process PDF files
    name_patterns: [~r/\.pdf$/i],
    
    # Skip temporary and hidden files
    exclude_patterns: [~r/^\./, ~r/~$/, ~r/\.tmp$/],
    
    # Size constraints (1KB to 100MB)
    min_size: 1024,
    max_size: 100_000_000,
    
    # MIME type validation
    mime_types: ["application/pdf"]
  },

  # Polling behavior
  poll_interval: %{
    initial: 1_000,      # Start checking every 1 second
    max: 30_000,         # Back off to 30 seconds when idle
    backoff_factor: 2.0  # Double interval when no files found
  },

  # Handler execution
  handler: {MyApp.PDFProcessor, :process_pdf, [:high_quality]},
  handler_timeout: 300_000,  # 5 minutes
  max_retries: 5,

  # Automatically create directories if they don't exist
  create_folders: true
}

{:ok, pid} = HotFolder.start_link(config)
```

### Folder Structure

The HotFolder creates and manages four directories within your SMB share:

- **Incoming**: Where new files are detected (`base_path/incoming`)
- **Processing**: Temporary location while files are being processed (`base_path/processing`)
- **Success**: Final destination for successfully processed files (`base_path/success`)
- **Errors**: Storage for files that failed processing (`base_path/errors`)

## File Processing Handlers

### Handler Function Signatures

Handlers receive a file info map and must return a success or error tuple:

```elixir
def my_handler(file_info) do
  # file_info = %{
  #   name: "document.pdf",           # Filename
  #   path: "incoming/document.pdf",  # Relative path in SMB share
  #   size: 1048576                   # File size in bytes
  # }
  
  case process_file(file_info) do
    :ok -> {:ok, %{result: "success", processed_at: DateTime.utc_now()}}
    {:error, reason} -> {:error, reason}
  end
end
```

### Module, Function, Args (MFA) Handlers

For more complex handlers with additional parameters:

```elixir
defmodule MyApp.DocumentProcessor do
  def process_document(file_info, quality, format) do
    # Your processing logic here
    {:ok, %{quality: quality, format: format}}
  end
end

# Configure handler with additional arguments
config = %{
  handler: {MyApp.DocumentProcessor, :process_document, [:high, :pdf]},
  # ... other options
}
```

### Handler Best Practices

1. **Idempotent Processing**: Design handlers to be safely re-runnable
2. **Error Reporting**: Return descriptive error messages for debugging
3. **Resource Cleanup**: Ensure temporary resources are cleaned up on both success and failure
4. **Progress Logging**: Use Logger for tracking processing progress

```elixir
defmodule MyApp.RobustProcessor do
  require Logger

  def process_file(file_info) do
    Logger.info("Starting processing: #{file_info.name}")
    
    temp_file = create_temp_file()
    
    try do
      with {:ok, content} <- read_file_content(file_info.path),
           {:ok, processed} <- transform_content(content),
           :ok <- save_result(processed, temp_file) do
        
        Logger.info("Successfully processed: #{file_info.name}")
        {:ok, %{output_file: temp_file}}
      else
        {:error, reason} = error ->
          Logger.error("Processing failed for #{file_info.name}: #{inspect(reason)}")
          error
      end
    after
      # Cleanup temporary resources
      cleanup_temp_files()
    end
  end
  
  # ... implementation details
end
```

## File Filtering

### Pattern-Based Filtering

Use regular expressions to control which files are processed:

```elixir
filters = %{
  # Process specific file types
  name_patterns: [
    ~r/\.pdf$/i,           # PDF files
    ~r/job_\d+\.txt$/,     # Job files with numbers
    ~r/report_.*\.xlsx$/i  # Excel reports
  ],
  
  # Skip unwanted files
  exclude_patterns: [
    ~r/^\./,        # Hidden files
    ~r/~$/,         # Backup files
    ~r/\.tmp$/,     # Temporary files
    ~r/\.lock$/     # Lock files
  ]
}
```

### Size-Based Filtering

Control processing based on file size:

```elixir
filters = %{
  min_size: 1024,        # Skip files smaller than 1KB
  max_size: 50_000_000,  # Skip files larger than 50MB
}
```

### MIME Type Filtering

Validate files by their MIME type (requires additional MIME detection):

```elixir
filters = %{
  mime_types: [
    "application/pdf",
    "text/plain",
    "application/json"
  ]
}
```

## Monitoring and Management

### Getting Statistics

Monitor HotFolder performance and activity:

```elixir
stats = Sambex.HotFolder.stats(pid)

# Returns:
# %{
#   files_processed: 150,
#   files_failed: 3,
#   total_size_processed: 52428800,
#   uptime: 3600,
#   current_status: :polling,
#   last_poll: ~U[2025-01-15 10:30:00Z],
#   poll_interval: 5000
# }
```

### Checking Status

Get the current operational status:

```elixir
status = Sambex.HotFolder.status(pid)

# Possible values:
# :polling                          # Waiting for files
# {:processing, "filename.pdf"}     # Currently processing a file
# :error                           # Error state
```

### Manual Polling

Trigger an immediate poll for new files:

```elixir
Sambex.HotFolder.poll_now(pid)
```

### Graceful Shutdown

Stop the HotFolder safely:

```elixir
Sambex.HotFolder.stop(pid)
```

## Production Patterns

### Supervised HotFolders

Integrate HotFolders into your application supervision tree:

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # SMB connections
      {Sambex.Connection, [
        url: "smb://fileserver/invoices",
        username: System.get_env("SMB_USER"),
        password: System.get_env("SMB_PASS"),
        name: :invoice_processor
      ]},
      
      # HotFolder processors
      {Sambex.HotFolder, [
        connection: :invoice_processor,
        base_path: "invoice-processing",
        handler: &MyApp.InvoiceProcessor.process/1
      ]},
      
      # Add more HotFolders as needed
      {Sambex.HotFolder, [
        connection: :invoice_processor,
        base_path: "receipt-processing", 
        handler: &MyApp.ReceiptProcessor.process/1
      ]}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Multiple Processing Pipelines

Set up different HotFolders for different file types:

```elixir
defmodule MyApp.DocumentPipelines do
  def child_spec(_) do
    children = [
      # PDF processing pipeline
      {Sambex.HotFolder, [
        connection: :document_server,
        base_path: "pdf-pipeline",
        handler: &MyApp.PDFProcessor.process/1,
        filters: %{name_patterns: [~r/\.pdf$/i]}
      ]},
      
      # Image processing pipeline
      {Sambex.HotFolder, [
        connection: :document_server,
        base_path: "image-pipeline",
        handler: &MyApp.ImageProcessor.process/1,
        filters: %{name_patterns: [~r/\.(jpg|png|tiff)$/i]}
      ]},
      
      # Data file processing
      {Sambex.HotFolder, [
        connection: :document_server,
        base_path: "data-pipeline",
        handler: &MyApp.DataProcessor.process/1,
        filters: %{name_patterns: [~r/\.(csv|json|xml)$/i]}
      ]}
    ]
    
    %{
      id: __MODULE__,
      type: :supervisor,
      start: {Supervisor, :start_link, [children, [strategy: :one_for_one]]}
    }
  end
end
```

### Error Handling and Recovery

Implement robust error handling for production use:

```elixir
defmodule MyApp.ProductionProcessor do
  require Logger

  def process_file(file_info) do
    try do
      Logger.metadata(file: file_info.name)
      Logger.info("Processing started")
      
      result = do_processing(file_info)
      
      Logger.info("Processing completed successfully")
      {:ok, result}
      
    rescue
      e in MyApp.RetryableError ->
        Logger.warning("Retryable error: #{Exception.message(e)}")
        {:error, {:retryable, Exception.message(e)}}
        
      e ->
        Logger.error("Fatal error: #{Exception.message(e)}")
        Logger.error(Exception.format_stacktrace(__STACKTRACE__))
        
        # Send notification for critical errors
        MyApp.Notifications.send_alert("File processing failed", %{
          file: file_info.name,
          error: Exception.message(e)
        })
        
        {:error, {:fatal, Exception.message(e)}}
    end
  end
  
  defp do_processing(file_info) do
    # Your processing logic here
    %{processed_at: DateTime.utc_now()}
  end
end
```

## Common Use Cases

### Document Processing Workflow

```elixir
defmodule MyApp.DocumentWorkflow do
  def process_document(file_info) do
    with {:ok, content} <- read_document(file_info.path),
         {:ok, validated} <- validate_document(content),
         {:ok, processed} <- convert_format(validated),
         :ok <- store_in_database(processed, file_info.name) do
      
      {:ok, %{
        document_id: generate_id(),
        pages: count_pages(processed),
        processed_at: DateTime.utc_now()
      }}
    else
      {:error, :invalid_format} -> 
        {:error, "Document format not supported"}
      {:error, :validation_failed} -> 
        {:error, "Document failed validation checks"}
      error -> error
    end
  end
  
  # ... implementation details
end

# Configure for PDF processing
{:ok, _} = Sambex.HotFolder.start_link(%{
  connection: :doc_server,
  base_path: "document-processing",
  handler: &MyApp.DocumentWorkflow.process_document/1,
  filters: %{
    name_patterns: [~r/\.pdf$/i],
    min_size: 1024,
    max_size: 100_000_000
  }
})
```

### Data Import Pipeline

```elixir
defmodule MyApp.DataImporter do
  def import_data_file(file_info) do
    case Path.extname(file_info.name) do
      ".csv" -> import_csv(file_info.path)
      ".json" -> import_json(file_info.path)
      ".xml" -> import_xml(file_info.path)
      ext -> {:error, "Unsupported format: #{ext}"}
    end
  end
  
  defp import_csv(path) do
    # CSV import logic
    {:ok, %{records_imported: 150, format: "csv"}}
  end
  
  defp import_json(path) do
    # JSON import logic
    {:ok, %{records_imported: 75, format: "json"}}
  end
  
  defp import_xml(path) do
    # XML import logic
    {:ok, %{records_imported: 200, format: "xml"}}
  end
end
```

### Backup and Archive System

```elixir
defmodule MyApp.BackupProcessor do
  def backup_file(file_info) do
    backup_location = generate_backup_path(file_info.name)
    
    with {:ok, content} <- read_file(file_info.path),
         {:ok, compressed} <- compress_content(content),
         :ok <- store_backup(compressed, backup_location),
         :ok <- update_backup_index(file_info, backup_location) do
      
      {:ok, %{
        backup_path: backup_location,
        original_size: file_info.size,
        compressed_size: byte_size(compressed),
        compression_ratio: calculate_ratio(file_info.size, byte_size(compressed))
      }}
    end
  end
  
  # ... implementation details
end
```

## Troubleshooting

### Common Issues

1. **Files Not Being Detected**
   - Check SMB connection and permissions
   - Verify folder paths and filter configurations
   - Ensure files are stable (not being written to)

2. **Handler Timeouts**
   - Increase `handler_timeout` for long-running processes
   - Optimize processing logic
   - Consider breaking large operations into smaller chunks

3. **High Resource Usage**
   - Adjust polling intervals for less frequent checks
   - Implement connection pooling for high-throughput scenarios
   - Monitor memory usage in handlers

4. **Files Stuck in Processing**
   - Check for handler exceptions or infinite loops
   - Verify proper error handling in custom handlers
   - Review handler timeout settings

### Debugging

Enable detailed logging:

```elixir
# In config/config.exs
config :logger, level: :debug

# Or set at runtime
Logger.configure(level: :debug)
```

Monitor file movements and processing:

```elixir
# Get detailed statistics
stats = Sambex.HotFolder.stats(pid)
IO.inspect(stats, label: "HotFolder Stats")

# Check current status
status = Sambex.HotFolder.status(pid)
IO.inspect(status, label: "Current Status")
```

## Performance Considerations

### Optimizing Polling

- Start with short intervals for responsive processing
- Use longer intervals for low-volume scenarios
- The backoff mechanism automatically optimizes for your workload

### Connection Management

- Reuse connections across multiple HotFolders when possible
- Consider connection pooling for high-throughput scenarios
- Monitor connection health and implement reconnection logic

### Handler Performance

- Keep handlers lightweight and focused
- Offload heavy processing to background jobs if needed
- Implement proper timeout handling for external dependencies

HotFolders provide a powerful and flexible foundation for building automated file processing workflows. By combining the robust SMB connectivity of Sambex with intelligent file monitoring and processing capabilities, you can create reliable, production-ready automation systems that handle a wide variety of file-based workflows.