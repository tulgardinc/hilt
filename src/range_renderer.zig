const std = @import("std");
const sg = @import("sokol").gfx;
const range_shd = @import("shaders/compiled/range.glsl.zig");
const State = @import("main.zig").State;

bindings: sg.Bindings,
pipeline: sg.Pipeline,
instances: [512]Instance = undefined,
instance_count: usize = 0,

const Self = @This();

const Instance = packed struct {
    x: f32,
    y: f32,
    w: f32,
    h: f32,
};

pub fn init() Self {
    var range_renderer = Self{
        .bindings = .{},
        .pipeline = undefined,
    };

    // Bottom left origin quad
    range_renderer.bindings.vertex_buffers[0] = sg.makeBuffer(.{
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

    range_renderer.bindings.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = @sizeOf(Instance) * range_renderer.instances.len,
    });

    const pip_descriptor: sg.PipelineDesc = .{
        .shader = sg.makeShader(range_shd.rangeShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.buffers[1].step_func = .PER_INSTANCE;
            l.attrs[range_shd.ATTR_range_pos] = .{ .format = .FLOAT2, .buffer_index = 0 };
            l.attrs[range_shd.ATTR_range_offset] = .{ .format = .FLOAT2, .buffer_index = 1 };
            l.attrs[range_shd.ATTR_range_scale] = .{ .format = .FLOAT2, .buffer_index = 1 };
            break :init l;
        },
    };

    range_renderer.pipeline = sg.makePipeline(pip_descriptor);

    return range_renderer;
}

pub fn setupDraw(self: *Self) void {
    self.instance_count = 0;
}

pub fn emitInstanceStart(self: *Self, x: f32, y: f32) void {
    const instance: Instance = .{
        .x = x,
        .y = y,
        .w = 0,
        .h = State.row_height,
    };

    self.instances[self.instance_count] = instance;
}

pub fn emitInstanceEnd(self: *Self, x1: f32) void {
    self.instances[self.instance_count].w = x1 - self.instances[self.instance_count].x;

    self.instance_count += 1;
}
