const std = @import("std");
const ft = @import("mach-freetype");
const font = @embedFile("assets/JetBrainsMono-Medium.ttf");
const State = @import("main.zig").State;

pub const ATLAS_W = 512;
pub const ATLAS_H = 512;

glyphs: [128]Glyph = undefined,
atlas_buffer: [ATLAS_W * ATLAS_H]u8 = .{0} ** (ATLAS_W * ATLAS_H),

const Self = @This();

pub const Glyph = struct {
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
    w: f32,
    h: f32,
    bearing_x: f32,
    bearing_y: f32,
    advance: i16,
};

pub fn init() !Self {
    var atlas: Self = .{};

    const ftlib = try ft.Library.init();
    defer ftlib.deinit();

    const face = try ftlib.createFaceMemory(font, 0);
    try face.setPixelSizes(0, 24);

    State.row_height = @as(f32, @floatFromInt(face.size().metrics().height)) / 64;
    State.font_descender = @abs(@as(f32, @floatFromInt(face.size().metrics().descender)) / 64);
    State.cursor_height = @as(f32, @floatFromInt(face.size().metrics().ascender - face.size().metrics().descender)) / 64;

    var pen_x: usize = 1;
    var pen_y: usize = 1;
    var row_h: usize = 0;

    for (32..127) |c| {
        try face.loadChar(@intCast(c), .{ .render = true });

        const slot = face.glyph();
        const bmp = slot.bitmap();

        if (pen_x + bmp.width() + 1 >= ATLAS_W) {
            pen_x = 1;
            pen_y += row_h + 1;
            row_h = 0;
        }

        var y: usize = 0;
        while (y < bmp.rows()) : (y += 1) {
            const dst_start = (pen_y + y) * ATLAS_W + pen_x;
            const src_start = y * bmp.width();
            std.mem.copyForwards(
                u8,
                atlas.atlas_buffer[dst_start .. dst_start + bmp.width()],
                bmp.buffer().?[src_start .. src_start + bmp.width()],
            );
        }

        atlas.glyphs[c] = Glyph{
            .u0 = @as(f32, @floatFromInt(pen_x)) / ATLAS_W,
            .v0 = @as(f32, @floatFromInt(pen_y)) / ATLAS_H,
            .u1 = (@as(f32, @floatFromInt(pen_x + bmp.width())) / ATLAS_W),
            .v1 = (@as(f32, @floatFromInt(pen_y + bmp.rows())) / ATLAS_H),
            .w = @floatFromInt(bmp.width()),
            .h = @floatFromInt(bmp.rows()),
            .bearing_x = @floatFromInt(slot.bitmapLeft()),
            .bearing_y = @floatFromInt(slot.bitmapTop()),
            .advance = @as(i16, @intCast(slot.advance().x)) >> 6,
        };

        pen_x += bmp.width() + 1;
        row_h = @max(row_h, bmp.rows());
    }

    return atlas;
}
