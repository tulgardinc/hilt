const std = @import("std");

const sg = @import("sokol").gfx;
const zalg = @import("zalgebra");
const text_shd = @import("shaders/compiled/text.glsl.zig");
const font = @embedFile("assets/JetBrainsMono-Medium.ttf");
const FontAtlas = @import("font_atlas.zig");
const Glyph = FontAtlas.Glyph;

bindings: sg.Bindings,
pipeline: sg.Pipeline,

instance_count: usize = 0,
instance_data: []GlyphInstance,
allocator: std.mem.Allocator,

font_atlas: FontAtlas,

font_image: sg.Image = undefined,

const Self = @This();

const GlyphInstance = packed struct {
    offset: packed struct { x: f32, y: f32 },
    dims: packed struct { w: f32, h: f32 },
    uv_rect: packed struct { u_off: f32, v_off: f32, w: f32, h: f32 },
    color: packed struct { r: f32, g: f32, b: f32, a: f32 },
};

pub fn init(max_char_count: usize, font_atlas: FontAtlas, allocator: std.mem.Allocator) !Self {
    const text_renderer: Self = .{
        .bindings = sg.Bindings{},
        .pipeline = undefined,
        .allocator = allocator,
        .instance_data = try allocator.alloc(GlyphInstance, max_char_count),
        .font_atlas = font_atlas,
    };

    return text_renderer;
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.instance_data);
}

pub fn initRenderer(self: *Self) void {
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
        .size = self.instance_data.len * @sizeOf(GlyphInstance),
    });

    self.bindings.samplers[text_shd.SMP_smp] = sg.makeSampler(.{
        .mag_filter = .LINEAR,
        .min_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    var image_descriptor: sg.ImageDesc = .{
        .width = FontAtlas.ATLAS_W,
        .height = FontAtlas.ATLAS_H,
        .pixel_format = .R8,
    };
    image_descriptor.data.subimage[0][0] = sg.asRange(&self.font_atlas.atlas_buffer);
    self.font_image = sg.makeImage(image_descriptor);
    self.bindings.images[text_shd.IMG_tex] = self.font_image;

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
