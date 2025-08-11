defmodule SambexIntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  # Test configuration
  @username "example1"
  @password "badpass"
  @test_share "smb://localhost:445/public"
  @private_share "smb://localhost:445/private"
  @private_username "example2"

  setup_all do
    # Initialize SMB client once for all tests
    case Sambex.init() do
      :ok ->
        :ok

      error ->
        raise "Failed to initialize SMB client: #{inspect(error)}"
    end
  end

  setup do
    # Generate unique filename for each test to avoid conflicts
    timestamp = :os.system_time(:microsecond)
    test_file = "#{@test_share}/test_#{timestamp}.txt"
    test_content = "Test content - #{DateTime.utc_now()}"

    %{
      test_file: test_file,
      test_content: test_content,
      timestamp: timestamp
    }
  end

  describe "SMB initialization" do
    test "init/0 returns :ok" do
      # Already initialized in setup_all, but test idempotency
      assert Sambex.init() == :ok
    end
  end

  describe "directory operations" do
    test "list_dir/3 successfully lists public share" do
      assert {:ok, files} = Sambex.list_dir(@test_share, @username, @password)
      assert is_list(files)
      # At least . and ..
      assert length(files) >= 2

      # Check that entries have correct format
      for {name, type} <- files do
        assert is_binary(name)
        assert type in [:file, :directory]
      end
    end

    test "list_dir/3 successfully lists private share with correct credentials" do
      assert {:ok, files} = Sambex.list_dir(@private_share, @private_username, @password)
      assert is_list(files)
      # At least . and ..
      assert length(files) >= 2
    end

    test "list_dir/3 fails with wrong credentials" do
      assert {:error, _reason} = Sambex.list_dir(@test_share, "wrong_user", "wrong_pass")
    end

    test "list_dir/3 fails with non-existent share" do
      nonexistent_share = "smb://localhost:445/nonexistent"
      assert {:error, _reason} = Sambex.list_dir(nonexistent_share, @username, @password)
    end
  end

  describe "file creation and writing" do
    test "write_file/4 creates new file successfully", %{
      test_file: test_file,
      test_content: test_content
    } do
      assert {:ok, bytes_written} =
               Sambex.write_file(test_file, test_content, @username, @password)

      assert bytes_written == byte_size(test_content)

      # Cleanup
      Sambex.delete_file(test_file, @username, @password)
    end

    test "write_file/4 fails with wrong credentials", %{
      test_file: test_file,
      test_content: test_content
    } do
      assert {:error, _reason} =
               Sambex.write_file(test_file, test_content, "wrong_user", "wrong_pass")
    end

    test "write_file/4 overwrites existing file", %{test_file: test_file} do
      original_content = "Original content"
      new_content = "New content"

      # Create original file
      assert {:ok, _} = Sambex.write_file(test_file, original_content, @username, @password)

      # Overwrite with new content
      assert {:ok, bytes_written} =
               Sambex.write_file(test_file, new_content, @username, @password)

      assert bytes_written == byte_size(new_content)

      # Verify new content
      assert {:ok, ^new_content} = Sambex.read_file(test_file, @username, @password)

      # Cleanup
      Sambex.delete_file(test_file, @username, @password)
    end
  end

  describe "file reading" do
    test "read_file/3 reads file content correctly", %{
      test_file: test_file,
      test_content: test_content
    } do
      # Create file first
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Read and verify content
      assert {:ok, ^test_content} = Sambex.read_file(test_file, @username, @password)

      # Cleanup
      Sambex.delete_file(test_file, @username, @password)
    end

    test "read_file/3 fails for non-existent file" do
      nonexistent_file = "#{@test_share}/nonexistent_#{:os.system_time(:microsecond)}.txt"
      assert {:error, _reason} = Sambex.read_file(nonexistent_file, @username, @password)
    end

    test "read_file/3 fails with wrong credentials", %{
      test_file: test_file,
      test_content: test_content
    } do
      # Create file first
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Try to read with wrong credentials
      assert {:error, _reason} = Sambex.read_file(test_file, "wrong_user", "wrong_pass")

      # Cleanup
      Sambex.delete_file(test_file, @username, @password)
    end

    test "read_file/3 handles empty files", %{timestamp: timestamp} do
      empty_file = "#{@test_share}/empty_#{timestamp}.txt"
      empty_content = ""

      # Create empty file
      assert {:ok, 0} = Sambex.write_file(empty_file, empty_content, @username, @password)

      # Read empty file
      assert {:ok, ^empty_content} = Sambex.read_file(empty_file, @username, @password)

      # Cleanup
      Sambex.delete_file(empty_file, @username, @password)
    end
  end

  describe "file deletion" do
    test "delete_file/3 successfully deletes existing file", %{
      test_file: test_file,
      test_content: test_content
    } do
      # Create file first
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Verify file exists
      assert {:ok, ^test_content} = Sambex.read_file(test_file, @username, @password)

      # Delete file
      assert :ok = Sambex.delete_file(test_file, @username, @password)

      # Verify file is deleted
      assert {:error, _reason} = Sambex.read_file(test_file, @username, @password)
    end

    test "delete_file/3 fails for non-existent file" do
      nonexistent_file = "#{@test_share}/nonexistent_#{:os.system_time(:microsecond)}.txt"

      # Should return error (not crash)
      result = Sambex.delete_file(nonexistent_file, @username, @password)
      assert match?({:error, _}, result) or match?({:error, _, _}, result)
    end

    test "delete_file/3 fails with wrong credentials", %{
      test_file: test_file,
      test_content: test_content
    } do
      # Create file first
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Try to delete with wrong credentials
      result = Sambex.delete_file(test_file, "wrong_user", "wrong_pass")
      assert match?({:error, _}, result) or match?({:error, _, _}, result)

      # Verify file still exists
      assert {:ok, ^test_content} = Sambex.read_file(test_file, @username, @password)

      # Cleanup
      Sambex.delete_file(test_file, @username, @password)
    end

    test "delete_file/3 removes file from directory listing", %{
      test_file: test_file,
      test_content: test_content
    } do
      filename = Path.basename(test_file)

      # Create file
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Verify file appears in directory listing
      assert {:ok, files_before} = Sambex.list_dir(@test_share, @username, @password)
      assert Enum.any?(files_before, fn {name, _type} -> name == filename end)

      # Delete file
      assert :ok = Sambex.delete_file(test_file, @username, @password)

      # Verify file no longer appears in directory listing
      assert {:ok, files_after} = Sambex.list_dir(@test_share, @username, @password)
      refute Enum.any?(files_after, fn {name, _type} -> name == filename end)
    end
  end

  describe "complete file lifecycle" do
    test "create -> read -> update -> delete workflow", %{timestamp: timestamp} do
      test_file = "#{@test_share}/lifecycle_#{timestamp}.txt"
      original_content = "Original content"
      updated_content = "Updated content"

      # Step 1: Create file
      assert {:ok, bytes1} = Sambex.write_file(test_file, original_content, @username, @password)
      assert bytes1 == byte_size(original_content)

      # Step 2: Read file
      assert {:ok, ^original_content} = Sambex.read_file(test_file, @username, @password)

      # Step 3: Update file (overwrite)
      assert {:ok, bytes2} = Sambex.write_file(test_file, updated_content, @username, @password)
      assert bytes2 == byte_size(updated_content)

      # Step 4: Read updated content
      assert {:ok, ^updated_content} = Sambex.read_file(test_file, @username, @password)

      # Step 5: Delete file
      assert :ok = Sambex.delete_file(test_file, @username, @password)

      # Step 6: Verify deletion
      assert {:error, _reason} = Sambex.read_file(test_file, @username, @password)
    end

    test "multiple files can be created and deleted independently", %{timestamp: timestamp} do
      file1 = "#{@test_share}/multi1_#{timestamp}.txt"
      file2 = "#{@test_share}/multi2_#{timestamp}.txt"
      content1 = "Content for file 1"
      content2 = "Content for file 2"

      # Create both files
      assert {:ok, _} = Sambex.write_file(file1, content1, @username, @password)
      assert {:ok, _} = Sambex.write_file(file2, content2, @username, @password)

      # Verify both files exist
      assert {:ok, ^content1} = Sambex.read_file(file1, @username, @password)
      assert {:ok, ^content2} = Sambex.read_file(file2, @username, @password)

      # Delete first file
      assert :ok = Sambex.delete_file(file1, @username, @password)

      # Verify first file is deleted, second still exists
      assert {:error, _} = Sambex.read_file(file1, @username, @password)
      assert {:ok, ^content2} = Sambex.read_file(file2, @username, @password)

      # Delete second file
      assert :ok = Sambex.delete_file(file2, @username, @password)

      # Verify both files are deleted
      assert {:error, _} = Sambex.read_file(file1, @username, @password)
      assert {:error, _} = Sambex.read_file(file2, @username, @password)
    end
  end

  describe "cross-share operations" do
    test "can perform operations on both public and private shares" do
      timestamp = :os.system_time(:microsecond)
      public_file = "#{@test_share}/cross_public_#{timestamp}.txt"
      private_file = "#{@private_share}/cross_private_#{timestamp}.txt"
      content = "Cross-share test content"

      # Create files on both shares
      assert {:ok, _} = Sambex.write_file(public_file, content, @username, @password)
      assert {:ok, _} = Sambex.write_file(private_file, content, @private_username, @password)

      # Read from both shares
      assert {:ok, ^content} = Sambex.read_file(public_file, @username, @password)
      assert {:ok, ^content} = Sambex.read_file(private_file, @private_username, @password)

      # Delete from both shares
      assert :ok = Sambex.delete_file(public_file, @username, @password)
      assert :ok = Sambex.delete_file(private_file, @private_username, @password)

      # Verify deletions
      assert {:error, _} = Sambex.read_file(public_file, @username, @password)
      assert {:error, _} = Sambex.read_file(private_file, @private_username, @password)
    end
  end

  describe "error handling and edge cases" do
    test "handles binary content correctly", %{timestamp: timestamp} do
      binary_file = "#{@test_share}/binary_#{timestamp}.bin"
      binary_content = <<0, 1, 2, 255, 128, 64, 32, 16, 8, 4, 2, 1>>

      # Create binary file
      assert {:ok, bytes} = Sambex.write_file(binary_file, binary_content, @username, @password)
      assert bytes == byte_size(binary_content)

      # Read binary file
      assert {:ok, ^binary_content} = Sambex.read_file(binary_file, @username, @password)

      # Delete binary file
      assert :ok = Sambex.delete_file(binary_file, @username, @password)
    end

    test "handles unicode content correctly", %{timestamp: timestamp} do
      unicode_file = "#{@test_share}/unicode_#{timestamp}.txt"
      unicode_content = "Hello 世界 🌍 Здравствуй мир! ¡Hola mundo! 🚀"

      # Create unicode file
      assert {:ok, bytes} = Sambex.write_file(unicode_file, unicode_content, @username, @password)
      assert bytes == byte_size(unicode_content)

      # Read unicode file
      assert {:ok, ^unicode_content} = Sambex.read_file(unicode_file, @username, @password)

      # Delete unicode file
      assert :ok = Sambex.delete_file(unicode_file, @username, @password)
    end

    test "handles large content efficiently", %{timestamp: timestamp} do
      large_file = "#{@test_share}/large_#{timestamp}.txt"
      # Create ~1MB of content
      large_content = String.duplicate("Large content test! ", 50_000)

      # Create large file
      assert {:ok, bytes} = Sambex.write_file(large_file, large_content, @username, @password)
      assert bytes == byte_size(large_content)

      # Read large file
      assert {:ok, ^large_content} = Sambex.read_file(large_file, @username, @password)

      # Delete large file
      assert :ok = Sambex.delete_file(large_file, @username, @password)
    end
  end

  describe "file moving and renaming" do
    test "move_file/4 successfully renames file in same directory", %{
      test_file: test_file,
      test_content: test_content,
      timestamp: timestamp
    } do
      # Create original file
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Define new filename in same directory
      renamed_file = "#{@test_share}/renamed_#{timestamp}.txt"

      # Move/rename the file
      assert :ok = Sambex.move_file(test_file, renamed_file, @username, @password)

      # Verify original file no longer exists
      assert {:error, _reason} = Sambex.read_file(test_file, @username, @password)

      # Verify new file exists with correct content
      assert {:ok, ^test_content} = Sambex.read_file(renamed_file, @username, @password)

      # Cleanup
      Sambex.delete_file(renamed_file, @username, @password)
    end

    test "move_file/4 fails for non-existent source file", %{timestamp: timestamp} do
      nonexistent_file = "#{@test_share}/nonexistent_#{timestamp}.txt"
      dest_file = "#{@test_share}/dest_#{timestamp}.txt"

      # Should return error for non-existent source
      result = Sambex.move_file(nonexistent_file, dest_file, @username, @password)
      assert match?({:error, _}, result) or match?({:error, _, _}, result)
    end

    test "move_file/4 fails with wrong credentials", %{
      test_file: test_file,
      test_content: test_content,
      timestamp: timestamp
    } do
      # Create original file
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      dest_file = "#{@test_share}/dest_#{timestamp}.txt"

      # Try to move with wrong credentials
      result = Sambex.move_file(test_file, dest_file, "wrong_user", "wrong_pass")
      assert match?({:error, _}, result) or match?({:error, _, _}, result)

      # Verify original file still exists
      assert {:ok, ^test_content} = Sambex.read_file(test_file, @username, @password)

      # Cleanup
      Sambex.delete_file(test_file, @username, @password)
    end

    test "move_file/4 overwrites existing destination file", %{
      test_content: test_content,
      timestamp: timestamp
    } do
      source_file = "#{@test_share}/source_#{timestamp}.txt"
      dest_file = "#{@test_share}/dest_#{timestamp}.txt"
      dest_content = "Destination content"

      # Create both source and destination files
      assert {:ok, _} = Sambex.write_file(source_file, test_content, @username, @password)
      assert {:ok, _} = Sambex.write_file(dest_file, dest_content, @username, @password)

      # Move source to destination (should overwrite)
      assert :ok = Sambex.move_file(source_file, dest_file, @username, @password)

      # Verify source no longer exists
      assert {:error, _reason} = Sambex.read_file(source_file, @username, @password)

      # Verify destination has source content
      assert {:ok, ^test_content} = Sambex.read_file(dest_file, @username, @password)

      # Cleanup
      Sambex.delete_file(dest_file, @username, @password)
    end

    test "move_file/4 updates directory listing correctly", %{
      test_file: test_file,
      test_content: test_content,
      timestamp: timestamp
    } do
      # Create original file
      assert {:ok, _} = Sambex.write_file(test_file, test_content, @username, @password)

      # Get directory listing before move
      assert {:ok, files_before} = Sambex.list_dir(@test_share, @username, @password)
      original_filename = "test_#{timestamp}.txt"
      assert Enum.any?(files_before, fn {name, _type} -> name == original_filename end)

      # Move to new name
      renamed_file = "#{@test_share}/moved_#{timestamp}.txt"
      assert :ok = Sambex.move_file(test_file, renamed_file, @username, @password)

      # Get directory listing after move
      assert {:ok, files_after} = Sambex.list_dir(@test_share, @username, @password)
      new_filename = "moved_#{timestamp}.txt"

      # Verify original name is gone and new name exists
      refute Enum.any?(files_after, fn {name, _type} -> name == original_filename end)
      assert Enum.any?(files_after, fn {name, _type} -> name == new_filename end)

      # Cleanup
      Sambex.delete_file(renamed_file, @username, @password)
    end
  end
end
