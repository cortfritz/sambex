# Sambex

Sambex is a library for interacting with SMB (Server Message Block) shares in Elixir.

## Questions

Because a little role-play solves many problems.

```text
Q: Is it any good?
A: Yes! File deletion is now working and all tests pass.

Q: Should you install it?
A: Yes! The SMB client is fully functional with comprehensive tests.

Q: I used this in production and everything went wrong.
A: Thanks for doing QA - please report any issues on GitHub.
```

## Features

✅ **Complete SMB Operations**
- Connect to SMB shares with authentication
- List directory contents
- Read files from SMB shares
- Write/create files on SMB shares
- **Delete files from SMB shares** (now working!)
- Upload local files to SMB shares
- Download files from SMB shares

✅ **Robust Implementation**
- Written in Zig with Elixir NIF interface
- Proper error handling and context management
- Support for binary and Unicode content
- Large file operations
- Multiple share support

✅ **Comprehensive Testing**
- Unit tests for basic functionality
- Integration tests against real SMB server
- 33 tests covering all operations
- Docker-based test environment

## Installation

Sambex can be installed by adding `sambex` to your list of dependencies
in `mix.exs`:

```elixir
def deps do
  [
    {:sambex, "~> 0.1.0-alpha2"}
  ]
end
```

## Usage

You must ensure to initialize the library before using it.

```elixir
iex> Sambex.init()
:ok
```

Then you can use the library to interact with SMB shares.

```elixir
iex> Sambex.list_dir("smb://localhost:445/private", "example2", "badpass")
{:ok, ["thing", "thing2"]}

iex> Sambex.read_file("smb://localhost:445/private/thing", "example2", "badpass")
{:ok, "thing\n"}

iex> Sambex.write_file("smb://localhost:445/private/thing2", "some content", "example2", "badpass")
{:ok, 12}
```

## Testing

Sambex includes a comprehensive test suite with both unit and integration tests.

### Quick Start

```bash
# Run all tests
mix test

# Run only unit tests (fast, no dependencies)
mix test --exclude integration

# Run only integration tests (requires SMB server)
mix test --only integration
```

### Test Runner

Use the interactive test runner for a better experience:

```bash
./test_runner.exs --help
./test_runner.exs --unit
./test_runner.exs --integration
./test_runner.exs --all
```

### Test Environment

The integration tests require a Docker-based SMB server:

```bash
# Start test SMB server
docker-compose up -d

# Run integration tests
mix test --only integration

# Stop test server
docker-compose down
```

### Test Coverage

- **33 total tests** covering all functionality
- **Unit tests**: Module structure, function exports, validation
- **Integration tests**: Complete file operations against real SMB server
- **Error handling**: Wrong credentials, non-existent files, network issues
- **Edge cases**: Empty files, large files, Unicode content, binary data

For detailed testing information, see [test/README.md](test/README.md).

## Roadmap

### ✅ Completed Features
- [x] Connect to SMB shares
- [x] List directory contents  
- [x] Read files
- [x] Write/create files
- [x] Delete files
- [x] Upload local files
- [x] Download files
- [x] Authentication support
- [x] Multiple share support
- [x] Comprehensive testing

### 🚧 Future Features
- [ ] Create directory
- [ ] Rename directory
- [ ] Delete directory
- [ ] Rename file
- [ ] Get file info/metadata
- [ ] Set file permissions
- [ ] Symbolic link support
