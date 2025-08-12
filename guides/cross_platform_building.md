# Cross-Platform Building

Sambex now supports automatic detection of libsmbclient installation paths across different platforms and environments.

## Automatic Detection

Sambex automatically detects the Samba library installation on:

- **macOS**: Homebrew (both Intel and Apple Silicon), MacPorts, system paths
- **Linux**: System packages (Debian/Ubuntu, RHEL/CentOS/Fedora), custom installations  
- **Docker/Alpine**: Package manager installations
- **Other Unix systems**: Standard system paths

## Platform-Specific Installation

### macOS

```bash
# Install via Homebrew (recommended)
brew install samba

# Or via MacPorts
sudo port install samba4
```

### Ubuntu/Debian

```bash
# Install development libraries
sudo apt-get update
sudo apt-get install libsmbclient-dev

# For older versions, you might need:
sudo apt-get install samba-dev
```

### RHEL/CentOS/Fedora

```bash
# Fedora/newer CentOS
sudo dnf install libsmbclient-devel

# Older CentOS/RHEL
sudo yum install libsmbclient-devel
```

### Alpine Linux (Docker)

```bash
# Install development package
apk add --no-cache samba-dev
```

### Arch Linux

```bash
# Install samba package (includes development headers)
sudo pacman -S samba
```

## Custom Installation Paths

If you have Samba installed in a non-standard location, set these environment variables:

```bash
export SAMBEX_INCLUDE_DIR=/path/to/samba/include
export SAMBEX_LIB_DIR=/path/to/samba/lib
```

## Docker Support

### Using Alpine Linux (smallest image)

```dockerfile
FROM elixir:1.18-alpine

# Install Samba development libraries
RUN apk add --no-cache build-base samba-dev

# Your application setup
WORKDIR /app
COPY . .
RUN mix deps.get && mix compile
```

### Using Ubuntu

```dockerfile
FROM elixir:1.18

# Install Samba development libraries
RUN apt-get update && \
    apt-get install -y libsmbclient-dev && \
    rm -rf /var/lib/apt/lists/*

# Your application setup
WORKDIR /app
COPY . .
RUN mix deps.get && mix compile
```

### Testing with Docker

You can test Sambex compilation in a clean environment:

```bash
# Test with Alpine Linux
docker build -f Dockerfile.test -t sambex-test .

# Or test manually
docker run --rm -v $(pwd):/app -w /app elixir:1.18-alpine sh -c '
  apk add --no-cache build-base samba-dev &&
  mix local.hex --force &&
  mix local.rebar --force &&
  mix deps.get &&
  mix compile
'
```

## CI/CD Integration

### GitHub Actions

```yaml
name: Test Sambex

on: [push, pull_request]

jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, macos-latest]
        elixir: [1.17, 1.18]
        otp: [26, 27]
    
    runs-on: ${{ matrix.os }}
    
    steps:
    - uses: actions/checkout@v4
    
    - name: Install Samba (Ubuntu)
      if: matrix.os == 'ubuntu-latest'
      run: sudo apt-get update && sudo apt-get install -y libsmbclient-dev
    
    - name: Install Samba (macOS)
      if: matrix.os == 'macos-latest'
      run: brew install samba
    
    - name: Setup Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}
    
    - name: Install dependencies
      run: mix deps.get
    
    - name: Compile
      run: mix compile
    
    - name: Run tests
      run: mix test
```

### GitLab CI

```yaml
stages:
  - test

variables:
  MIX_ENV: test

.test_template: &test_template
  stage: test
  before_script:
    - mix local.hex --force
    - mix local.rebar --force
    - mix deps.get
  script:
    - mix compile
    - mix test

test:ubuntu:
  <<: *test_template
  image: elixir:1.18
  before_script:
    - apt-get update && apt-get install -y libsmbclient-dev
    - mix local.hex --force
    - mix local.rebar --force
    - mix deps.get

test:alpine:
  <<: *test_template
  image: elixir:1.18-alpine
  before_script:
    - apk add --no-cache build-base samba-dev
    - mix local.hex --force
    - mix local.rebar --force
    - mix deps.get
```

## Troubleshooting

### Library Not Found

If you get errors like "libsmbclient not found":

1. **Check if Samba is installed**:
   ```bash
   # On most systems
   find /usr -name "libsmbclient.h" 2>/dev/null
   find /opt -name "libsmbclient.h" 2>/dev/null
   
   # Check for the library
   find /usr -name "*smbclient*" 2>/dev/null
   ```

2. **Install the development package** (not just the runtime):
   - Make sure you install `-dev` or `-devel` packages
   - On some systems, you need `samba-dev` instead of `libsmbclient-dev`

3. **Set environment variables** for custom installations:
   ```bash
   export SAMBEX_INCLUDE_DIR=/custom/path/include
   export SAMBEX_LIB_DIR=/custom/path/lib
   ```

### Docker Build Issues

1. **Make sure to install build tools**:
   ```dockerfile
   # Alpine
   RUN apk add --no-cache build-base samba-dev
   
   # Ubuntu/Debian
   RUN apt-get update && apt-get install -y build-essential libsmbclient-dev
   ```

2. **Check the build output** for auto-detection messages:
   ```
   Found Samba in system paths (Debian/Ubuntu)
   ```

### Version Conflicts

If you have multiple Samba versions installed:

1. **Use environment variables** to specify the correct version:
   ```bash
   export SAMBEX_INCLUDE_DIR=/usr/include/samba-4.0
   export SAMBEX_LIB_DIR=/usr/lib/x86_64-linux-gnu
   ```

2. **Check pkg-config** (on Linux):
   ```bash
   pkg-config --cflags --libs smbclient
   ```

## Platform-Specific Notes

### macOS

- Homebrew installs are automatically detected for both Intel and Apple Silicon
- The system automatically finds the latest Samba version installed
- If you have both Homebrew and MacPorts, Homebrew takes precedence

### Linux

- Most distributions package `libsmbclient-dev` or similar
- RHEL/CentOS may use `samba-4.0` include paths
- Alpine Linux uses `samba-dev` package

### Windows (WSL)

Sambex works in WSL with Linux packages:

```bash
# In WSL Ubuntu
sudo apt-get install libsmbclient-dev
```

## Build Verification

To verify your build setup:

```bash
# Clean and rebuild
mix clean
mix compile

# You should see auto-detection messages like:
# Found Samba via Homebrew (Apple Silicon)
# Found Samba in system paths (Debian/Ubuntu)
```

The build system will automatically detect and use the appropriate paths for your platform.