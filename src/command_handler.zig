const std = @import("std");
const Mode = @import("main.zig").Mode;
const sapp = @import("sokol").app;

const CodeWithMod = packed struct {
    shift: bool = false,
    control: bool = false,
    alt: bool = false,
    super: bool = false,
    code_point: u28 = 0,
};

const ActionMap = std.AutoHashMap(u32, MapOrAction);

const ActionMaps = struct {
    char_map: ?ActionMap = null,
    key_map: ?ActionMap = null,
};

const MapOrAction = union(enum) {
    maps: ActionMaps,
    action: *const fn () void,
};

current_maps_ptr: ?*const ActionMaps = null,
command_map: std.AutoHashMap(Mode, ActionMaps),
allocator: std.mem.Allocator,

const Self = @This();

pub fn init(allocator: std.mem.Allocator) Self {
    return .{
        .command_map = std.AutoHashMap(Mode, ActionMaps).init(allocator),
        .allocator = allocator,
    };
}

fn deinitActionMapsRec(maps_ptr: *ActionMaps) void {
    if (maps_ptr.key_map) |*key_map_ptr| {
        var child_iter = key_map_ptr.valueIterator();
        while (child_iter.next()) |child_ptr| {
            if (child_ptr.* == .maps) {
                deinitActionMapsRec(&child_ptr.maps);
            }
        }
        key_map_ptr.deinit();
    }
    if (maps_ptr.char_map) |*char_map_ptr| {
        var child_iter = char_map_ptr.valueIterator();
        while (child_iter.next()) |child_ptr| {
            if (child_ptr.* == .maps) {
                deinitActionMapsRec(&child_ptr.maps);
            }
        }
        char_map_ptr.deinit();
    }
}

pub fn deinit(self: *Self) void {
    var action_maps_iter = self.command_map.valueIterator();
    while (action_maps_iter.next()) |maps_ptr| {
        deinitActionMapsRec(maps_ptr);
    }
    self.command_map.deinit();
}

pub fn addCommand(self: *Self, bind: []const u8, mode: Mode, action: *const fn () void) !void {
    if (bind.len == 0) return error.KeybindDescriptionEmpty;

    const entry = try self.command_map.getOrPut(mode);
    if (!entry.found_existing) {
        entry.value_ptr.* = .{};
    }

    var current_maps_ptr: *ActionMaps = entry.value_ptr;
    var char_index: usize = 0;

    while (char_index < bind.len) {
        const char: u32 = @intCast(bind[char_index]);

        // TODO: escape
        if (char == '<') {
            var end_index: usize = 0;
            for (char_index + 1..bind.len) |i| {
                if (bind[i] == '>') {
                    end_index = i;
                    break;
                }
            }
            if (end_index == 0) return error.MalformedBind;

            const code_with_mod = try parseKey(bind[char_index + 1 .. end_index]);

            std.debug.print("string: {s}\n", .{bind});
            std.debug.print("char index: {}\n", .{char_index});
            std.debug.print("end index: {}\n", .{end_index});
            std.debug.print("char: {c}\n", .{@as(u8, @intCast(code_with_mod >> 4))});
            std.debug.print("registered: {b}\n\n", .{code_with_mod});

            if (current_maps_ptr.key_map == null) {
                current_maps_ptr.key_map = ActionMap.init(self.allocator);
            }
            const key_map_ptr = &current_maps_ptr.key_map.?;

            const result = try key_map_ptr.getOrPut(code_with_mod);
            if (!result.found_existing) {
                if (end_index == bind.len - 1) {
                    result.value_ptr.* = MapOrAction{ .action = action };
                    return;
                } else {
                    result.value_ptr.* = MapOrAction{ .maps = ActionMaps{} };
                }
            }
            current_maps_ptr = &result.value_ptr.maps;

            char_index = end_index + 1;

            continue;
        }

        if (current_maps_ptr.char_map == null) {
            current_maps_ptr.char_map = ActionMap.init(self.allocator);
        }
        const char_map_ptr = &current_maps_ptr.char_map.?;

        const char_shifted = char << 4;

        const result = try char_map_ptr.getOrPut(char_shifted);
        if (!result.found_existing) {
            if (char_index == bind.len - 1) {
                result.value_ptr.* = MapOrAction{ .action = action };
                return;
            } else {
                result.value_ptr.* = MapOrAction{ .maps = ActionMaps{} };
            }
        }
        current_maps_ptr = &result.value_ptr.maps;

        char_index += 1;
    }
}

// This leaves behind empty hashmaps
pub fn removeCommand(self: *Self, bind: []const u8, mode: Mode) !void {
    if (bind.len == 0) return error.KeybindDescriptionEmpty;

    var current_maps_ptr: *ActionMaps = self.command_map.getPtr(mode) orelse return;
    var char_index: usize = 0;

    while (char_index < bind.len) {
        const char = bind[char_index];

        // TODO: escape
        if (char == '<') {
            var end_index = 0;
            for (bind[char_index + 1 ..]) |i| {
                if (char == '>') end_index = i;
            }
            if (end_index == 0) error.MalformedBind;

            const key_code = try parseKey(bind[char_index + 1 .. end_index - 1]);

            if (current_maps_ptr.key_map == null) return;
            const key_map_ptr = &current_maps_ptr.key_map.?;
            const map_or_action_ptr: *MapOrAction = try key_map_ptr.getPtr(key_code) orelse return;

            switch (map_or_action_ptr.*) {
                .maps => |*maps_ptr| {
                    current_maps_ptr = maps_ptr;
                },
                .action => {
                    key_map_ptr.remove(char);
                    return;
                },
            }

            char_index = end_index + 1;

            return;
        }

        if (current_maps_ptr.char_map == null) return;
        const char_map_ptr = &current_maps_ptr.char_map.?;
        const map_or_action_ptr = char_map_ptr.getPtr(char) orelse return;

        switch (map_or_action_ptr.*) {
            .maps => |*maps_ptr| {
                current_maps_ptr = maps_ptr;
            },
            .action => {
                map_or_action_ptr.remove(char);
                return;
            },
        }

        char_index += 1;
    }
}

pub fn onInput(self: *Self, mode: Mode, event: [*c]const sapp.Event) void {
    if (event) |e| {
        if (self.current_maps_ptr == null) {
            self.current_maps_ptr = self.command_map.getPtr(mode);
        }
        const current_maps_ptr = self.current_maps_ptr.?;

        switch (e.*.type) {
            .KEY_DOWN => {
                const shifted_code: u32 = @bitCast(@intFromEnum(e.*.key_code) << 4);
                const code_with_mod = shifted_code | e.*.modifiers;

                if (e.*.char_code != 0) {
                    std.debug.print("raw {b}\n", .{@intFromEnum(e.*.key_code)});
                    std.debug.print("code {b}\n", .{shifted_code});
                    std.debug.print("code + mod: {b}\n", .{code_with_mod});
                }

                if (current_maps_ptr.key_map == null) return;
                const key_map_ptr = &current_maps_ptr.key_map.?;
                const map_or_action_ptr = key_map_ptr.getPtr(code_with_mod) orelse return;
                switch (map_or_action_ptr.*) {
                    .maps => |*maps_ptr| {
                        self.current_maps_ptr = maps_ptr;
                    },
                    .action => |action| {
                        action();
                        self.current_maps_ptr = null;
                        return;
                    },
                }
            },
            .CHAR => {
                const shifted_code: u32 = @bitCast(e.*.char_code << 4);
                const code_with_mod = shifted_code;

                if (current_maps_ptr.char_map == null) return;
                const char_map_ptr = &current_maps_ptr.char_map.?;
                const map_or_action_ptr = char_map_ptr.getPtr(code_with_mod) orelse return;
                switch (map_or_action_ptr.*) {
                    .maps => |*maps_ptr| {
                        self.current_maps_ptr = maps_ptr;
                    },
                    .action => |action| {
                        action();
                        self.current_maps_ptr = null;
                        return;
                    },
                }
            },
            else => {},
        }
    }
}

pub fn clearInputSequence(self: *Self) void {
    self.current_map_ptr = null;
}

const parseKey = blk: {
    @setEvalBranchQuota(5000);
    const keycode_enum_info: std.builtin.Type.Enum = @typeInfo(sapp.Keycode).@"enum";

    var kv_list: []const struct { []const u8, i32 } = &.{};

    for (keycode_enum_info.fields) |enum_field| {
        var name: []const u8 = &.{};
        for (enum_field.name) |c| {
            if (c == '_') continue;
            name = name ++ .{std.ascii.toLower(c)};
        }
        kv_list = kv_list ++ .{
            .{ name, @as(u32, @intCast(enum_field.value)) },
        };
    }

    const static_map = std.static_string_map.StaticStringMap(u32).initComptime(kv_list);

    const func = struct {
        pub fn parser(string: []const u8) !u32 {
            var i: usize = 0;
            var input_start: usize = 0;

            var code_with_mod = CodeWithMod{};

            while (i < string.len) : (i += 1) {
                const char = string[i];
                if (char == '-') {
                    switch (string[i - 1]) {
                        'C' => code_with_mod.control = true,
                        's' => code_with_mod.super = true,
                        'S' => code_with_mod.shift = true,
                        'A' => code_with_mod.alt = true,
                        else => return error.MalformedBind,
                    }
                    if (i != string.len - 1) {
                        input_start = i + 1;
                    } else {
                        return error.MalformedBind;
                    }
                }
            }

            std.debug.print("{s}\n", .{string[input_start .. i - 1]});
            code_with_mod.code_point = @intCast(static_map.get(string[input_start..i]) orelse return error.InvalidKey);

            return @bitCast(code_with_mod);
        }
    }.parser;
    @setEvalBranchQuota(1000);

    break :blk func;
};
