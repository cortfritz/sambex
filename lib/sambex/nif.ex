defmodule Sambex.Nif do
  @moduledoc false

  # Detect system library paths for libsmbclient
  @external_resource "lib/sambex/build_config.ex"
  {{build_include_dirs, build_link_libs}, _bindings} =
    Code.eval_file("lib/sambex/build_config.ex")

  use Zig,
    otp_app: :sambex,
    c: [
      include_dirs: build_include_dirs,
      link_lib: build_link_libs
    ]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  // C imports for libsmbclient
  const c = @cImport({
      @cInclude("libsmbclient.h");
      @cInclude("stdlib.h");
      @cInclude("string.h");
      @cInclude("errno.h");
      @cInclude("sys/stat.h");
  });

  // Global credentials storage
  var global_workgroup: [256]u8 = undefined;
  var global_username: [256]u8 = undefined;
  var global_password: [256]u8 = undefined;
  var credentials_set: bool = false;

  // Authentication callback
  fn auth_callback(srv: [*c]const u8, shr: [*c]const u8, workgroup: [*c]u8, workgroup_len: c_int, username: [*c]u8, username_len: c_int, password: [*c]u8, password_len: c_int) callconv(.c) void {
      _ = srv;
      _ = shr;

      if (!credentials_set) return;

      // Copy workgroup
      const max_wg_len = @as(usize, @intCast(workgroup_len - 1));
      const wg_len = if (max_wg_len < global_workgroup.len - 1) max_wg_len else global_workgroup.len - 1;
      @memcpy(workgroup[0..wg_len], global_workgroup[0..wg_len]);
      workgroup[wg_len] = 0;

      // Copy username
      const max_user_len = @as(usize, @intCast(username_len - 1));
      const user_len = if (max_user_len < global_username.len - 1) max_user_len else global_username.len - 1;
      @memcpy(username[0..user_len], global_username[0..user_len]);
      username[user_len] = 0;

      // Copy password
      const max_pass_len = @as(usize, @intCast(password_len - 1));
      const pass_len = if (max_pass_len < global_password.len - 1) max_pass_len else global_password.len - 1;
      @memcpy(password[0..pass_len], global_password[0..pass_len]);
      password[pass_len] = 0;
  }

  /// Initialize SMB client
  pub fn init_smb() beam.term {
      // Initialize libsmbclient
      const result = c.smbc_init(auth_callback, 0);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const init_failed_atom = beam.make_into_atom("init_failed", .{});
          return beam.make(.{error_atom, init_failed_atom}, .{});
      }
      return beam.make_into_atom("ok", .{});
  }

  /// Create and initialize SMB context
  fn create_smb_context() ?*c.SMBCCTX {
      const ctx = c.smbc_new_context();
      if (ctx == null) {
          return null;
      }

      // Set authentication function
      c.smbc_setFunctionAuthData(ctx, auth_callback);

      // Initialize the context
      if (c.smbc_init_context(ctx) == null) {
          _ = c.smbc_free_context(ctx, @intCast(1));
          return null;
      }

      return ctx;
  }

  /// Test function to verify compilation
  pub fn add_one(number: i64) i64 {
      return number + 1;
  }

  /// Set global credentials
  pub fn set_credentials(workgroup: []const u8, username: []const u8, password: []const u8) beam.term {
      if (workgroup.len >= global_workgroup.len or username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const too_long_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, too_long_atom}, .{});
      }

      // Store credentials in global variables
      @memcpy(global_workgroup[0..workgroup.len], workgroup);
      global_workgroup[workgroup.len] = 0;

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      credentials_set = true;

      return beam.make_into_atom("ok", .{});
  }

  /// Open directory and return file descriptor
  pub fn open_dir(url: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const dir = c.smbc_opendir(url_cstr.ptr);
      if (dir < 0) {
          const error_atom = beam.make_error_atom(.{});
          const open_dir_failed_atom = beam.make_into_atom("open_dir_failed", .{});
          return beam.make(.{error_atom, open_dir_failed_atom}, .{});
      }

      const ok_atom = beam.make_into_atom("ok", .{});
      const fd_term = beam.make(@as(i64, @intCast(dir)), .{});
      return beam.make(.{ok_atom, fd_term}, .{});
  }

  /// Close directory
  pub fn close_dir(fd: i32) beam.term {
      const result = c.smbc_closedir(fd);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const close_dir_failed_atom = beam.make_into_atom("close_dir_failed", .{});
          return beam.make(.{error_atom, close_dir_failed_atom}, .{});
      }
      return beam.make_into_atom("ok", .{});
  }

  /// Connect to SMB share
  pub fn connect(url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const ctx = create_smb_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_failed_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, context_failed_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, @intCast(1));

      // Store credentials for this operation
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const too_long_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, too_long_atom}, .{});
      }

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      // Set default workgroup if not already set
      if (!credentials_set) {
          const default_wg = "WORKGROUP";
          @memcpy(global_workgroup[0..default_wg.len], default_wg);
          global_workgroup[default_wg.len] = 0;
      }

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const dir = c.smbc_opendir(url_cstr.ptr);
      if (dir < 0) {
          const error_atom = beam.make_error_atom(.{});
          const connection_failed_atom = beam.make_into_atom("connection_failed", .{});
          return beam.make(.{error_atom, connection_failed_atom}, .{});
      }

      _ = c.smbc_closedir(dir);
      return beam.make_into_atom("ok", .{});
  }

  /// List directory contents
  pub fn list_dir(url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const ctx = create_smb_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_failed_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, context_failed_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, @intCast(1));

      // Store credentials for this operation
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const too_long_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, too_long_atom}, .{});
      }

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      // Set default workgroup if not already set
      if (!credentials_set) {
          const default_wg = "WORKGROUP";
          @memcpy(global_workgroup[0..default_wg.len], default_wg);
          global_workgroup[default_wg.len] = 0;
      }

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const dir = c.smbc_opendir(url_cstr.ptr);
      if (dir < 0) {
          const error_atom = beam.make_error_atom(.{});
          const open_dir_failed_atom = beam.make_into_atom("open_dir_failed", .{});
          return beam.make(.{error_atom, open_dir_failed_atom}, .{});
      }
      defer _ = c.smbc_closedir(dir);

      var files: std.ArrayListUnmanaged(beam.term) = .{};

      while (true) {
          const dirent = c.smbc_readdir(@as(c_uint, @intCast(dir)));
          if (dirent == null) break;

          const name = std.mem.span(@as([*:0]const u8, @ptrCast(&dirent.*.name)));
          const file_type_str = switch (dirent.*.smbc_type) {
              c.SMBC_DIR => "directory",
              c.SMBC_FILE => "file",
              c.SMBC_PRINTER_SHARE => "printer",
              c.SMBC_COMMS_SHARE => "comms",
              c.SMBC_IPC_SHARE => "ipc",
              c.SMBC_FILE_SHARE => "share",
              c.SMBC_WORKGROUP => "workgroup",
              c.SMBC_SERVER => "server",
              else => "unknown",
          };

          const name_binary = beam.make(name, .{});
          const file_type_atom = beam.make_into_atom(file_type_str, .{});
          const entry = beam.make(.{name_binary, file_type_atom}, .{});
          files.append(allocator, entry) catch {
              const error_atom = beam.make_error_atom(.{});
              const memory_error_atom = beam.make_into_atom("memory_error", .{});
              return beam.make(.{error_atom, memory_error_atom}, .{});
          };
      }

      const ok_atom = beam.make_into_atom("ok", .{});
      const file_list = beam.make(files.items, .{});
      return beam.make(.{ok_atom, file_list}, .{});
  }

  /// Read file from SMB share
  pub fn read_file(url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const ctx = create_smb_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_failed_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, context_failed_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, @intCast(1));

      // Store credentials for this operation
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const too_long_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, too_long_atom}, .{});
      }

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      // Set default workgroup if not already set
      if (!credentials_set) {
          const default_wg = "WORKGROUP";
          @memcpy(global_workgroup[0..default_wg.len], default_wg);
          global_workgroup[default_wg.len] = 0;
      }

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const fd = c.smbc_open(url_cstr.ptr, c.O_RDONLY, 0);
      if (fd < 0) {
          const error_atom = beam.make_error_atom(.{});
          const open_file_failed_atom = beam.make_into_atom("open_file_failed", .{});
          return beam.make(.{error_atom, open_file_failed_atom}, .{});
      }
      defer _ = c.smbc_close(fd);

      // Get file size
      var stat_buf: c.struct_stat = undefined;
      if (c.smbc_fstat(fd, &stat_buf) < 0) {
          const error_atom = beam.make_error_atom(.{});
          const stat_failed_atom = beam.make_into_atom("stat_failed", .{});
          return beam.make(.{error_atom, stat_failed_atom}, .{});
      }

      const file_size: usize = @intCast(stat_buf.st_size);
      const buffer = allocator.alloc(u8, file_size) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const bytes_read = c.smbc_read(fd, buffer.ptr, file_size);
      if (bytes_read < 0) {
          const error_atom = beam.make_error_atom(.{});
          const read_failed_atom = beam.make_into_atom("read_failed", .{});
          return beam.make(.{error_atom, read_failed_atom}, .{});
      }

      const data = buffer[0..@as(usize, @intCast(bytes_read))];
      const ok_atom = beam.make_into_atom("ok", .{});
      const data_binary = beam.make(data, .{});
      return beam.make(.{ok_atom, data_binary}, .{});
  }

  /// Write file to SMB share
  pub fn write_file(url: []const u8, content: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const ctx = create_smb_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_failed_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, context_failed_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, @intCast(1));

      // Store credentials for this operation
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const too_long_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, too_long_atom}, .{});
      }

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      // Set default workgroup if not already set
      if (!credentials_set) {
          const default_wg = "WORKGROUP";
          @memcpy(global_workgroup[0..default_wg.len], default_wg);
          global_workgroup[default_wg.len] = 0;
      }

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const fd = c.smbc_open(url_cstr.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, 0o644);
      if (fd < 0) {
          const error_atom = beam.make_error_atom(.{});
          const open_file_failed_atom = beam.make_into_atom("open_file_failed", .{});
          return beam.make(.{error_atom, open_file_failed_atom}, .{});
      }
      defer _ = c.smbc_close(fd);

      const bytes_written = c.smbc_write(fd, content.ptr, content.len);
      if (bytes_written < 0) {
          const error_atom = beam.make_error_atom(.{});
          const write_failed_atom = beam.make_into_atom("write_failed", .{});
          return beam.make(.{error_atom, write_failed_atom}, .{});
      }

      const ok_atom = beam.make_into_atom("ok", .{});
      const bytes_written_int = beam.make(@as(i64, @intCast(bytes_written)), .{});
      return beam.make(.{ok_atom, bytes_written_int}, .{});
  }

  /// Delete file from SMB share
  pub fn delete_file(url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const ctx = create_smb_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_failed_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, context_failed_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, @intCast(1));

      // Store credentials for this operation
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const too_long_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, too_long_atom}, .{});
      }

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      // Set default workgroup if not already set
      if (!credentials_set) {
          const default_wg = "WORKGROUP";
          @memcpy(global_workgroup[0..default_wg.len], default_wg);
          global_workgroup[default_wg.len] = 0;
      }

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      // Set the context as current for libsmbclient
      const old_ctx = c.smbc_set_context(ctx);
      defer _ = c.smbc_set_context(old_ctx);

      // Delete the file using the proper context
      const result = c.smbc_unlink(url_cstr.ptr);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const delete_failed_atom = beam.make_into_atom("delete_failed", .{});
          const result_term = beam.make(result, .{});
          return beam.make(.{error_atom, delete_failed_atom, result_term}, .{});
      }

      return beam.make_into_atom("ok", .{});
  }

  /// Move/rename file on SMB share
  pub fn move_file(source_url: []const u8, dest_url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      // Create SMB context
      const ctx = c.smbc_new_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_error_atom = beam.make_into_atom("context_creation_failed", .{});
          return beam.make(.{error_atom, context_error_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, 0);

      // Initialize context
      if (c.smbc_init_context(ctx) == null) {
          const error_atom = beam.make_error_atom(.{});
          const init_error_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, init_error_atom}, .{});
      }

      // Set authentication callback
      c.smbc_setFunctionAuthData(ctx, auth_callback);

      // Set credentials
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const creds_error_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, creds_error_atom}, .{});
      }

      @memcpy(global_workgroup[0..9], "WORKGROUP");
      global_workgroup[9] = 0;

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      credentials_set = true;

      const source_cstr = allocator.dupeZ(u8, source_url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const dest_cstr = allocator.dupeZ(u8, dest_url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      // Set the context as current for libsmbclient
      const old_ctx = c.smbc_set_context(ctx);
      defer _ = c.smbc_set_context(old_ctx);

      // Rename/move the file using the proper context
      const result = c.smbc_rename(source_cstr.ptr, dest_cstr.ptr);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const move_failed_atom = beam.make_into_atom("move_failed", .{});
          const result_term = beam.make(result, .{});
          return beam.make(.{error_atom, move_failed_atom, result_term}, .{});
      }

      return beam.make_into_atom("ok", .{});
  }

  /// Get file statistics/metadata from SMB share
  pub fn get_file_stats(url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      // Create SMB context
      const ctx = c.smbc_new_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_error_atom = beam.make_into_atom("context_creation_failed", .{});
          return beam.make(.{error_atom, context_error_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, 0);

      // Initialize context
      if (c.smbc_init_context(ctx) == null) {
          const error_atom = beam.make_error_atom(.{});
          const init_error_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, init_error_atom}, .{});
      }

      // Set authentication callback
      c.smbc_setFunctionAuthData(ctx, auth_callback);

      // Set credentials
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const creds_error_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, creds_error_atom}, .{});
      }

      @memcpy(global_workgroup[0..9], "WORKGROUP");
      global_workgroup[9] = 0;

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      // Set the context as current for libsmbclient
      const old_ctx = c.smbc_set_context(ctx);
      defer _ = c.smbc_set_context(old_ctx);

      // Get file statistics
      var stat_buf: c.struct_stat = undefined;
      const result = c.smbc_stat(url_cstr.ptr, &stat_buf);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const stat_failed_atom = beam.make_into_atom("stat_failed", .{});
          const result_term = beam.make(result, .{});
          return beam.make(.{error_atom, stat_failed_atom, result_term}, .{});
      }

      // Convert file mode to file type atom
      const file_type_atom = if (c.S_ISREG(stat_buf.st_mode))
          beam.make_into_atom("file", .{})
      else if (c.S_ISDIR(stat_buf.st_mode))
          beam.make_into_atom("directory", .{})
      else if (c.S_ISLNK(stat_buf.st_mode))
          beam.make_into_atom("symlink", .{})
      else
          beam.make_into_atom("other", .{});

      // Create a map with file statistics
      const ok_atom = beam.make_into_atom("ok", .{});
      const size_atom = beam.make_into_atom("size", .{});
      const type_atom = beam.make_into_atom("type", .{});
      const mode_atom = beam.make_into_atom("mode", .{});
      const atime_atom = beam.make_into_atom("access_time", .{});
      const mtime_atom = beam.make_into_atom("modification_time", .{});
      const ctime_atom = beam.make_into_atom("change_time", .{});
      const uid_atom = beam.make_into_atom("uid", .{});
      const gid_atom = beam.make_into_atom("gid", .{});
      const links_atom = beam.make_into_atom("links", .{});

      const size_term = beam.make(@as(i64, @intCast(stat_buf.st_size)), .{});
      const mode_term = beam.make(@as(i32, @intCast(stat_buf.st_mode & 0o7777)), .{});
      // Handle timespec field differences between macOS and Linux
      const atime_term = if (@hasField(@TypeOf(stat_buf), "st_atimespec"))
          beam.make(@as(i64, @intCast(stat_buf.st_atimespec.tv_sec)), .{})
      else
          beam.make(@as(i64, @intCast(stat_buf.st_atim.tv_sec)), .{});
      
      const mtime_term = if (@hasField(@TypeOf(stat_buf), "st_mtimespec"))
          beam.make(@as(i64, @intCast(stat_buf.st_mtimespec.tv_sec)), .{})
      else
          beam.make(@as(i64, @intCast(stat_buf.st_mtim.tv_sec)), .{});
      
      const ctime_term = if (@hasField(@TypeOf(stat_buf), "st_ctimespec"))
          beam.make(@as(i64, @intCast(stat_buf.st_ctimespec.tv_sec)), .{})
      else
          beam.make(@as(i64, @intCast(stat_buf.st_ctim.tv_sec)), .{});
      const uid_term = beam.make(@as(i32, @intCast(stat_buf.st_uid)), .{});
      const gid_term = beam.make(@as(i32, @intCast(stat_buf.st_gid)), .{});
      const links_term = beam.make(@as(i32, @intCast(stat_buf.st_nlink)), .{});

      // Create a map using individual key-value pairs
      var map_entries = [_]beam.term{
          size_atom, size_term,
          type_atom, file_type_atom,
          mode_atom, mode_term,
          atime_atom, atime_term,
          mtime_atom, mtime_term,
          ctime_atom, ctime_term,
          uid_atom, uid_term,
          gid_atom, gid_term,
          links_atom, links_term
      };

      const stats_map = beam.make(map_entries[0..], .{map_entries.len / 2});

      return beam.make(.{ok_atom, stats_map}, .{});
  }

  /// Create directory on SMB share
  pub fn mkdir(url: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      // Create SMB context
      const ctx = c.smbc_new_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_error_atom = beam.make_into_atom("context_creation_failed", .{});
          return beam.make(.{error_atom, context_error_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, 0);

      // Initialize context
      if (c.smbc_init_context(ctx) == null) {
          const error_atom = beam.make_error_atom(.{});
          const init_error_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, init_error_atom}, .{});
      }

      // Set authentication callback
      c.smbc_setFunctionAuthData(ctx, auth_callback);

      // Set credentials
      if (username.len >= global_username.len or password.len >= global_password.len) {
          const error_atom = beam.make_error_atom(.{});
          const creds_error_atom = beam.make_into_atom("credentials_too_long", .{});
          return beam.make(.{error_atom, creds_error_atom}, .{});
      }

      @memcpy(global_workgroup[0..9], "WORKGROUP");
      global_workgroup[9] = 0;

      @memcpy(global_username[0..username.len], username);
      global_username[username.len] = 0;

      @memcpy(global_password[0..password.len], password);
      global_password[password.len] = 0;

      credentials_set = true;

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      // Set the context as current for libsmbclient
      const old_ctx = c.smbc_set_context(ctx);
      defer _ = c.smbc_set_context(old_ctx);

      // Create the directory with permissions 0755
      const result = c.smbc_mkdir(url_cstr.ptr, 0o755);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const mkdir_failed_atom = beam.make_into_atom("mkdir_failed", .{});
          return beam.make(.{error_atom, mkdir_failed_atom}, .{});
      }

      return beam.make_into_atom("ok", .{});
  }
  """
end
