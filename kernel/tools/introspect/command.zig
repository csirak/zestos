const utils = @import("utils.zig");

const Self = @This();
const ParseFn = *const fn (source: []u8, context: ?*anyopaque) ?Self;

type: union(enum) {
    parse: ParseFn,
    children: []const Self,
    end: void,
},

pub const end = Self{ .type = .end };

pub fn parse(self: Self, source: []u8, context: ?*anyopaque) ?Self {
    const src = utils.cleanSource(source);
    return switch (self.type) {
        .parse => self.type.parse(source, context),
        .children => |c| {
            for (c) |child| if (child.parse(src, context)) |p| return p;
            return null;
        },
        .end => null,
    };
}
