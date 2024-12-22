const std = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const buffer = @import("../utils/buffer.zig");
const pool = @import("../utils/pool.zig");

pub const Logger = struct {
    const Self = @This();

    // Existing fields
    allocator: std.mem.Allocator,
    config: config.LogConfig,
    mutex: std.Thread.Mutex,
    file: ?std.fs.File,
    buffer: []u8,
    buffer_pos: usize,

    // New fields for enhanced functionality
    circular_buffer: ?*buffer.CircularBuffer,
    buffer_pool: ?*pool.Pool(buffer.CircularBuffer),
    async_queue: ?std.ArrayList(*buffer.CircularBuffer),
    flush_timer: ?std.time.Timer,

    pub fn init(allocator: std.mem.Allocator, cfg: config.LogConfig) !*Self {
        var logger = try allocator.create(Self);

        // Initialize base logger
        logger.* = .{
            .allocator = allocator,
            .config = cfg,
            .mutex = std.Thread.Mutex{},
            .file = null,
            .buffer = try allocator.alloc(u8, cfg.buffer_size),
            .buffer_pos = 0,
            .circular_buffer = null,
            .buffer_pool = null,
            .async_queue = null,
            .flush_timer = null,
        };

        // Initialize enhanced features based on config
        if (cfg.async_mode) {
            logger.circular_buffer = try buffer.CircularBuffer.init(allocator, cfg.buffer_size);
            logger.async_queue = std.ArrayList(*buffer.CircularBuffer).init(allocator);

            // Initialize buffer pool if enabled
            const BufferPool = pool.Pool(buffer.CircularBuffer);
            logger.buffer_pool = try BufferPool.init(
                allocator,
                4, // Initial pool size
                createBuffer,
                destroyBuffer,
            );

            // Setup flush timer if configured
            if (cfg.enable_metadata) {
                logger.flush_timer = try std.time.Timer.start();
            }
        }

        if (cfg.enable_file_logging) {
            if (cfg.file_path) |path| {
                logger.file = try std.fs.cwd().createFile(path, .{});
            }
        }

        return logger;
    }

    // In logger.zig, add back the rotateLog function:
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

    pub fn deinit(self: *Self) void {
        if (self.file) |file| {
            file.close();
        }

        // Cleanup enhanced features
        if (self.circular_buffer) |cb| {
            cb.deinit();
        }

        if (self.buffer_pool) |bp| {
            bp.deinit();
        }

        if (self.async_queue) |queue| {
            for (queue.items) |buf| {
                buf.deinit();
            }
            queue.deinit();
        }

        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    // Enhanced log function with async support
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

        if (self.config.async_mode) {
            return try self.asyncLog(level, fmt, args, metadata);
        } else {
            return try self.syncLog(level, fmt, args, metadata);
        }
    }

    // Asynchronous logging implementation
    fn asyncLog(
        self: *Self,
        level: types.LogLevel,
        comptime fmt: []const u8,
        args: anytype,
        metadata: ?types.LogMetadata,
    ) !void {
        const circular_buffer = self.circular_buffer orelse return error.BufferNotInitialized;

        // Format log message
        var temp_buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&temp_buffer);
        const temp_allocator = fba.allocator();

        const message = try std.fmt.allocPrint(
            temp_allocator,
            "[{d}] {s}[{s}] " ++ fmt ++ "\n",
            .{
                if (metadata) |m| m.timestamp else std.time.timestamp(),
                if (self.config.enable_colors) level.toColor() else "",
                level.toString(),
            } ++ args,
        );

        // Write to circular buffer
        _ = try circular_buffer.write(message);

        // Check if we need to flush
        if (self.shouldFlush()) {
            try self.flushBuffers();
        }
    }

    // Synchronous logging implementation (existing functionality)
    fn syncLog(
        self: *Self,
        level: types.LogLevel,
        comptime fmt: []const u8,
        args: anytype,
        metadata: ?types.LogMetadata,
    ) !void {
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
            const plain_level = try std.fmt.allocPrint(allocator, "[{s}] ", .{level.toString()});
            try file.writeAll(plain_level);
            try file.writeAll(message);

            if (self.config.enable_rotation) {
                const file_size = try file.getEndPos();
                if (file_size >= self.config.max_file_size) {
                    try self.rotateLog();
                }
            }
        }
    }

    fn shouldFlush(self: *Self) bool {
        if (self.circular_buffer) |cb| {
            if (cb.len() >= cb.capacity() * 3 / 4) {
                return true;
            }
        }

        if (self.flush_timer) |*timer| { // Note the *timer to get mutable pointer
            const elapsed = timer.read();
            if (elapsed >= std.time.ns_per_ms * 100) { // Flush every 100ms
                return true;
            }
        }

        return false;
    }

    // Helper function to flush buffers
    fn flushBuffers(self: *Self) !void {
        if (self.circular_buffer) |cb| {
            var temp_buffer: [4096]u8 = undefined;
            const bytes_read = try cb.read(&temp_buffer);

            if (bytes_read > 0) {
                if (self.file) |file| {
                    try file.writeAll(temp_buffer[0..bytes_read]);
                }

                const stderr = std.io.getStdErr().writer();
                try stderr.writeAll(temp_buffer[0..bytes_read]);
            }
        }

        if (self.flush_timer) |*timer| {
            timer.reset();
        }
    }
};

// Helper functions for buffer pool
fn createBuffer(allocator: std.mem.Allocator) !buffer.CircularBuffer {
    const cb = try buffer.CircularBuffer.init(allocator, 4096);
    return cb.*;
}
fn destroyBuffer(buf: *buffer.CircularBuffer) void {
    buf.deinit();
}
