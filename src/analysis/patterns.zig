// src/analysis/patterns.zig
const std = @import("std");
const types = @import("../core/types.zig");
const errors = @import("../core/errors.zig");

pub const Pattern = struct {
    template: []const u8,
    pattern_type: types.PatternType,
    metadata: types.PatternMetadata,
    variables: std.ArrayList(types.PatternVariable),
    hash: u64,

    pub fn init(allocator: std.mem.Allocator, template: []const u8, pattern_type: types.PatternType) !*Pattern {
        const pattern = try allocator.create(Pattern);
        pattern.* = .{
            .template = try allocator.dupe(u8, template),
            .pattern_type = pattern_type,
            .metadata = .{
                .first_seen = std.time.timestamp(),
                .last_seen = std.time.timestamp(),
                .frequency = 1,
                .confidence = 1.0,
            },
            .variables = std.ArrayList(types.PatternVariable).init(allocator),
            .hash = std.hash.Wyhash.hash(0, template),
        };
        try pattern.detectVariables(allocator, template);
        return pattern;
    }

    pub fn deinit(self: *Pattern, allocator: std.mem.Allocator) void {
        allocator.free(self.template);
        for (self.variables.items) |*vari| {
            for (vari.seen_values.items) |value| {
                allocator.free(value);
            }
            vari.seen_values.deinit();
        }
        self.variables.deinit();
        allocator.destroy(self);
    }

    pub fn updateMetadata(self: *Pattern) void {
        self.metadata.last_seen = std.time.timestamp();
        self.metadata.frequency += 1;
    }

    pub fn detectVariables(self: *Pattern, allocator: std.mem.Allocator, message: []const u8) !void {
        var words = std.mem.split(u8, message, " ");
        while (words.next()) |word| {
            if (isVariable(word)) {
                var seen_values = std.ArrayList([]const u8).init(allocator);
                try seen_values.append(try allocator.dupe(u8, word));

                try self.variables.append(.{
                    .position = self.variables.items.len,
                    .var_type = determineVarType(word),
                    .seen_values = seen_values,
                });
            }
        }
    }

    fn isVariable(word: []const u8) bool {
        if (word.len == 0) return false;
        // Check for numbers
        if (std.ascii.isDigit(word[0])) return true;
        // Check for IP addresses
        var dots: u8 = 0;
        for (word) |char| {
            if (char == '.') dots += 1;
        }
        if (dots == 3) return true;
        // Check for email
        if (std.mem.indexOf(u8, word, "@") != null) return true;
        return false;
    }

    fn determineVarType(word: []const u8) types.VarType {
        // Check for IP addresses first (more specific than numbers)
        var dots: u8 = 0;
        var number_sections: u8 = 0;
        var sections = std.mem.split(u8, word, ".");
        while (sections.next()) |section| {
            dots += 1;
            if (std.ascii.isDigit(section[0])) {
                number_sections += 1;
            }
        }
        if (dots == 4 and number_sections == 4) return .ip_address;

        // Then other types
        if (std.ascii.isDigit(word[0])) return .number;
        if (std.mem.indexOf(u8, word, "@") != null) return .email;
        return .string;
    }
};

pub const PatternAnalyzer = struct {
    patterns: std.AutoHashMap(u64, *Pattern),
    mutex: std.Thread.Mutex,
    allocator: std.mem.Allocator,
    config: Config,

    pub const Config = struct {
        similarity_threshold: f32 = 0.85,
        max_pattern_age: i64 = 60 * 60 * 24, // 24 hours
        max_patterns: usize = 1000,
    };

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: Config) Self {
        return .{
            .patterns = std.AutoHashMap(u64, *Pattern).init(allocator),
            .mutex = .{},
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.patterns.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.patterns.deinit();
    }

    pub fn analyzeMessage(self: *Self, message: []const u8) !?*Pattern {
        self.mutex.lock();
        defer self.mutex.unlock();

        // Calculate message hash
        const msg_hash = std.hash.Wyhash.hash(0, message);

        // Check for exact match
        if (self.patterns.get(msg_hash)) |pattern| {
            pattern.updateMetadata();
            return pattern;
        }

        // Look for similar patterns
        if (try self.findSimilarPattern(message)) |similar| {
            similar.updateMetadata();
            return similar;
        }

        // Create new pattern
        const new_pattern = try Pattern.init(
            self.allocator,
            message,
            self.detectPatternType(message),
        );
        try self.patterns.put(msg_hash, new_pattern);

        // Cleanup old patterns if needed
        try self.cleanup();

        return new_pattern;
    }

    fn findSimilarPattern(self: *Self, message: []const u8) !?*Pattern {
        var best_match: ?*Pattern = null;
        var best_similarity: f32 = 0;

        var it = self.patterns.iterator();
        while (it.next()) |entry| {
            const similarity = try self.calculateSimilarity(message, entry.value_ptr.*.template);
            if (similarity > self.config.similarity_threshold and similarity > best_similarity) {
                best_similarity = similarity;
                best_match = entry.value_ptr.*;
            }
        }

        return best_match;
    }

    fn calculateSimilarity(self: *Self, a: []const u8, b: []const u8) !f32 {
        // Simple Levenshtein distance-based similarity
        const distance = try self.levenshteinDistance(a, b);
        const max_length = @max(a.len, b.len);
        return 1.0 - @as(f32, @floatFromInt(distance)) / @as(f32, @floatFromInt(max_length));
    }

    fn levenshteinDistance(self: *Self, a: []const u8, b: []const u8) !usize {
        var matrix = try std.ArrayList([]usize).initCapacity(self.allocator, a.len + 1);
        defer matrix.deinit();

        for (0..a.len + 1) |i| {
            var row = try self.allocator.alloc(usize, b.len + 1);
            try matrix.append(row);
            row[0] = i;
        }

        for (0..b.len + 1) |j| {
            matrix.items[0][j] = j;
        }

        for (1..a.len + 1) |i| {
            for (1..b.len + 1) |j| {
                const cost: usize = if (a[i - 1] == b[j - 1]) 0 else 1;
                matrix.items[i][j] = @min(
                    matrix.items[i - 1][j] + 1,
                    @min(
                        matrix.items[i][j - 1] + 1,
                        matrix.items[i - 1][j - 1] + cost,
                    ),
                );
            }
        }

        const result = matrix.items[a.len][b.len];

        for (matrix.items) |row| {
            self.allocator.free(row);
        }

        return result;
    }

    fn detectPatternType(self: *Self, message: []const u8) types.PatternType {
        _ = self;
        if (std.mem.startsWith(u8, message, "CUSTOM_TYPE:")) {
            return .custom;
        }
        if (std.mem.indexOf(u8, message, "error") != null or
            std.mem.indexOf(u8, message, "fail") != null)
        {
            return .err;
        }
        if (std.mem.indexOf(u8, message, "metric") != null or
            std.mem.indexOf(u8, message, "measure") != null)
        {
            return .metric;
        }
        if (std.mem.indexOf(u8, message, "event") != null) {
            return .event;
        }
        return .message;
    }

    const PatternInfo = struct { hash: u64, last_seen: i64 };

    // Update cleanup to enforce max_patterns
    fn cleanup(self: *Self) !void {
        const now = std.time.timestamp();
        var to_remove = std.ArrayList(u64).init(self.allocator);
        defer to_remove.deinit();

        // First, remove old patterns
        var it = self.patterns.iterator();
        while (it.next()) |entry| {
            if (now - entry.value_ptr.*.metadata.last_seen > self.config.max_pattern_age) {
                try to_remove.append(entry.key_ptr.*);
            }
        }

        // Then, if we're still over the limit, remove oldest patterns
        if (self.patterns.count() > self.config.max_patterns) {
            var patterns = std.ArrayList(PatternInfo).init(self.allocator);
            defer patterns.deinit();

            it = self.patterns.iterator();
            while (it.next()) |entry| {
                try patterns.append(.{
                    .hash = entry.key_ptr.*,
                    .last_seen = entry.value_ptr.*.metadata.last_seen,
                });
            }

            // Sort by last_seen
            std.mem.sort(PatternInfo, patterns.items, {}, struct {
                pub fn lessThan(_: void, a: PatternInfo, b: PatternInfo) bool {
                    return a.last_seen < b.last_seen;
                }
            }.lessThan);

            // Add oldest patterns to removal list until we're under max_patterns
            const remove_count = self.patterns.count() - self.config.max_patterns;
            for (patterns.items[0..remove_count]) |pattern| {
                try to_remove.append(pattern.hash);
            }
        }

        // Remove all marked patterns
        for (to_remove.items) |hash| {
            if (self.patterns.fetchRemove(hash)) |kv| {
                kv.value.deinit(self.allocator);
            }
        }
    }

    pub fn getPatternCount(self: *Self) usize {
        self.mutex.lock();
        defer self.mutex.unlock();
        return self.patterns.count();
    }
};

test "pattern analyzer basic usage" {
    const testing = std.testing;

    var analyzer = PatternAnalyzer.init(testing.allocator, .{});
    defer analyzer.deinit();

    // Test message analysis
    const msg1 = "User logged in: admin";
    const pattern1 = try analyzer.analyzeMessage(msg1);
    try testing.expect(pattern1 != null);

    // Test similar message
    const msg2 = "User logged in: user123";
    const pattern2 = try analyzer.analyzeMessage(msg2);
    try testing.expect(pattern2 != null);

    // Test pattern count
    try testing.expectEqual(@as(usize, 1), analyzer.getPatternCount());
}
