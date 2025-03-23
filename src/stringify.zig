//! https://github.com/msgpack/msgpack/blob/master/spec.md

const std = @import("std");
const testing = std.testing;

pub fn stringify(value: anytype, out_stream: anytype) !void {
    const T = @TypeOf(value);

    switch (@typeInfo((T))) {
        .null => {
            try out_stream.writeByte(0xc0);
        },
        .optional => {
            if (value) |v| {
                try stringify(v, out_stream);
            } else {
                try stringify(null, out_stream);
            }
        },
        .bool => {
            try out_stream.writeByte(if (value) 0xc3 else 0xc2);
        },
        .comptime_int => {
            try stringify(
                @as(std.math.IntFittingRange(value, value), value),
                out_stream,
            );
        },
        .int => {
            // TODO: Ensure this is smaller that i64

            // positive fixint stores 7-bit positive integer
            if (value >= 0 and value <= 0x7F) {
                try out_stream.writeByte(@intCast(value));
                return;
            }

            // negative fixint stores 5-bit negative integer
            if (value >= -32 and value < 0) {
                try out_stream.writeByte(@bitCast(@as(i8, @intCast(value))));
                return;
            }

            const prefix = switch (T) {
                u8 => 0xcc,
                u16 => 0xcd,
                u32 => 0xce,
                u64 => 0xcf,
                i8 => 0xd0,
                i16 => 0xd1,
                i32 => 0xd2,
                i64 => 0xd3,
                else => unreachable,
            };

            try out_stream.writeByte(prefix);
            try out_stream.writeInt(T, value, .big);
        },
        .array => {
            // Coerce `[N]T` to `*const [N]T` (and then to `[]const T`).
            return stringify(&value, out_stream);
        },
        .@"struct" => |struct_info| {
            if (struct_info.is_tuple) {
                @panic("Tuple is not yet supported.");
            }

            if (struct_info.fields.len < 16) {
                const header: u8 = 0x80 | @as(u8, @intCast(value.len));
                try out_stream.writeByte(header);
            } else {
                @panic("Struct with more than 15 fields is not yet supported.");
            }

            for (struct_info.fields) |field| {
                try stringify(field.name, out_stream);
                try stringify(@field(value, field.name), out_stream);
            }
        },
        .pointer => |ptr_info| {
            switch (ptr_info.size) {
                .one => {
                    switch (@typeInfo(ptr_info.child)) {
                        .array => {
                            // Coerce `*[N]T` to `[]const T`.
                            const Slice = []const std.meta.Elem(ptr_info.child);
                            return stringify(@as(Slice, value), out_stream);
                        },
                        else => {
                            return stringify(value.*, out_stream);
                        },
                    }
                },
                .many, .slice => {
                    if (ptr_info.size == .many and ptr_info.sentinel() == null) {
                        @compileError("unable to stringify type '" ++ @typeName(T) ++ "' without sentinel");
                    }

                    const slice = if (ptr_info.size == .many) std.mem.span(value) else value;

                    // This is a []const u8, or some similar Zig string.
                    if (ptr_info.child == u8 and std.unicode.utf8ValidateSlice(slice)) {
                        return writeString(slice, out_stream);
                    }

                    if (value.len < 16) {
                        const header: u8 = 0x90 | @as(u8, @intCast(value.len));
                        try out_stream.writeByte(header);
                    } else if (value.len < std.math.maxInt(u16)) {
                        try out_stream.writeByte(0xdc);
                        try out_stream.writeInt(u16, @intCast(value.len), .big);
                    } else if (value.len < std.math.maxInt(u32)) {
                        try out_stream.writeByte(0xdc);
                        try out_stream.writeInt(u32, @intCast(value.len), .big);
                    } else {
                        // Too big length
                        unreachable;
                    }

                    for (value) |v| {
                        try stringify(v, out_stream);
                    }
                },
                else => @compileError("Unable to stringify type '" ++ @typeName(T) ++ "'"),
            }
        },
        else => {
            @panic("This is not implemented yet for: " ++ @typeName(T));
        },
    }
}

fn writeString(s: []const u8, out_stream: anytype) !void {
    if (s.len < std.math.maxInt(u5)) {
        const header: u8 = 0xA0 | @as(u8, @intCast(s.len));
        try out_stream.writeByte(header);
    } else if (s.len < std.math.maxInt(u8)) {
        try out_stream.writeByte(0xd9);
        try out_stream.writeInt(u8, @intCast(s.len), .little);
    } else if (s.len < std.math.maxInt(u16)) {
        try out_stream.writeByte(0xda);
        try out_stream.writeInt(u16, @intCast(s.len), .big);
    } else if (s.len < std.math.maxInt(u32)) {
        try out_stream.writeByte(0xdb);
        try out_stream.writeInt(u32, @intCast(s.len), .big);
    } else {
        // Too big length
        unreachable;
    }

    return out_stream.writeAll(s);
}

test "stringify" {
    // Null and optional
    try expectPack(null, &.{0xc0});

    // Boolean
    try expectPack(true, &.{0xc3});
    try expectPack(false, &.{0xc2});

    // Numbers
    try expectPack(10, &.{10});
    try expectPack(-32, &.{0b11100000});
    try expectPack(140, &.{ 0xcc, 140 });

    // Array
    try expectPack([_]bool{ true, false, true }, &.{ 0x90 | 3, 0xc3, 0xc2, 0xc3 });

    // String
    try expectPack("test", &.{ 0xA0 | 4, 't', 'e', 's', 't' });
    try expectPack("", &.{0xA0 | 0});
}

fn expectPack(value: anytype, expected: []const u8) !void {
    var out = std.ArrayList(u8).init(testing.allocator);
    defer out.deinit();

    try stringify(value, out.writer());
    try testing.expectEqualSlices(u8, expected, out.items);
}
