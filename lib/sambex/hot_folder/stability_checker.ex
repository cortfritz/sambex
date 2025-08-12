defmodule Sambex.HotFolder.StabilityChecker do
  @moduledoc """
  File stability checking to ensure files are completely uploaded before processing.

  Tracks file sizes across multiple polls to detect when uploads are complete.
  Files are considered stable when their size doesn't change for a configurable period.
  """

  @type file_stability :: %{
          name: String.t(),
          size: non_neg_integer(),
          first_seen: DateTime.t(),
          last_seen: DateTime.t(),
          stable_since: DateTime.t() | nil,
          checks: non_neg_integer()
        }

  @type stability_state :: %{
          tracked_files: %{String.t() => file_stability()},
          stability_checks: pos_integer(),
          stability_duration: pos_integer()
        }

  @doc """
  Creates a new stability checker state.

  ## Options

  - `stability_checks`: Number of consecutive polls with same size required (default: 2)
  - `stability_duration`: Minimum time in milliseconds file must be stable (default: 5000)

  ## Examples

      iex> Sambex.HotFolder.StabilityChecker.new()
      %{tracked_files: %{}, stability_checks: 2, stability_duration: 5000}

      iex> Sambex.HotFolder.StabilityChecker.new(stability_checks: 3, stability_duration: 10000)
      %{tracked_files: %{}, stability_checks: 3, stability_duration: 10000}

  """
  @spec new(keyword()) :: stability_state()
  def new(opts \\ []) do
    %{
      tracked_files: %{},
      stability_checks: Keyword.get(opts, :stability_checks, 2),
      stability_duration: Keyword.get(opts, :stability_duration, 5_000)
    }
  end

  @doc """
  Updates the stability state with current file information and returns stable files.

  Returns a tuple of `{stable_files, updated_state}` where stable_files is a list
  of files that are considered stable and ready for processing.

  ## Examples

      iex> state = Sambex.HotFolder.StabilityChecker.new()
      iex> files = [%{name: "test.pdf", size: 1024}]
      iex> {stable, _new_state} = Sambex.HotFolder.StabilityChecker.check_stability(files, state)
      iex> stable
      []

  """
  @spec check_stability([map()], stability_state()) :: {[map()], stability_state()}
  def check_stability(current_files, state) do
    now = DateTime.utc_now()
    current_file_map = Map.new(current_files, &{&1.name, &1})

    # Update tracking for current files
    updated_tracked =
      current_files
      |> Enum.reduce(state.tracked_files, fn file, acc ->
        update_file_tracking(file, acc, now)
      end)
      |> remove_disappeared_files(current_file_map, now)

    # Find stable files
    stable_files =
      updated_tracked
      |> Enum.filter(fn {_name, tracking} ->
        file_stable?(tracking, state, now)
      end)
      |> Enum.map(fn {name, _tracking} ->
        Map.get(current_file_map, name)
      end)
      |> Enum.reject(&is_nil/1)

    new_state = %{state | tracked_files: updated_tracked}
    {stable_files, new_state}
  end

  @doc """
  Removes a file from stability tracking.

  Used when a file has been moved to processing to prevent it from being
  considered again in future polls.

  ## Examples

      iex> state = %{tracked_files: %{"test.pdf" => %{}}}
      iex> new_state = Sambex.HotFolder.StabilityChecker.remove_file(state, "test.pdf")
      iex> new_state.tracked_files
      %{}

  """
  @spec remove_file(stability_state(), String.t()) :: stability_state()
  def remove_file(state, filename) do
    %{state | tracked_files: Map.delete(state.tracked_files, filename)}
  end

  @doc """
  Gets the current tracking information for a file.

  ## Examples

      iex> state = %{tracked_files: %{"test.pdf" => %{size: 1024, checks: 2}}}
      iex> Sambex.HotFolder.StabilityChecker.get_file_tracking(state, "test.pdf")
      %{size: 1024, checks: 2}

      iex> Sambex.HotFolder.StabilityChecker.get_file_tracking(state, "nonexistent.pdf")
      nil

  """
  @spec get_file_tracking(stability_state(), String.t()) :: file_stability() | nil
  def get_file_tracking(state, filename) do
    Map.get(state.tracked_files, filename)
  end

  @doc """
  Returns statistics about the current stability tracking state.

  ## Examples

      iex> state = %{tracked_files: %{"a.pdf" => %{stable_since: ~U[2025-01-15 10:00:00Z]}, "b.pdf" => %{stable_since: nil}}}
      iex> Sambex.HotFolder.StabilityChecker.get_stats(state)
      %{total_tracked: 2, stable_count: 1, unstable_count: 1}

  """
  @spec get_stats(stability_state()) :: map()
  def get_stats(state) do
    tracked_files = Map.values(state.tracked_files)

    stable_count =
      tracked_files
      |> Enum.count(fn tracking -> not is_nil(tracking.stable_since) end)

    %{
      total_tracked: length(tracked_files),
      stable_count: stable_count,
      unstable_count: length(tracked_files) - stable_count
    }
  end

  ## Private Functions

  defp update_file_tracking(file, tracked_files, now) do
    case Map.get(tracked_files, file.name) do
      nil ->
        # First time seeing this file
        tracking = %{
          name: file.name,
          size: file.size,
          first_seen: now,
          last_seen: now,
          stable_since: nil,
          checks: 1
        }

        Map.put(tracked_files, file.name, tracking)

      existing ->
        if existing.size == file.size do
          # Size hasn't changed, increment checks and last_seen
          updated = %{existing | last_seen: now, checks: existing.checks + 1}
          # Pass updated record to maybe_mark_stable
          updated = %{
            updated
            | stable_since: maybe_mark_stable(updated, now)
          }

          Map.put(tracked_files, file.name, updated)
        else
          # Size changed, reset stability
          updated = %{existing | size: file.size, last_seen: now, stable_since: nil, checks: 1}
          Map.put(tracked_files, file.name, updated)
        end
    end
  end

  defp maybe_mark_stable(%{stable_since: nil, checks: checks}, now) when checks >= 2 do
    # Mark as stable on the second consecutive check with same size
    now
  end

  defp maybe_mark_stable(%{stable_since: stable_since}, _now) when not is_nil(stable_since) do
    # Already stable, keep the original timestamp
    stable_since
  end

  defp maybe_mark_stable(%{stable_since: nil}, _now) do
    # Not enough checks yet, remain unstable
    nil
  end

  defp remove_disappeared_files(tracked_files, current_file_map, now) do
    # Remove files that haven't been seen for longer than stability duration
    # 60 seconds
    cutoff_time = DateTime.add(now, -60_000, :millisecond)

    tracked_files
    |> Enum.filter(fn {name, tracking} ->
      Map.has_key?(current_file_map, name) or
        DateTime.compare(tracking.last_seen, cutoff_time) == :gt
    end)
    |> Map.new()
  end

  defp file_stable?(tracking, state, now) do
    # File must:
    # 1. Have enough consecutive checks with same size
    # 2. Be stable for minimum duration
    # 3. Have a stable_since timestamp

    case tracking.stable_since do
      nil ->
        false

      stable_since ->
        duration_ms = DateTime.diff(now, stable_since, :millisecond)

        tracking.checks >= state.stability_checks and
          duration_ms >= state.stability_duration
    end
  end
end
