const std = @import("std");
const sapp = @import("sokol").app;

pub fn genParserFunc() fn ([]const u8) ?i32 {
    const keycode_enum_info: std.builtin.Type.Enum = @typeInfo(sapp.Keycode).@"enum";

    comptime var kv_list: []const struct { []const u8, i32 } = &.{};

    inline for (keycode_enum_info.fields) |enum_field| {
        comptime var name: []const u8 = &.{};
        for (enum_field.name) |c| {
            if (c == '_') continue;
            name = name ++ .{std.ascii.toLower(c)};
        }
        kv_list = kv_list ++ .{
            .{ name, @as(i32, @intCast(enum_field.value)) },
        };
    }

    const static_map = std.static_string_map.StaticStringMap(i32).initComptime(kv_list);

    return struct {
        pub fn parser(string: []const u8) ?i32 {
            return static_map.get(string);
        }
    }.parser;
}
