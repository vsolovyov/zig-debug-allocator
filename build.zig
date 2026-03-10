const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // With libc: crashes on gVisor
    const exe = b.addExecutable(.{
        .name = "repro-libc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("direct.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    exe.root_module.link_libc = true;
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    b.step("run", "With libc (crashes on gVisor)").dependOn(&run_cmd.step);

    // Without libc: works everywhere (control)
    const exe_no = b.addExecutable(.{
        .name = "repro-no-libc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("direct.zig"),
            .target = target,
            .optimize = .Debug,
        }),
    });
    b.installArtifact(exe_no);

    const run_no = b.addRunArtifact(exe_no);
    run_no.step.dependOn(b.getInstallStep());
    b.step("run-no-libc", "Without libc (works)").dependOn(&run_no.step);
}
