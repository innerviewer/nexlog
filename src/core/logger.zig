const std = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");

pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: config.LogConfig,
    mutex: std.Thread.Mutex,
    file: ?std.fs.File,
    buffer: []u8,
    buffer_pos: usize,

    pub fn init(allocator: std.mem.Allocator, cfg: config.LogConfig) !*Self {
        var logger = try allocator.create(Self);

        logger.* = .{
            .allocator = allocator,
            .config = cfg,
            .mutex = std.Thread.Mutex{},
            .file = null,
            .buffer = try allocator.alloc(u8, cfg.buffer_size),
            .buffer_pos = 0,
        };

        if (cfg.enable_file_logging) {
            if (cfg.file_path) |path| {
                logger.file = try std.fs.cwd().createFile(path, .{});
            }
        }

        return logger;
    }

    pub fn deinit(self: *Self) void {
        if (self.file) |file| {
            file.close();
        }
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    pub fn log(
        self: *Self,
        level: types.LogLevel,
        comptime fmt: []const u8,
        args: anytype,
        metadata: ?types.LogMetadata,
    ) !void {
        if (@intFromEnum(level) < @intFromEnum(self.config.min_level)) {
            return;
        }

        self.mutex.lock();
        defer self.mutex.unlock();

        var fba = std.heap.FixedBufferAllocator.init(self.buffer);
        const allocator = fba.allocator();

        // Format timestamp
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        const time_str = try std.fmt.allocPrint(allocator, "[{d}] ", .{timestamp});

        // Format log level
        const level_str = if (self.config.enable_colors)
            try std.fmt.allocPrint(allocator, "{s}[{s}]\x1b[0m ", .{ level.toColor(), level.toString() })
        else
            try std.fmt.allocPrint(allocator, "[{s}] ", .{level.toString()});

        // Format message
        const message = try std.fmt.allocPrint(allocator, fmt ++ "\n", args);

        // Write to console
        const stderr = std.io.getStdErr().writer();
        try stderr.writeAll(time_str);
        try stderr.writeAll(level_str);
        try stderr.writeAll(message);

        // Write to file if enabled
        if (self.file) |file| {
            try file.writeAll(time_str);
            // Strip colors for file output
            const plain_level = try std.fmt.allocPrint(allocator, "[{s}] ", .{level.toString()});
            try file.writeAll(plain_level);
            try file.writeAll(message);

            // Check rotation
            if (self.config.enable_rotation) {
                const file_size = try file.getEndPos();
                if (file_size >= self.config.max_file_size) {
                    try self.rotateLog();
                }
            }
        }
    }

    fn rotateLog(self: *Self) !void {
        if (self.config.file_path) |path| {
            // Close current file
            if (self.file) |file| {
                file.close();
            }

            // Rotate existing files
            var i: usize = self.config.max_rotated_files;
            while (i > 0) : (i -= 1) {
                const old_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{d}",
                    .{ path, i - 1 },
                );
                defer self.allocator.free(old_path);
                const new_path = try std.fmt.allocPrint(
                    self.allocator,
                    "{s}.{d}",
                    .{ path, i },
                );
                defer self.allocator.free(new_path);

                std.fs.cwd().rename(old_path, new_path) catch |err| switch (err) {
                    error.FileNotFound => continue,
                    else => return err,
                };
            }

            // Rename current log file
            const backup_path = try std.fmt.allocPrint(
                self.allocator,
                "{s}.1",
                .{path},
            );
            defer self.allocator.free(backup_path);
            try std.fs.cwd().rename(path, backup_path);

            // Create new log file
            self.file = try std.fs.cwd().createFile(path, .{});
        }
    }
};
