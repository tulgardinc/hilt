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

const Mode = enum { normal, insert, visual };

pub const state = struct {
    var pass_action: sg.PassAction = .{};
    var text_renderer: TextRenderer = undefined;
    var cursor_renderer: CursorRenderer = undefined;
    var range_renderer: RangeRenderer = undefined;
    pub var buffer: Buffer = undefined;
    var mode: Mode = .normal;

    var cursor_nwidth: f32 = 0.0;
    var cursor_nchar_x_offset: f32 = 0.0;

    var start_time: f64 = 0;
    var viewport = struct {
        top: f32 = 0,
        bottom: f32 = 0,
        left: f32 = 0,
        right: f32 = 0,
    }{};
};

export fn init() void {
    stime.setup();

    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{
            .func = slog.func,
        },
    });

    state.start_time = stime.ms(stime.now());

    state.cursor_renderer = CursorRenderer.init();
    state.range_renderer = RangeRenderer.init();
    state.text_renderer.initRenderer();

    state.cursor_nwidth = state.text_renderer.glyphs[97].w;
    state.cursor_nchar_x_offset = state.text_renderer.glyphs[97].bearing_x;

    state.viewport.right = sapp.widthf();
    state.viewport.bottom = sapp.heightf();

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
    row_height: f32 = 30.0,

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
        state.text_renderer.emitInstanceData(
            state.text_renderer.glyphs[char],
            ds.pen_x,
            ds.pen_y,
            if (ds.char_index == state.buffer.gap_start) zalg.Vec4.new(0.0, 0.0, 0.0, 1.0) else zalg.Vec4.one(),
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
    state.text_renderer.setupDraw();

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

    if (drawing_state.cursor_y + 10.0 > state.viewport.bottom) {
        state.viewport.bottom = drawing_state.cursor_y;
        state.viewport.top = state.viewport.bottom - sapp.heightf();
    } else if (drawing_state.cursor_y < state.viewport.top + drawing_state.row_height) {
        state.viewport.top = drawing_state.cursor_y - drawing_state.row_height;
        state.viewport.bottom = state.viewport.top + sapp.heightf();
    } else {
        state.viewport.bottom = state.viewport.top + sapp.heightf();
    }
    state.viewport.right = sapp.widthf();

    const ortho = zalg.orthographic(
        state.viewport.left,
        state.viewport.right,
        state.viewport.bottom,
        state.viewport.top,
        -1.0,
        1.0,
    );

    const cursor_width: f32 = if (state.mode == .normal or state.mode == .visual) state.cursor_nwidth else 2.0;
    const cursor_x_offset: f32 = if (state.mode == .normal or state.mode == .visual) state.cursor_nchar_x_offset else 0.0;

    const cursor_scale = zalg.Mat4.scale(
        zalg.Mat4.identity(),
        zalg.Vec3.new(cursor_width, 28.0, 0.0),
    );
    const cursor_position = zalg.Mat4.translate(
        zalg.Mat4.identity(),
        zalg.Vec3.new(drawing_state.cursor_x + cursor_x_offset + (cursor_width / 2.0), drawing_state.cursor_y - 10.0, 0.0),
    );
    const cursor_vs_params: cursor_shd.VsParams = .{
        .mvp = ortho.mul(cursor_position.mul(cursor_scale)),
    };

    const cursor_fs_params: cursor_shd.FsParams = .{
        .time = if (state.mode == .insert) @floatCast(stime.ms(stime.now()) - state.start_time) else 0,
    };

    const text_vs_params: text_shd.VsParams = .{
        .mvp = ortho,
    };

    if (state.buffer.getTextLength() > 0) {
        sg.updateBuffer(
            state.text_renderer.bindings.vertex_buffers[1],
            sg.asRange(state.text_renderer.instance_data[0..state.text_renderer.instance_count]),
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
    // draw cursor
    sg.applyPipeline(state.cursor_renderer.pipeline);
    sg.applyBindings(state.cursor_renderer.bindings);
    sg.applyUniforms(cursor_shd.UB_vs_params, sg.asRange(&cursor_vs_params));
    sg.applyUniforms(cursor_shd.UB_fs_params, sg.asRange(&cursor_fs_params));
    sg.draw(0, 6, 1);
    // draw text
    sg.applyPipeline(state.text_renderer.pipeline);
    sg.applyBindings(state.text_renderer.bindings);
    sg.applyUniforms(text_shd.UB_vs_params, sg.asRange(&text_vs_params));
    sg.draw(0, 6, @intCast(state.text_renderer.instance_count));
    sg.endPass();
    sg.commit();
}

export fn event(e: [*c]const sapp.Event) void {
    if (e) |ev| {
        switch (state.mode) {
            .normal => switch (ev.*.type) {
                .KEY_DOWN => {
                    switch (ev.*.key_code) {
                        .H => {
                            if (state.buffer.gap_start == 0) return;
                            state.buffer.moveGap(state.buffer.gap_start - 1) catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                            state.buffer.desired_offset = state.buffer.getLeftOffset();
                        },
                        .L => {
                            state.buffer.moveGap(state.buffer.gap_start + 1) catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                            state.buffer.desired_offset = state.buffer.getLeftOffset();
                        },
                        .K => {
                            state.buffer.moveGapUpByLine() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        },
                        .J => {
                            state.buffer.moveGapDownByLine() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        },
                        .X => {
                            state.buffer.deleteCharRight() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        },
                        else => {},
                    }
                },
                else => {},
            },
            .insert => switch (ev.*.type) {
                .KEY_DOWN => {
                    switch (ev.*.key_code) {
                        .BACKSPACE => {
                            if (state.buffer.hasRange()) {
                                state.buffer.deleteRange() catch |err| {
                                    std.debug.print("{}\n", .{err});
                                };
                                state.buffer.clearRange();
                            } else {
                                if (state.buffer.getBeforeGap().len > 0) {
                                    state.buffer.deleteCharLeft() catch unreachable;
                                }
                            }
                        },
                        .ENTER => {
                            if (state.buffer.hasRange()) {
                                state.buffer.deleteRange() catch |err| {
                                    std.debug.print("{}\n", .{err});
                                };
                                state.buffer.clearRange();
                            }
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
                            if (ev.*.modifiers == sapp.modifier_shift) {
                                state.buffer.rangeUp() catch |err| {
                                    std.debug.print("{}\n", .{err});
                                };
                            } else {
                                state.buffer.clearRange();
                            }
                            state.buffer.moveGapUpByLine() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        },
                        .DOWN => {
                            if (ev.*.modifiers == sapp.modifier_shift) {
                                state.buffer.rangeDown() catch |err| {
                                    std.debug.print("{}\n", .{err});
                                };
                            } else {
                                state.buffer.clearRange();
                            }
                            state.buffer.moveGapDownByLine() catch |err| {
                                std.debug.print("{}\n", .{err});
                            };
                        },
                        .C => {
                            if (ev.*.modifiers == sapp.modifier_ctrl and !ev.*.key_repeat) {
                                if (!state.buffer.hasRange()) return;
                                const clipboard_buffer = allocator.alloc(u8, state.buffer.getRangeLength() + 1) catch unreachable;
                                defer allocator.free(clipboard_buffer);
                                state.buffer.getRangeText(clipboard_buffer) catch |err| {
                                    std.debug.print("{}", .{err});
                                };
                                clipboard_buffer[clipboard_buffer.len - 1] = 0;
                                sapp.setClipboardString(@as([:0]const u8, @ptrCast(@constCast(clipboard_buffer))));
                            }
                        },
                        .X => {
                            if (ev.*.modifiers == sapp.modifier_ctrl and !ev.*.key_repeat) {
                                if (!state.buffer.hasRange()) return;
                                const clipboard_buffer = allocator.alloc(u8, state.buffer.getRangeLength() + 1) catch unreachable;
                                defer allocator.free(clipboard_buffer);
                                state.buffer.getRangeText(clipboard_buffer) catch {};
                                state.buffer.deleteRange() catch {};
                                state.buffer.clearRange();
                                clipboard_buffer[clipboard_buffer.len - 1] = 0;
                                sapp.setClipboardString(@as([:0]const u8, @ptrCast(@constCast(clipboard_buffer))));
                            }
                        },
                        .V => {
                            if (ev.*.modifiers == sapp.modifier_ctrl) {
                                if (state.buffer.hasRange()) {
                                    state.buffer.deleteRange() catch {};
                                    state.buffer.clearRange();
                                }
                                const clipboard_string = sapp.getClipboardString();
                                state.buffer.addString(@ptrCast(clipboard_string)) catch |err| {
                                    std.debug.print("{}\n", .{err});
                                };
                            }
                        },
                        else => {},
                    }
                },
                .CHAR => {
                    if (state.buffer.hasRange()) {
                        state.buffer.deleteRange() catch |err| {
                            std.debug.print("{}\n", .{err});
                        };
                        state.buffer.clearRange();
                    }
                    state.buffer.addChar(@intCast(ev.*.char_code)) catch |err| {
                        std.debug.print("{}\n", .{err});
                    };
                },
                else => {},
            },
            .visual => {},
        }
    }
}

export fn cleanup() void {
    state.buffer.deinit();
    state.text_renderer.deinit();
    _ = gpa.deinit();
    sg.shutdown();
}

pub fn main() !void {
    var args = try std.process.argsWithAllocator(allocator);
    _ = args.skip();

    if (args.next()) |file_path| {
        const cwd = std.fs.cwd();
        const file_stats = try cwd.statFile(file_path);
        std.debug.print("file size: {}\n", .{file_stats.size});
        const buffer_size = if (file_stats.size == 0) Buffer.INITIAL_BUFFER_SIZE else try std.math.ceilPowerOfTwo(usize, @intCast(file_stats.size + Buffer.INITIAL_BUFFER_SIZE));
        state.buffer = try Buffer.initFromFile(@ptrCast(file_path), file_stats.size, buffer_size, allocator);
        state.text_renderer = try TextRenderer.init(buffer_size, allocator);
    } else {
        state.buffer = try Buffer.init(Buffer.INITIAL_BUFFER_SIZE, allocator);
        state.text_renderer = try TextRenderer.init(Buffer.INITIAL_BUFFER_SIZE, allocator);
    }

    args.deinit();

    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .enable_clipboard = true,
        .width = 960,
        .height = 540,
        .icon = .{ .sokol_default = true },
        .window_title = "test",
        .logger = .{ .func = slog.func },
        .win32_console_attach = true,
        .swap_interval = 1,
    });
}
