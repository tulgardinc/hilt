const std = @import("std");
const zalg = @import("zalgebra");
const ft = @import("mach-freetype");

const Buffer = @import("buffer.zig");
const Viewport = @import("viewport.zig").Viewport;
const Cursor = @import("cursor.zig");
const CommandHandler = @import("command_handler.zig");
const setDefaultKeybinds = @import("default_keybinds.zig").setDefaultBinds;

const TextRenderer = @import("text_renderer.zig");
const CursorRenderer = @import("cursor_renderer.zig");
const RangeRenderer = @import("range_renderer.zig");
const LineHighlightRenderer = @import("line_highlight_renderer.zig");
const LineNumberRenderer = @import("line_number_renderer.zig");
const FontAtlas = @import("font_atlas.zig");

const cursor_shd = @import("shaders/compiled/cursor.glsl.zig");
const text_shd = @import("shaders/compiled/text.glsl.zig");
const range_shd = @import("shaders/compiled/range.glsl.zig");
const hl_shd = @import("shaders/compiled/line_highlight.glsl.zig");
const ln_shd = @import("shaders/compiled/line_number.glsl.zig");

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
    pub var pass_action: sg.PassAction = .{};
    pub var text_renderer: TextRenderer = undefined;
    pub var cursor_renderer: CursorRenderer = undefined;
    pub var range_renderer: RangeRenderer = undefined;
    pub var hl_renderer: LineHighlightRenderer = undefined;
    pub var ln_renderer: LineNumberRenderer = undefined;
    pub var font_atlas: FontAtlas = undefined;

    pub var buffer: Buffer = undefined;
    pub var mode: Mode = .normal;

    pub var command_handler: CommandHandler = undefined;

    pub var cursor: Cursor = Cursor.init();

    pub var cursor_nwidth: f32 = 0.0;
    pub var cursor_height: f32 = 0.0;
    pub var cursor_nchar_x_offset: f32 = 0.0;

    pub var start_time: f64 = 0;
    pub var viewport: Viewport = undefined;

    pub var row_height: f32 = 0.0;
    pub var font_descender: f32 = 0.0;

    pub var delta_time: f32 = 0.0;
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

    State.viewport = Viewport.init();
    State.viewport.height = sapp.heightf();
    State.viewport.width = sapp.widthf();

    State.cursor_renderer = CursorRenderer.init();
    State.range_renderer = RangeRenderer.init();
    State.hl_renderer = LineHighlightRenderer.init();
    State.command_handler = CommandHandler.init(allocator);

    State.font_atlas = FontAtlas.init() catch undefined;

    State.cursor_nwidth = State.font_atlas.glyphs[97].w;
    State.cursor_nchar_x_offset = State.font_atlas.glyphs[97].bearing_x;

    const max_char_count: usize = @intFromFloat((@ceil(2160.0 / State.row_height) + 30) * @ceil(3840.0 / State.cursor_nwidth));
    std.debug.print("max char count: {}\n", .{max_char_count});
    State.text_renderer = TextRenderer.init(
        max_char_count,
        State.font_atlas,
        allocator,
    ) catch undefined;

    State.text_renderer.initRenderer();

    State.ln_renderer = LineNumberRenderer.init();

    setDefaultKeybinds(&State.command_handler) catch unreachable;

    State.cursor_nwidth = State.font_atlas.glyphs[97].w;
    State.cursor_nchar_x_offset = State.font_atlas.glyphs[97].bearing_x;

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
    const INITIAL_PEN_X = 80.0;

    pen_x: f32 = INITIAL_PEN_X,

    line_number_buffer: [16]u8 = undefined,
    current_line: usize = 1,

    vertex_index: usize = 0,

    drawing_range: bool = false,
};

fn drawChar(ds: *DrawingState, char_index: usize, line_index: usize) void {
    const pen_y = @as(f32, @floatFromInt(line_index)) * State.row_height;
    const char = State.buffer.data[State.buffer.toBufferIndex(char_index)];

    if (State.buffer.range_start) |range_start| {
        if (char_index == range_start) {
            ds.drawing_range = true;
            if (range_start == State.buffer.gap_start) {
                State.range_renderer.emitInstanceStart(State.cursor.position.x() + State.cursor_nwidth, pen_y + State.font_descender);
            } else {
                State.range_renderer.emitInstanceStart(ds.pen_x, pen_y + State.font_descender);
            }
        }
    }

    if (ds.drawing_range) {
        if (char_index == State.buffer.range_end) {
            ds.drawing_range = false;
            if (State.buffer.range_end == State.buffer.toCharIndex(State.buffer.gap_end)) {
                State.range_renderer.emitInstanceEnd(State.cursor.position.x() + State.cursor_nwidth);
            } else {
                State.range_renderer.emitInstanceEnd(ds.pen_x);
            }
        }
    }

    if (char != '\n') {
        if (char >= 32 and char < 127) {
            const glyph = State.font_atlas.glyphs[char];
            State.text_renderer.emitInstanceData(
                glyph,
                ds.pen_x,
                pen_y,
                zalg.Vec4.one(),
            );
            ds.pen_x += @floatFromInt(glyph.advance);
            ds.vertex_index += 6;
        }
    } else {
        if (ds.drawing_range) {
            const stop_width = if (ds.pen_x == DrawingState.INITIAL_PEN_X) ds.pen_x + State.cursor_nwidth else ds.pen_x;
            State.range_renderer.emitInstanceEnd(stop_width);
        }
        ds.pen_x = 80;
        if (ds.drawing_range) {
            State.range_renderer.emitInstanceStart(ds.pen_x, pen_y + State.row_height + State.font_descender);
        }
    }
}

export fn frame() void {
    State.delta_time = @floatCast(sapp.frameDuration());

    var drawing_state = DrawingState{};

    State.range_renderer.setupDraw();
    State.text_renderer.setupDraw();
    State.ln_renderer.setupDraw();

    State.viewport.width = sapp.widthf();
    State.viewport.height = sapp.heightf();
    State.viewport.update();

    const top_line: usize = @intFromFloat(@max(0, @floor(State.viewport.position.y() / State.row_height) - 5));
    const bottom_line: usize = @min(top_line + @as(usize, @intFromFloat(@ceil(State.viewport.height / State.row_height))) + 10, State.buffer.getLineCount());

    const top_line_start_char_index = State.buffer.getLineStart(top_line);

    if (State.buffer.range_start) |range_start| {
        if (top_line_start_char_index > range_start) {
            drawing_state.drawing_range = true;
            std.debug.print("LINE BEHIND\n", .{});
        }
    }

    var line_start_index: usize = top_line_start_char_index;
    for (top_line..bottom_line) |line_index| {
        const line_number_slice = std.fmt.bufPrintIntToSlice(&drawing_state.line_number_buffer, line_index + 1, 10, .lower, .{});
        var ln_index = line_number_slice.len;
        var ln_pen_x: f32 = 50.0;
        while (ln_index > 0) {
            ln_index -= 1;
            const glyph = State.font_atlas.glyphs[line_number_slice[ln_index]];
            State.ln_renderer.emitInstanceData(
                glyph,
                ln_pen_x,
                @as(f32, @floatFromInt(line_index)) * State.row_height,
                zalg.Vec4.one(),
            );
            ln_pen_x -= @floatFromInt(glyph.advance);
        }

        var char_index: usize = line_start_index;

        while (char_index < State.buffer.data.len - State.buffer.getGapLength()) : (char_index += 1) {
            const buffer_index = State.buffer.toBufferIndex(char_index);
            drawChar(&drawing_state, char_index, line_index);
            if (State.buffer.data[buffer_index] == '\n') {
                break;
            }
        }

        line_start_index += State.buffer.line_lengths.items[line_index];
    }

    if (drawing_state.drawing_range) {
        State.range_renderer.emitInstanceEnd(drawing_state.pen_x);
        drawing_state.drawing_range = false;
    }

    const current_line_y = @as(f32, @floatFromInt(State.buffer.current_line)) * State.row_height;
    if (current_line_y - State.row_height < State.viewport.position.y() + 3 * State.row_height) {
        const new_target = zalg.Vec2.new(0, current_line_y - 4 * State.row_height);
        if (new_target.y() < State.viewport.target_position.y()) {
            State.viewport.setPosition(new_target);
        }
    } else if (current_line_y > State.viewport.position.y() + State.viewport.height - 2 * State.row_height) {
        const new_target = zalg.Vec2.new(0, current_line_y - State.viewport.height + 2 * State.row_height);
        if (new_target.y() > State.viewport.target_position.y()) {
            State.viewport.setPosition(new_target);
        }
    }

    const ortho = zalg.orthographic(
        State.viewport.position.x(),
        State.viewport.position.x() + State.viewport.width,
        State.viewport.position.y() + State.viewport.height,
        State.viewport.position.y(),
        -1.0,
        1.0,
    );

    const cursor_width: f32 = if (State.mode == .normal or State.mode == .visual) State.cursor_nwidth else 2.0;
    const cursor_x_offset: f32 = if (State.mode == .normal or State.mode == .visual) State.cursor_nchar_x_offset else 0.0;

    var cursor_x: f32 = DrawingState.INITIAL_PEN_X;
    for (State.buffer.data[State.buffer.getLineStart(State.buffer.current_line - 1)..State.buffer.gap_start]) |c| {
        cursor_x += @floatFromInt(State.font_atlas.glyphs[c].advance);
    }
    State.cursor.target_position = zalg.Vec2.new(cursor_x + cursor_x_offset, @as(f32, @floatFromInt(State.buffer.current_line - 1)) * State.row_height + @abs(State.font_descender));
    State.cursor.update();

    const cursor_center = zalg.Mat4.identity().translate(zalg.Vec3.new(-0.5, 0.5, 0));
    const cursor_rad: f32 = @floatCast(std.math.atan2(State.cursor.vel.x(), State.cursor.vel.y()));
    const cursor_angle: f32 = std.math.radiansToDegrees(cursor_rad);
    const cursor_rotate = zalg.Mat4.fromRotation(cursor_angle, zalg.Vec3.forward());
    const cursor_stretch: f32 = 1.0 + State.cursor.vel.length() * 0.00025;
    const cursor_scale_vel = zalg.Mat4.fromScale(zalg.Vec3.new(1.0 / cursor_stretch, cursor_stretch, 0));
    const cursor_unrotate = zalg.Mat4.fromRotation(-cursor_angle, zalg.Vec3.forward());
    const cursor_uncenter = zalg.Mat4.fromTranslate(zalg.Vec3.new(0.5, -0.5, 0));
    const cursor_scale = zalg.Mat4.fromScale(zalg.Vec3.new(cursor_width, State.cursor_height, 0.0));
    const cursor_translation = zalg.Mat4.fromTranslate(State.cursor.position.toVec3(0.0));

    const cursor_vs_params: cursor_shd.VsParams = .{
        .mvp = ortho.mul(cursor_translation)
            .mul(cursor_scale)
            .mul(cursor_uncenter)
            .mul(cursor_unrotate)
            .mul(cursor_scale_vel)
            .mul(cursor_rotate)
            .mul(cursor_center),
    };
    const cursor_fs_params: cursor_shd.FsParams = .{
        .time = if (State.mode == .insert) @floatCast(stime.ms(stime.now()) - State.start_time) else 0,
    };

    // Same for ln numbers
    const text_vs_params: text_shd.VsParams = .{
        .mvp = ortho,
    };
    const text_fs_params: text_shd.FsParams = .{
        .cursor_position = State.cursor.position.toArray(),
        .cursor_dimensions = zalg.Vec2.new(cursor_width, State.cursor_height).toArray(),
    };

    const hl_vs_params: hl_shd.VsParams = .{
        .mvp = ortho
            .mul(zalg.Mat4.fromTranslate(zalg.Vec3.new(0, State.cursor.position.y(), 0)))
            .mul(zalg.Mat4.fromScale(zalg.Vec3.new(sapp.widthf(), State.cursor_height, 0))),
    };

    if (State.text_renderer.instance_count > 0) {
        sg.updateBuffer(
            State.text_renderer.bindings.vertex_buffers[1],
            sg.asRange(State.text_renderer.instance_data[0..State.text_renderer.instance_count]),
        );
    }

    if (State.ln_renderer.instance_count > 0) {
        sg.updateBuffer(
            State.ln_renderer.bindings.vertex_buffers[1],
            sg.asRange(State.ln_renderer.instances[0..State.ln_renderer.instance_count]),
        );
    }

    if (State.range_renderer.instance_count > 0) {
        sg.updateBuffer(
            State.range_renderer.bindings.vertex_buffers[1],
            sg.asRange(State.range_renderer.instances[0..State.range_renderer.instance_count]),
        );
    }

    sg.beginPass(.{
        .swapchain = sglue.swapchain(),
        .action = State.pass_action,
    });
    // draw active line highlight
    sg.applyPipeline(State.hl_renderer.pipeline);
    sg.applyBindings(State.hl_renderer.bindings);
    sg.applyUniforms(hl_shd.UB_vs_params, sg.asRange(&hl_vs_params));
    sg.draw(0, 6, 1);
    // draw range
    sg.applyPipeline(State.range_renderer.pipeline);
    sg.applyBindings(State.range_renderer.bindings);
    sg.applyUniforms(range_shd.UB_vs_params, sg.asRange(&range_shd.VsParams{ .mvp = ortho }));
    sg.draw(0, 6, @intCast(State.range_renderer.instance_count));
    // draw line numbers
    sg.applyPipeline(State.ln_renderer.pipeline);
    sg.applyBindings(State.ln_renderer.bindings);
    sg.applyUniforms(ln_shd.UB_vs_params, sg.asRange(&text_vs_params));
    sg.applyUniforms(ln_shd.UB_fs_params, sg.asRange(&text_fs_params));
    sg.draw(0, 6, @intCast(State.ln_renderer.instance_count));
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
    sg.applyUniforms(text_shd.UB_fs_params, sg.asRange(&text_fs_params));
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
    } else {
        State.buffer = try Buffer.init(Buffer.INITIAL_BUFFER_SIZE, allocator);
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
