// src/nexlog.zig
const std = @import("std");

pub const core = struct {
    pub const logger = @import("core/logger.zig");
    pub const config = @import("core/config.zig");
    pub const init = @import("core/init.zig");
    pub const errors = @import("core/errors.zig");
    pub const types = @import("core/types.zig");
};

// Re-export main types and functions
pub const Logger = core.logger.Logger;
pub const LogLevel = core.types.LogLevel;
pub const LogConfig = core.config.LogConfig;
pub const LogMetadata = core.types.LogMetadata;
pub const LogError = core.errors.LogError;

// Re-export initialization functions
pub const init = core.init.init;
pub const initWithConfig = core.init.initWithConfig;
pub const deinit = core.init.deinit;
pub const isInitialized = core.init.isInitialized;
pub const getDefaultLogger = core.init.getDefaultLogger;
pub const LogBuilder = core.init.LogBuilder;

// Example test
test "basic log test" {
    const testing = std.testing;
    const allocator = testing.allocator;

    const cfg = LogConfig{
        .min_level = .debug,
        .enable_colors = false,
        .enable_file_logging = false,
    };

    var log = try Logger.init(allocator, cfg);
    defer log.deinit();

    try log.log(.err, "Test message", .{}, null);
}
