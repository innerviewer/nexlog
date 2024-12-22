const std = @import("std");
const types = @import("types.zig");
const config = @import("config.zig");
const errors = @import("errors.zig");

const console = @import("../output/console.zig");
const file = @import("../output/file.zig");
const network = @import("../output/network.zig");

pub const Logger = struct {
    const Self = @This();

    allocator: std.mem.Allocator,
    config: config.LogConfig,
    mutex: std.Thread.Mutex,

    // Output handlers
    console_handler: ?*console.ConsoleHandler,
    file_handler: ?*file.FileHandler,
    network_handler: ?*network.NetworkHandler,

    pub fn init(allocator: std.mem.Allocator, cfg: config.LogConfig) !*Self {
        var logger = try allocator.create(Self);

        // Initialize base logger
        logger.* = .{
            .allocator = allocator,
            .config = cfg,
            .mutex = std.Thread.Mutex{},
            .console_handler = null,
            .file_handler = null,
            .network_handler = null,
        };

        // Initialize console handler by default
        const console_config = console.ConsoleConfig{
            .use_stderr = true,
            .enable_colors = cfg.enable_colors,
            .buffer_size = cfg.buffer_size,
        };
        logger.console_handler = try console.ConsoleHandler.init(allocator, console_config);

        // Initialize file handler if enabled
        if (cfg.enable_file_logging) {
            if (cfg.file_path) |path| {
                const file_config = file.FileConfig{
                    .path = path,
                    .mode = .append,
                    .max_size = cfg.max_file_size,
                    .enable_rotation = cfg.enable_rotation,
                    .max_rotated_files = cfg.max_rotated_files,
                    .buffer_size = cfg.buffer_size,
                };
                logger.file_handler = try file.FileHandler.init(allocator, file_config);
            }
        }

        // Network handler is initialized on demand through addNetworkHandler()

        return logger;
    }

    pub fn deinit(self: *Self) void {
        if (self.console_handler) |h| {
            h.deinit();
        }
        if (self.file_handler) |h| {
            h.deinit();
        }
        if (self.network_handler) |h| {
            h.deinit();
        }
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

        // Format message once for all handlers
        var temp_buffer: [4096]u8 = undefined;
        var fba = std.heap.FixedBufferAllocator.init(&temp_buffer);
        const message = try std.fmt.allocPrint(
            fba.allocator(),
            fmt,
            args,
        );

        // Send to all active handlers
        if (self.console_handler) |h| {
            h.write(level, message, metadata) catch |err| {
                std.debug.print("Console handler error: {}\n", .{err});
            };
        }

        if (self.file_handler) |h| {
            h.write(level, message, metadata) catch |err| {
                std.debug.print("File handler error: {}\n", .{err});
            };
        }

        if (self.network_handler) |h| {
            h.write(level, message, metadata) catch |err| {
                std.debug.print("Network handler error: {}\n", .{err});
            };
        }
    }

    // Helper methods for adding/removing handlers
    pub fn addNetworkHandler(self: *Self, endpoint: network.NetworkEndpoint) !void {
        if (self.network_handler != null) {
            return error.HandlerAlreadyExists;
        }

        const network_config = network.NetworkConfig{
            .endpoint = endpoint,
            .buffer_size = self.config.buffer_size,
        };
        self.network_handler = try network.NetworkHandler.init(self.allocator, network_config);
    }

    pub fn removeNetworkHandler(self: *Self) void {
        if (self.network_handler) |h| {
            h.deinit();
            self.network_handler = null;
        }
    }

    // Flush all handlers
    pub fn flush(self: *Self) !void {
        if (self.console_handler) |h| {
            try h.flush();
        }
        if (self.file_handler) |h| {
            try h.flush();
        }
        if (self.network_handler) |h| {
            try h.flush();
        }
    }
};
