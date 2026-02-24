defmodule Sambex.HotFolder.Config do
  @moduledoc """
  Configuration structure and validation for Sambex HotFolder.

  The HotFolder configuration defines how files are monitored and processed,
  including connection details, folder structure, filtering rules, and
  processing behavior.

  ## Configuration Options

  ### Connection Settings
  You can either provide connection details directly or reference an existing connection:

      # Direct connection
      %Config{
        url: "smb://server/share",
        username: "user",
        password: "pass"
      }

      # Use existing connection
      %Config{
        connection: :my_connection
      }

  ### Folder Structure
  All folder names are relative to the base_path within the SMB share:

      %Config{
        base_path: "print-queue",
        folders: %{
          incoming: "inbox",
          processing: "working",
          success: "completed",
          errors: "failed"
        }
      }

  ### File Filtering
  Control which files are processed using various filter criteria:

      %Config{
        filters: %{
          name_patterns: [~r/\.pdf$/i, ~r/job_\\d+\\.txt$/],
          exclude_patterns: [~r/^\\./],  # Skip hidden files
          min_size: 1024,               # 1KB minimum
          max_size: 50_000_000,         # 50MB maximum
          mime_types: ["application/pdf"]
        }
      }
  """

  @type handler_spec ::
          (map() -> {:ok, any()} | {:error, any()})
          | {module(), atom(), list()}

  @type folder_config :: %{
          incoming: String.t(),
          processing: String.t(),
          success: String.t(),
          errors: String.t()
        }

  @type filter_config :: %{
          name_patterns: [Regex.t()],
          exclude_patterns: [Regex.t()],
          min_size: non_neg_integer(),
          max_size: non_neg_integer() | :infinity,
          mime_types: [String.t()]
        }

  @type poll_config :: %{
          initial: pos_integer(),
          max: pos_integer(),
          backoff_factor: float()
        }

  @type t :: %__MODULE__{
          # Connection (either connection name OR url+credentials)
          connection: atom() | nil,
          url: String.t() | nil,
          username: String.t() | nil,
          password: String.t() | nil,

          # Core functionality
          handler: handler_spec() | nil,
          base_path: String.t(),

          # Folder names (all relative to base_path)
          folders: folder_config(),

          # Polling behavior
          poll_interval: poll_config(),

          # File filtering
          filters: filter_config(),

          # Processing options
          handler_timeout: pos_integer(),
          max_retries: non_neg_integer(),
          create_folders: boolean()
        }

  defstruct [
    # Connection (either connection name OR url+credentials)
    connection: nil,
    url: nil,
    username: nil,
    password: nil,

    # Core functionality
    handler: nil,
    base_path: "",

    # Folder names (all relative to base_path)
    folders: %{
      incoming: "incoming",
      processing: "processing",
      success: "success",
      errors: "errors"
    },

    # Polling behavior
    poll_interval: %{
      initial: 2_000,
      max: 30_000,
      backoff_factor: 1.5
    },

    # File filtering (exclude_patterns populated at runtime to avoid Regex in struct default)
    filters: %{
      name_patterns: [],
      exclude_patterns: [],
      min_size: 0,
      max_size: :infinity,
      mime_types: []
    },

    # Processing options
    handler_timeout: 60_000,
    max_retries: 3,
    create_folders: true
  ]

  @doc """
  Creates and validates a HotFolder configuration.

  ## Examples

      iex> {:ok, config} = Sambex.HotFolder.Config.new(%{
      ...>    url: "smb://server/share",
      ...>    username: "user",
      ...>    password: "pass",
      ...>    handler: &IO.inspect/1
      ...>  })
      iex> config.url
      "smb://server/share"

      iex> Sambex.HotFolder.Config.new(%{handler: &IO.inspect/1})
      {:error, "Must provide either connection name or url+username+password"}

  """
  @spec new(map()) :: {:ok, t()} | {:error, String.t()}
  def new(params) when is_map(params) do
    config = struct(__MODULE__, params)
    # Apply default exclude pattern for hidden files if not specified
    config = apply_default_filters(config)
    validate(config)
  end

  defp apply_default_filters(%__MODULE__{filters: filters} = config) do
    default_exclude = [~r/^\./]

    updated_filters =
      if filters[:exclude_patterns] == [] do
        Map.put(filters, :exclude_patterns, default_exclude)
      else
        filters
      end

    %{config | filters: updated_filters}
  end

  @doc """
  Creates and validates a HotFolder configuration, raising on error.

  ## Examples

      iex> config = Sambex.HotFolder.Config.new!(%{
      ...>   connection: :my_connection,
      ...>   handler: &IO.inspect/1
      ...> })
      iex> config.connection
      :my_connection

  """
  @spec new!(map()) :: t()
  def new!(params) when is_map(params) do
    case new(params) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Validates a HotFolder configuration.

  Returns `{:ok, config}` if valid, `{:error, reason}` otherwise.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, String.t()}
  def validate(%__MODULE__{} = config) do
    with :ok <- validate_connection(config),
         :ok <- validate_handler(config),
         :ok <- validate_folders(config),
         :ok <- validate_poll_interval(config),
         :ok <- validate_filters(config),
         :ok <- validate_processing_options(config) do
      {:ok, config}
    end
  end

  # Private validation functions

  defp validate_connection(%{connection: nil, url: nil}) do
    {:error, "Must provide either connection name or url+username+password"}
  end

  defp validate_connection(%{connection: conn}) when is_atom(conn) and not is_nil(conn) do
    :ok
  end

  defp validate_connection(%{url: url, username: username, password: password})
       when is_binary(url) and is_binary(username) and is_binary(password) do
    if String.starts_with?(url, "smb://") do
      :ok
    else
      {:error, "URL must start with 'smb://'"}
    end
  end

  defp validate_connection(_) do
    {:error, "Invalid connection configuration"}
  end

  defp validate_handler(%{handler: nil}) do
    {:error, "Handler is required"}
  end

  defp validate_handler(%{handler: handler}) when is_function(handler, 1) do
    :ok
  end

  defp validate_handler(%{handler: {mod, fun, args}})
       when is_atom(mod) and is_atom(fun) and is_list(args) do
    if function_exported?(mod, fun, length(args) + 1) do
      :ok
    else
      {:error, "Handler function #{mod}.#{fun}/#{length(args) + 1} does not exist"}
    end
  end

  defp validate_handler(_) do
    {:error, "Handler must be a function/1 or {module, function, args} tuple"}
  end

  defp validate_folders(%{folders: folders}) when is_map(folders) do
    required_keys = [:incoming, :processing, :success, :errors]

    case Enum.find(required_keys, fn key -> !Map.has_key?(folders, key) end) do
      nil ->
        if Enum.all?(Map.values(folders), &is_binary/1) do
          :ok
        else
          {:error, "All folder names must be strings"}
        end

      missing_key ->
        {:error, "Missing required folder: #{missing_key}"}
    end
  end

  defp validate_folders(_) do
    {:error, "Folders must be a map"}
  end

  defp validate_poll_interval(%{
         poll_interval: %{initial: initial, max: max, backoff_factor: factor}
       })
       when is_integer(initial) and initial > 0 and
              is_integer(max) and max >= initial and
              is_float(factor) and factor > 1.0 do
    :ok
  end

  defp validate_poll_interval(_) do
    {:error, "Invalid poll interval configuration"}
  end

  defp validate_filters(%{filters: filters}) when is_map(filters) do
    with :ok <- validate_patterns(filters[:name_patterns] || []),
         :ok <- validate_patterns(filters[:exclude_patterns] || []),
         :ok <- validate_size_limits(filters),
         :ok <- validate_mime_types(filters[:mime_types] || []) do
      :ok
    end
  end

  defp validate_filters(_) do
    {:error, "Filters must be a map"}
  end

  defp validate_patterns(patterns) when is_list(patterns) do
    if Enum.all?(patterns, fn pattern -> match?(%Regex{}, pattern) end) do
      :ok
    else
      {:error, "Name and exclude patterns must be regex patterns"}
    end
  end

  defp validate_patterns(_), do: {:error, "Patterns must be a list"}

  defp validate_size_limits(%{min_size: min, max_size: max})
       when is_integer(min) and min >= 0 and
              (max == :infinity or (is_integer(max) and max >= min)) do
    :ok
  end

  defp validate_size_limits(%{min_size: min}) when is_integer(min) and min >= 0, do: :ok

  defp validate_size_limits(%{max_size: max})
       when max == :infinity or (is_integer(max) and max >= 0),
       do: :ok

  defp validate_size_limits(%{}), do: :ok

  defp validate_mime_types(types) when is_list(types) do
    if Enum.all?(types, &is_binary/1) do
      :ok
    else
      {:error, "MIME types must be strings"}
    end
  end

  defp validate_mime_types(_), do: {:error, "MIME types must be a list"}

  defp validate_processing_options(%{handler_timeout: timeout, max_retries: retries})
       when is_integer(timeout) and timeout > 0 and is_integer(retries) and retries >= 0 do
    :ok
  end

  defp validate_processing_options(_) do
    {:error, "Invalid processing options"}
  end

  @doc """
  Returns the full path for a given folder type.

  ## Examples

      iex> config = %Sambex.HotFolder.Config{base_path: "queue", folders: %{incoming: "inbox"}}
      iex> Sambex.HotFolder.Config.folder_path(config, :incoming)
      "queue/inbox"

      iex> config = %Sambex.HotFolder.Config{base_path: "", folders: %{success: "done"}}
      iex> Sambex.HotFolder.Config.folder_path(config, :success)
      "done"

  """
  @spec folder_path(t(), atom()) :: String.t()
  def folder_path(%__MODULE__{base_path: base, folders: folders}, folder_type) do
    folder_name = Map.get(folders, folder_type)

    case {base, folder_name} do
      {"", name} -> name
      {base, name} -> Path.join(base, name)
    end
  end

  @doc """
  Returns all folder paths as a map.

  ## Examples

      iex> config = %Sambex.HotFolder.Config{base_path: "queue"}
      iex> Sambex.HotFolder.Config.all_folder_paths(config)
      %{
        incoming: "queue/incoming",
        processing: "queue/processing",
        success: "queue/success",
        errors: "queue/errors"
      }

  """
  @spec all_folder_paths(t()) :: %{atom() => String.t()}
  def all_folder_paths(%__MODULE__{} = config) do
    Map.new([:incoming, :processing, :success, :errors], fn folder_type ->
      {folder_type, folder_path(config, folder_type)}
    end)
  end
end
