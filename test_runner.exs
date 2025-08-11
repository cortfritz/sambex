#!/usr/bin/env elixir

# Sambex Test Runner
# Demonstrates all testing capabilities of the SMB client library

defmodule TestRunner do
  @moduledoc """
  Comprehensive test runner for Sambex SMB client library.

  This script demonstrates how to run different types of tests and provides
  a convenient way to verify that all functionality is working correctly.
  """

  def main(args \\ []) do
    IO.puts("""
    ╔══════════════════════════════════════════════════════════════╗
    ║                    SAMBEX TEST RUNNER                        ║
    ║              SMB Client Library Test Suite                   ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    case args do
      ["--help"] -> show_help()
      ["--unit"] -> run_unit_tests()
      ["--integration"] -> run_integration_tests()
      ["--all"] -> run_all_tests()
      ["--coverage"] -> run_coverage_tests()
      ["--check-server"] -> check_smb_server()
      [] -> interactive_menu()
      _ -> show_help()
    end
  end

  defp interactive_menu do
    IO.puts("Select test type to run:")
    IO.puts("1. Unit Tests (fast, no SMB server required)")
    IO.puts("2. Integration Tests (requires SMB server)")
    IO.puts("3. All Tests")
    IO.puts("4. Coverage Report")
    IO.puts("5. Check SMB Server Status")
    IO.puts("6. Help")
    IO.puts("0. Exit")
    IO.write("\nEnter your choice (0-6): ")

    case IO.read(:line) |> String.trim() do
      "1" ->
        run_unit_tests()

      "2" ->
        run_integration_tests()

      "3" ->
        run_all_tests()

      "4" ->
        run_coverage_tests()

      "5" ->
        check_smb_server()

      "6" ->
        show_help()

      "0" ->
        IO.puts("Goodbye!")

      _ ->
        IO.puts("Invalid choice. Please try again.\n")
        interactive_menu()
    end
  end

  defp show_help do
    IO.puts("""
    Sambex Test Runner - Usage:

    Options:
      --unit          Run unit tests only (fast, no dependencies)
      --integration   Run integration tests (requires SMB server)
      --all           Run all tests
      --coverage      Run tests with coverage report
      --check-server  Check if SMB server is running
      --help          Show this help

    Examples:
      ./test_runner.exs --unit
      ./test_runner.exs --integration
      ./test_runner.exs --all

    Prerequisites for Integration Tests:
      1. Docker and Docker Compose installed
      2. SMB server running: docker-compose up -d
      3. Ports 139 and 445 available

    Test Structure:
      • Unit Tests: Basic module functionality, no external dependencies
      • Integration Tests: Full SMB operations against real server
      • Coverage: Detailed code coverage analysis

    For CI/CD:
      Use --unit for fast feedback
      Use --integration for full verification
    """)
  end

  defp run_unit_tests do
    print_section("UNIT TESTS")
    IO.puts("Running unit tests (no SMB server required)...")
    IO.puts("These tests verify module structure, function exports, and basic validation.\n")

    {_output, exit_code} = run_mix_command(["test", "--exclude", "integration"])

    if exit_code == 0 do
      IO.puts("\n✅ Unit tests PASSED!")
      IO.puts("All basic functionality is working correctly.")
    else
      IO.puts("\n❌ Unit tests FAILED!")
      IO.puts("Check the output above for details.")
    end

    print_divider()
  end

  defp run_integration_tests do
    print_section("INTEGRATION TESTS")

    unless check_smb_server_quiet() do
      IO.puts("❌ SMB server is not running!")
      IO.puts("Please start it with: docker-compose up -d")
      IO.puts("Then wait a few seconds for it to initialize.")
      :return
    end

    IO.puts("✅ SMB server is running")
    IO.puts("Running integration tests against real SMB server...")
    IO.puts("These tests verify complete file operations: create, read, write, delete.\n")

    {_output, exit_code} = run_mix_command(["test", "--only", "integration"])

    if exit_code == 0 do
      IO.puts("\n🎉 Integration tests PASSED!")
      IO.puts("All SMB operations are working correctly, including file deletion!")
    else
      IO.puts("\n❌ Integration tests FAILED!")
      IO.puts("Check the SMB server status and try again.")
    end

    print_divider()
  end

  defp run_all_tests do
    print_section("ALL TESTS")

    unless check_smb_server_quiet() do
      IO.puts("⚠️  SMB server is not running - integration tests will be skipped")
      IO.puts("To run full tests: docker-compose up -d")
      IO.puts("\nRunning unit tests only...\n")
      run_unit_tests()
      :return
    end

    IO.puts("✅ SMB server is running")
    IO.puts("Running complete test suite (unit + integration)...\n")

    {_output, exit_code} = run_mix_command(["test"])

    if exit_code == 0 do
      IO.puts("\n🚀 ALL TESTS PASSED!")
      IO.puts("Sambex SMB client is fully functional!")
      print_success_summary()
    else
      IO.puts("\n❌ Some tests FAILED!")
      IO.puts("Check the output above for details.")
    end

    print_divider()
  end

  defp run_coverage_tests do
    print_section("COVERAGE REPORT")
    IO.puts("Generating test coverage report...\n")

    {_output, exit_code} = run_mix_command(["test", "--cover"])

    if exit_code == 0 do
      IO.puts("\n📊 Coverage report generated successfully!")
      IO.puts("Check the coverage/ directory for detailed HTML reports.")
    else
      IO.puts("\n❌ Coverage generation failed!")
    end

    print_divider()
  end

  defp check_smb_server do
    print_section("SMB SERVER STATUS")

    if check_smb_server_quiet() do
      IO.puts("✅ SMB server is running correctly")
      print_server_info()
    else
      IO.puts("❌ SMB server is not running")
      print_server_setup_help()
    end

    print_divider()
  end

  defp check_smb_server_quiet do
    case System.cmd("docker", ["ps", "--filter", "name=sambex-samba-1", "--format", "{{.Status}}"]) do
      {"Up " <> _, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp print_server_info do
    IO.puts("\nServer Configuration:")
    IO.puts("• Host: localhost")
    IO.puts("• Ports: 139, 445")
    IO.puts("• Public Share: smb://localhost:445/public")
    IO.puts("  - Username: example1")
    IO.puts("  - Password: badpass")
    IO.puts("• Private Share: smb://localhost:445/private")
    IO.puts("  - Username: example2")
    IO.puts("  - Password: badpass")

    IO.puts("\nTest Connection:")
    IO.puts("smbclient //localhost/public -U example1%badpass -c 'ls'")
  end

  defp print_server_setup_help do
    IO.puts("\nTo start the SMB server:")
    IO.puts("1. Make sure Docker is running")
    IO.puts("2. Run: docker-compose up -d")
    IO.puts("3. Wait 5-10 seconds for initialization")
    IO.puts("4. Verify: docker ps")

    IO.puts("\nIf you encounter issues:")
    IO.puts("• Check if ports 139/445 are already in use")
    IO.puts("• Try: docker-compose down && docker-compose up -d")
    IO.puts("• Check Docker logs: docker-compose logs samba")
  end

  defp print_success_summary do
    IO.puts("""

    🎯 SAMBEX FUNCTIONALITY VERIFIED:
    ═══════════════════════════════════
    ✅ SMB Connection & Authentication
    ✅ Directory Listing
    ✅ File Creation & Writing
    ✅ File Reading
    ✅ File Deletion (WORKING!)
    ✅ Error Handling
    ✅ Multiple Share Support
    ✅ Binary & Unicode Content
    ✅ Large File Operations

    Your SMB client is ready for production use!
    """)
  end

  defp run_mix_command(args) do
    System.cmd("mix", args, stderr_to_stdout: true, into: IO.stream(:stdio, :line))
  end

  defp print_section(title) do
    IO.puts("\n" <> String.duplicate("=", 60))
    IO.puts("  #{title}")
    IO.puts(String.duplicate("=", 60))
  end

  defp print_divider do
    IO.puts(String.duplicate("-", 60))
  end
end

# Run the test runner with command line arguments
TestRunner.main(System.argv())
