# Configure ExUnit
ExUnit.start()

# Set default timeout for integration tests
ExUnit.configure(timeout: 60_000)

# Helper function to check if SMB server is available
defmodule TestHelper do
  def smb_server_available? do
    case System.cmd("docker", ["ps", "--filter", "name=sambex-samba-1", "--format", "{{.Status}}"]) do
      {"Up " <> _, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  def ensure_smb_server! do
    unless smb_server_available?() do
      raise """
      SMB server is not running!
      Please start it with: docker-compose up -d
      """
    end
  end
end

# Ensure SMB server is running before integration tests
if System.get_env("SKIP_INTEGRATION") != "true" do
  TestHelper.ensure_smb_server!()
end
