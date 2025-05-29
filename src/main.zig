const std = @import("std");
const zalg = @import("zalgebra");
const ft = @import("mach-freetype");

const Buffer = @import("buffer.zig");
const TextRenderer = @import("text_renderer.zig");
const CursorRenderer = @import("cursor_renderer.zig");

const cursor_shd = @import("shaders/compiled/cursor.glsl.zig");
const text_shd = @import("shaders/compiled/text.glsl.zig");

const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const stime = sokol.time;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

pub const state = struct {
    var pass_action: sg.PassAction = .{};
    var text_renderer: TextRenderer = undefined;
    var cursor_renderer: CursorRenderer = undefined;
    pub var buffer: Buffer = undefined;

    var start_time: f64 = 0;
};

export fn init() void {
    state.buffer = Buffer.init(4096, allocator) catch unreachable;

    stime.setup();

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{
            .func = slog.func,
        },
    });

    state.start_time = stime.ms(stime.now());

    state.text_renderer = TextRenderer.init();
    state.cursor_renderer = CursorRenderer.init();

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{
            .r = 0.2,
            .g = 0.0,
            .b = 0.5,
            .a = 1.0,
        },
    };
}

export fn frame() void {
    var pen_x: usize = 20;
    var pen_y: usize = 100;
    const row_height = 50;

    var cursor_x: usize = 0;
    var cursor_y: usize = 100;

    var char_index: usize = 0;
    var vertex_index: usize = 0;
    while (char_index < state.buffer.getTextLength()) {
        for (state.buffer.getBeforeGap()) |char| {
            if (char != '\n') {
                const glyph = state.text_renderer.glyphs[char];
                state.text_renderer.emitQuad(
                    vertex_index,
                    state.text_renderer.glyphs[char],
                    pen_x,
                    pen_y,
                );
                pen_x += @intCast(glyph.advance);
                vertex_index += 6;
            } else {
                pen_x = 20;
                pen_y += row_height;
            }
            char_index += 1;
        }

        cursor_x = pen_x;
        cursor_y = pen_y;

        for (state.buffer.getAfterGap()) |char| {
            if (char != '\n') {
                const glyph = state.text_renderer.glyphs[char];
                state.text_renderer.emitQuad(
                    vertex_index,
                    state.text_renderer.glyphs[char],
                    pen_x,
                    pen_y,
                );
                pen_x += @intCast(glyph.advance);
                vertex_index += 6;
            } else {
                pen_x = 20;
                pen_y += row_height;
            }
            char_index += 1;
        }
    }

    const vertex_count = vertex_index;

    const ortho = zalg.orthographic(
        0.0,
        sapp.widthf(),
        sapp.heightf(),
        0.0,
        -1.0,
        1.0,
    );

    const cursor_scale = zalg.Mat4.scale(
        zalg.Mat4.identity(),
        zalg.Vec3.new(2.0, 45.0, 0.0),
    );
    const cursor_position = zalg.Mat4.translate(
        zalg.Mat4.identity(),
        zalg.Vec3.new(@floatFromInt(cursor_x), @floatFromInt(cursor_y - 22), 0.0),
    );
    const cursor_vs_params: cursor_shd.VsParams = .{
        .mvp = ortho.mul(cursor_position.mul(cursor_scale)),
    };

    const cursor_fs_params: cursor_shd.FsParams = .{
        .time = @floatCast(stime.ms(stime.now()) - state.start_time),
    };

    const text_vs_params: text_shd.VsParams = .{
        .mvp = ortho,
    };

    if (state.buffer.getTextLength() > 0) {
        sg.updateBuffer(
            state.text_renderer.bindings.vertex_buffers[0],
            sg.asRange(state.text_renderer.vertices[0..vertex_count]),
        );
    }

    sg.beginPass(.{
        .swapchain = sglue.swapchain(),
        .action = state.pass_action,
    });
    // draw text
    sg.applyPipeline(state.text_renderer.pipeline);
    sg.applyBindings(state.text_renderer.bindings);
    sg.applyUniforms(text_shd.UB_vs_params, sg.asRange(&text_vs_params));
    sg.draw(0, @intCast(vertex_count), 1);
    // draw cursor
    sg.applyPipeline(state.cursor_renderer.pipeline);
    sg.applyBindings(state.cursor_renderer.bindings);
    sg.applyUniforms(cursor_shd.UB_vs_params, sg.asRange(&cursor_vs_params));
    sg.applyUniforms(cursor_shd.UB_fs_params, sg.asRange(&cursor_fs_params));
    sg.draw(0, 6, 1);
    sg.endPass();
    sg.commit();
}

export fn event(e: [*c]const sapp.Event) void {
    if (e) |ev| {
        switch (ev.*.type) {
            .KEY_DOWN => {
                switch (ev.*.key_code) {
                    .BACKSPACE => {
                        if (state.buffer.getBeforeGap().len > 0) {
                            state.buffer.deleteChar() catch unreachable;
                        }
                    },
                    .ENTER => {
                        state.buffer.addChar('\n') catch unreachable;
                    },
                    .LEFT => {
                        if (state.buffer.gap_start == 0) return;
                        state.buffer.moveGap(state.buffer.gap_start - 1) catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    .RIGHT => {
                        state.buffer.moveGap(state.buffer.gap_start + 1) catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    .UP => {
                        state.buffer.moveGapUpByLine() catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    .DOWN => {
                        state.buffer.moveGapDownByLine() catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    else => {},
                }
            },
            .CHAR => {
                state.buffer.addChar(@intCast(ev.*.char_code)) catch unreachable;
            },
            else => {},
        }
    }
}

export fn cleanup() void {
    state.buffer.deinit();
    sg.shutdown();
}

pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 960,
        .height = 540,
        .icon = .{ .sokol_default = true },
        .window_title = "test",
        .logger = .{ .func = slog.func },
        .win32_console_attach = true,
        .swap_interval = 1,
    });
}
