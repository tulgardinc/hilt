const std = @import("std");
const zalg = @import("zalgebra");
const ft = @import("mach-freetype");
const fa = @import("font-assets");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;

const shd = @import("shaders/compiled/retry.glsl.zig");

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};

    var char_count: usize = 0;
    var text: [1024]u8 = undefined;
    var vertices: [1024]Vertex = undefined;
    var glyphs: [128]Glyph = undefined;
    var atlas_pixels: [ATLAS_W * ATLAS_H]u8 = .{0} ** (ATLAS_W * ATLAS_H);
};

const ATLAS_W = 512;
const ATLAS_H = 512;

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

const Vertex = packed struct { x: f32, y: f32, u: f32, v: f32 };

fn buildAtlas() !void {
    const ftlib = try ft.Library.init();
    defer ftlib.deinit();

    const face = try ftlib.createFaceMemory(fa.fira_sans_regular_ttf, 0);
    try face.setPixelSizes(0, 48);

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
                state.atlas_pixels[dst_start .. dst_start + bmp.width()],
                bmp.buffer().?[src_start .. src_start + bmp.width()],
            );
        }

        state.glyphs[c] = Glyph{
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

fn emitQuad(char_index: usize, g: Glyph, x: usize, y: usize) void {
    // x: left y: bottom
    // y+ = down
    const vertex_index = char_index * 6;

    const fx: f32 = @as(f32, @floatFromInt(x)) + g.bearing_x;
    const fy: f32 = @as(f32, @floatFromInt(y)) - g.bearing_y;

    const p1: Vertex = .{
        .x = fx,
        .y = fy,
        .u = g.u0,
        .v = g.v0,
    };
    const p2: Vertex = .{
        .x = fx + g.w,
        .y = fy,
        .u = g.u1,
        .v = g.v0,
    };
    const p3: Vertex = .{
        .x = fx + g.w,
        .y = fy + g.h,
        .u = g.u1,
        .v = g.v1,
    };
    const p4: Vertex = .{
        .x = fx,
        .y = fy + g.h,
        .u = g.u0,
        .v = g.v1,
    };

    state.vertices[vertex_index] = p1;
    state.vertices[vertex_index + 1] = p2;
    state.vertices[vertex_index + 2] = p4;
    state.vertices[vertex_index + 3] = p2;
    state.vertices[vertex_index + 4] = p3;
    state.vertices[vertex_index + 5] = p4;
}

export fn init() void {
    buildAtlas() catch |e| {
        std.debug.print("failed to build atlas {}\n", .{e});
    };

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
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

    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = @sizeOf(Vertex) * 1024,
    });

    state.bind.samplers[shd.SMP_smp] = sg.makeSampler(.{
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
    image_descriptor.data.subimage[0][0] = sg.asRange(&state.atlas_pixels);
    state.bind.images[shd.IMG_tex] = sg.makeImage(image_descriptor);

    var pip_descriptor: sg.PipelineDesc = .{
        .cull_mode = .BACK,
        .shader = sg.makeShader(shd.retryShaderDesc(sg.queryBackend())),
        .depth = .{
            .compare = .LESS_EQUAL,
            .write_enabled = true,
        },
        .layout = init: {
            var l: sg.VertexLayoutState = .{};
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[shd.ATTR_retry_pos] = .{
                .format = .FLOAT2,
            };
            l.attrs[shd.ATTR_retry_uv0] = .{
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

    state.pip = sg.makePipeline(pip_descriptor);
}

export fn frame() void {
    var pen_x: usize = 20;
    for (state.text[0..state.char_count], 0..) |char, i| {
        const glyph = state.glyphs[char];
        emitQuad(i, state.glyphs[char], pen_x, 100);
        pen_x += @intCast(glyph.advance);
    }

    const vs_params: shd.VsParams = .{
        .mvp = zalg.orthographic(
            0.0,
            sapp.widthf(),
            sapp.heightf(),
            0.0,
            -1.0,
            1.0,
        ),
    };

    if (state.char_count > 0) {
        sg.updateBuffer(
            state.bind.vertex_buffers[0],
            sg.asRange(state.vertices[0 .. state.char_count * 6]),
        );
    }

    sg.beginPass(.{
        .swapchain = sglue.swapchain(),
        .action = state.pass_action,
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, @intCast(state.char_count * 6), 1);
    sg.endPass();
    sg.commit();
}

export fn event(e: [*c]const sapp.Event) void {
    if (e) |ev| {
        switch (ev.*.type) {
            .KEY_DOWN => {
                if (ev.*.key_code == .BACKSPACE) {
                    if (state.char_count > 0) {
                        state.char_count -= 1;
                    }
                }
            },
            .CHAR => {
                state.text[state.char_count] = @intCast(ev.*.char_code);
                state.char_count += 1;
            },
            else => {},
        }
    }
}

export fn cleanup() void {
    sg.shutdown();
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 640,
        .height = 480,
        .icon = .{ .sokol_default = true },
        .window_title = "test",
        .logger = .{ .func = slog.func },
        .win32_console_attach = true,
        .swap_interval = 1,
    });
}
