const std = @import("std");

pub fn build(b: *std.Build) void {
    // const target = b.standardTargetOptions(.{ .default_target = .{ .os_tag = .windows } });
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{ .target = target, .optimize = optimize });
    const dep_zalgebra = b.dependency("zalgebra", .{ .target = target, .optimize = optimize });
    const dep_freetype = b.dependency("mach-freetype", .{ .target = target, .optimize = optimize });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "sokol_test",
        .root_module = exe_mod,
    });

    exe.root_module.addImport("sokol", dep_sokol.module("sokol"));
    exe.root_module.addImport("zalgebra", dep_zalgebra.module("zalgebra"));
    exe.root_module.addImport("mach-freetype", dep_freetype.module("mach-freetype"));
    exe.linkSystemLibrary("GL");
    exe.linkSystemLibrary("X11");
    exe.linkSystemLibrary("Xi");
    exe.linkSystemLibrary("Xcursor");
    exe.linkSystemLibrary("asound");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    var shader_dir = std.fs.cwd().openDir("./src/shaders/", .{ .iterate = true }) catch unreachable;
    defer shader_dir.close();

    shader_dir.makeDir("compiled") catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => unreachable,
    };

    var iterator = shader_dir.iterate();

    var compile_steps = std.ArrayList(*std.Build.Step).init(b.allocator);

    while (iterator.next() catch unreachable) |entry| {
        if (entry.kind == .directory) continue;

        const path = std.fmt.allocPrint(
            b.allocator,
            "src/shaders/{s}",
            .{entry.name},
        ) catch unreachable;

        const new_name = std.fmt.allocPrint(
            b.allocator,
            "src/shaders/compiled/{s}.zig",
            .{entry.name},
        ) catch unreachable;

        const cmd = b.addSystemCommand(&[_][]const u8{
            "./sokol-tools/zig-out/bin/sokol-shdc",
            "-i",
            path,
            "-o",
            new_name,
            "-l",
            "glsl410",
            "-f",
            "sokol_zig",
        });

        compile_steps.append(&cmd.step) catch unreachable;
    }

    const shader_step = b.step("shader", "compile sokol shaders");
    for (compile_steps.items) |step| shader_step.dependOn(step);
}
