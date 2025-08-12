# Build configuration for Sambex
# This file detects the correct libsmbclient paths for different platforms

# Try environment variables first
include_dir = System.get_env("SAMBEX_INCLUDE_DIR")
lib_dir = System.get_env("SAMBEX_LIB_DIR")

if include_dir && lib_dir do
  IO.puts("Using Samba paths from environment variables:")
  IO.puts("  Include: #{include_dir}")
  IO.puts("  Lib: #{lib_dir}")
  {[include_dir], "-lsmbclient"}
else
  # Auto-detect based on platform and common locations
  case :os.type() do
    {:unix, :darwin} ->
      # macOS - try Homebrew locations
      cond do
        # Homebrew ARM (Apple Silicon)
        File.exists?("/opt/homebrew/include/libsmbclient.h") ->
          IO.puts("Found Samba via Homebrew (Apple Silicon)")

          # Try to find exact version in Cellar
          if File.exists?("/opt/homebrew/Cellar/samba") do
            case File.ls("/opt/homebrew/Cellar/samba") do
              {:ok, [version | _]} ->
                version_path = "/opt/homebrew/Cellar/samba/#{version}"
                {["#{version_path}/include"], "#{version_path}/lib/libsmbclient.dylib"}

              _ ->
                {["/opt/homebrew/include"], "-lsmbclient"}
            end
          else
            {["/opt/homebrew/include"], "-lsmbclient"}
          end

        # Homebrew Intel
        File.exists?("/usr/local/include/libsmbclient.h") ->
          IO.puts("Found Samba via Homebrew (Intel)")
          {["/usr/local/include"], "-lsmbclient"}

        # MacPorts
        File.exists?("/opt/local/include/libsmbclient.h") ->
          IO.puts("Found Samba via MacPorts")
          {["/opt/local/include"], "-lsmbclient"}

        # System paths
        File.exists?("/usr/include/libsmbclient.h") ->
          IO.puts("Found Samba in system paths")
          {["/usr/include"], "-lsmbclient"}

        true ->
          raise CompileError,
            description: """
            libsmbclient not found on macOS.

            Please install Samba:
              brew install samba

            Or set custom paths:
              export SAMBEX_INCLUDE_DIR=/path/to/samba/include
              export SAMBEX_LIB_DIR=/path/to/samba/lib
            """
      end

    {:unix, :linux} ->
      # Linux - try common package manager locations
      cond do
        # Try Debian/Ubuntu paths first
        File.exists?("/usr/include/libsmbclient.h") ->
          IO.puts("Found Samba in system paths (Debian/Ubuntu)")

          if File.exists?("/usr/lib/aarch64-linux-gnu/libsmbclient.so") do
            {["/usr/include"], "/usr/lib/aarch64-linux-gnu/libsmbclient.so"}
          else
            if File.exists?("/usr/lib/x86_64-linux-gnu/libsmbclient.so") do
              {["/usr/include"], "/usr/lib/x86_64-linux-gnu/libsmbclient.so"}
            else
              if File.exists?("/usr/lib/libsmbclient.so") do
                {["/usr/include"], "/usr/lib/libsmbclient.so"}
              else
                {["/usr/include"], "-lsmbclient"}
              end
            end
          end

        # RHEL/CentOS/Fedora with newer Samba (including Ubuntu/Debian and Alpine Linux)
        File.exists?("/usr/include/samba-4.0/libsmbclient.h") ->
          IO.puts("Found Samba in /usr/include/samba-4.0")

          cond do
            # Ubuntu/Debian ARM64
            File.exists?("/usr/lib/aarch64-linux-gnu/libsmbclient.so") ->
              {["/usr/include/samba-4.0"], "/usr/lib/aarch64-linux-gnu/libsmbclient.so"}

            # Ubuntu/Debian x86_64
            File.exists?("/usr/lib/x86_64-linux-gnu/libsmbclient.so") ->
              {["/usr/include/samba-4.0"], "/usr/lib/x86_64-linux-gnu/libsmbclient.so"}

            # Standard Linux /usr/lib
            File.exists?("/usr/lib/libsmbclient.so") ->
              {["/usr/include/samba-4.0"], "/usr/lib/libsmbclient.so"}

            # Fallback to linker flag
            true ->
              {["/usr/include/samba-4.0"], "-lsmbclient"}
          end

        # Try /usr/local
        File.exists?("/usr/local/include/libsmbclient.h") ->
          IO.puts("Found Samba in /usr/local")
          {["/usr/local/include"], "-lsmbclient"}

        true ->
          raise CompileError,
            description: """
            libsmbclient not found on Linux.

            Please install Samba development libraries:
              # Ubuntu/Debian:
              sudo apt-get install libsmbclient-dev

              # RHEL/CentOS/Fedora:
              sudo dnf install libsmbclient-devel

              # Alpine:
              sudo apk add samba-dev

            Or set custom paths:
              export SAMBEX_INCLUDE_DIR=/path/to/samba/include
              export SAMBEX_LIB_DIR=/path/to/samba/lib
            """
      end

    _ ->
      # Other Unix systems
      if File.exists?("/usr/include/libsmbclient.h") do
        IO.puts("Found Samba in system paths")
        {["/usr/include"], "-lsmbclient"}
      else
        raise CompileError,
          description: """
          libsmbclient not found.

          Please install Samba development libraries for your system,
          or set custom paths:
            export SAMBEX_INCLUDE_DIR=/path/to/samba/include
            export SAMBEX_LIB_DIR=/path/to/samba/lib
          """
      end
  end
end
