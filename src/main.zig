const std = @import("std");
const zalg = @import("zalgebra");
const ft = @import("mach-freetype");
const fa = @import("font-assets");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;

const shd = @import("shaders/compiled/text.glsl.zig");

const ATLAS_W = 512;
const ATLAS_H = 512;

const Glyph = struct {
    u0: f32,
    v0: f32,
    u1: f32,
    v1: f32,
    w: u32,
    h: u32,
    bearing_x: i32,
    bearing_y: i32,
    advance: i16,
};

const Vertex = packed struct { x: f32, y: f32, u: f32, v: f32 };

const state = struct {
    var pass_action: sg.PassAction = .{};
    var bind: sg.Bindings = .{};
    var pip: sg.Pipeline = .{};
    var glyphs: [128]Glyph = undefined;
    var atlas_pixels: [ATLAS_W * ATLAS_H]u8 = .{0} ** (ATLAS_W * ATLAS_H);
    var vertices: [1024]Vertex = undefined;

    const view: zalg.Mat4 = zalg.Mat4.lookAt(
        zalg.Vec3.new(0.0, 0.0, 1.0),
        zalg.Vec3.zero(),
        zalg.Vec3.up(),
    );
};

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
            .u1 = (@as(f32, @floatFromInt(pen_x + bmp.width())) / ATLAS_W) * 32767,
            .v1 = (@as(f32, @floatFromInt(pen_y + bmp.rows())) / ATLAS_H) * 32767,
            .w = bmp.width(),
            .h = bmp.rows(),
            .bearing_x = slot.bitmapLeft(),
            .bearing_y = slot.bitmapTop(),
            .advance = @as(i16, @intCast(slot.advance().x)) >> 6,
        };

        pen_x += bmp.width() + 1;
        row_h = @max(row_h, bmp.rows());
    }
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    buildAtlas() catch |e| {
        std.debug.print("Freetype failed: {}\n", .{e});
        return;
    };

    var image_desc: sg.ImageDesc = .{
        .width = ATLAS_W,
        .height = ATLAS_H,
        .pixel_format = .R8,
        .label = "font_atlas",
    };
    image_desc.data.subimage[0][0] = sg.asRange(&state.atlas_pixels);

    const font_image = sg.makeImage(image_desc);

    const font_smp = sg.makeSampler(.{
        .min_filter = .LINEAR,
        .mag_filter = .LINEAR,
        .wrap_u = .CLAMP_TO_EDGE,
        .wrap_v = .CLAMP_TO_EDGE,
    });

    state.bind.vertex_buffers[0] = sg.makeBuffer(.{
        .usage = .{ .stream_update = true },
        .size = 1024 * @sizeOf(Vertex),
    });

    state.bind.images[shd.IMG_tex] = font_image;
    state.bind.samplers[shd.SMP_tex_smp] = font_smp;

    state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.textShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.buffers[0].stride = @sizeOf(Vertex);
            l.buffers[0].step_func = .PER_VERTEX;
            l.attrs[shd.ATTR_text_pos] = .{
                .format = .FLOAT2,
                .buffer_index = 0,
                .offset = 0,
            };
            l.attrs[shd.ATTR_text_uv0] = .{
                .format = .FLOAT2,
                .buffer_index = 0,
                .offset = @sizeOf([2]f32),
            };
            break :init l;
        },
        .depth = .{
            .compare = .ALWAYS,
            .write_enabled = false,
        },
        .cull_mode = .NONE,
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

fn emitQuad(base: usize, x: f32, y: f32, g: Glyph) void {
    const x0 = x + @as(f32, @floatFromInt(g.bearing_x));
    const y0 = y - @as(f32, @floatFromInt(g.bearing_y));
    const x1 = x0 + @as(f32, @floatFromInt(g.w));
    const y1 = y0 + @as(f32, @floatFromInt(g.h));

    state.vertices[base + 0] = .{ .x = x0, .y = y0, .u = g.u0, .v = g.v0 };
    state.vertices[base + 1] = .{ .x = x0, .y = y1, .u = g.u0, .v = g.v1 };
    state.vertices[base + 2] = .{ .x = x1, .y = y1, .u = g.u1, .v = g.v1 };
    state.vertices[base + 3] = .{ .x = x0, .y = y0, .u = g.u0, .v = g.v0 };
    state.vertices[base + 4] = .{ .x = x1, .y = y1, .u = g.u1, .v = g.v1 };
    state.vertices[base + 5] = .{ .x = x1, .y = y0, .u = g.u1, .v = g.v0 };
}

export fn frame() void {
    const text = "Hello World!";

    var pen_x: f32 = 20;
    const pen_y: f32 = 120;

    var vtx_count: usize = 0;
    for (text) |byte| {
        const g = state.glyphs[byte];
        emitQuad(vtx_count, pen_x, pen_y, g);
        vtx_count += 6;
        pen_x += @floatFromInt(g.advance);
    }

    sg.updateBuffer(state.bind.vertex_buffers[0], sg.asRange(state.vertices[0..vtx_count]));

    const vs_params: shd.VsParams = .{ .mvp = zalg.Mat4.orthographic(
        0,
        sapp.widthf(),
        sapp.heightf(),
        0,
        -1,
        5,
    ) };
    const fs_params: shd.FsParams = .{ .color = .{ 1, 1, 1, 1 } };

    sg.beginPass(.{
        .action = state.pass_action,
        .swapchain = sglue.swapchain(),
    });
    sg.applyPipeline(state.pip);
    sg.applyBindings(state.bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    sg.applyUniforms(shd.UB_fs_params, sg.asRange(&fs_params));
    sg.draw(0, @intCast(vtx_count), 1);
    sg.endPass();
    sg.commit();
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
