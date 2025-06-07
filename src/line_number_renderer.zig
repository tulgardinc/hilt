const std = @import("std");
const State = @import("main.zig").State;
const Glyph = @import("text_renderer.zig").Glyph;

const ft = @import("mach-freetype");
const sg = @import("sokol").gfx;
const zalg = @import("zalgebra");

const ln_shd = @import("shaders/compiled/line_number.glsl.zig");

bindings: sg.Bindings,
pipeline: sg.Pipeline,

instance_count: usize = 0,
instances: [4096]Instance = undefined,

const Self = @This();

const Instance = packed struct {
    offset: packed struct { x: f32, y: f32 },
    dims: packed struct { w: f32, h: f32 },
    uv_rect: packed struct { u_off: f32, v_off: f32, w: f32, h: f32 },
    color: packed struct { r: f32, g: f32, b: f32, a: f32 },
};

pub fn init() Self {
    var text_renderer: Self = .{
        .bindings = sg.Bindings{},
        .pipeline = undefined,
    };

    text_renderer.bindings.vertex_buffers[0] = sg.makeBuffer(.{
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

    text_renderer.bindings.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = text_renderer.instances.len * @sizeOf(Instance),
    });

    text_renderer.bindings.samplers[ln_shd.SMP_smp] = sg.makeSampler(.{
        .mag_filter = .LINEAR,
        .min_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    text_renderer.bindings.images[ln_shd.IMG_tex] = State.text_renderer.font_image;

    var pip_descriptor: sg.PipelineDesc = .{
        .cull_mode = .BACK,
        .shader = sg.makeShader(ln_shd.lineNumberShaderDesc(sg.queryBackend())),
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .layout = init: {
            var l: sg.VertexLayoutState = .{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[ln_shd.ATTR_line_number_pos] = .{
                .format = .FLOAT2,
                .buffer_index = 0,
            };
            l.attrs[ln_shd.ATTR_line_number_uv_in] = .{
                .format = .FLOAT2,
                .buffer_index = 0,
            };

            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[ln_shd.ATTR_line_number_offset] = .{
                .format = .FLOAT2,
                .buffer_index = 1,
            };
            l.attrs[ln_shd.ATTR_line_number_dims] = .{
                .format = .FLOAT2,
                .buffer_index = 1,
            };
            l.attrs[ln_shd.ATTR_line_number_uv_rect_in] = .{
                .format = .FLOAT4,
                .buffer_index = 1,
            };
            l.attrs[ln_shd.ATTR_line_number_col_in] = .{
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

    text_renderer.pipeline = sg.makePipeline(pip_descriptor);

    return text_renderer;
}

pub fn setupDraw(self: *Self) void {
    self.instance_count = 0;
}

pub fn emitInstanceData(self: *Self, g: Glyph, x: f32, y: f32, col: zalg.Vec4) void {
    // x: left y: bottom
    // y+ = down

    self.instances[self.instance_count] = .{
        .color = .{ .r = col.x(), .g = col.y(), .b = col.z(), .a = col.w() },
        .offset = .{ .x = x + g.bearing_x, .y = y - g.bearing_y },
        .dims = .{ .w = g.w, .h = g.h },
        .uv_rect = .{ .u_off = g.u0, .v_off = g.v0, .w = g.u1 - g.u0, .h = g.v1 - g.v0 },
    };

    self.instance_count += 1;
}
