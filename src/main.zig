const std = @import("std");
const zalg = @import("zalgebra");
const ft = @import("mach-freetype");

const Buffer = @import("buffer.zig");
const CommandHandler = @import("command_handler.zig");
const setDefaultKeybinds = @import("default_keybinds.zig").setDefaultBinds;

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

pub const Mode = enum { normal, insert, visual };

pub const State = struct {
    var pass_action: sg.PassAction = .{};
    var text_renderer: TextRenderer = undefined;
    var cursor_renderer: CursorRenderer = undefined;
    var range_renderer: RangeRenderer = undefined;
    pub var buffer: Buffer = undefined;
    var mode: Mode = .normal;

    var command_handler: CommandHandler = undefined;

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

    State.start_time = stime.ms(stime.now());

    State.cursor_renderer = CursorRenderer.init();
    State.range_renderer = RangeRenderer.init();
    State.command_handler = CommandHandler.init(allocator);

    setDefaultKeybinds(&State.command_handler) catch unreachable;

    State.text_renderer.initRenderer();

    State.cursor_nwidth = State.text_renderer.glyphs[97].w;
    State.cursor_nchar_x_offset = State.text_renderer.glyphs[97].bearing_x;

    State.viewport.right = sapp.widthf();
    State.viewport.bottom = sapp.heightf();

    State.pass_action.colors[0] = .{
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
    if (State.buffer.range_start) |range_start| {
        if (ds.char_index == range_start) {
            ds.drawing_range = true;
            State.range_renderer.emitLeftEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
    }

    if (ds.drawing_range) {
        if (ds.char_index == State.buffer.range_end) {
            ds.drawing_range = false;
            State.range_renderer.emitRightEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
    }

    if (char != '\n') {
        const glyph = State.text_renderer.glyphs[char];
        State.text_renderer.emitInstanceData(
            State.text_renderer.glyphs[char],
            ds.pen_x,
            ds.pen_y,
            if (ds.char_index == State.buffer.gap_start) zalg.Vec4.new(0.0, 0.0, 0.0, 1.0) else zalg.Vec4.one(),
        );
        ds.pen_x += @floatFromInt(glyph.advance);
        ds.vertex_index += 6;
    } else {
        if (ds.drawing_range) {
            State.range_renderer.emitRightEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
        ds.pen_x = 20;
        ds.pen_y += ds.row_height;
        if (ds.drawing_range) {
            State.range_renderer.emitLeftEdge(ds.pen_x, ds.pen_y, ds.pen_y - ds.row_height);
        }
    }

    ds.char_index += 1;
}

export fn frame() void {
    var drawing_state = DrawingState{};

    State.range_renderer.setupDraw();
    State.text_renderer.setupDraw();

    //std.debug.print("{s}\n", .{State.buffer.getBeforeGap()});

    for (State.buffer.getBeforeGap()) |char| {
        drawChar(&drawing_state, char);
    }

    drawing_state.cursor_x = drawing_state.pen_x;
    drawing_state.cursor_y = drawing_state.pen_y;

    for (State.buffer.getAfterGap()) |char| {
        drawChar(&drawing_state, char);
    }

    if (drawing_state.drawing_range) {
        State.range_renderer.emitRightEdge(
            drawing_state.pen_x,
            drawing_state.pen_y,
            drawing_state.pen_y - drawing_state.row_height,
        );
    }

    if (drawing_state.cursor_y + 10.0 > State.viewport.bottom) {
        State.viewport.bottom = drawing_state.cursor_y;
        State.viewport.top = State.viewport.bottom - sapp.heightf();
    } else if (drawing_state.cursor_y < State.viewport.top + drawing_state.row_height) {
        State.viewport.top = drawing_state.cursor_y - drawing_state.row_height;
        State.viewport.bottom = State.viewport.top + sapp.heightf();
    } else {
        State.viewport.bottom = State.viewport.top + sapp.heightf();
    }
    State.viewport.right = sapp.widthf();

    const ortho = zalg.orthographic(
        State.viewport.left,
        State.viewport.right,
        State.viewport.bottom,
        State.viewport.top,
        -1.0,
        1.0,
    );

    const cursor_width: f32 = if (State.mode == .normal or State.mode == .visual) State.cursor_nwidth else 2.0;
    const cursor_x_offset: f32 = if (State.mode == .normal or State.mode == .visual) State.cursor_nchar_x_offset else 0.0;

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
        .time = if (State.mode == .insert) @floatCast(stime.ms(stime.now()) - State.start_time) else 0,
    };

    const text_vs_params: text_shd.VsParams = .{
        .mvp = ortho,
    };

    if (State.buffer.getTextLength() > 0) {
        sg.updateBuffer(
            State.text_renderer.bindings.vertex_buffers[1],
            sg.asRange(State.text_renderer.instance_data[0..State.text_renderer.instance_count]),
        );
    }

    sg.beginPass(.{
        .swapchain = sglue.swapchain(),
        .action = State.pass_action,
    });
    // draw range
    sg.applyPipeline(State.range_renderer.pipeline);
    sg.applyBindings(State.range_renderer.bindings);
    sg.applyUniforms(range_shd.UB_vs_params, sg.asRange(&range_shd.VsParams{ .mvp = ortho }));
    sg.draw(0, @intCast(State.range_renderer.vertex_count), 1);
    // draw cursor
    sg.applyPipeline(State.cursor_renderer.pipeline);
    sg.applyBindings(State.cursor_renderer.bindings);
    sg.applyUniforms(cursor_shd.UB_vs_params, sg.asRange(&cursor_vs_params));
    sg.applyUniforms(cursor_shd.UB_fs_params, sg.asRange(&cursor_fs_params));
    sg.draw(0, 6, 1);
    // draw text
    sg.applyPipeline(State.text_renderer.pipeline);
    sg.applyBindings(State.text_renderer.bindings);
    sg.applyUniforms(text_shd.UB_vs_params, sg.asRange(&text_vs_params));
    sg.draw(0, 6, @intCast(State.text_renderer.instance_count));
    sg.endPass();
    sg.commit();
}

export fn event(e: [*c]const sapp.Event) void {
    State.command_handler.onInput(State.mode, e);
}

export fn cleanup() void {
    State.command_handler.deinit();
    State.buffer.deinit();
    State.text_renderer.deinit();
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
        State.buffer = try Buffer.initFromFile(@ptrCast(file_path), file_stats.size, buffer_size, allocator);
        State.text_renderer = try TextRenderer.init(buffer_size, allocator);
    } else {
        State.buffer = try Buffer.init(Buffer.INITIAL_BUFFER_SIZE, allocator);
        State.text_renderer = try TextRenderer.init(Buffer.INITIAL_BUFFER_SIZE, allocator);
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
