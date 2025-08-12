defmodule Sambex.HotFolder.Handler do
  @moduledoc """
  Safe handler execution with timeout and retry logic for HotFolder file processing.

  Provides a robust execution framework for user-defined file handlers, including:
  - Timeout protection to prevent hung handlers
  - Retry logic with exponential backoff
  - Comprehensive error tracking and reporting
  - Support for both function and MFA handler formats
  """

  require Logger

  @type handler_spec ::
          (map() -> {:ok, any()} | {:error, any()})
          | {module(), atom(), list()}

  @type execution_result ::
          {:ok, any()}
          | {:error, :timeout}
          | {:error, :max_retries_exceeded}
          | {:error, any()}

  @type retry_state :: %{
          attempt: pos_integer(),
          max_retries: non_neg_integer(),
          backoff_base: pos_integer(),
          errors: [%{attempt: pos_integer(), error: any(), timestamp: DateTime.t()}]
        }

  @doc """
  Executes a handler with the given file info, including timeout and retry logic.

  ## Examples

      iex> handler = fn _file -> {:ok, :processed} end
      iex> file = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}
      iex> Sambex.HotFolder.Handler.execute(handler, file, %{timeout: 5000, max_retries: 3})
      {:ok, :processed}

      iex> failing_handler = fn _file -> {:error, :processing_failed} end
      iex> Sambex.HotFolder.Handler.execute(failing_handler, file, %{timeout: 5000, max_retries: 2})
      {:error, :max_retries_exceeded}

  """
  @spec execute(handler_spec(), map(), map()) ::
          {:ok, any()} | {:error, :max_retries_exceeded, retry_state()} | {:error, any()}
  def execute(handler, file_info, opts \\ %{}) do
    timeout = Map.get(opts, :timeout, 60_000)
    max_retries = Map.get(opts, :max_retries, 3)
    backoff_base = Map.get(opts, :backoff_base, 1_000)

    retry_state = %{
      attempt: 0,
      max_retries: max_retries,
      backoff_base: backoff_base,
      errors: []
    }

    execute_with_retries(handler, file_info, timeout, retry_state)
  end

  @doc """
  Validates that a handler specification is properly formatted and callable.

  ## Examples

      iex> Sambex.HotFolder.Handler.validate_handler(fn _file -> :ok end)
      :ok

      iex> Sambex.HotFolder.Handler.validate_handler({IO, :inspect, []})
      :ok

      iex> Sambex.HotFolder.Handler.validate_handler({NonExistent, :function, []})
      {:error, "Handler function NonExistent.function/1 does not exist"}

  """
  @spec validate_handler(handler_spec()) :: :ok | {:error, String.t()}
  def validate_handler(handler) when is_function(handler, 1), do: :ok

  def validate_handler({mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args) do
    # +1 for the file_info parameter
    arity = length(args) + 1

    if function_exported?(mod, fun, arity) do
      :ok
    else
      {:error, "Handler function #{mod}.#{fun}/#{arity} does not exist"}
    end
  end

  def validate_handler(_) do
    {:error, "Handler must be a function/1 or {module, function, args} tuple"}
  end

  ## Private Functions

  defp execute_with_retries(handler, file_info, timeout, retry_state) do
    %{attempt: attempt, max_retries: max_retries} = retry_state

    if attempt >= max_retries do
      {:error, :max_retries_exceeded, retry_state}
    else
      new_retry_state = %{retry_state | attempt: attempt + 1}

      case execute_single_attempt(handler, file_info, timeout) do
        {:ok, result} ->
          Logger.debug(
            "Handler succeeded on attempt #{new_retry_state.attempt} for file #{file_info.name}"
          )

          {:ok, result}

        {:error, reason} ->
          error_entry = %{
            attempt: new_retry_state.attempt,
            error: reason,
            timestamp: DateTime.utc_now()
          }

          updated_retry_state = %{new_retry_state | errors: [error_entry | retry_state.errors]}

          Logger.warning(
            "Handler failed on attempt #{new_retry_state.attempt} for file #{file_info.name}: #{inspect(reason)}"
          )

          if new_retry_state.attempt < max_retries do
            # Wait before retrying with exponential backoff
            backoff_delay = calculate_backoff_delay(new_retry_state)
            Process.sleep(backoff_delay)

            execute_with_retries(handler, file_info, timeout, updated_retry_state)
          else
            {:error, :max_retries_exceeded, updated_retry_state}
          end
      end
    end
  end

  defp execute_single_attempt(handler, file_info, timeout) do
    task =
      Task.async(fn ->
        try do
          call_handler(handler, file_info)
        rescue
          e -> {:error, {:exception, e}}
        catch
          :exit, reason -> {:error, {:exit, reason}}
          :throw, reason -> {:error, {:throw, reason}}
          :error, reason -> {:error, {:error, reason}}
        end
      end)

    case Task.yield(task, timeout) do
      {:ok, result} ->
        result

      nil ->
        # Timeout occurred
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}

      {:exit, reason} ->
        {:error, {:task_exit, reason}}
    end
  end

  defp call_handler(handler, file_info) when is_function(handler, 1) do
    handler.(file_info)
  end

  defp call_handler({mod, fun, args}, file_info) do
    apply(mod, fun, [file_info | args])
  end

  defp calculate_backoff_delay(%{attempt: attempt, backoff_base: base}) do
    # Exponential backoff: base * (2 ^ (attempt - 1))
    # With some jitter to prevent thundering herd
    base_delay = base * :math.pow(2, attempt - 1)
    # 10% jitter, minimum 1ms
    jitter_amount = max(1, round(base_delay * 0.1))
    jitter = :rand.uniform(jitter_amount)

    round(base_delay + jitter)
  end

  @doc """
  Generates a detailed error report for a failed handler execution.

  ## Examples

      iex> retry_state = %{
      ...>   attempt: 3,
      ...>   max_retries: 3,
      ...>   errors: [
      ...>     %{attempt: 1, error: :timeout, timestamp: ~U[2025-01-15 10:00:00Z]},
      ...>     %{attempt: 2, error: :invalid_format, timestamp: ~U[2025-01-15 10:00:15Z]}
      ...>   ]
      ...> }
      iex> file_info = %{name: "test.pdf", path: "inbox/test.pdf", size: 1024}
      iex> handler = fn _ -> :ok end
      iex> report = Sambex.HotFolder.Handler.generate_error_report(file_info, handler, retry_state)
      iex> String.contains?(report, "Error processing file: test.pdf")
      true

  """
  @spec generate_error_report(map(), handler_spec(), retry_state()) :: String.t()
  def generate_error_report(file_info, handler, retry_state) do
    %{attempt: attempts, errors: errors} = retry_state

    handler_desc =
      case handler do
        fun when is_function(fun, 1) -> "#{inspect(fun)}"
        {mod, fun, args} -> "#{mod}.#{fun}/#{length(args) + 1}"
      end

    final_error =
      case List.first(errors) do
        nil -> "unknown"
        %{error: error} -> inspect(error)
      end

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # Build error history
    error_history =
      errors
      # Show chronological order
      |> Enum.reverse()
      |> Enum.map(fn %{attempt: attempt, error: error, timestamp: ts} ->
        "Attempt #{attempt} (#{DateTime.to_iso8601(ts)}): #{inspect(error)}"
      end)
      |> Enum.join("\n")

    """
    Error processing file: #{file_info.name}
    Timestamp: #{timestamp}
    File Path: #{file_info.path}
    File Size: #{file_info.size} bytes
    Attempts: #{attempts}
    Final Error: #{final_error}
    Handler: #{handler_desc}

    Error History:
    #{error_history}
    """
  end
end
