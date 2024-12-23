const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

pub const ConsoleConfig = struct {
    use_stderr: bool = true,
    enable_colors: bool = true,
    buffer_size: usize = 4096,
};

pub const ConsoleHandler = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: ConsoleConfig,
    mutex: std.Thread.Mutex,
    writer: std.fs.File.Writer,
    buffer: []u8,
    buffer_pos: usize,

    pub fn init(allocator: std.mem.Allocator, config: ConsoleConfig) !*Self {
        const self = try allocator.create(Self);

        self.* = .{
            .allocator = allocator,
            .config = config,
            .mutex = std.Thread.Mutex{},
            .writer = if (config.use_stderr) std.io.getStdErr().writer() else std.io.getStdOut().writer(),
            .buffer = try allocator.alloc(u8, config.buffer_size),
            .buffer_pos = 0,
        };

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.buffer);
        self.allocator.destroy(self);
    }

    pub fn write(self: *Self, level: types.LogLevel, message: []const u8, metadata: ?types.LogMetadata) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        var fba = std.heap.FixedBufferAllocator.init(self.buffer);
        const allocator = fba.allocator();

        // Format timestamp
        const timestamp = if (metadata) |m| m.timestamp else std.time.timestamp();
        const time_str = try std.fmt.allocPrint(allocator, "[{d}] ", .{timestamp});

        // Format log level with colors if enabled
        const level_str = if (self.config.enable_colors)
            try std.fmt.allocPrint(allocator, "{s}[{s}]\x1b[0m ", .{ level.toColor(), level.toString() })
        else
            try std.fmt.allocPrint(allocator, "[{s}] ", .{level.toString()});

        // Write to console with optional metadata
        try self.writer.writeAll(time_str);
        try self.writer.writeAll(level_str);

        if (metadata) |m| {
            const meta_str = try std.fmt.allocPrint(allocator, "[{s}:{d}] ", .{ m.file, m.line });
            try self.writer.writeAll(meta_str);
        }

        try self.writer.writeAll(message);
        try self.writer.writeAll("\n");
    }

    pub fn flush(self: *Self) !void {
        // For console output, we don't need to do anything special for flushing
        // as we write immediately, but we keep this method for consistency with other handlers
        _ = self;
    }
};
