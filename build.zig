const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = .riscv64,
        .os_tag = .freestanding,
    } });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });

    const kernel = b.addExecutable(.{
        .name = "kernel",
        .root_source_file = b.path("kernel/entry.zig"),
        .optimize = optimize,
        .target = target,
        .linkage = .static,
        .code_model = .medium,
    });

    const start = b.addObject(.{
        .name = "start",
        .root_source_file = b.path("kernel/start.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    const kernelvec = b.addObject(.{
        .name = "kernelvec",
        .root_source_file = b.path("kernel/asm/kernelvec.zig"),
        .target = target,
        .optimize = optimize,
    });

    const switch_context = b.addObject(.{
        .name = "switch_context",
        .root_source_file = b.path("kernel/asm/switch_context.zig"),
        .target = target,
        .optimize = optimize,
    });

    const trampoline = b.addObject(.{
        .name = "trampoline",
        .root_source_file = b.path("kernel/asm/trampoline.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    kernel.setLinkerScript(b.path("kernel/kernel.ld"));

    kernel.addObject(start);
    kernel.addObject(trampoline);
    kernel.addObject(kernelvec);
    kernel.addObject(switch_context);

    b.installArtifact(kernel);

    const run_cmd_str = [_][]const u8{
        "qemu-system-riscv64",
        "-m",
        "512",
        "-smp",
        "4",
        // "1",
        "-no-reboot",
        "-nographic",
        "-bios",
        "none",
        "-M",
        "virt",
        "-kernel",
        "./zig-out/bin/kernel",
    };

    const run_cmd = b.addSystemCommand(&run_cmd_str);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the kernel");
    run_step.dependOn(&run_cmd.step);

    const debug_add = [_][]const u8{ "-S", "-s" };
    const debug_cmd_str = run_cmd_str ++ debug_add;

    const debug_cmd = b.addSystemCommand(&debug_cmd_str);
    debug_cmd.step.dependOn(b.getInstallStep());

    const debug_step = b.step("debug", "Debug the kernel");
    debug_step.dependOn(&debug_cmd.step);
}
