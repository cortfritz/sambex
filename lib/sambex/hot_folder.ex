defmodule Sambex.HotFolder do
  @moduledoc """
  A GenServer that monitors an SMB share directory for new files and processes them automatically.

  HotFolder implements the "hot folder" pattern common in printing and document processing industries,
  where files dropped into a monitored directory trigger automated processing workflows.

  ## Features

  - **Sequential Processing**: Files are processed one at a time to ensure deterministic behavior
  - **Flexible Connection Management**: Use existing connections or create new ones
  - **Rich File Filtering**: Filter files by name patterns, size, and MIME types
  - **Automatic Folder Management**: Creates and manages processing, success, and error folders
  - **Robust Error Handling**: Retries failed processing with exponential backoff
  - **Efficient Polling**: Smart polling with backoff to minimize network overhead

  ## Basic Usage

      # Simple configuration with direct connection
      {:ok, pid} = Sambex.HotFolder.start_link(%{
        url: "smb://server/print-queue",
        username: "printer",
        password: "secret",
        handler: &MyApp.process_print_job/1
      })

      # Using an existing named connection
      {:ok, pid} = Sambex.HotFolder.start_link(%{
        connection: :print_server,
        handler: &MyApp.process_print_job/1
      })

  ## Advanced Configuration

      config = %Sambex.HotFolder.Config{
        connection: :print_server,
        base_path: "hot-folders/pdf-processor",
        handler: {MyApp.PDFProcessor, :process, [:high_quality]},

        folders: %{
          incoming: "inbox",
          processing: "working",
          success: "completed",
          errors: "failed"
        },

        filters: %{
          name_patterns: [~r/\.pdf$/i],
          min_size: 1024,
          max_size: 100_000_000,  # 100MB
          exclude_patterns: [~r/^\./, ~r/~$/]
        },

        poll_interval: %{
          initial: 1_000,
          max: 30_000,
          backoff_factor: 2.0
        },

        handler_timeout: 300_000,  # 5 minutes
        max_retries: 5
      }

      {:ok, pid} = Sambex.HotFolder.start_link(config)

  ## File Processing Workflow

  1. **Discovery**: Files are discovered in the incoming folder during polling
  2. **Filtering**: Files are checked against configured filters
  3. **Stability Check**: Files must have stable size to ensure complete upload
  4. **Processing**: File is moved to processing folder and handler is called
  5. **Success**: On success, file is moved to success folder
  6. **Error**: On failure, file is moved to errors folder with error report

  ## Handler Interface

  Handlers receive a file info map and should return `{:ok, result}` or `{:error, reason}`:

      def process_file(file_info) do
        # file_info contains: %{path: "...", name: "...", size: ...}
        case do_processing(file_info.path) do
          :ok -> {:ok, %{processed_at: DateTime.utc_now()}}
          {:error, reason} -> {:error, reason}
        end
      end

  ## Monitoring and Stats

      # Get current statistics
      Sambex.HotFolder.stats(pid)
      # => %{files_processed: 150, files_failed: 3, uptime: 3600, ...}

      # Get current status
      Sambex.HotFolder.status(pid)
      # => :polling | {:processing, "filename.pdf"} | :error

  """

  use GenServer
  require Logger

  alias Sambex.HotFolder.Config
  alias Sambex.HotFolder.FileFilter
  alias Sambex.HotFolder.FileManager
  alias Sambex.HotFolder.Handler
  alias Sambex.HotFolder.StabilityChecker

  @type file_info :: %{
          path: String.t(),
          name: String.t(),
          size: non_neg_integer()
        }

  @type stats :: %{
          files_processed: non_neg_integer(),
          files_failed: non_neg_integer(),
          current_status: atom(),
          uptime: non_neg_integer(),
          last_poll: DateTime.t() | nil,
          current_interval: pos_integer()
        }

  defmodule State do
    @moduledoc false

    defstruct [
      :config,
      :connection_pid,
      :connection_owned,
      :poll_timer,
      :current_interval,
      :known_files,
      :stability_checker,
      :stats,
      :status,
      :start_time
    ]

    @type t :: %__MODULE__{
            config: Config.t(),
            connection_pid: pid() | nil,
            connection_owned: boolean(),
            poll_timer: reference() | nil,
            current_interval: pos_integer(),
            known_files: MapSet.t(),
            stability_checker: map(),
            stats: map(),
            status: atom(),
            start_time: DateTime.t()
          }
  end

  ## Public API

  @doc """
  Starts a HotFolder GenServer.

  ## Options

  - `config` - A `Sambex.HotFolder.Config` struct or map of configuration options
  - `name` - Optional name for the GenServer (for registration)

  ## Examples

      {:ok, pid} = Sambex.HotFolder.start_link(%{
        url: "smb://server/share",
        username: "user",
        password: "pass",
        handler: &MyApp.process/1
      })

      {:ok, pid} = Sambex.HotFolder.start_link(config, name: :pdf_processor)

  """
  @spec start_link(Config.t() | map(), keyword()) :: GenServer.on_start()
  def start_link(config, opts \\ [])

  def start_link(%Config{} = config, opts) do
    GenServer.start_link(__MODULE__, config, opts)
  end

  def start_link(config_map, opts) when is_map(config_map) do
    case Config.new(config_map) do
      {:ok, config} -> start_link(config, opts)
      {:error, reason} -> {:error, {:invalid_config, reason}}
    end
  end

  @doc """
  Returns the current statistics for the HotFolder.

  ## Examples

      stats = Sambex.HotFolder.stats(pid)
      # => %{
      #   files_processed: 42,
      #   files_failed: 3,
      #   current_status: :polling,
      #   uptime: 3600,
      #   last_poll: ~U[2025-01-15 10:30:00Z],
      #   current_interval: 5000
      # }

  """
  @spec stats(GenServer.server()) :: stats()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  @doc """
  Returns the current status of the HotFolder.

  Possible statuses:
  - `:starting` - HotFolder is initializing
  - `:polling` - Actively polling for files
  - `{:processing, filename}` - Currently processing a file
  - `:error` - An error has occurred

  """
  @spec status(GenServer.server()) :: atom() | {atom(), String.t()}
  def status(server) do
    GenServer.call(server, :status)
  end

  @doc """
  Forces an immediate poll for new files.

  Returns `:ok` if poll was triggered, or `{:error, reason}` if not possible.
  """
  @spec poll_now(GenServer.server()) :: :ok | {:error, atom()}
  def poll_now(server) do
    GenServer.call(server, :poll_now)
  end

  @doc """
  Stops the HotFolder gracefully.

  Any file currently being processed will complete before shutdown.
  """
  @spec stop(GenServer.server(), term()) :: :ok
  def stop(server, reason \\ :normal) do
    GenServer.stop(server, reason)
  end

  ## GenServer Callbacks

  @impl GenServer
  def init(%Config{} = config) do
    Process.flag(:trap_exit, true)

    state = %State{
      config: config,
      connection_pid: nil,
      connection_owned: false,
      poll_timer: nil,
      current_interval: config.poll_interval.initial,
      known_files: MapSet.new(),
      stability_checker: StabilityChecker.new(),
      stats: init_stats(),
      status: :starting,
      start_time: DateTime.utc_now()
    }

    # Initialize connection and start polling
    {:ok, state, {:continue, :initialize}}
  end

  @impl GenServer
  def handle_continue(:initialize, state) do
    case setup_connection(state) do
      {:ok, new_state} ->
        case maybe_create_folders(new_state) do
          :ok ->
            # Start polling
            timer = schedule_poll(new_state.current_interval)
            final_state = %{new_state | poll_timer: timer, status: :polling}

            Logger.info("HotFolder started, monitoring #{incoming_path(final_state)}")

            # Emit telemetry for successful startup
            :telemetry.execute(
              [:sambex, :hot_folder, :started],
              %{poll_interval: new_state.current_interval},
              %{
                hot_folder_pid: self(),
                incoming_path: incoming_path(final_state),
                config: final_state.config
              }
            )

            {:noreply, final_state}

          {:error, reason} ->
            Logger.error("Failed to create folders: #{inspect(reason)}")
            {:stop, {:folder_creation_failed, reason}, state}
        end

      {:error, reason} ->
        Logger.error("Failed to setup connection: #{inspect(reason)}")
        {:stop, {:connection_failed, reason}, state}
    end
  end

  @impl GenServer
  def handle_call(:stats, _from, state) do
    stats =
      Map.merge(state.stats, %{
        current_status: state.status,
        uptime: DateTime.diff(DateTime.utc_now(), state.start_time),
        current_interval: state.current_interval
      })

    {:reply, stats, state}
  end

  def handle_call(:status, _from, state) do
    {:reply, state.status, state}
  end

  def handle_call(:poll_now, _from, %{status: {:processing, _}} = state) do
    {:reply, {:error, :busy}, state}
  end

  def handle_call(:poll_now, _from, state) do
    # Cancel current timer and poll immediately
    if state.poll_timer do
      Process.cancel_timer(state.poll_timer)
    end

    send(self(), :poll)
    {:reply, :ok, %{state | poll_timer: nil}}
  end

  @impl GenServer
  def handle_info(:poll, state) do
    new_state = %{state | poll_timer: nil}
    poll_start = System.monotonic_time()

    case poll_for_files(new_state) do
      {:ok, files, updated_state} ->
        poll_duration = System.monotonic_time() - poll_start

        # Emit telemetry for completed poll
        :telemetry.execute(
          [:sambex, :hot_folder, :poll_completed],
          %{duration: poll_duration, files_found: length(files)},
          %{hot_folder_pid: self(), config: state.config}
        )

        case files do
          [] ->
            # No files found, increase poll interval
            new_interval =
              calculate_next_interval(updated_state.current_interval, updated_state.config)

            timer = schedule_poll(new_interval)

            final_state = %{
              updated_state
              | current_interval: new_interval,
                poll_timer: timer,
                stats: update_stats(updated_state.stats, :last_poll, DateTime.utc_now())
            }

            {:noreply, final_state}

          [file | _] ->
            # Found files, process the first one
            # Reset interval since we found activity
            timer = schedule_poll(updated_state.config.poll_interval.initial)

            processing_state = %{
              updated_state
              | current_interval: updated_state.config.poll_interval.initial,
                poll_timer: timer,
                status: {:processing, file.name}
            }

            # Emit telemetry for file discovery
            :telemetry.execute(
              [:sambex, :hot_folder, :file_discovered],
              %{file_size: file.size},
              %{hot_folder_pid: self(), file_name: file.name, file_path: file.path}
            )

            # Process the file asynchronously
            send(self(), {:process_file, file})
            {:noreply, processing_state}
        end

      {:error, reason} ->
        Logger.warning("Poll failed: #{inspect(reason)}")

        # Emit telemetry for poll error
        :telemetry.execute(
          [:sambex, :hot_folder, :poll_failed],
          %{},
          %{hot_folder_pid: self(), error: reason}
        )

        # Schedule retry with longer interval
        new_interval = calculate_next_interval(state.current_interval, state.config)
        timer = schedule_poll(new_interval)

        error_state = %{state | current_interval: new_interval, poll_timer: timer, status: :error}

        {:noreply, error_state}
    end
  end

  def handle_info({:process_file, file}, state) do
    process_start = System.monotonic_time()
    result = process_single_file(file, state)
    process_duration = System.monotonic_time() - process_start

    # Emit telemetry based on result
    case result do
      :ok ->
        :telemetry.execute(
          [:sambex, :hot_folder, :file_processed],
          %{duration: process_duration, file_size: file.size},
          %{hot_folder_pid: self(), file_name: file.name, file_path: file.path}
        )

      {:error, reason} ->
        :telemetry.execute(
          [:sambex, :hot_folder, :file_failed],
          %{duration: process_duration, file_size: file.size},
          %{hot_folder_pid: self(), file_name: file.name, file_path: file.path, error: reason}
        )
    end

    # Update stats and reset status
    updated_stats =
      case result do
        :ok -> update_stats(state.stats, :files_processed, &(&1 + 1))
        {:error, _} -> update_stats(state.stats, :files_failed, &(&1 + 1))
      end

    # Remove processed file from stability tracking
    new_stability_checker = StabilityChecker.remove_file(state.stability_checker, file.name)

    new_state = %{
      state
      | stats: updated_stats,
        stability_checker: new_stability_checker,
        status: :polling
    }

    {:noreply, new_state}
  end

  def handle_info({:EXIT, pid, reason}, %{connection_pid: pid, connection_owned: true} = state) do
    Logger.error("Connection process died: #{inspect(reason)}")
    {:stop, {:connection_died, reason}, state}
  end

  def handle_info({:EXIT, _pid, _reason}, state) do
    # Ignore exits from other processes
    {:noreply, state}
  end

  @impl GenServer
  def terminate(reason, state) do
    # Cancel polling timer
    if state.poll_timer do
      Process.cancel_timer(state.poll_timer)
    end

    # Emit telemetry for shutdown
    uptime = DateTime.diff(DateTime.utc_now(), state.start_time)

    :telemetry.execute(
      [:sambex, :hot_folder, :stopped],
      %{
        uptime: uptime,
        files_processed: state.stats.files_processed,
        files_failed: state.stats.files_failed
      },
      %{hot_folder_pid: self(), reason: reason}
    )

    # Clean up owned connection
    if state.connection_owned and state.connection_pid do
      GenServer.stop(state.connection_pid, :normal)
    end

    :ok
  end

  ## Private Functions

  defp init_stats do
    %{
      files_processed: 0,
      files_failed: 0,
      last_poll: nil
    }
  end

  defp update_stats(stats, key, value_or_fun) do
    case value_or_fun do
      fun when is_function(fun, 1) -> Map.update(stats, key, 0, fun)
      value -> Map.put(stats, key, value)
    end
  end

  defp setup_connection(%{config: %{connection: conn_name}} = state) when not is_nil(conn_name) do
    case Registry.lookup(Sambex.ConnectionRegistry, conn_name) do
      [{pid, _}] ->
        Process.link(pid)
        {:ok, %{state | connection_pid: pid, connection_owned: false}}

      [] ->
        {:error, {:connection_not_found, conn_name}}
    end
  end

  defp setup_connection(%{config: %{url: url, username: username, password: password}} = state) do
    case Sambex.Connection.start_link(url: url, username: username, password: password) do
      {:ok, pid} ->
        Process.link(pid)
        {:ok, %{state | connection_pid: pid, connection_owned: true}}

      error ->
        error
    end
  end

  defp maybe_create_folders(%{config: %{create_folders: false}}), do: :ok

  defp maybe_create_folders(%{config: config, connection_pid: conn_pid}) do
    FileManager.ensure_folders_exist(conn_pid, config)
  end

  defp incoming_path(state) do
    Config.folder_path(state.config, :incoming)
  end

  defp poll_for_files(state) do
    path = incoming_path(state)

    case Sambex.Connection.list_dir(state.connection_pid, path) do
      {:ok, entries} ->
        # Filter to only files (not directories) and get full file information
        file_results =
          entries
          |> Enum.filter(fn {_name, type} -> type == :file end)
          |> Enum.map(fn {name, _type} ->
            file_path = Path.join(path, name)
            FileManager.get_file_info(state.connection_pid, file_path)
          end)

        # Separate successful file info from errors
        {files, _errors} =
          file_results
          |> Enum.split_with(fn
            {:ok, _file_info} -> true
            {:error, _reason} -> false
          end)

        # Extract file info and apply filters
        all_files =
          files
          |> Enum.map(fn {:ok, file_info} -> file_info end)
          |> Enum.filter(&passes_filters?(&1, state.config))

        # Check for file stability
        {stable_files, new_stability_checker} =
          StabilityChecker.check_stability(all_files, state.stability_checker)

        # Only process files that are stable and not already known
        processable_files =
          stable_files
          |> Enum.reject(&file_known?(&1, state.known_files))

        # Add stable files to known set
        new_known =
          Enum.reduce(processable_files, state.known_files, fn file, acc ->
            MapSet.put(acc, file.name)
          end)

        updated_state = %{
          state
          | known_files: new_known,
            stability_checker: new_stability_checker
        }

        {:ok, processable_files, updated_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp passes_filters?(file, config) do
    FileFilter.passes?(file, config)
  end

  defp file_known?(file, known_files) do
    MapSet.member?(known_files, file.name)
  end

  defp process_single_file(file, state) do
    Logger.info("Processing file: #{file.name}")

    # Step 1: Move file to processing folder
    case FileManager.move_to_processing(state.connection_pid, file.name, state.config) do
      :ok ->
        # Step 2: Execute handler with timeout and retry logic
        handler_opts = %{
          timeout: state.config.handler_timeout,
          max_retries: state.config.max_retries,
          backoff_base: 1_000
        }

        case Handler.execute(state.config.handler, file, handler_opts) do
          {:ok, _result} ->
            # Step 3a: Move to success folder
            case FileManager.move_to_success(state.connection_pid, file.name, state.config) do
              :ok ->
                Logger.info("Successfully processed file: #{file.name}")
                :ok

              {:error, reason} ->
                Logger.error("Failed to move #{file.name} to success folder: #{inspect(reason)}")
                {:error, {:move_success_failed, reason}}
            end

          {:error, :max_retries_exceeded, retry_state} ->
            # Step 3b: Move to errors folder with report
            error_report = Handler.generate_error_report(file, state.config.handler, retry_state)

            case FileManager.move_to_errors(
                   state.connection_pid,
                   file.name,
                   state.config,
                   error_report
                 ) do
              :ok ->
                Logger.warning(
                  "File processing failed after #{retry_state.attempt} attempts: #{file.name}"
                )

                {:error, :max_retries_exceeded}

              {:error, reason} ->
                Logger.error("Failed to move #{file.name} to errors folder: #{inspect(reason)}")
                {:error, {:move_errors_failed, reason}}
            end
        end

      {:error, reason} ->
        Logger.error("Failed to move #{file.name} to processing folder: #{inspect(reason)}")
        {:error, {:move_processing_failed, reason}}
    end
  end

  defp calculate_next_interval(current, config) do
    next = round(current * config.poll_interval.backoff_factor)
    min(next, config.poll_interval.max)
  end

  defp schedule_poll(interval) do
    Process.send_after(self(), :poll, interval)
  end
end
