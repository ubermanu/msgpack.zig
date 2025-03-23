//! https://github.com/msgpack/msgpack/blob/master/spec.md

const std = @import("std");

pub fn parseFromSlice(comptime T: type, allocator: std.mem.Allocator, s: []const u8) !T {
    _ = allocator;
    _ = s;
}

test {
    _ = @import("stringify.zig");
}
