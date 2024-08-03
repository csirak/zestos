const std = @import("std");
const Builder = @import("std").build.Builder;
const Target = @import("std").Target;
const CrossTarget = @import("std").zig.CrossTarget;
const Feature = @import("std").Target.Cpu.Feature;

const objFiles = [_][]u8{"main"};

pub fn build(b: *Builder) void {
    const target = CrossTarget{ .cpu_arch = Target.Cpu.Arch.riscv64, .os_tag = Target.Os.Tag.freestanding };

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const kernel = b.addExecutable(.{ .name = "kernel", .root_source_file = .{ .path = "kernel/entry.zig" }, .optimize = optimize, .target = target, .linkage = std.build.CompileStep.Linkage.static });
    kernel.code_model = .medium;

    const start = b.addObject(.{
        .name = "start",
        .root_source_file = .{ .path = "kernel/start.zig" },
        .target = target,
        .optimize = optimize,
    });
    start.code_model = .medium;

    // const main = b.addObject(.{
    //     .name = "main",
    //     .root_source_file = .{ .path = "kernel/main.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });
    // main.code_model = .medium;

    const trampoline = b.addObject(.{
        .name = "trampoline",
        .root_source_file = .{ .path = "kernel/trampoline.zig" },
        .target = target,
        .optimize = optimize,
    });
    trampoline.code_model = .medium;

    trampoline.addIncludePath(.{ .path = "kernel" });

    // const lib = b.addObject(.{
    //     .name = "lib",
    //     .root_source_file = .{ .path = "kernel/lib.zig" },
    //     .target = target,
    //     .optimize = optimize,
    // });

    kernel.addIncludePath(.{ .path = "kernel" });
    kernel.setLinkerScript(.{ .path = "kernel/kernel.ld" });
    kernel.addObject(start);
    kernel.addObject(trampoline);

    // kernel.addObject(main);
    // kernel.addObject(lib);

    b.installArtifact(kernel);

    const run_cmd_str = [_][]const u8{
        "qemu-system-riscv64",
        "-m",
        "512",
        "-smp",
        "1",
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
        "1",
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
