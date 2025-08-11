defmodule Sambex.Nif do
  @moduledoc """
  Native functions for SMB client operations using Zigler.
  """

  use Zig,
    otp_app: :sambex,
    c: [
      include_dirs: ["/opt/homebrew/Cellar/samba/4.22.3/include"],
      link_lib: "/opt/homebrew/Cellar/samba/4.22.3/lib/libsmbclient.dylib"
    ]

  ~Z"""
  const std = @import("std");
  const beam = @import("beam");

  // C imports for libsmbclient
  const c = @cImport({
      @cInclude("libsmbclient.h");
      @cInclude("stdlib.h");
      @cInclude("string.h");
  });

  // Authentication callback
  fn auth_callback(_: [*c]const u8, _: [*c]const u8, _: [*c]u8, _: c_int, _: [*c]u8, _: c_int, _: [*c]u8, _: c_int) callconv(.C) void {
      // This is a basic callback - authentication will be handled differently
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

  /// Set global credentials (simplified approach)
  pub fn set_credentials(workgroup: []const u8, username: []const u8, password: []const u8) beam.term {
      var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
      defer arena.deinit();
      const allocator = arena.allocator();

      const workgroup_cstr = allocator.dupeZ(u8, workgroup) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const username_cstr = allocator.dupeZ(u8, username) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const password_cstr = allocator.dupeZ(u8, password) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const ctx = create_smb_context();
      if (ctx == null) {
          const error_atom = beam.make_error_atom(.{});
          const context_failed_atom = beam.make_into_atom("context_init_failed", .{});
          return beam.make(.{error_atom, context_failed_atom}, .{});
      }
      defer _ = c.smbc_free_context(ctx, @intCast(1));

      c.smbc_set_credentials_with_fallback(ctx, workgroup_cstr.ptr, username_cstr.ptr, password_cstr.ptr);
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

      const workgroup_cstr = allocator.dupeZ(u8, "WORKGROUP") catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const username_cstr = allocator.dupeZ(u8, username) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const password_cstr = allocator.dupeZ(u8, password) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      c.smbc_set_credentials_with_fallback(ctx, workgroup_cstr.ptr, username_cstr.ptr, password_cstr.ptr);

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

      const workgroup_cstr = allocator.dupeZ(u8, "WORKGROUP") catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const username_cstr = allocator.dupeZ(u8, username) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const password_cstr = allocator.dupeZ(u8, password) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      c.smbc_set_credentials_with_fallback(ctx, workgroup_cstr.ptr, username_cstr.ptr, password_cstr.ptr);

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

      var files = std.ArrayList(beam.term).init(allocator);

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
          files.append(entry) catch {
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

      const workgroup_cstr = allocator.dupeZ(u8, "WORKGROUP") catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const username_cstr = allocator.dupeZ(u8, username) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const password_cstr = allocator.dupeZ(u8, password) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      c.smbc_set_credentials_with_fallback(ctx, workgroup_cstr.ptr, username_cstr.ptr, password_cstr.ptr);

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

      const workgroup_cstr = allocator.dupeZ(u8, "WORKGROUP") catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const username_cstr = allocator.dupeZ(u8, username) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const password_cstr = allocator.dupeZ(u8, password) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      c.smbc_set_credentials_with_fallback(ctx, workgroup_cstr.ptr, username_cstr.ptr, password_cstr.ptr);

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

      const workgroup_cstr = allocator.dupeZ(u8, "WORKGROUP") catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const username_cstr = allocator.dupeZ(u8, username) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };
      const password_cstr = allocator.dupeZ(u8, password) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      c.smbc_set_credentials_with_fallback(ctx, workgroup_cstr.ptr, username_cstr.ptr, password_cstr.ptr);

      const url_cstr = allocator.dupeZ(u8, url) catch {
          const error_atom = beam.make_error_atom(.{});
          const memory_error_atom = beam.make_into_atom("memory_error", .{});
          return beam.make(.{error_atom, memory_error_atom}, .{});
      };

      const result = c.smbc_unlink(url_cstr.ptr);
      if (result < 0) {
          const error_atom = beam.make_error_atom(.{});
          const delete_failed_atom = beam.make_into_atom("delete_failed", .{});
          return beam.make(.{error_atom, delete_failed_atom}, .{});
      }

      return beam.make_into_atom("ok", .{});
  }
  """
end
