const std = @import("std");

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

vertices: []TextVertex,
allocator: std.mem.Allocator,

const Self = @This();

const TextVertex = packed struct { x: f32, y: f32, u: f32, v: f32 };

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

pub fn init(vertex_buffer_size: usize, allocator: std.mem.Allocator) !Self {
    const text_renderer: Self = .{
        .bindings = sg.Bindings{},
        .pipeline = undefined,
        .allocator = allocator,
        .vertices = try allocator.alloc(TextVertex, vertex_buffer_size),
    };

    return text_renderer;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.vertices);
}

pub fn initRenderer(self: *Self) void {
    buildAtlas(self) catch |e| {
        std.debug.print("failed to build atlas: {}\n", .{e});
    };

    self.bindings.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = self.vertices.len * @sizeOf(TextVertex),
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
            };
            l.attrs[text_shd.ATTR_text_uv0] = .{
                .format = .FLOAT2,
            };
            break :init l;
        },
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

pub fn emitQuad(self: *Self, vertex_index: usize, g: Glyph, x: f32, y: f32) void {
    // x: left y: bottom
    // y+ = down

    const fx: f32 = x + g.bearing_x;
    const fy: f32 = y - g.bearing_y;

    const p1: TextVertex = .{
        .x = fx,
        .y = fy,
        .u = g.u0,
        .v = g.v0,
    }; // top left
    const p2: TextVertex = .{
        .x = fx + g.w,
        .y = fy,
        .u = g.u1,
        .v = g.v0,
    }; // top right
    const p3: TextVertex = .{
        .x = fx + g.w,
        .y = fy + g.h,
        .u = g.u1,
        .v = g.v1,
    }; // bottom right
    const p4: TextVertex = .{
        .x = fx,
        .y = fy + g.h,
        .u = g.u0,
        .v = g.v1,
    }; // bottom left

    self.vertices[vertex_index] = p1;
    self.vertices[vertex_index + 1] = p2;
    self.vertices[vertex_index + 2] = p4;
    self.vertices[vertex_index + 3] = p2;
    self.vertices[vertex_index + 4] = p3;
    self.vertices[vertex_index + 5] = p4;
}
