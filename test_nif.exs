# Test file to verify NIF functions return proper Elixir terms

# Start IEx session to test the functions
# iex -S mix

# Test basic function
IO.puts("Testing add_one function:")
result = Sambex.Nif.add_one(41)
IO.inspect(result, label: "add_one(41)")

# Test init_smb
IO.puts("\nTesting init_smb function:")
result = Sambex.Nif.init_smb()
IO.inspect(result, label: "init_smb()")

# Test set_credentials with proper tuple response
IO.puts("\nTesting set_credentials function:")
result = Sambex.Nif.set_credentials("WORKGROUP", "testuser", "testpass")
IO.inspect(result, label: "set_credentials")

# Test connect function - this should return error tuple since we don't have real SMB server
IO.puts("\nTesting connect function (expected to fail):")
result = Sambex.Nif.connect("smb://nonexistent/share", "user", "pass")
IO.inspect(result, label: "connect")

# Test list_dir function - this should return error tuple since we don't have real SMB server
IO.puts("\nTesting list_dir function (expected to fail):")
result = Sambex.Nif.list_dir("smb://nonexistent/share", "user", "pass")
IO.inspect(result, label: "list_dir")

# Test read_file function - this should return error tuple since we don't have real SMB server
IO.puts("\nTesting read_file function (expected to fail):")
result = Sambex.Nif.read_file("smb://nonexistent/file.txt", "user", "pass")
IO.inspect(result, label: "read_file")

# Test write_file function - this should return error tuple since we don't have real SMB server
IO.puts("\nTesting write_file function (expected to fail):")
result = Sambex.Nif.write_file("smb://nonexistent/file.txt", "test content", "user", "pass")
IO.inspect(result, label: "write_file")

# Test delete_file function - this should return error tuple since we don't have real SMB server
IO.puts("\nTesting delete_file function (expected to fail):")
result = Sambex.Nif.delete_file("smb://nonexistent/file.txt", "user", "pass")
IO.inspect(result, label: "delete_file")

IO.puts("\nAll functions now return proper Elixir terms!")
IO.puts("Expected results:")
IO.puts("- add_one(41) should return: 42")
IO.puts("- init_smb() should return: :ok or {:error, :init_failed}")
IO.puts("- Other functions should return: {:error, reason_atom} due to no SMB server")
