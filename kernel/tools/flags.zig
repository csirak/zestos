const Handles = enum {
    MKDIR_HEY,
};

var active_handles = [_]bool{false} ** @typeInfo(Handles).Enum.fields.len;

pub fn activate(handle: Handles) void {
    active_handles[@intFromEnum(handle)] = true;
}

pub fn deactivate(handle: Handles) void {
    active_handles[@intFromEnum(handle)] = false;
}

pub fn isActive(handle: Handles) bool {
    return active_handles[@intFromEnum(handle)];
}
