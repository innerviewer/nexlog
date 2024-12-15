// tests/pattern_tests.zig
const std = @import("std");
const testing = std.testing;
const nexlog = @import("nexlog");

test "pattern: basic type detection" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const err_pattern = try analyzer.analyzeMessage("Connection error occurred");
    try testing.expect(err_pattern != null);
    try testing.expectEqual(nexlog.PatternType.err, err_pattern.?.pattern_type);

    const metric_pattern = try analyzer.analyzeMessage("CPU usage metric: 85%");
    try testing.expect(metric_pattern != null);
    try testing.expectEqual(nexlog.PatternType.metric, metric_pattern.?.pattern_type);

    const event_pattern = try analyzer.analyzeMessage("System startup event");
    try testing.expect(event_pattern != null);
    try testing.expectEqual(nexlog.PatternType.event, event_pattern.?.pattern_type);
}

test "pattern: similarity matching" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    // Test similar messages
    const msg1 = "User admin logged in from 192.168.1.1";
    const msg2 = "User john logged in from 192.168.1.2";

    const pattern1 = try analyzer.analyzeMessage(msg1);
    try testing.expect(pattern1 != null);

    const pattern2 = try analyzer.analyzeMessage(msg2);
    try testing.expect(pattern2 != null);

    // Should detect these as the same pattern
    try testing.expectEqual(pattern1.?.hash, pattern2.?.hash);
}

test "pattern: variable detection" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    // Test number variable
    const msg_number = "Process used 1234 MB of memory";
    const pattern_number = try analyzer.analyzeMessage(msg_number);
    try testing.expect(pattern_number != null);
    try testing.expect(pattern_number.?.variables.items.len > 0);
    try testing.expectEqual(nexlog.VarType.number, pattern_number.?.variables.items[0].var_type);

    // Test IP address variable
    const msg_ip = "Connection from 192.168.1.1";
    const pattern_ip = try analyzer.analyzeMessage(msg_ip);
    try testing.expect(pattern_ip != null);
    try testing.expect(pattern_ip.?.variables.items.len > 0);
    try testing.expectEqual(nexlog.VarType.ip_address, pattern_ip.?.variables.items[0].var_type);

    // Test email variable
    const msg_email = "Email received from test@example.com";
    const pattern_email = try analyzer.analyzeMessage(msg_email);
    try testing.expect(pattern_email != null);
    try testing.expect(pattern_email.?.variables.items.len > 0);
    try testing.expectEqual(nexlog.VarType.email, pattern_email.?.variables.items[0].var_type);
}

test "pattern: cleanup and limits" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{
        .max_patterns = 2,
        .max_pattern_age = 0, // Immediate cleanup
    });
    defer analyzer.deinit();

    // Add patterns up to limit
    _ = try analyzer.analyzeMessage("First message");
    _ = try analyzer.analyzeMessage("Second message");
    _ = try analyzer.analyzeMessage("Third message"); // Should trigger cleanup

    try testing.expectEqual(@as(usize, 2), analyzer.getPatternCount());
}

test "pattern: metadata tracking" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const msg = "Test message";
    const pattern = try analyzer.analyzeMessage(msg);
    try testing.expect(pattern != null);

    // Test metadata
    try testing.expectEqual(@as(u32, 1), pattern.?.metadata.frequency);
    try testing.expect(pattern.?.metadata.first_seen > 0);
    try testing.expect(pattern.?.metadata.last_seen > 0);
    try testing.expect(pattern.?.metadata.confidence > 0);
}

test "pattern: concurrent access" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const ThreadContext = struct {
        analyzer: *nexlog.PatternAnalyzer,
        message: []const u8,

        fn run(ctx: @This()) !void {
            var i: usize = 0;
            while (i < 100) : (i += 1) {
                _ = try ctx.analyzer.analyzeMessage(ctx.message);
            }
        }
    };

    var threads: [3]std.Thread = undefined;
    const contexts = [_]ThreadContext{
        .{ .analyzer = &analyzer, .message = "Thread 1 message" },
        .{ .analyzer = &analyzer, .message = "Thread 2 message" },
        .{ .analyzer = &analyzer, .message = "Thread 3 message" },
    };

    // Start threads
    for (&threads, 0..) |*thread, i| {
        thread.* = try std.Thread.spawn(.{}, ThreadContext.run, .{contexts[i]});
    }

    // Wait for threads
    for (threads) |thread| {
        thread.join();
    }

    // Verify thread safety
    try testing.expect(analyzer.getPatternCount() > 0);
}

test "pattern: custom pattern types" {
    var analyzer = nexlog.PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    const custom_msg = "CUSTOM_TYPE: Special message";
    const pattern = try analyzer.analyzeMessage(custom_msg);
    try testing.expect(pattern != null);
    try testing.expectEqual(nexlog.PatternType.custom, pattern.?.pattern_type);
}
