const std = @import("std");
const State = @import("main.zig").State;

pub fn moveLeft() void {
    if (State.buffer.gap_start == 0) return;
    State.buffer.moveGap(State.buffer.gap_start - 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLineOffset();
}

pub fn moveRight() void {
    State.buffer.moveGap(State.buffer.gap_end + 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLineOffset();
}

pub fn moveUp() void {
    State.buffer.moveGapUpByLine() catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn moveDown() void {
    State.buffer.moveGapDownByLine() catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn deleteAtPoint() void {
    State.buffer.deleteCharsRight(1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn moveTop() void {
    State.buffer.moveGap(0) catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn moveBottom() void {
    State.buffer.moveGap(State.buffer.data.len - 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn upByHalf() void {
    const half_height: f32 = (State.viewport.bottom - State.viewport.top) / 2.0;
    const row_count: usize = @as(usize, @intFromFloat(half_height)) / @as(usize, @intFromFloat(State.row_height));
    const y_delta: f32 = @as(f32, @floatFromInt(row_count)) * State.row_height;
    if (State.buffer.current_line < row_count) {
        State.buffer.moveGap(0) catch undefined;
        State.buffer.desired_offset = State.buffer.getLineOffset();
        return;
    }
    const line_start = State.buffer.getLine(State.buffer.current_line - row_count);
    const desired = State.buffer.getDesiredOffsetOnLine(line_start);
    State.buffer.moveGap(desired) catch undefined;
    State.viewport.top -= y_delta;
    State.viewport.bottom -= y_delta;
}

pub fn downByHalf() void {
    const half_height: f32 = (State.viewport.bottom - State.viewport.top) / 2.0;
    const row_count: usize = @as(usize, @intFromFloat(half_height)) / @as(usize, @intFromFloat(State.row_height));
    const y_delta: f32 = @as(f32, @floatFromInt(row_count)) * State.row_height;
    const line_start = State.buffer.getLine(State.buffer.current_line + row_count);
    const desired = State.buffer.getDesiredOffsetOnLine(line_start);
    // TODO: inefficient
    if (State.buffer.getLine(desired) != line_start) {
        State.buffer.moveGap(desired) catch undefined;
        State.viewport.top += y_delta;
        State.viewport.bottom += y_delta;
    }
}

pub fn centerLine() void {
    const height = State.viewport.bottom - State.viewport.top;
    const new_top = @as(f32, @floatFromInt(State.buffer.current_line + 3)) * State.row_height - (height / 2.0);
    State.viewport.top = new_top;
    State.viewport.bottom = new_top + height;
}

pub fn moveWordStartRight() void {
    var found_first_gap = false;
    for (State.buffer.gap_end..State.buffer.data.len) |i| {
        if (State.buffer.data[i] == ' ' or State.buffer.data[i] == '\n') {
            found_first_gap = true;
        } else if (found_first_gap) {
            State.buffer.moveGap(i) catch |err| {
                std.debug.print("{}\n", .{err});
            };
            State.buffer.desired_offset = State.buffer.getLineOffset();
            return;
        }
    }
    State.buffer.moveGap(State.buffer.data.len - State.buffer.getGapLength()) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLineOffset();
}

pub fn moveWordStartLeft() void {
    if (State.buffer.gap_start == 0) return;

    var i: usize = State.buffer.gap_start;
    var found_first_word = State.buffer.data[i - 1] != ' ' and State.buffer.data[i - 1] != '\n';

    while (i > 1) {
        i -= 1;
        if (State.buffer.data[i - 1] == ' ' or State.buffer.data[i - 1] == '\n') {
            if (found_first_word) {
                State.buffer.moveGap(i) catch |err| {
                    std.debug.print("{}\n", .{err});
                };
                State.buffer.desired_offset = State.buffer.getLineOffset();
                return;
            }
        } else {
            found_first_word = true;
        }
    }
    State.buffer.moveGap(0) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLineOffset();
}

pub fn moveWordEndRight() void {
    if (State.buffer.gap_end == State.buffer.data.len) return;

    const begin_char = State.buffer.data[State.buffer.gap_end + 1];
    var found_first_word = begin_char != '\n' and begin_char != ' ';

    for (State.buffer.gap_end..State.buffer.data.len - 1) |i| {
        if (State.buffer.data[i + 1] == ' ' or State.buffer.data[i + 1] == '\n') {
            if (found_first_word) {
                State.buffer.moveGap(i) catch |err| {
                    std.debug.print("{}\n", .{err});
                };
                State.buffer.desired_offset = State.buffer.getLineOffset();
                return;
            }
        } else {
            found_first_word = true;
        }
    }
    State.buffer.moveGap(State.buffer.data.len - State.buffer.getGapLength()) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLineOffset();
}
