const std = @import("std");
const State = @import("main.zig").State;

const ft = @import("mach-freetype");
const sg = @import("sokol").gfx;
const zalg = @import("zalgebra");

const text_shd = @import("shaders/compiled/text.glsl.zig");

const font = @embedFile("assets/JetBrainsMono-Medium.ttf");
const ATLAS_W = 512;
const ATLAS_H = 512;

bindings: sg.Bindings,
pipeline: sg.Pipeline,

glyphs: [128]Glyph = undefined,
font_atlas: [ATLAS_W * ATLAS_H]u8 = .{0} ** (ATLAS_W * ATLAS_H),

instance_count: usize = 0,
instance_data: []TextIndexData,
allocator: std.mem.Allocator,

const Self = @This();

const TextIndexData = packed struct {
    offset: packed struct { x: f32, y: f32 },
    dims: packed struct { w: f32, h: f32 },
    uv_rect: packed struct { u_off: f32, v_off: f32, w: f32, h: f32 },
    color: packed struct { r: f32, g: f32, b: f32, a: f32 },
};

const Glyph = struct {
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

pub fn init(max_char_count: usize, allocator: std.mem.Allocator) !Self {
    const text_renderer: Self = .{
        .bindings = sg.Bindings{},
        .pipeline = undefined,
        .allocator = allocator,
        .instance_data = try allocator.alloc(TextIndexData, max_char_count),
    };

    return text_renderer;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.instance_data);
}

pub fn initRenderer(self: *Self) void {
    buildAtlas(self) catch |e| {
        std.debug.print("failed to build atlas: {}\n", .{e});
    };

    self.bindings.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(
            &[_]f32{
                0.0, 0.0, 0.0, 0.0,
                1.0, 0.0, 1.0, 0.0,
                0.0, 1.0, 0.0, 1.0,
                1.0, 0.0, 1.0, 0.0,
                1.0, 1.0, 1.0, 1.0,
                0.0, 1.0, 0.0, 1.0,
            },
        ),
    });

    self.bindings.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = self.instance_data.len * @sizeOf(TextIndexData),
    });

    self.bindings.samplers[text_shd.SMP_smp] = sg.makeSampler(.{
        .mag_filter = .LINEAR,
        .min_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    var image_descriptor: sg.ImageDesc = .{
        .width = ATLAS_W,
        .height = ATLAS_H,
        .pixel_format = .R8,
    };
    image_descriptor.data.subimage[0][0] = sg.asRange(&self.font_atlas);
    self.bindings.images[text_shd.IMG_tex] = sg.makeImage(image_descriptor);

    var pip_descriptor: sg.PipelineDesc = .{
        .cull_mode = .BACK,
        .shader = sg.makeShader(text_shd.textShaderDesc(sg.queryBackend())),
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .layout = init: {
            var l: sg.VertexLayoutState = .{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[text_shd.ATTR_text_pos] = .{
                .format = .FLOAT2,
                .buffer_index = 0,
            };
            l.attrs[text_shd.ATTR_text_uv_in] = .{
                .format = .FLOAT2,
                .buffer_index = 0,
            };

            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[text_shd.ATTR_text_offset] = .{
                .format = .FLOAT2,
                .buffer_index = 1,
            };
            l.attrs[text_shd.ATTR_text_dims] = .{
                .format = .FLOAT2,
                .buffer_index = 1,
            };
            l.attrs[text_shd.ATTR_text_uv_rect_in] = .{
                .format = .FLOAT4,
                .buffer_index = 1,
            };
            l.attrs[text_shd.ATTR_text_col_in] = .{
                .format = .FLOAT4,
                .buffer_index = 1,
            };
            break :init l;
        },
        .face_winding = .CW,
    };
    pip_descriptor.colors[0].blend.enabled = true;
    pip_descriptor.colors[0].blend.src_factor_rgb = .SRC_ALPHA;
    pip_descriptor.colors[0].blend.dst_factor_rgb = .ONE_MINUS_SRC_ALPHA;
    pip_descriptor.colors[0].blend.src_factor_alpha = .SRC_ALPHA;
    pip_descriptor.colors[0].blend.dst_factor_alpha = .ONE_MINUS_SRC_ALPHA;

    self.pipeline = sg.makePipeline(pip_descriptor);
}

fn buildAtlas(self: *Self) !void {
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
                self.font_atlas[dst_start .. dst_start + bmp.width()],
                bmp.buffer().?[src_start .. src_start + bmp.width()],
            );
        }

        self.glyphs[c] = Glyph{
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
}

pub fn setupDraw(self: *Self) void {
    self.instance_count = 0;
}

pub fn emitInstanceData(self: *Self, g: Glyph, x: f32, y: f32, col: zalg.Vec4) void {
    // x: left y: bottom
    // y+ = down

    self.instance_data[self.instance_count] = .{
        .color = .{ .r = col.x(), .g = col.y(), .b = col.z(), .a = col.w() },
        .offset = .{ .x = x + g.bearing_x, .y = y - g.bearing_y },
        .dims = .{ .w = g.w, .h = g.h },
        .uv_rect = .{ .u_off = g.u0, .v_off = g.v0, .w = g.u1 - g.u0, .h = g.v1 - g.v0 },
    };

    self.instance_count += 1;
}
