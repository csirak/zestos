const addrs = [_]u64{
    0x800053be,
    0x80061d30,
    0x80050990,
};

const std = @import("std");
const DW = std.dwarf;
var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
const alloc = gpa.allocator();

const dw_elf = @import("dwarf_elf.zig");

pub fn main() !void {
    var sections: DW.DwarfInfo.SectionArray = DW.DwarfInfo.null_section_array;
    var di = try dw_elf.readElfDebugInfo(
        alloc,
        "zig-out/bin/kernel",
        null,
        null,
        &sections,
        null,
    );
    const symbol_info = dw_elf.getSymbolFromDwarf(alloc, addrs[0], &di) catch |err| return err;
    defer symbol_info.deinit(alloc);
    const li = symbol_info.line_info.?;
    std.debug.print("{s}:{d}:{d}\n", .{ li.file_name, li.line, li.column });
}
