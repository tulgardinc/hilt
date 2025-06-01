const std = @import("std");
const State = @import("main.zig").State;

pub fn moveLeft() void {
    if (State.buffer.gap_start == 0) return;
    State.buffer.moveGap(State.buffer.gap_start - 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLeftOffset();
}

pub fn moveRight() void {
    State.buffer.moveGap(State.buffer.gap_start + 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
    State.buffer.desired_offset = State.buffer.getLeftOffset();
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
    State.buffer.deleteCharRight() catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn moveTop() void {
    State.buffer.moveGap(0) catch |err| {
        std.debug.print("{}\n", .{err});
    };
}

pub fn moveBottom() void {
    State.buffer.moveGap(State.buffer.getTextLength() - 1) catch |err| {
        std.debug.print("{}\n", .{err});
    };
}
