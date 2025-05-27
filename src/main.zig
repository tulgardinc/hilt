const std = @import("std");
const zalg = @import("zalgebra");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;

const shd = @import("shaders/compiled/instancing.glsl.zig");

const MAX_PARTICLES = 512 * 1024;
const NUM_PARTICLES_PER_FRAME = 10;

var engine = std.Random.Sfc64.init(0);
const rand = engine.random();

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var ry: f32 = 0.0;
    var num_particles: u32 = 0;
    var pos: [MAX_PARTICLES]zalg.Vec3 = undefined;
    var vel: [MAX_PARTICLES]zalg.Vec3 = undefined;

    const view: zalg.Mat4 = zalg.Mat4.lookAt(
        zalg.Vec3.new(0.0, 1.5, 6.0),
        zalg.Vec3.zero(),
        zalg.Vec3.up(),
    );
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const r = 0.05;
    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .data = sg.asRange(&[_]f32{
            0.0, -r,  0.0, 1.0, 0.0, 0.0, 1.0,
            r,   0.0, r,   0.0, 1.0, 0.0, 1.0,
            r,   0.0, -r,  0.0, 0.0, 1.0, 1.0,
            -r,  0.0, -r,  1.0, 1.0, 0.0, 1.0,
            -r,  0.0, r,   0.0, 1.0, 1.0, 1.0,
            0.0, r,   0.0, 1.0, 0.0, 1.0, 1.0,
        }),
    });

    state.bind.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            2, 1, 0, 3, 2, 0,
            4, 3, 0, 1, 4, 0,
            5, 1, 2, 5, 2, 3,
            5, 3, 4, 5, 4, 1,
        }),
    });

    state.bind.vertex_buffers[1] = sg.makeBuffer(.{
        .usage = .{ .stream_update = true },
        .size = MAX_PARTICLES * @sizeOf(zalg.Vec3),
    });

    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.instancingShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[1].step_func = .PER_INSTANCE;
            //l.buffers[1].stride = @sizeOf(zalg.Vec3);
            l.attrs[shd.ATTR_instancing_pos] = .{ .format = .FLOAT3, .buffer_index = 0 };
            l.attrs[shd.ATTR_instancing_color0] = .{ .format = .FLOAT4, .buffer_index = 0 };
            l.attrs[shd.ATTR_instancing_inst_pos] = .{ .format = .FLOAT3, .buffer_index = 1 };
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .cull_mode = .BACK,
    });

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{
            .r = 0.2,
            .g = 0.0,
            .b = 0.5,
            .a = 1.0,
        },
    };
    std.debug.print("Backend: {}\n", .{sg.queryBackend()});
}

export fn frame() void {
    // emit new particles
    const frame_time: f32 = @floatCast(sapp.frameDuration());

    for (0..NUM_PARTICLES_PER_FRAME) |_| {
        if (state.num_particles < MAX_PARTICLES) {
            state.pos[state.num_particles] = zalg.Vec3.zero();
            state.vel[state.num_particles] = zalg.Vec3.new(
                rand.float(f32) - 0.5,
                rand.float(f32) * 0.5 + 2.0,
                rand.float(f32) - 0.5,
            );
            state.num_particles += 1;
        } else {
            break;
        }
    }

    var gpu_pos: [MAX_PARTICLES][3]f32 = undefined;

    for (0..MAX_PARTICLES) |i| {
        const vel = &state.vel[i];
        const pos = &state.pos[i];
        const velY = vel.yMut();
        velY.* -= frame_time;
        const posY = pos.yMut();
        pos.* = pos.add(vel.mul(zalg.Vec3.set(frame_time)));
        if (posY.* < -2.0) {
            posY.* = -2.0;
            velY.* = -velY.*;
            vel.* = vel.mul(zalg.Vec3.set(0.8));
        }

        gpu_pos[i] = pos.toArray();
    }

    sg.updateBuffer(state.bind.vertex_buffers[1], sg.asRange(gpu_pos[0..state.num_particles]));

    state.ry += 0.1;
    const vs_params = computeVsParams(0, state.ry);

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 24, state.num_particles);
    sg.endPass();
    sg.commit();
}

fn computeVsParams(rx: f32, ry: f32) shd.VsParams {
    const rxm = zalg.Mat4.fromRotation(rx, zalg.Vec3.right());
    const rym = zalg.Mat4.fromRotation(ry, zalg.Vec3.up());
    const model = zalg.Mat4.mul(rxm, rym);
    const aspect = sapp.widthf() / sapp.heightf();
    const proj = zalg.Mat4.perspective(60, aspect, 0.01, 30.0);
    return shd.VsParams{
        .mvp = zalg.Mat4.mul(zalg.Mat4.mul(proj, state.view), model),
    };
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "test",
        .logger = .{ .func = slog.func },
        .win32_console_attach = true,
        .swap_interval = 1,
    });
}
