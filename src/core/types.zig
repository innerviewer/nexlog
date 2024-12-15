// core/types.zig
pub const LogLevel = enum {
    trace,
    debug,
    info,
    warn,
    err, // Changed from 'error' to 'err'
    critical,

    pub fn toString(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR", // Display string can still be "ERROR"
            .critical => "CRITICAL",
        };
    }

    pub fn toColor(self: LogLevel) []const u8 {
        return switch (self) {
            .trace => "\x1b[90m", // Gray
            .debug => "\x1b[36m", // Cyan
            .info => "\x1b[32m", // Green
            .warn => "\x1b[33m", // Yellow
            .err => "\x1b[31m", // Red
            .critical => "\x1b[35m", // Magenta
        };
    }
};

pub const LogMetadata = struct {
    timestamp: i64,
    thread_id: usize,
    file: []const u8,
    line: u32,
    function: []const u8,
};
