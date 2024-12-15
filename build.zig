const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "Nexlog",
        .root_source_file = b.path("src/nexlog.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    // Create the nexlog module for tests to use
    const nexlog_module = b.addModule("nexlog", .{
        .root_source_file = b.path("src/nexlog.zig"),
    });

    // Library unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/nexlog.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addImport("nexlog", nexlog_module);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Test step that will run all tests
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Add tests from tests directory
    var tests_dir = std.fs.cwd().openDir("tests", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        unreachable;
    };

    var it = tests_dir.iterate();
    while (it.next() catch unreachable) |entry| {
        if (entry.kind == .file) {
            const extension = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, extension, ".zig")) {
                const test_path = b.fmt("tests/{s}", .{entry.name});
                const test_exe = b.addTest(.{
                    .root_source_file = b.path(test_path),
                    .target = target,
                    .optimize = optimize,
                });
                test_exe.root_module.addImport("nexlog", nexlog_module);

                const run_test = b.addRunArtifact(test_exe);
                test_step.dependOn(&run_test.step);
            }
        }
    }

    // build.zig section for examples

    // Create an examples step
    const run_examples = b.step("examples", "Run all examples");

    // Add examples from examples directory
    var examples_dir = std.fs.cwd().openDir("examples", .{ .iterate = true }) catch |err| {
        if (err == error.FileNotFound) return;
        unreachable;
    };

    var examples_it = examples_dir.iterate();
    while (examples_it.next() catch unreachable) |entry| {
        if (entry.kind == .file) {
            const extension = std.fs.path.extension(entry.name);
            if (std.mem.eql(u8, extension, ".zig")) {
                // Check if file has content
                const example_file = examples_dir.openFile(entry.name, .{}) catch continue;
                defer example_file.close();

                const file_size = example_file.getEndPos() catch continue;
                if (file_size == 0) continue; // Skip empty files

                const example_path = b.fmt("examples/{s}", .{entry.name});
                const example_name = std.fs.path.stem(entry.name);

                // Create executable for this example
                const example_exe = b.addExecutable(.{
                    .name = example_name,
                    .root_source_file = b.path(example_path),
                    .target = target,
                    .optimize = optimize,
                });
                example_exe.root_module.addImport("nexlog", nexlog_module);

                // Install the example binary
                b.installArtifact(example_exe);

                // Create run step for this example
                const run_cmd = b.addRunArtifact(example_exe);
                const run_step = b.step(b.fmt("run-{s}", .{example_name}), b.fmt("Run the {s} example", .{example_name}));
                run_step.dependOn(&run_cmd.step);

                // Add to main examples step
                run_examples.dependOn(&run_cmd.step);
            }
        }
    }
}
