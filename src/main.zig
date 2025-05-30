const std = @import("std");
const zalg = @import("zalgebra");
const ft = @import("mach-freetype");

const Buffer = @import("buffer.zig");
const TextRenderer = @import("text_renderer.zig");
const CursorRenderer = @import("cursor_renderer.zig");
const RangeRenderer = @import("range_renderer.zig");

const cursor_shd = @import("shaders/compiled/cursor.glsl.zig");
const text_shd = @import("shaders/compiled/text.glsl.zig");
const range_shd = @import("shaders/compiled/range.glsl.zig");

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
    var range_renderer: RangeRenderer = undefined;
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
    state.range_renderer = RangeRenderer.init();

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

const DrawingState = struct {
    pen_x: f32 = 20.0,
    pen_y: f32 = 100.0,
    row_height: f32 = 50.0,

    cursor_x: f32 = 0.0,
    cursor_y: f32 = 100.0,

    char_index: usize = 0,
    vertex_index: usize = 0,

    drawing_range: bool = false,
};

fn drawChar(ds: *DrawingState, char: u8) void {
    if (state.buffer.range_start) |range_start| {
        if (ds.char_index == range_start) {
            ds.drawing_range = true;
            state.range_renderer.emitLeftEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
    }

    if (ds.drawing_range) {
        if (ds.char_index == state.buffer.range_end) {
            ds.drawing_range = false;
            state.range_renderer.emitRightEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
    }

    if (char != '\n') {
        const glyph = state.text_renderer.glyphs[char];
        state.text_renderer.emitQuad(
            ds.vertex_index,
            state.text_renderer.glyphs[char],
            ds.pen_x,
            ds.pen_y,
        );
        ds.pen_x += @floatFromInt(glyph.advance);
        ds.vertex_index += 6;
    } else {
        if (ds.drawing_range) {
            state.range_renderer.emitRightEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
        ds.pen_x = 20;
        ds.pen_y += ds.row_height;
        if (ds.drawing_range) {
            state.range_renderer.emitLeftEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
    }

    ds.char_index += 1;
}

export fn frame() void {
    var drawing_state = DrawingState{};

    state.range_renderer.setupDraw();

    for (state.buffer.getBeforeGap()) |char| {
        drawChar(&drawing_state, char);
    }

    drawing_state.cursor_x = drawing_state.pen_x;
    drawing_state.cursor_y = drawing_state.pen_y;

    for (state.buffer.getAfterGap()) |char| {
        drawChar(&drawing_state, char);
    }

    if (drawing_state.drawing_range) {
        state.range_renderer.emitRightEdge(
            drawing_state.pen_x,
            drawing_state.pen_y,
            drawing_state.pen_y - drawing_state.row_height,
        );
    }

    const vertex_count = drawing_state.vertex_index;

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
        zalg.Vec3.new(4.0, 45.0, 0.0),
    );
    const cursor_position = zalg.Mat4.translate(
        zalg.Mat4.identity(),
        zalg.Vec3.new(drawing_state.cursor_x, drawing_state.cursor_y - 22.0, 0.0),
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

    if (state.range_renderer.vertex_count > 0) {
        sg.updateBuffer(
            state.range_renderer.bindings.vertex_buffers[0],
            sg.asRange(state.range_renderer.vertices[0..state.range_renderer.vertex_count]),
        );
    }

    sg.beginPass(.{
        .swapchain = sglue.swapchain(),
        .action = state.pass_action,
    });
    // draw range
    sg.applyPipeline(state.range_renderer.pipeline);
    sg.applyBindings(state.range_renderer.bindings);
    sg.applyUniforms(range_shd.UB_vs_params, sg.asRange(&range_shd.VsParams{ .mvp = ortho }));
    sg.draw(0, @intCast(state.range_renderer.vertex_count), 1);
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
                        if (ev.*.modifiers == sapp.modifier_shift) {
                            state.buffer.rangeLeft() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        } else {
                            state.buffer.clearRange();
                        }
                        if (state.buffer.gap_start == 0) return;
                        state.buffer.moveGap(state.buffer.gap_start - 1) catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    .RIGHT => {
                        if (ev.*.modifiers == sapp.modifier_shift) {
                            state.buffer.rangeRight() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        } else {
                            state.buffer.clearRange();
                        }
                        state.buffer.moveGap(state.buffer.gap_start + 1) catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    .UP => {
                        state.buffer.clearRange();
                        state.buffer.moveGapUpByLine() catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                    },
                    .DOWN => {
                        state.buffer.clearRange();
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
