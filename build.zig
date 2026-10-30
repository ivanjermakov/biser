const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("biser", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_mod = b.addTest(.{ .root_module = mod });
    const test_run = b.addRunArtifact(test_mod);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&test_run.step);

    const check_step = b.step("check", "");
    check_step.dependOn(&test_run.step);
}
