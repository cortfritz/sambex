# Sambex CI/CD Pipeline

This document describes the continuous integration and deployment setup for the Sambex SMB client library.

## Overview

Sambex uses GitHub Actions to provide comprehensive automated testing, code quality checks, and release verification. The CI/CD pipeline ensures that all changes maintain the high quality and reliability of the SMB client functionality.

## Workflows

### Primary CI Workflow (`ci.yml`)

**Triggers**: Push and Pull Requests to `main`, `master`, `develop` branches

**Jobs**:
- **Multi-version Testing**: Tests across Elixir 1.17-1.18 and OTP 26-27
- **Unit Tests**: Fast tests without external dependencies
- **Integration Tests**: Full SMB operations against Docker Samba server
- **Code Quality**: Formatting, Credo analysis, dependency audit
- **Coverage**: Test coverage reporting with ExCoveralls
- **Release Build**: Production build verification

### Comprehensive Test Workflow (`test.yml`)

**More detailed pipeline with separate jobs**:
- Isolated unit test execution
- Dedicated integration testing with SMB server setup
- Detailed coverage analysis
- Code quality checks (Credo, Dialyzer)
- Release verification

## Test Environment

### SMB Server Configuration

The CI automatically sets up a Docker-based Samba server with:

```yaml
services:
  samba:
    image: dperson/samba
    ports: [139:139, 445:445]
```

**Test Shares**:
- `public`: Username `example1`, password `badpass`
- `private`: Username `example2`, password `badpass`

**Key Configuration**:
- VFS objects disabled to allow file deletion
- Proper permissions for all file operations
- Health checks to ensure server readiness

### Dependencies

**System Requirements**:
- `libsmbclient-dev`: SMB client library
- `smbclient`: Command-line SMB client for testing
- `build-essential`: Compilation tools for Zig NIFs

**Elixir Dependencies**:
- Testing: ExUnit, ExCoveralls
- Quality: Credo, Dialyxir, mix_audit
- Documentation: ExDoc

## Quality Gates

All code must pass these checks:

### 🧪 Testing
- ✅ All unit tests pass (33 tests)
- ✅ All integration tests pass (22 tests)
- ✅ Test coverage maintained
- ✅ No test timeouts or flaky tests

### 📝 Code Quality
- ✅ Code formatting (`mix format --check-formatted`)
- ✅ No compiler warnings (`mix compile --warnings-as-errors`)
- ✅ Credo static analysis (`mix credo --strict`)
- ✅ Dependency security audit (`mix deps.audit`)

### 🔧 Build Verification
- ✅ Production compilation succeeds
- ✅ Documentation generation works
- ✅ Hex package builds correctly

## Running Locally

### Prerequisites
```bash
# Start SMB server
docker-compose up -d

# Install dependencies
mix deps.get
```

### Full CI Simulation
```bash
# All quality checks
mix format --check-formatted
mix compile --warnings-as-errors
mix credo --strict
mix deps.audit

# All tests
mix test --exclude integration  # Unit tests
mix test --only integration     # Integration tests
mix test                        # All tests

# Coverage and docs
mix test --cover
mix docs
```

### Quick Development Cycle
```bash
# Fast feedback loop
mix test --exclude integration
mix format
mix credo
```

## Branch Protection

**Main branches** (`main`, `master`, `develop`) are protected with:
- ✅ Require pull request reviews
- ✅ Require status checks to pass
- ✅ Require branches to be up to date
- ✅ Require conversation resolution

## Coverage Reporting

Test coverage is automatically tracked and reported:
- **Target**: Maintain >80% test coverage
- **Reports**: Generated on every push
- **Trends**: Coverage changes shown in PRs

## Performance Monitoring

CI tracks performance metrics:
- **Test execution time**: Monitor for regressions
- **Compilation time**: Track build performance
- **Memory usage**: SMB operations efficiency

## Failure Handling

### Common Issues and Solutions

**SMB Server Connection Failures**:
- CI waits up to 60 seconds for server startup
- Automatic retry with exponential backoff
- Graceful degradation to unit tests only

**Flaky Tests**:
- Each test uses unique timestamps to avoid conflicts
- Proper cleanup after each test
- Isolation between test runs

**Build Failures**:
- Clear error reporting in CI logs
- Automatic artifact collection for debugging
- Notifications to maintainers

## Contributing

### PR Requirements
- [ ] All CI checks pass
- [ ] No decrease in test coverage
- [ ] Code follows style guide
- [ ] Documentation updated
- [ ] Breaking changes documented

### Development Workflow
1. Create feature branch
2. Make changes with tests
3. Run local CI simulation
4. Submit PR
5. Address CI feedback
6. Merge after approval

## Monitoring and Alerts

**Success Metrics**:
- ✅ All tests passing
- ✅ Coverage maintained
- ✅ No security vulnerabilities
- ✅ Fast build times (<5 minutes)

**Alerting**:
- Failed builds notify maintainers
- Coverage drops trigger warnings
- Security issues create urgent alerts

## Release Process

**Automated Checks on Main**:
- Full test suite execution
- Release build verification
- Documentation updates
- Hex package preparation

**Manual Release Steps**:
1. Update version in `mix.exs`
2. Update `CHANGELOG.md`
3. Create release tag
4. Publish to Hex.pm

## Security

**Dependency Scanning**:
- `mix_audit` checks for known vulnerabilities
- Automated dependency updates via Dependabot
- Regular security reviews

**Secrets Management**:
- No hardcoded credentials
- GitHub secrets for sensitive data
- Minimal permission principle

## Future Enhancements

**Planned Improvements**:
- [ ] Performance benchmarking
- [ ] Cross-platform testing (Windows, macOS)
- [ ] Integration with external SMB servers
- [ ] Automated release deployment
- [ ] Advanced security scanning

---

For questions about the CI/CD setup, please open an issue or check the workflow files in `.github/workflows/`.