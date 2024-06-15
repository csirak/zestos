const std = @import("std");
const Target = std.Target;
const CrossTarget = std.zig.CrossTarget;
const Feature = std.Target.Cpu.Feature;

const objFiles = [_][]u8{"main"};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{
        .cpu_arch = Target.Cpu.Arch.riscv64,
        .os_tag = Target.Os.Tag.freestanding,
    } });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
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

    const trampoline = b.addObject(.{
        .name = "trampoline",
        .root_source_file = b.path("kernel/asm/trampoline.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    trampoline.addIncludePath(b.path("kernel"));

    const trap = b.addObject(.{
        .name = "trap",
        .root_source_file = b.path("kernel/trap.zig"),
        .target = target,
        .optimize = optimize,
        .code_model = .medium,
    });

    kernel.addIncludePath(b.path("kernel"));
    kernel.setLinkerScript(b.path("kernel/kernel.ld"));
    kernel.addObject(start);
    kernel.addObject(trampoline);

    kernel.addObject(kernelvec);
    kernel.addObject(trap);

    b.installArtifact(kernel);

    const run_cmd_str = [_][]const u8{
        "qemu-system-riscv64",
        "-m",
        "512",
        "-smp",
        "4",
        // "2",
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

    const debug_cmd_str = [_][]const u8{
        "qemu-system-riscv64",
        "-m",
        "512",
        "-smp",
        "4",
        // "2",
        "-no-reboot",
        "-nographic",
        "-bios",
        "none",
        "-M",
        "virt",
        "-kernel",
        "./zig-out/bin/kernel",
        "-S",
        "-s",
    };

    const debug_cmd = b.addSystemCommand(&debug_cmd_str);
    debug_cmd.step.dependOn(b.getInstallStep());

    const debug_step = b.step("debug", "Debug the kernel");
    debug_step.dependOn(&debug_cmd.step);
}
