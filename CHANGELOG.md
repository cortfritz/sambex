# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
