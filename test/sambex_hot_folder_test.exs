defmodule Sambex.HotFolderTest do
  use ExUnit.Case, async: true
  doctest Sambex.HotFolder.Config
  doctest Sambex.HotFolder.FileFilter

  alias Sambex.HotFolder
  alias Sambex.HotFolder.Config
  alias Sambex.HotFolder.FileFilter
  alias Sambex.HotFolder.Handler
  alias Sambex.HotFolder.StabilityChecker

  describe "Config" do
    test "creates valid config with connection name" do
      {:ok, config} =
        Config.new(%{
          connection: :test_connection,
          handler: fn _ -> {:ok, :processed} end
        })

      assert config.connection == :test_connection
      assert is_function(config.handler, 1)
    end

    test "creates valid config with URL and credentials" do
      {:ok, config} =
        Config.new(%{
          url: "smb://server/share",
          username: "user",
          password: "pass",
          handler: fn _ -> {:ok, :processed} end
        })

      assert config.url == "smb://server/share"
      assert config.username == "user"
      assert config.password == "pass"
    end

    test "rejects config without connection or URL" do
      {:error, reason} =
        Config.new(%{
          handler: fn _ -> {:ok, :processed} end
        })

      assert reason == "Must provide either connection name or url+username+password"
    end

    test "rejects config without handler" do
      {:error, reason} =
        Config.new(%{
          connection: :test_connection
        })

      assert reason == "Handler is required"
    end

    test "validates MFA handler format" do
      defmodule TestHandler do
        def process(_file, _extra_arg), do: {:ok, :processed}
      end

      {:ok, config} =
        Config.new(%{
          connection: :test_connection,
          handler: {TestHandler, :process, [:extra_arg]}
        })

      assert config.handler == {TestHandler, :process, [:extra_arg]}
    end

    test "folder_path returns correct paths" do
      config = %Config{
        base_path: "hot-folders/print",
        folders: %{incoming: "inbox", success: "done"}
      }

      assert Config.folder_path(config, :incoming) == "hot-folders/print/inbox"
      assert Config.folder_path(config, :success) == "hot-folders/print/done"
    end

    test "folder_path handles empty base_path" do
      config = %Config{
        base_path: "",
        folders: %{incoming: "inbox"}
      }

      assert Config.folder_path(config, :incoming) == "inbox"
    end

    test "all_folder_paths returns all paths" do
      config = %Config{base_path: "test"}
      paths = Config.all_folder_paths(config)

      assert paths == %{
               incoming: "test/incoming",
               processing: "test/processing",
               success: "test/success",
               errors: "test/errors"
             }
    end
  end

  describe "FileFilter" do
    test "passes all files when no filters configured" do
      file = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}
      config = %Config{filters: %{}}

      assert FileFilter.passes?(file, config) == true
    end

    test "filters by name patterns" do
      pdf_file = %{name: "doc.pdf", path: "inbox/doc.pdf", size: 1024}
      txt_file = %{name: "doc.txt", path: "inbox/doc.txt", size: 512}

      config = %Config{
        filters: %{name_patterns: [~r/\.pdf$/i]}
      }

      assert FileFilter.passes?(pdf_file, config) == true
      assert FileFilter.passes?(txt_file, config) == false
    end

    test "filters by exclude patterns" do
      normal_file = %{name: "document.pdf", path: "inbox/document.pdf", size: 1024}
      hidden_file = %{name: ".hidden", path: "inbox/.hidden", size: 100}
      temp_file = %{name: "document.pdf~", path: "inbox/document.pdf~", size: 1000}

      config = %Config{
        filters: %{exclude_patterns: [~r/^\./, ~r/~$/]}
      }

      assert FileFilter.passes?(normal_file, config) == true
      assert FileFilter.passes?(hidden_file, config) == false
      assert FileFilter.passes?(temp_file, config) == false
    end

    test "filters by file size" do
      small_file = %{name: "small.pdf", path: "inbox/small.pdf", size: 500}
      medium_file = %{name: "medium.pdf", path: "inbox/medium.pdf", size: 5000}
      large_file = %{name: "large.pdf", path: "inbox/large.pdf", size: 50_000}

      config = %Config{
        filters: %{min_size: 1000, max_size: 10_000}
      }

      assert FileFilter.passes?(small_file, config) == false
      assert FileFilter.passes?(medium_file, config) == true
      assert FileFilter.passes?(large_file, config) == false
    end

    test "filters multiple files" do
      files = [
        %{name: "doc1.pdf", path: "inbox/doc1.pdf", size: 2000},
        %{name: "doc2.txt", path: "inbox/doc2.txt", size: 1500},
        %{name: ".hidden", path: "inbox/.hidden", size: 100},
        %{name: "doc3.pdf", path: "inbox/doc3.pdf", size: 3000}
      ]

      config = %Config{
        filters: %{
          name_patterns: [~r/\.pdf$/],
          exclude_patterns: [~r/^\./],
          min_size: 1000
        }
      }

      result = FileFilter.filter_files(files, config)

      assert length(result) == 2
      assert Enum.map(result, & &1.name) == ["doc1.pdf", "doc3.pdf"]
    end

    test "mime_type_from_extension returns correct types" do
      assert FileFilter.mime_type_from_extension("document.pdf") == "application/pdf"
      # Case insensitive
      assert FileFilter.mime_type_from_extension("image.JPG") == "image/jpeg"
      assert FileFilter.mime_type_from_extension("text.txt") == "text/plain"
      assert FileFilter.mime_type_from_extension("unknown.xyz") == "application/octet-stream"
    end
  end

  describe "Handler" do
    test "executes successful handler" do
      handler = fn file -> {:ok, "processed #{file.name}"} end
      file = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}

      result = Handler.execute(handler, file, %{timeout: 1000, max_retries: 1})
      assert {:ok, "processed test.pdf"} = result
    end

    test "handles handler timeout" do
      slow_handler = fn _file ->
        Process.sleep(100)
        {:ok, "done"}
      end

      file = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}

      result = Handler.execute(slow_handler, file, %{timeout: 50, max_retries: 1})
      assert {:error, :max_retries_exceeded, _retry_state} = result
    end

    test "retries failed handler" do
      # Handler that fails twice then succeeds
      agent = Agent.start_link(fn -> 0 end)
      {:ok, pid} = agent

      handler = fn _file ->
        count = Agent.get_and_update(pid, &{&1, &1 + 1})

        if count < 2 do
          {:error, :temporary_failure}
        else
          {:ok, :success}
        end
      end

      file = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}
      result = Handler.execute(handler, file, %{timeout: 1000, max_retries: 3, backoff_base: 1})

      assert {:ok, :success} = result
      Agent.stop(pid)
    end

    test "validates handler function" do
      assert :ok = Handler.validate_handler(fn _file -> :ok end)
      assert {:error, _} = Handler.validate_handler("not a function")
    end

    test "validates MFA handler" do
      defmodule TestMod do
        def test_handler(_file, _arg), do: {:ok, :done}
      end

      assert :ok = Handler.validate_handler({TestMod, :test_handler, [:arg]})
      assert {:error, _} = Handler.validate_handler({NonExistent, :function, []})
    end

    test "generates error report" do
      retry_state = %{
        attempt: 2,
        max_retries: 2,
        errors: [
          %{attempt: 1, error: :timeout, timestamp: ~U[2025-01-15 10:00:00Z]},
          %{attempt: 2, error: :invalid_data, timestamp: ~U[2025-01-15 10:00:15Z]}
        ]
      }

      file = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}
      handler = fn _file -> :ok end

      report = Handler.generate_error_report(file, handler, retry_state)

      assert String.contains?(report, "Error processing file: test.pdf")
      assert String.contains?(report, "Attempts: 2")
      assert String.contains?(report, "Attempt 1")
      assert String.contains?(report, "Attempt 2")
    end
  end

  describe "StabilityChecker" do
    test "creates new stability checker" do
      checker = StabilityChecker.new()
      assert %{tracked_files: %{}, stability_checks: 2, stability_duration: 5000} = checker
    end

    test "creates checker with custom options" do
      checker = StabilityChecker.new(stability_checks: 3, stability_duration: 10_000)
      assert %{stability_checks: 3, stability_duration: 10_000} = checker
    end

    test "tracks new files" do
      checker = StabilityChecker.new()
      files = [%{name: "test.pdf", size: 1024}]

      {stable_files, new_checker} = StabilityChecker.check_stability(files, checker)

      assert stable_files == []
      assert Map.has_key?(new_checker.tracked_files, "test.pdf")

      tracking = new_checker.tracked_files["test.pdf"]
      assert tracking.name == "test.pdf"
      assert tracking.size == 1024
      assert tracking.checks == 1
    end

    test "detects file size changes" do
      checker = StabilityChecker.new()

      # First poll - file is 1024 bytes
      files_v1 = [%{name: "test.pdf", size: 1024}]
      {_stable, checker} = StabilityChecker.check_stability(files_v1, checker)

      # Second poll - file grew to 2048 bytes (still uploading)
      files_v2 = [%{name: "test.pdf", size: 2048}]
      {stable_files, new_checker} = StabilityChecker.check_stability(files_v2, checker)

      assert stable_files == []
      tracking = new_checker.tracked_files["test.pdf"]
      assert tracking.size == 2048
      # Reset due to size change
      assert tracking.checks == 1
      assert is_nil(tracking.stable_since)
    end

    test "marks files stable after consistent size" do
      # Use minimal settings but allow for timing
      checker = StabilityChecker.new(stability_duration: 1, stability_checks: 2)
      files = [%{name: "test.pdf", size: 1024}]

      # First check - file detected
      {stable_files, checker} = StabilityChecker.check_stability(files, checker)
      # Not stable yet (only 1 check)
      assert stable_files == []

      # Second check with same size - marks as potentially stable
      {stable_files, checker} = StabilityChecker.check_stability(files, checker)
      # Still not stable due to duration requirement
      assert stable_files == []

      # Wait a bit and check again - should be stable now
      Process.sleep(5)
      {stable_files, _checker} = StabilityChecker.check_stability(files, checker)

      # Should now be stable
      assert length(stable_files) == 1
      assert List.first(stable_files).name == "test.pdf"
    end

    test "removes files from tracking" do
      checker = StabilityChecker.new()
      files = [%{name: "test.pdf", size: 1024}]

      {_stable, checker} = StabilityChecker.check_stability(files, checker)
      assert Map.has_key?(checker.tracked_files, "test.pdf")

      new_checker = StabilityChecker.remove_file(checker, "test.pdf")
      assert not Map.has_key?(new_checker.tracked_files, "test.pdf")
    end

    test "provides tracking statistics" do
      checker = StabilityChecker.new(stability_duration: 1)

      files = [
        %{name: "stable.pdf", size: 1024},
        %{name: "unstable.pdf", size: 2048}
      ]

      # Make one file stable
      {_stable, checker} =
        StabilityChecker.check_stability([%{name: "stable.pdf", size: 1024}], checker)

      Process.sleep(2)

      {_stable, checker} =
        StabilityChecker.check_stability([%{name: "stable.pdf", size: 1024}], checker)

      # Add unstable file
      {_stable, checker} = StabilityChecker.check_stability(files, checker)

      stats = StabilityChecker.get_stats(checker)
      assert stats.total_tracked == 2
      assert stats.stable_count == 1
      assert stats.unstable_count == 1
    end
  end

  # Note: We can't easily test the full HotFolder GenServer without a real SMB connection
  # More comprehensive tests would require setting up mock connections

  describe "HotFolder basic functionality" do
    test "rejects invalid configuration" do
      assert {:error, {:invalid_config, _}} = HotFolder.start_link(%{})
    end
  end
end
