const sg = @import("sokol").gfx;
const hl_shd = @import("shaders/compiled/line_highlight.glsl.zig");

bindings: sg.Bindings,
pipeline: sg.Pipeline,

const Self = @This();

pub fn init() Self {
    var highlight_renderer = Self{
        .bindings = .{},
        .pipeline = undefined,
    };

    highlight_renderer.bindings.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(
            &[_]f32{
                0.0, -1.0,
                1.0, -1.0,
                0.0, 0.0,
                1.0, -1.0,
                1.0, 0.0,
                0.0, 0.0,
            },
        ),
    });

    const pip_descriptor: sg.PipelineDesc = .{
        .shader = sg.makeShader(hl_shd.cursorShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[hl_shd.ATTR_cursor_pos] = .{ .format = .FLOAT2 };
            break :init l;
        },
    };
    highlight_renderer.pipeline = sg.makePipeline(pip_descriptor);

    return highlight_renderer;
}
