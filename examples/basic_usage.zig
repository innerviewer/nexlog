// examples/basic_usage.zig
const std = @import("std");
const nexlog = @import("nexlog");

pub fn main() !void {
    // Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize logger with builder pattern
    var builder = nexlog.LogBuilder.init();
    try builder
        .setMinLevel(.debug)
        .enableColors(true)
        .enableFileLogging(true, "app.log")
        .build(allocator);
    defer nexlog.deinit();

    // Get the default logger
    const logger = nexlog.getDefaultLogger().?;

    // Create default metadata
    const metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 0,
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    // Basic logging examples
    try logger.log(.info, "Application started", .{}, metadata);
    try logger.log(.debug, "Debug information: {s}", .{"initialization complete"}, metadata);

    // Simulate some application events
    try simulateUserLogin(logger);
    try processOrders(logger);

    // Log application shutdown
    try logger.log(.info, "Application shutting down", .{}, metadata);
}

fn simulateUserLogin(logger: *nexlog.Logger) !void {
    const metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 0,
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    try logger.log(.debug, "Attempting user login", .{}, metadata);

    // Simulate some validation
    const username = "test_user";
    try logger.log(.debug, "Validating user: {s}", .{username}, metadata);

    // Simulate successful login
    try logger.log(.info, "User {s} logged in successfully", .{username}, metadata);
}

fn processOrders(logger: *nexlog.Logger) !void {
    const metadata = nexlog.LogMetadata{
        .timestamp = std.time.timestamp(),
        .thread_id = 0,
        .file = @src().file,
        .line = @src().line,
        .function = @src().fn_name,
    };

    const orders = [_]u32{ 1001, 1002, 1003 };

    try logger.log(.info, "Processing {} orders", .{orders.len}, metadata);

    for (orders) |order_id| {
        try logger.log(.debug, "Processing order {}", .{order_id}, metadata);

        // Simulate processing time
        std.time.sleep(100 * std.time.ns_per_ms);

        // Simulate occasional warnings
        if (order_id == 1002) {
            try logger.log(.warn, "Order {} requires manual review", .{order_id}, metadata);
        }

        try logger.log(.info, "Order {} processed successfully", .{order_id}, metadata);
    }

    try logger.log(.info, "All orders processed", .{}, metadata);
}
