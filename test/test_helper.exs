# Configure ExUnit
ExUnit.start()

# Set default timeout for integration tests
ExUnit.configure(timeout: 60_000)

# Helper function to check if SMB server is available
defmodule TestHelper do
  def smb_server_available? do
    if System.get_env("CI") == "true" do
      # In CI, check if SMB port is open
      case System.cmd("nc", ["-z", "localhost", "445"]) do
        {_, 0} -> true
        _ -> false
      end
    else
      # Local development - check Docker container
      case System.cmd("docker", [
             "ps",
             "--filter",
             "name=sambex-samba-1",
             "--format",
             "{{.Status}}"
           ]) do
        {"Up " <> _, 0} -> true
        _ -> false
      end
    end
  rescue
    _ -> false
  end

  def ensure_smb_server! do
    unless smb_server_available?() do
      if System.get_env("CI") == "true" do
        IO.puts("Warning: SMB server not detected in CI environment")
      else
        raise """
        SMB server is not running!
        Please start it with: docker-compose up -d
        """
      end
    end
  end

  def wait_for_smb_server(timeout \\ 30_000) do
    start_time = System.monotonic_time(:millisecond)

    do_wait_for_server(start_time, timeout)
  end

  defp do_wait_for_server(start_time, timeout) do
    if System.monotonic_time(:millisecond) - start_time > timeout do
      false
    else
      if smb_server_available?() do
        true
      else
        Process.sleep(1000)
        do_wait_for_server(start_time, timeout)
      end
    end
  end
end

# Ensure SMB server is running before integration tests
unless System.get_env("SKIP_INTEGRATION") == "true" do
  if System.get_env("CI") == "true" do
    # In CI, wait for SMB server to be ready
    if TestHelper.wait_for_smb_server(60_000) do
      IO.puts("SMB server detected in CI environment")
    else
      IO.puts("Warning: SMB server not ready in CI - integration tests may fail")
    end
  else
    # Local development - require server to be running
    TestHelper.ensure_smb_server!()
  end
end
