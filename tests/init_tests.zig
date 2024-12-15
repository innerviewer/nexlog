// tests/init_tests.zig
const std = @import("std");
const testing = std.testing;
const nexlog = @import("nexlog");

test "init: basic initialization" {
    // Setup
    try nexlog.init(testing.allocator);
    defer nexlog.deinit();

    // Verify
    try testing.expect(nexlog.isInitialized());
    try testing.expect(nexlog.getDefaultLogger() != null);
}

test "init: double initialization should fail" {
    // First initialization
    try nexlog.init(testing.allocator);
    defer nexlog.deinit();

    // Second initialization should fail
    try testing.expectError(error.AlreadyInitialized, nexlog.init(testing.allocator));
}

test "init: builder pattern" {
    // Setup builder
    var builder = nexlog.LogBuilder.init();
    try builder
        .setMinLevel(.debug)
        .enableColors(false)
        .enableFileLogging(true, "test.log")
        .build(testing.allocator);
    defer nexlog.deinit();

    // Verify configuration
    const logger = nexlog.getDefaultLogger().?;
    try testing.expectEqual(logger.config.min_level, .debug);
    try testing.expect(!logger.config.enable_colors);
    try testing.expect(logger.config.enable_file_logging);
    try testing.expectEqualStrings("test.log", logger.config.file_path.?);
}

test "init: deinitialization" {
    // Setup
    try nexlog.init(testing.allocator);
    try testing.expect(nexlog.isInitialized());

    // Cleanup
    nexlog.deinit();

    // Verify cleanup
    try testing.expect(!nexlog.isInitialized());
    try testing.expect(nexlog.getDefaultLogger() == null);
}
