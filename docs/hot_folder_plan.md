# Sambex HotFolder Implementation Plan

## Overview

The HotFolder feature adds automated file processing capabilities to Sambex, implementing the printing industry concept of "hot folders" where files dropped into a monitored directory are automatically processed through configurable workflows.

## Core Requirements

- **Sequential Processing**: One file at a time (concurrency = 1)
- **Stateless Operation**: Rescan on startup, no persistent state
- **Connection Flexibility**: Support both managed and reused connections
- **Auto Folder Management**: Create folders with configurable names
- **Rich Filtering**: Size, MIME type, and name pattern filtering
- **Deterministic Behavior**: Prevent conflicting HotFolder instances

## Architecture

```
Sambex.HotFolder (GenServer)
├── Sequential Processing (concurrency = 1)
├── Stateless Operation (rescan on startup)
├── Connection Flexibility (own connection OR reuse existing)
├── Auto Folder Management (configurable names)
└── Rich Filtering (size, mime, name patterns)

Supporting Modules:
├── Sambex.HotFolder.Config        # Validation & defaults
├── Sambex.HotFolder.FileFilter    # Size/mime/name filtering
├── Sambex.HotFolder.FolderManager # Auto-create & manage folders
└── Sambex.HotFolder.Handler       # Safe handler execution
```

## Folder Structure

Default configurable folder structure within the watched share:

```
/watched-folder/
├── incoming/     # Files dropped here trigger processing (configurable name)
├── processing/   # Files moved here during handler execution (configurable name)
├── success/      # Successfully processed files (configurable name)
└── errors/       # Failed files with error reports (configurable name)
```

## Configuration Structure

```elixir
defmodule Sambex.HotFolder.Config do
  defstruct [
    # Connection (either connection name OR url+credentials)
    connection: nil,
    url: nil,
    username: nil, 
    password: nil,
    
    # Core functionality
    handler: nil,               # Required: function or {mod, fun, args}
    base_path: "",             # Optional: subdirectory within share
    
    # Folder names (all relative to base_path)
    folders: %{
      incoming: "incoming",
      processing: "processing", 
      success: "success",
      errors: "errors"
    },
    
    # Polling behavior
    poll_interval: %{
      initial: 2_000,
      max: 30_000,
      backoff_factor: 1.5
    },
    
    # File filtering
    filters: %{
      name_patterns: [],        # [~r/\.pdf$/i]
      exclude_patterns: [~r/^\./], # Skip hidden files by default
      min_size: 0,
      max_size: :infinity,
      mime_types: []            # [] means allow all
    },
    
    # Processing options  
    handler_timeout: 60_000,    # 1 minute default
    max_retries: 3,
    create_folders: true        # Auto-create missing folders
  ]
end
```

## Usage Examples

### Simple Usage
```elixir
{:ok, pid} = Sambex.HotFolder.start_link(%{
  url: "smb://server/print-queue", 
  username: "user",
  password: "pass",
  handler: &MyApp.ProcessPrintJob.handle/1
})
```

### Advanced Configuration
```elixir
config = %Sambex.HotFolder.Config{
  connection: :my_connection,  # Use existing named connection
  handler: {MyApp.Handler, :process, []},
  folders: %{
    incoming: "inbox",
    processing: "working", 
    success: "completed",
    errors: "failed"
  },
  filters: %{
    name_patterns: [~r/\.pdf$/i, ~r/\.jpg$/i],
    min_size: 1024,
    max_size: 50_000_000,
    mime_types: ["application/pdf", "image/jpeg"]
  }
}

{:ok, pid} = Sambex.HotFolder.start_link(config)
```

## File Filtering System

### Supported Filter Types

1. **Name Patterns**: Regex patterns for filename matching
   ```elixir
   name_patterns: [~r/\.pdf$/i, ~r/job_\d+\.txt$/]
   ```

2. **Size Constraints**: Min/max file sizes in bytes
   ```elixir
   min_size: 1024,      # 1KB minimum
   max_size: 50_000_000 # 50MB maximum
   ```

3. **MIME Types**: Content-type validation (requires header inspection)
   ```elixir
   mime_types: ["application/pdf", "image/jpeg", "text/plain"]
   ```

4. **Exclusion Patterns**: Files to skip
   ```elixir
   exclude_patterns: [~r/^\./, ~r/~$/]  # Hidden files, temp files
   ```

## Handler Interface

Handlers receive a file info struct and return success/error tuples:

```elixir
def process_file(file_info) do
  # file_info: %{path: "inbox/document.pdf", name: "document.pdf", size: 2048}
  case do_work(file_info) do
    {:ok, result} -> {:ok, result} 
    {:error, reason} -> {:error, reason}
  end
end
```

## Polling Strategy

Efficient polling with exponential backoff:

- Start at 2 seconds when no files found
- Multiply by 1.5 each empty poll
- Cap at 30 seconds maximum
- Reset to 2 seconds when files are found
- Detect file completion by stable size over multiple polls

## Error Handling

### Retry Logic
1. Move file to processing folder
2. Execute handler with timeout
3. On failure, retry up to `max_retries` with exponential backoff
4. On final failure, move to errors folder with error report

### Error Report Format
```
Error processing file: document.pdf
Timestamp: 2025-01-15T10:30:00Z
Attempts: 3
Final Error: {:error, :invalid_format}
Handler: MyApp.ProcessFile.handle/1
HotFolder: #PID<0.123.0>

Error History:
Attempt 1 (2025-01-15T10:29:30Z): {:error, :network_timeout}  
Attempt 2 (2025-01-15T10:29:45Z): {:error, :invalid_format}
Attempt 3 (2025-01-15T10:30:00Z): {:error, :invalid_format}
```

## Uniqueness Validation

Multiple HotFolder instances cannot watch the same URL with overlapping filters:

```elixir
# This would conflict:
HotFolder.start_link(url: "smb://server/folder", name_patterns: [~r/\.pdf$/])
HotFolder.start_link(url: "smb://server/folder", name_patterns: [~r/\.PDF$/i])

# This would be allowed:
HotFolder.start_link(url: "smb://server/folder", name_patterns: [~r/\.pdf$/])
HotFolder.start_link(url: "smb://server/folder", name_patterns: [~r/\.jpg$/])
```

## Implementation Phases

### Phase 1: Core GenServer & Basic Polling
- `Sambex.HotFolder` GenServer with connection management
- Basic directory polling and file detection
- Simple file moving between folders

### Phase 2: Filtering & Configuration  
- `Sambex.HotFolder.Config` validation
- `Sambex.HotFolder.FileFilter` implementation
- Name pattern and size filtering

### Phase 3: Handler Execution & Error Handling
- Safe handler execution with timeouts
- Retry logic with exponential backoff  
- Error report generation

### Phase 4: Advanced Features
- MIME type detection (using file headers)
- Folder auto-creation
- Comprehensive telemetry

### Phase 5: Testing & Documentation
- Unit tests for all components
- Integration tests with mock SMB server
- Usage guides and examples

## Telemetry Events

```elixir
:telemetry.execute([:sambex, :hot_folder, :file_processed], %{duration: duration}, metadata)
:telemetry.execute([:sambex, :hot_folder, :file_failed], %{attempts: 3}, metadata)
:telemetry.execute([:sambex, :hot_folder, :poll_completed], %{files_found: 5}, metadata)
```

## Connection Management

The HotFolder supports two connection modes:

1. **Managed Connection**: HotFolder creates and manages its own connection
2. **Reused Connection**: HotFolder uses an existing named connection from the registry

This flexibility allows for both simple standalone usage and integration with existing connection management strategies.

## Success Criteria

- ✅ Sequential, deterministic file processing
- ✅ Robust error handling with detailed reporting  
- ✅ Efficient polling with smart backoff
- ✅ Rich filtering capabilities
- ✅ Flexible connection management
- ✅ Auto-creation of folder structure
- ✅ Comprehensive monitoring and observability
- ✅ Easy integration with existing Sambex infrastructure