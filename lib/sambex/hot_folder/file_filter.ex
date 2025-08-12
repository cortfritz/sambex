defmodule Sambex.HotFolder.FileFilter do
  @moduledoc """
  File filtering functionality for Sambex HotFolder.

  Provides utilities to filter files based on various criteria including
  name patterns, size limits, and MIME types.
  """

  alias Sambex.HotFolder.Config

  @type file_info :: %{
          name: String.t(),
          path: String.t(),
          size: non_neg_integer()
        }

  @doc """
  Checks if a file passes all configured filters.

  ## Examples

      iex> file = %{name: "document.pdf", path: "inbox/document.pdf", size: 1024}
      iex> config = %Sambex.HotFolder.Config{filters: %{name_patterns: [~r/\.pdf$/i]}}
      iex> Sambex.HotFolder.FileFilter.passes?(file, config)
      true

      iex> file = %{name: ".hidden", path: "inbox/.hidden", size: 100}
      iex> config = %Sambex.HotFolder.Config{filters: %{exclude_patterns: [~r/^\./]}}
      iex> Sambex.HotFolder.FileFilter.passes?(file, config)
      false

  """
  @spec passes?(file_info(), Config.t()) :: boolean()
  def passes?(file, %Config{filters: filters}) do
    passes_name_patterns?(file, filters) and
      passes_exclude_patterns?(file, filters) and
      passes_size_limits?(file, filters) and
      passes_mime_types?(file, filters)
  end

  @doc """
  Filters a list of files, returning only those that pass all filters.

  ## Examples

      iex> files = [%{name: "doc.pdf", path: "inbox/doc.pdf", size: 1024}]
      iex> {:ok, config} = Sambex.HotFolder.Config.new(%{
      ...>   connection: :test, 
      ...>   handler: fn _ -> :ok end,
      ...>   filters: %{name_patterns: [~r/\\.pdf$/]}
      ...> })
      iex> result = Sambex.HotFolder.FileFilter.filter_files(files, config)
      iex> length(result)
      1

  """
  @spec filter_files([file_info()], Config.t()) :: [file_info()]
  def filter_files(files, config) when is_list(files) do
    Enum.filter(files, &passes?(&1, config))
  end

  ## Private Functions

  defp passes_name_patterns?(_file, %{name_patterns: []}), do: true

  defp passes_name_patterns?(file, %{name_patterns: patterns}) do
    Enum.any?(patterns, &Regex.match?(&1, file.name))
  end

  defp passes_name_patterns?(_file, _config), do: true

  defp passes_exclude_patterns?(_file, %{exclude_patterns: []}), do: true

  defp passes_exclude_patterns?(file, %{exclude_patterns: patterns}) do
    not Enum.any?(patterns, &Regex.match?(&1, file.name))
  end

  defp passes_exclude_patterns?(_file, _config), do: true

  defp passes_size_limits?(file, filters) do
    min_size = Map.get(filters, :min_size, 0)
    max_size = Map.get(filters, :max_size, :infinity)

    file.size >= min_size and
      (max_size == :infinity or file.size <= max_size)
  end

  defp passes_mime_types?(_file, %{mime_types: []}), do: true

  defp passes_mime_types?(file, %{mime_types: types}) when length(types) > 0 do
    # Use extension-based MIME type detection
    detected_type = mime_type_from_extension(file.name)

    Enum.any?(types, fn allowed_type ->
      # Support both exact matches and wildcard patterns
      case String.split(allowed_type, "/") do
        [main_type, "*"] ->
          String.starts_with?(detected_type, main_type <> "/")

        _ ->
          detected_type == allowed_type
      end
    end)
  end

  defp passes_mime_types?(_file, _config), do: true

  @doc """
  Detects MIME type of a file based on its content.

  This is a placeholder implementation that uses extension-based detection.
  In a full implementation, this would read file headers and detect MIME types.

  ## Examples

      iex> Sambex.HotFolder.FileFilter.detect_mime_type("document.pdf")
      "application/pdf"

  """
  @spec detect_mime_type(String.t()) :: String.t() | nil
  def detect_mime_type(file_path) do
    # For now, use extension-based detection as a fallback
    mime_type_from_extension(file_path)
  end

  @doc """
  Returns a MIME type based on file extension as a fallback.

  ## Examples

      iex> Sambex.HotFolder.FileFilter.mime_type_from_extension("document.pdf")
      "application/pdf"

      iex> Sambex.HotFolder.FileFilter.mime_type_from_extension("image.jpg")
      "image/jpeg"

      iex> Sambex.HotFolder.FileFilter.mime_type_from_extension("unknown.xyz")
      "application/octet-stream"

  """
  @spec mime_type_from_extension(String.t()) :: String.t()
  def mime_type_from_extension(filename) do
    extension = filename |> Path.extname() |> String.downcase()

    case extension do
      ".pdf" -> "application/pdf"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".png" -> "image/png"
      ".gif" -> "image/gif"
      ".txt" -> "text/plain"
      ".html" -> "text/html"
      ".htm" -> "text/html"
      ".css" -> "text/css"
      ".js" -> "application/javascript"
      ".json" -> "application/json"
      ".xml" -> "application/xml"
      ".zip" -> "application/zip"
      ".doc" -> "application/msword"
      ".docx" -> "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
      ".xls" -> "application/vnd.ms-excel"
      ".xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      ".ppt" -> "application/vnd.ms-powerpoint"
      ".pptx" -> "application/vnd.openxmlformats-officedocument.presentationml.presentation"
      _ -> "application/octet-stream"
    end
  end
end
