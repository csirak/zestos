const std = @import("std");
const fs = @import("kernel/fs/makeFs.zig");

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

    fs.makeFs(false);

    userFiles(b, target) catch |e| {
        std.debug.print("Error: {}\n", .{e});
        @panic("err");
    };

    const run_cmd_str = [_][]const u8{
        "qemu-system-riscv64",
        "-m",
        "128M",
        "-smp",
        // "4",
        "1",
        "-nographic",
        "-bios",
        "none",
        "-machine",
        "virt",
        "-kernel",
        "./zig-out/bin/kernel",
        "-global",
        "virtio-mmio.force-legacy=false",
        "-drive",
        "file=fs.img,if=none,format=raw,id=x0",
        "-device",
        "virtio-blk-device,drive=x0,bus=virtio-mmio-bus.0",
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

fn userFiles(b: *std.Build, target: std.Build.ResolvedTarget) !void {
    const user_program_path = "user";
    const dir = try std.fs.cwd().openDir(user_program_path, .{});
    var it = dir.iterate();
    while (try it.next()) |entry| {
        const name = entry.name;
        const file = "zig";
        const paths = [_][]const u8{ user_program_path, name };
        const full_path = try std.fs.path.join(b.allocator, &paths);
        if (entry.kind == .file) {
            if (name.len < file.len or !std.mem.eql(u8, name[name.len - file.len ..], file)) continue;

            const parts = [_][]const u8{ "_", name[0 .. name.len - file.len - 1] };

            const prog_name = try std.mem.concat(b.allocator, u8, &parts);
            const prog = b.addExecutable(.{
                .name = prog_name,
                .root_source_file = b.path(full_path),
                .optimize = .Debug,
                .target = target,
                .code_model = .medium,
            });

            prog.setLinkerScript(b.path("user/user.ld"));
            prog.link_z_max_page_size = 4096;
            b.getInstallStep().dependOn(&b.addInstallArtifact(prog, .{
                .dest_dir = .{
                    .override = .{
                        .custom = "../user/bin",
                    },
                },
            }).step);
        }
    }
}
