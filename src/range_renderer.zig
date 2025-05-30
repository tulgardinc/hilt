const std = @import("std");
const sg = @import("sokol").gfx;
const range_shd = @import("shaders/compiled/range.glsl.zig");

bindings: sg.Bindings,
pipeline: sg.Pipeline,
vertices: [512]Vertex = undefined,
vertex_count: usize = 0,

const Self = @This();

const Vertex = packed struct {
    x: f32,
    y: f32,
};

pub fn init() Self {
    var range_renderer = Self{
        .bindings = .{},
        .pipeline = undefined,
    };

    range_renderer.bindings.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = @sizeOf(Vertex) * 512,
    });

    const pip_descriptor: sg.PipelineDesc = .{
        .shader = sg.makeShader(range_shd.rangeShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[range_shd.ATTR_range_pos] = .{ .format = .FLOAT2 };
            break :init l;
        },
    };

    range_renderer.pipeline = sg.makePipeline(pip_descriptor);

    return range_renderer;
}

pub fn setupDraw(self: *Self) void {
    self.vertex_count = 0;
}

pub fn emitLeftEdge(self: *Self, x0: f32, y0: f32, y1: f32) void {
    // bottom left
    const p1: Vertex = .{
        .x = x0,
        .y = y0,
    };
    // top left
    const p2: Vertex = .{
        .x = x0,
        .y = y1,
    };

    self.vertices[self.vertex_count] = p1;
    self.vertices[self.vertex_count + 1] = p2;
}

pub fn emitRightEdge(self: *Self, x1: f32, y0: f32, y1: f32) void {
    // top right
    const p3: Vertex = .{
        .x = x1,
        .y = y1,
    };

    // bottom right
    const p4: Vertex = .{
        .x = x1,
        .y = y0,
    };

    const p1 = self.vertices[self.vertex_count];

    self.vertices[self.vertex_count + 2] = p3;
    self.vertices[self.vertex_count + 3] = p1;
    self.vertices[self.vertex_count + 4] = p3;
    self.vertices[self.vertex_count + 5] = p4;

    self.vertex_count += 6;
}
