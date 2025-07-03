const std = @import("std");
const State = @import("main.zig").State;
const zalg = @import("zalgebra");

pub fn switchToNormalMode() void {
    State.mode = .normal;
    State.buffer.clearRange();
}

pub fn switchToInsertMode() void {
    State.mode = .insert;
}

pub fn switchToVisualMode() void {
    State.mode = .visual;
    State.buffer.range_start = State.buffer.gap_start;
    State.buffer.range_end = State.buffer.gap_start + 1;
}

pub fn switchToInsertModeRight() void {
    moveRight();
    State.mode = .insert;
}

pub fn moveLeft() void {
    if (State.buffer.gap_start == 0) return;
    State.buffer.moveGap(State.buffer.gap_start - 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
}

pub fn moveRight() void {
    State.buffer.moveGap(State.buffer.gap_end + 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
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
    std.debug.print("CALLED DELETE\n", .{});
    State.buffer.deleteCharsRight(1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn deleteRange() void {
    if (State.buffer.hasRange()) {
        State.buffer.deleteRange() catch |err| {
            std.debug.print("{}\n", .{err});
        };
        switchToNormalMode();
    }
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
    const half_height: f32 = State.viewport.height / 2.0;
    const viewport_desired_position: zalg.Vec2 = State.viewport.getDesiredPosition();
    const relative_dist: f32 = @as(f32, @floatFromInt(State.buffer.current_line)) * State.row_height - viewport_desired_position.y();
    const row_count: usize = @as(usize, @intFromFloat(half_height)) / @as(usize, @intFromFloat(State.row_height));
    if (State.buffer.current_line < row_count) {
        State.buffer.moveGap(0) catch undefined;
        State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
        return;
    }
    const target_line_number = State.buffer.current_line - row_count;
    const line_start = State.buffer.getLine(target_line_number);
    const desired = State.buffer.getDesiredOffsetOnLine(line_start);
    State.buffer.moveGap(desired) catch undefined;
    var pos: zalg.Vec2 = State.viewport.position;
    pos.yMut().* = @as(f32, @floatFromInt(target_line_number)) * State.row_height - relative_dist;
    State.viewport.setPosition(pos);
}

pub fn downByHalf() void {
    const half_height: f32 = State.viewport.height / 2.0;
    const viewport_desired_position: zalg.Vec2 = State.viewport.getDesiredPosition();
    const relative_dist: f32 = @as(f32, @floatFromInt(State.buffer.current_line)) * State.row_height - viewport_desired_position.y();
    const row_count: usize = @as(usize, @intFromFloat(half_height)) / @as(usize, @intFromFloat(State.row_height));
    const target_line_number = State.buffer.current_line + row_count;
    const line_start = State.buffer.toBufferIndex(State.buffer.getLine(target_line_number));
    const desired = State.buffer.getDesiredOffsetOnLine(line_start);
    // TODO: inefficient
    if (State.buffer.toBufferIndex(State.buffer.getLineStart(desired)) != line_start) {
        State.buffer.moveGap(desired) catch unreachable;
        var pos: zalg.Vec2 = State.viewport.position;
        pos.yMut().* = @as(f32, @floatFromInt(target_line_number)) * State.row_height - relative_dist;
        State.viewport.setPosition(pos);
    }
}

pub fn centerLine() void {
    const new_top = @as(f32, @floatFromInt(State.buffer.current_line)) * State.row_height - (State.viewport.height / 2.0);
    var pos: zalg.Vec2 = State.viewport.position;
    pos.yMut().* = new_top;
    State.viewport.setPosition(pos);
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
            State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
            return;
        }
    }
    State.buffer.moveGap(State.buffer.data.len - State.buffer.getGapLength()) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
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
                State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
                return;
            }
        } else {
            found_first_word = true;
        }
    }
    State.buffer.moveGap(0) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
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
                State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
                return;
            }
        } else {
            found_first_word = true;
        }
    }
    State.buffer.moveGap(State.buffer.data.len - State.buffer.getGapLength()) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getCurrentLineOffset();
}

pub fn deleteLeft() void {
    if (State.buffer.getBeforeGap().len > 0) {
        State.buffer.deleteCharsLeft(1) catch unreachable;
    }
}

pub fn breakLine() void {
    if (State.buffer.getBeforeGap().len > 0) {
        State.buffer.addChar('\n') catch unreachable;
    }
}
