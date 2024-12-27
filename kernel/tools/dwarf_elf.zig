const std = @import("std");
const builtin = @import("builtin");
const math = std.math;
const mem = std.mem;
const io = std.io;
const posix = std.posix;
const fs = std.fs;
const testing = std.testing;
const elf = std.elf;
const DW = std.dwarf;
const macho = std.macho;
const coff = std.coff;
const pdb = std.pdb;
const root = @import("root");
const File = std.fs.File;
const windows = std.os.windows;
const native_arch = builtin.cpu.arch;
const native_os = builtin.os.tag;
const native_endian = native_arch.endian();

pub fn assert(ok: bool) void {
    if (!ok) unreachable; // assertion failure
}

fn chopSlice(ptr: []const u8, offset: u64, size: u64) error{Overflow}![]const u8 {
    const start = math.cast(usize, offset) orelse return error.Overflow;
    const end = start + (math.cast(usize, size) orelse return error.Overflow);
    return ptr[start..end];
}

fn mapWholeFile(file: File) ![]align(mem.page_size) const u8 {
    nosuspend {
        defer file.close();

        const file_len = math.cast(usize, try file.getEndPos()) orelse math.maxInt(usize);
        const mapped_mem = try posix.mmap(
            null,
            file_len,
            posix.PROT.READ,
            .{ .TYPE = .SHARED },
            file.handle,
            0,
        );
        errdefer posix.munmap(mapped_mem);

        return mapped_mem;
    }
}

const ModuleDebugInfo = DW.DwarfInfo;

pub fn getSymbolFromDwarf(allocator: mem.Allocator, address: u64, di: *DW.DwarfInfo) !std.debug.SymbolInfo {
    if (nosuspend di.findCompileUnit(address)) |compile_unit| {
        return .{
            .symbol_name = nosuspend di.getSymbolName(address) orelse "???",
            .compile_unit_name = compile_unit.die.getAttrString(di, DW.AT.name, di.section(.debug_str), compile_unit.*) catch |err| switch (err) {
                error.MissingDebugInfo, error.InvalidDebugInfo => "???",
            },
            .line_info = nosuspend di.getLineNumberInfo(allocator, compile_unit.*, address) catch |err| switch (err) {
                error.MissingDebugInfo, error.InvalidDebugInfo => null,
                else => return err,
            },
        };
    } else |err| switch (err) {
        error.MissingDebugInfo, error.InvalidDebugInfo => {
            return .{};
        },
        else => return err,
    }
}
pub fn readElfDebugInfo(
    allocator: mem.Allocator,
    elf_filename: ?[]const u8,
    build_id: ?[]const u8,
    expected_crc: ?u32,
    parent_sections: *DW.DwarfInfo.SectionArray,
    parent_mapped_mem: ?[]align(mem.page_size) const u8,
) !ModuleDebugInfo {
    nosuspend {
        const elf_file = (if (elf_filename) |filename| blk: {
            break :blk fs.cwd().openFile(filename, .{});
        } else fs.openSelfExe(.{})) catch |err| switch (err) {
            error.FileNotFound => return error.MissingDebugInfo,
            else => return err,
        };

        const mapped_mem = try mapWholeFile(elf_file);
        if (expected_crc) |crc| if (crc != std.hash.crc.Crc32.hash(mapped_mem)) return error.InvalidDebugInfo;

        const hdr: *const elf.Ehdr = @ptrCast(&mapped_mem[0]);
        if (!mem.eql(u8, hdr.e_ident[0..4], elf.MAGIC)) return error.InvalidElfMagic;
        if (hdr.e_ident[elf.EI_VERSION] != 1) return error.InvalidElfVersion;

        const endian: std.builtin.Endian = switch (hdr.e_ident[elf.EI_DATA]) {
            elf.ELFDATA2LSB => .little,
            elf.ELFDATA2MSB => .big,
            else => return error.InvalidElfEndian,
        };
        assert(endian == native_endian); // this is our own debug info

        const shoff = hdr.e_shoff;
        const str_section_off = shoff + @as(u64, hdr.e_shentsize) * @as(u64, hdr.e_shstrndx);
        const str_shdr: *const elf.Shdr = @ptrCast(@alignCast(&mapped_mem[math.cast(usize, str_section_off) orelse return error.Overflow]));
        const header_strings = mapped_mem[str_shdr.sh_offset..][0..str_shdr.sh_size];
        const shdrs = @as(
            [*]const elf.Shdr,
            @ptrCast(@alignCast(&mapped_mem[shoff])),
        )[0..hdr.e_shnum];

        var sections: DW.DwarfInfo.SectionArray = DW.DwarfInfo.null_section_array;

        // Combine section list. This takes ownership over any owned sections from the parent scope.
        for (parent_sections, &sections) |*parent, *section| {
            if (parent.*) |*p| {
                section.* = p.*;
                p.owned = false;
            }
        }
        errdefer for (sections) |section| if (section) |s| if (s.owned) allocator.free(s.data);

        var separate_debug_filename: ?[]const u8 = null;
        var separate_debug_crc: ?u32 = null;

        for (shdrs) |*shdr| {
            if (shdr.sh_type == elf.SHT_NULL or shdr.sh_type == elf.SHT_NOBITS) continue;
            const name = mem.sliceTo(header_strings[shdr.sh_name..], 0);

            if (mem.eql(u8, name, ".gnu_debuglink")) {
                const gnu_debuglink = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
                const debug_filename = mem.sliceTo(@as([*:0]const u8, @ptrCast(gnu_debuglink.ptr)), 0);
                const crc_offset = mem.alignForward(usize, @intFromPtr(&debug_filename[debug_filename.len]) + 1, 4) - @intFromPtr(gnu_debuglink.ptr);
                const crc_bytes = gnu_debuglink[crc_offset..][0..4];
                separate_debug_crc = mem.readInt(u32, crc_bytes, native_endian);
                separate_debug_filename = debug_filename;
                continue;
            }

            var section_index: ?usize = null;
            inline for (@typeInfo(DW.DwarfSection).Enum.fields, 0..) |section, i| {
                if (mem.eql(u8, "." ++ section.name, name)) section_index = i;
            }
            if (section_index == null) continue;
            if (sections[section_index.?] != null) continue;

            const section_bytes = try chopSlice(mapped_mem, shdr.sh_offset, shdr.sh_size);
            sections[section_index.?] = if ((shdr.sh_flags & elf.SHF_COMPRESSED) > 0) blk: {
                var section_stream = io.fixedBufferStream(section_bytes);
                var section_reader = section_stream.reader();
                const chdr = section_reader.readStruct(elf.Chdr) catch continue;
                if (chdr.ch_type != .ZLIB) continue;

                var zlib_stream = std.compress.zlib.decompressor(section_stream.reader());

                const decompressed_section = try allocator.alloc(u8, chdr.ch_size);
                errdefer allocator.free(decompressed_section);

                const read = zlib_stream.reader().readAll(decompressed_section) catch continue;
                assert(read == decompressed_section.len);

                break :blk .{
                    .data = decompressed_section,
                    .virtual_address = shdr.sh_addr,
                    .owned = true,
                };
            } else .{
                .data = section_bytes,
                .virtual_address = shdr.sh_addr,
                .owned = false,
            };
        }

        const missing_debug_info =
            sections[@intFromEnum(DW.DwarfSection.debug_info)] == null or
            sections[@intFromEnum(DW.DwarfSection.debug_abbrev)] == null or
            sections[@intFromEnum(DW.DwarfSection.debug_str)] == null or
            sections[@intFromEnum(DW.DwarfSection.debug_line)] == null;

        // Attempt to load debug info from an external file
        // See: https://sourceware.org/gdb/onlinedocs/gdb/Separate-Debug-Files.html
        if (missing_debug_info) {

            // Only allow one level of debug info nesting
            if (parent_mapped_mem) |_| {
                return error.MissingDebugInfo;
            }

            const global_debug_directories = [_][]const u8{
                "/usr/lib/debug",
            };

            // <global debug directory>/.build-id/<2-character id prefix>/<id remainder>.debug
            if (build_id) |id| blk: {
                if (id.len < 3) break :blk;

                // Either md5 (16 bytes) or sha1 (20 bytes) are used here in practice
                const extension = ".debug";
                var id_prefix_buf: [2]u8 = undefined;
                var filename_buf: [38 + extension.len]u8 = undefined;

                _ = std.fmt.bufPrint(&id_prefix_buf, "{s}", .{std.fmt.fmtSliceHexLower(id[0..1])}) catch unreachable;
                const filename = std.fmt.bufPrint(
                    &filename_buf,
                    "{s}" ++ extension,
                    .{std.fmt.fmtSliceHexLower(id[1..])},
                ) catch break :blk;

                for (global_debug_directories) |global_directory| {
                    const path = try fs.path.join(allocator, &.{ global_directory, ".build-id", &id_prefix_buf, filename });
                    defer allocator.free(path);

                    return readElfDebugInfo(allocator, path, null, separate_debug_crc, &sections, mapped_mem) catch continue;
                }
            }

            // use the path from .gnu_debuglink, in the same search order as gdb
            if (separate_debug_filename) |separate_filename| blk: {
                if (elf_filename != null and mem.eql(u8, elf_filename.?, separate_filename)) return error.MissingDebugInfo;

                // <cwd>/<gnu_debuglink>
                if (readElfDebugInfo(allocator, separate_filename, null, separate_debug_crc, &sections, mapped_mem)) |debug_info| return debug_info else |_| {}

                // <cwd>/.debug/<gnu_debuglink>
                {
                    const path = try fs.path.join(allocator, &.{ ".debug", separate_filename });
                    defer allocator.free(path);

                    if (readElfDebugInfo(allocator, path, null, separate_debug_crc, &sections, mapped_mem)) |debug_info| return debug_info else |_| {}
                }

                var cwd_buf: [fs.MAX_PATH_BYTES]u8 = undefined;
                const cwd_path = posix.realpath(".", &cwd_buf) catch break :blk;

                // <global debug directory>/<absolute folder of current binary>/<gnu_debuglink>
                for (global_debug_directories) |global_directory| {
                    const path = try fs.path.join(allocator, &.{ global_directory, cwd_path, separate_filename });
                    defer allocator.free(path);
                    if (readElfDebugInfo(allocator, path, null, separate_debug_crc, &sections, mapped_mem)) |debug_info| return debug_info else |_| {}
                }
            }

            return error.MissingDebugInfo;
        }

        var di = DW.DwarfInfo{
            .endian = endian,
            .sections = sections,
            .is_macho = false,
        };

        try DW.openDwarfDebugInfo(&di, allocator);

        return di;
    }
}
