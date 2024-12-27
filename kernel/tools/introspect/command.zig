const utils = @import("utils.zig");

const Source = @import("source.zig");

const Self = @This();
const ParseFn = *const fn (source: *Source, context: ?*anyopaque) ?Self;

type: union(enum) {
    parse: ParseFn,
    children: []const Self,
    end: void,
},
help: ?[]const u8 = null,

pub const end = Self{ .type = .end };

pub fn parse(self: Self, src: *Source, context: ?*anyopaque) ?Self {
    if (src.matchIden("h")) |_| if (self.help) |h| utils.logln(h);
    return switch (self.type) {
        .parse => self.type.parse(src, context),
        .children => |c| {
            for (c) |child| if (child.parse(src, context)) |p| return p;
            return null;
        },
        .end => null,
    };
}
