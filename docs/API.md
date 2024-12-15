# Nexlog API Documentation

## Core Logger

The core logger provides the fundamental logging functionality in Nexlog. It supports multiple log levels, colored output, file logging, and thread-safe operations.

### Basic Usage

```zig
// Initialize the logger
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// Using the builder pattern
var builder = nexlog.LogBuilder.init();
try builder
    .setMinLevel(.debug)
    .enableColors(true)
    .enableFileLogging(true, "app.log")
    .build(allocator);

// Get logger instance
const logger = nexlog.getDefaultLogger().?;

// Create metadata
const metadata = nexlog.LogMetadata{
    .timestamp = std.time.timestamp(),
    .thread_id = 0,
    .file = @src().file,
    .line = @src().line,
    .function = @src().fn_name,
};

// Log messages
try logger.log(.info, "Hello {s}", .{"world"}, metadata);
```

### Log Levels

Nexlog supports six log levels:
- `trace`: Finest-grained information
- `debug`: Debugging information
- `info`: General information
- `warn`: Warning messages
- `err`: Error messages
- `critical`: Critical failures

Each level can be colored differently when console output is enabled:
- trace: Gray
- debug: Cyan
- info: Green
- warn: Yellow
- err: Red
- critical: Magenta

### Configuration

The logger can be configured using `LogConfig`:

```zig
const config = nexlog.LogConfig{
    .min_level = .info,          // Minimum log level to output
    .enable_colors = true,       // Enable colored console output
    .enable_file_logging = true, // Enable logging to file
    .file_path = "app.log",      // Log file path
    .max_file_size = 10 * 1024 * 1024, // Maximum log file size
    .enable_rotation = true,     // Enable log file rotation
    .max_rotated_files = 5,      // Number of backup files to keep
    .buffer_size = 4096,         // Internal buffer size
    .async_mode = false,         // Synchronous logging
    .enable_metadata = true,     // Include metadata in logs
};
```

### Thread Safety

The logger is thread-safe by default, using a mutex to protect concurrent access. Each log operation is atomic, ensuring that log messages from different threads don't interfere with each other.

### Metadata

Each log message can include metadata:
- Timestamp
- Thread ID
- Source file
- Line number
- Function name

### Error Handling

The logger uses Zig's error union type for robust error handling:

```zig
pub const LogError = error{
    MetadataError,
    BufferFull,
    InvalidLogLevel,
    MessageTooLarge,
    FileLockFailed,
    FileRotationFailed,
    InvalidConfiguration,
    ThreadInitFailed,
    FormattingError,
    FilterError,
    AlreadyInitialized,
};
```

### Output Format

Log messages follow this format:
```
[timestamp] [LEVEL] message
```

Example:
```
[1734269785] [INFO] Application started
[1734269785] [DEBUG] Processing item 42
```