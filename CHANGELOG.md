# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2025-08-12

### Added

- **Hot Folders**: Monitor directories for changes and trigger actions on file events
  - `Sambex.HotFolder` GenServer for monitoring directories
  - `Sambex.HotFolderSupervisor` for managing hot folder processes
  - Named hot folders via Registry for easy reference to multiple folders
  - Anonymous hot folders for simple use cases
  - Hot folder pooling and lifecycle management
  - Automatic supervision and fault tolerance

## [0.2.0] - 2025-08-12

### Added

- **Connection-based API**: New GenServer-based connection management for more idiomatic Elixir usage
  - `Sambex.Connection` GenServer for persistent SMB connections
  - `Sambex.ConnectionSupervisor` for managing connection processes
  - Named connections via Registry for easy reference to multiple shares
  - Anonymous connections for simple use cases
  - Connection pooling and lifecycle management
  - Automatic supervision and fault tolerance

### Features

#### Connection Management
- **Named Connections**: Register connections with atoms for easy reference
  ```elixir
  {:ok, _} = Sambex.Connection.start_link(
    url: "smb://server/share",
    username: "user",
    password: "pass",
    name: :main_share
  )
  Sambex.Connection.list_dir(:main_share, "/")
  ```

- **Anonymous Connections**: Simple connection creation without names
  ```elixir
  {:ok, conn} = Sambex.Connection.connect("smb://server/share", "user", "pass")
  Sambex.Connection.read_file(conn, "/file.txt")
  ```

- **Supervised Connections**: Full OTP supervision tree integration
  ```elixir
  {:ok, conn} = Sambex.ConnectionSupervisor.start_connection(
    url: "smb://server/share",
    username: "user",
    password: "pass",
    name: :supervised_share
  )
  ```

#### API Improvements
- All existing SMB operations now available through connections:
  - `Sambex.Connection.list_dir/2`
  - `Sambex.Connection.read_file/2`
  - `Sambex.Connection.write_file/3`
  - `Sambex.Connection.delete_file/2`
  - `Sambex.Connection.move_file/3`
  - `Sambex.Connection.get_file_stats/2`
  - `Sambex.Connection.upload_file/3`
  - `Sambex.Connection.download_file/3`

- Connection management functions:
  - `Sambex.Connection.disconnect/1`
  - `Sambex.ConnectionSupervisor.list_connections/0`
  - `Sambex.ConnectionSupervisor.stop_connection/1`

### Benefits

- **Security**: Credentials stored in GenServer state, not passed on every operation
- **Performance**: Connection reuse and persistent state
- **Fault Tolerance**: OTP supervision ensures connections can be restarted
- **Multiple Shares**: Easy management of connections to different SMB shares
- **Elixir Idioms**: Follows OTP patterns and Elixir best practices

### Documentation

- Updated module documentation with both API usage patterns
- Added comprehensive examples for connection-based API
- Migration guide from direct API to connection API
- Complete function documentation for all new modules

### Testing

- **69 total tests** with comprehensive coverage of new connection API
- Tests for anonymous and named connections
- Supervisor behavior verification
- Registry integration testing
- Function export and documentation validation
- Fixed segfault issues in test suite

### Backwards Compatibility

- **100% backwards compatible** - all existing code continues to work unchanged
- Original direct API (`Sambex.list_dir/3`, etc.) remains fully functional
- No breaking changes to existing function signatures
- Existing applications can migrate incrementally

### Technical Implementation

- **OTP Application**: `Sambex.Application` starts supervision tree automatically
- **Registry**: Named connection management via `Sambex.Registry`
- **Dynamic Supervisor**: `Sambex.DynamicConnectionSupervisor` for connection processes
- **GenServer**: `Sambex.Connection` manages individual SMB connection state
- **URL Building**: Automatic path resolution for connection-relative operations

## [0.1.1]

### Added

- **File Statistics/Metadata Functionality**: Added `get_file_stats/3` function to get file metadata from SMB shares
  - Returns comprehensive file information including size, type, permissions, timestamps
  - Supports both files and directories
  - Cross-platform compatibility (macOS stat structure handling)
  - Proper error handling for non-existent files and authentication failures
  - Comprehensive test coverage with 8 new integration tests

### Changed

- Updated README.md to include file stats documentation
- Updated roadmap to reflect completed file stats feature

### Technical Details
- Added `get_file_stats` function to Sambex.Nif module using `smbc_stat` from libsmbclient
- Added corresponding Elixir wrappers with automatic data conversion
- Enhanced sys/stat.h support for cross-platform compatibility
- All tests pass (46 total tests, 0 failures)

## [0.1.0]

### Added
- **Move/Rename File Functionality**: Added `move_file/4` function to move or rename files on SMB shares
  - Supports renaming files within the same directory
  - Supports moving files between directories on the same share
  - Handles overwriting existing destination files
  - Proper error handling for non-existent files and authentication failures
  - Comprehensive test coverage with 5 new integration tests

### Changed
- Updated README.md to include move/rename functionality documentation
- Updated roadmap to reflect completed move/rename feature

### Technical Details
- Added `move_file` function to Sambex.Nif module using `smbc_rename` from libsmbclient
- Added corresponding Elixir wrapper in main Sambex module
- Maintains consistent error handling patterns with existing functions
- All tests pass (38 total tests, 0 failures)

## [0.1.0-alpha2] - Previous Release

### Added
- Complete SMB operations support
- File deletion functionality (fixed VFS module issues)
- Comprehensive test suite with 33 tests
- CI/CD pipeline with GitHub Actions
- Docker-based test environment
- Code quality tools (Credo, ExCoveralls, Dialyxir)

### Features
- Connect to SMB shares with authentication
- List directory contents
- Read files from SMB shares
- Write/create files on SMB shares
- Delete files from SMB shares
- Upload local files to SMB shares
- Download files from SMB shares

### Technical Implementation
- Written in Zig with Elixir NIF interface
- Proper error handling and context management
- Support for binary and Unicode content
- Large file operations
- Multiple share support
- Robust testing infrastructure

### Testing
- Unit tests for module structure and function exports
- Integration tests against real SMB server
- File statistics and metadata validation tests
- File move/rename operation tests
- Error handling tests for edge cases
- Performance tests for large files
- Unicode and binary content tests

### CI/CD
- Multi-version testing (Elixir 1.17-1.18 × OTP 26-27)
- Automated code quality checks
- Test coverage reporting
- Docker-based integration testing
