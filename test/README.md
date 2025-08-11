# Sambex Testing Guide

This document explains how to run the various tests for the Sambex SMB client library.

## Test Structure

The test suite is organized into two main categories:

### Unit Tests (`sambex_test.exs`)
- Tests basic module functionality without requiring external dependencies
- Tests function exports, documentation, and error handling
- Can be run without the SMB server running
- Fast and suitable for CI/CD pipelines

### Integration Tests (`sambex_integration_test.exs`)
- Tests complete SMB operations against a real SMB server
- Requires Docker and the SMB server to be running
- Tagged with `@moduletag :integration`
- Tests file creation, reading, writing, deletion, and directory operations

## Prerequisites

### For Unit Tests
- Elixir and Mix installed
- Compiled Sambex library

### For Integration Tests
- Docker and Docker Compose installed
- SMB server running (see setup instructions below)

## Running Tests

### Run All Tests
```bash
mix test
```

### Run Only Unit Tests
```bash
mix test --exclude integration
```

### Run Only Integration Tests
```bash
mix test --only integration
```

### Run Specific Test File
```bash
# Unit tests only
mix test test/sambex_test.exs

# Integration tests only
mix test test/sambex_integration_test.exs
```

### Run Specific Test
```bash
mix test test/sambex_integration_test.exs -t "delete_file/3 successfully deletes existing file"
```

## SMB Server Setup

The integration tests require a running SMB server. Use the provided Docker Compose configuration:

### Start SMB Server
```bash
docker-compose up -d
```

### Check SMB Server Status
```bash
docker-compose ps
```

### Stop SMB Server
```bash
docker-compose down
```

### SMB Server Configuration
The test server provides two shares:
- **public**: Accessible with username `example1` and password `badpass`
- **private**: Accessible with username `example2` and password `badpass`

## Environment Variables

### Skip Integration Tests
If you want to run tests without starting the SMB server:
```bash
SKIP_INTEGRATION=true mix test
```

### Test Timeout
Integration tests have a default timeout of 60 seconds. You can adjust this:
```bash
mix test --timeout 120000  # 2 minutes
```

## Test Coverage

### Generate Coverage Report
```bash
mix test --cover
```

### Detailed Coverage
```bash
MIX_ENV=test mix coveralls
MIX_ENV=test mix coveralls.html
```

## Troubleshooting

### SMB Server Not Running
If you see errors about SMB server not being available:
1. Make sure Docker is running
2. Start the SMB server: `docker-compose up -d`
3. Wait a few seconds for the server to fully start
4. Check server status: `docker ps`

### Permission Errors
If you encounter permission errors:
1. Make sure the Docker volumes have correct permissions
2. Try rebuilding the SMB server: `docker-compose down && docker-compose up -d`

### Connection Errors
If SMB connections fail:
1. Verify the server is listening on ports 139 and 445: `docker-compose ps`
2. Check if another SMB service is using those ports
3. Try connecting manually: `smbclient //localhost/public -U example1%badpass`

### Compilation Errors
If Zig/NIF compilation fails:
1. Make sure you have the required dependencies installed (see main README)
2. Clean and recompile: `mix clean && mix compile`
3. Check that libsmbclient is properly installed

## Test Data

### Temporary Files
Integration tests create temporary files with unique timestamps to avoid conflicts. These files are automatically cleaned up after each test.

### Test Isolation
Each integration test runs in isolation with its own test files to prevent interference between tests.

## Continuous Integration

### GitHub Actions Example
```yaml
name: Test
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    services:
      samba:
        image: dperson/samba
        ports:
          - 139:139
          - 445:445
        options: >-
          --health-cmd "smbclient -L localhost -N"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test --exclude integration  # Unit tests only
      - run: mix test --only integration     # Integration tests
```

## Writing New Tests

### Unit Test Guidelines
- Test function behavior without external dependencies
- Focus on error handling and edge cases
- Keep tests fast and deterministic

### Integration Test Guidelines
- Test complete workflows
- Use unique filenames (include timestamps)
- Always clean up created files
- Test both success and failure scenarios
- Use descriptive test names

### Test Naming Convention
```elixir
test "function_name/arity does something under specific condition" do
  # Test implementation
end
```

## Performance Testing

For performance testing, you can use the provided benchmark scripts:
```bash
# Run basic performance test
mix run final_test.exs

# Time specific operations
time mix test test/sambex_integration_test.exs -t "handles large content"
```
