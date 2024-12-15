// errors.zig
const std = @import("std");

/// Core logging errors
pub const LogError = error{
    BufferFull,
    InvalidLogLevel,
    MessageTooLarge,
    FileLockFailed,
    FileRotationFailed,
    InvalidConfiguration,
    ThreadInitFailed,
    MetadataError,
    FormattingError,
    FilterError,
    AlreadyInitialized, // Added this error

};

/// File-related errors
pub const FileError = error{
    FileNotFound,
    PermissionDenied,
    DirectoryNotFound,
    DiskFull,
    RotationLimitReached,
    InvalidFilePath,
    LockTimeout,
};

/// Buffer-related errors
pub const BufferError = error{
    BufferOverflow,
    BufferUnderflow,
    InvalidAlignment,
    FlushFailed,
    CompactionFailed,
};

/// Configuration errors
pub const ConfigError = error{
    InvalidLogLevel,
    InvalidBufferSize,
    InvalidRotationPolicy,
    InvalidFilterExpression,
    InvalidTimeFormat,
    InvalidPath,
    ConflictingOptions,
};

/// Comprehensive error set combining all logging-related errors
pub const Error = LogError || FileError || BufferError || ConfigError || std.fs.File.OpenError || std.fs.File.WriteError;

/// Error context structure for detailed error reporting
pub const ErrorContext = struct {
    file: []const u8,
    line: u32,
    error_type: Error,
    message: []const u8,
    timestamp: i64,

    pub fn init(
        error_type: Error,
        message: []const u8,
        file: []const u8,
        line: u32,
    ) ErrorContext {
        return .{
            .error_type = error_type,
            .message = message,
            .file = file,
            .line = line,
            .timestamp = std.time.timestamp(),
        };
    }

    pub fn format(self: ErrorContext, writer: anytype) !void {
        try writer.print(
            "Error[{d}] {s}:{d}: {s} - {s}\n",
            .{
                self.timestamp,
                self.file,
                self.line,
                @errorName(self.error_type),
                self.message,
            },
        );
    }
};

/// Error handler type for custom error handling
pub const ErrorHandler = struct {
    /// Function pointer type for error callbacks
    pub const ErrorFn = *const fn (context: ErrorContext) Error!void;

    handler_fn: ErrorFn,
    max_retries: u32,
    retry_delay_ms: u32,

    pub fn init(handler_fn: ErrorFn, max_retries: u32, retry_delay_ms: u32) ErrorHandler {
        return .{
            .handler_fn = handler_fn,
            .max_retries = max_retries,
            .retry_delay_ms = retry_delay_ms,
        };
    }

    pub fn handle(self: *const ErrorHandler, context: ErrorContext) Error!void {
        var retries: u32 = 0;
        while (retries < self.max_retries) : (retries += 1) {
            self.handler_fn(context) catch |err| {
                if (retries == self.max_retries - 1) return err;
                std.time.sleep(self.retry_delay_ms * std.time.ns_per_ms);
                continue;
            };
            break;
        }
    }
};

/// Helper function to create error context
pub fn makeError(
    error_type: Error,
    message: []const u8,
    file: []const u8,
    line: u32,
) ErrorContext {
    return ErrorContext.init(error_type, message, file, line);
}

/// Default error handler that prints to stderr
pub fn defaultErrorHandler(context: ErrorContext) Error!void {
    const stderr = std.io.getStdErr().writer();
    try context.format(stderr);
}
