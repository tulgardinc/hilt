const sg = @import("sokol").gfx;
const cursor_shd = @import("shaders/compiled/cursor.glsl.zig");

bindings: sg.Bindings,
pipeline: sg.Pipeline,

const Self = @This();

pub fn init() Self {
    var cursor_renderer = Self{
        .bindings = .{},
        .pipeline = undefined,
    };

    cursor_renderer.bindings.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(
            &[_]f32{
                -0.5, 0.5,
                0.5,  0.5,
                -0.5, -0.5,
                0.5,  0.5,
                0.5,  -0.5,
                -0.5, -0.5,
            },
        ),
    });

    var pip_descriptor: sg.PipelineDesc = .{
        .shader = sg.makeShader(cursor_shd.cursorShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[cursor_shd.ATTR_cursor_pos] = .{ .format = .FLOAT2 };
            break :init l;
        },
    };
    pip_descriptor.colors[0].blend.enabled = true;
    pip_descriptor.colors[0].blend.src_factor_rgb = .SRC_ALPHA;
    pip_descriptor.colors[0].blend.dst_factor_rgb = .ONE_MINUS_SRC_ALPHA;
    pip_descriptor.colors[0].blend.src_factor_alpha = .SRC_ALPHA;
    pip_descriptor.colors[0].blend.dst_factor_alpha = .ONE_MINUS_SRC_ALPHA;

    cursor_renderer.pipeline = sg.makePipeline(pip_descriptor);

    return cursor_renderer;
}
