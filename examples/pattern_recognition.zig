// examples/pattern_recognition.zig
const std = @import("std");
const nexlog = @import("nexlog");

fn simulateComplexLogs() ![]const []const u8 {
    return &[_][]const u8{
        "User session 123e4567-e89b-12d3-a456-426614174000 started from IP 192.168.1.100 with client_id=mobile_app",
        "User session 987fcdeb-51a2-12d3-a456-426614174000 started from IP 192.168.1.101 with client_id=web_client",
        "Session 123e4567-e89b-12d3-a456-426614174000 ended after 3600 seconds",
        "Error: Database connection failed after 5 retries - err_code=DB_001",
        "Critical Error: Master node 192.168.1.200 unreachable - cluster_health=degraded",
        "Warning: High latency detected (150ms) on endpoint /api/users",
        "Performance Metric: Query latency=50ms endpoint=/api/products method=GET",
        "System Metric: Memory usage=2.5GB, CPU=75%, Disk=80%",
        "Application Metric: Cache hit_rate=85.5% size=1.2GB",
        "Event: {\"type\": \"user_action\", \"action\": \"purchase\", \"amount\": 150.50, \"currency\": \"USD\"}",
        "Event: {\"type\": \"user_action\", \"action\": \"refund\", \"amount\": 75.25, \"currency\": \"USD\"}",
        "Error: Transaction 12345 failed - {\"error\": \"insufficient_funds\", \"account\": \"user_123\", \"required\": 100.00, \"available\": 75.50}",
        "Error: Authentication failed for user admin@example.com - {\"reason\": \"invalid_2fa\", \"attempts\": 3, \"next_try\": \"5min\"}",
    };
}

fn processLogBatch(analyzer: *nexlog.PatternAnalyzer, logs: []const []const u8) !void {
    for (logs) |msg| {
        _ = try analyzer.analyzeMessage(msg);
    }
}

fn handleBufferFull(analyzer: *nexlog.PatternAnalyzer) !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Performing emergency cleanup...\n", .{});

    // Custom cleanup logic could go here
    _ = analyzer;
}

fn printErrorSet(comptime T: type) void {
    const stderr = std.io.getStdErr().writer();
    stderr.print("Error set: {}\n", .{@typeInfo(@typeInfo(T).Fn.return_type.?).ErrorUnion.error_set}) catch {};
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n=== Advanced Pattern Analysis Example ===\n\n", .{});

    var analyzer = nexlog.PatternAnalyzer.init(allocator, .{
        .similarity_threshold = 0.90,
        .max_patterns = 10,
        .max_pattern_age = 60 * 60,
    });
    defer analyzer.deinit();

    const logs = try simulateComplexLogs();

    // Process each log and print its pattern
    for (logs) |msg| {
        if (try analyzer.analyzeMessage(msg)) |pattern| {
            try stdout.print("\nLog: {s}\nPattern Type: {s}\n", .{ msg, @tagName(pattern.pattern_type) });
        }
    }

    try stdout.print("\n=== Pattern Analysis Results ===\n", .{});
    try stdout.print("Total Patterns Detected: {d}\n", .{analyzer.getPatternCount()});

    try stdout.print("\n=== Testing Error Conditions ===\n", .{});

    {
        const large_message = try allocator.alloc(u8, 10000);
        defer allocator.free(large_message);
        @memset(large_message, 'A');

        _ = analyzer.analyzeMessage(large_message) catch |err| {
            try stdout.print("Expected error occurred: {s}\n", .{@errorName(err)});
            return err;
        };
    }

    _ = analyzer.analyzeMessage("") catch |err| {
        try stdout.print("Empty message error: {s}\n", .{@errorName(err)});
        return err;
    };

    try stdout.print("\nExample completed successfully!\n", .{});
}
