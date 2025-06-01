const CommandHandler = @import("command_handler.zig");
const Commands = @import("commands.zig");

pub fn setDefaultBinds(command_handler: *CommandHandler) !void {
    try command_handler.addCommand("<C-a>", .normal, Commands.moveRight);
    // try command_handler.addCommand("l", .normal, Commands.moveRight);
    // try command_handler.addCommand("h", .normal, Commands.moveLeft);
    // try command_handler.addCommand("j", .normal, Commands.moveDown);
    // try command_handler.addCommand("k", .normal, Commands.moveUp);
    // try command_handler.addCommand("x", .normal, Commands.deleteAtPoint);
    // try command_handler.addCommand("gg", .normal, Commands.moveTop);
    // try command_handler.addCommand("G", .normal, Commands.moveBottom);
    // try command_handler.addCommand("w", .normal, Commands.moveWordStartRight);
    // try command_handler.addCommand("e", .normal, Commands.moveWordEndRight);
    // try command_handler.addCommand("b", .normal, Commands.moveWordStartLeft);
}

// if (e) |ev| {
//     switch (state.mode) {
//         .normal => switch (ev.*.type) {
//             .KEY_DOWN => {
//                 switch (ev.*.key_code) {
//                     .H => {
//                         if (state.buffer.gap_start == 0) return;
//                         state.buffer.moveGap(state.buffer.gap_start - 1) catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                         state.buffer.desired_offset = state.buffer.getLeftOffset();
//                     },
//                     .L => {
//                         state.buffer.moveGap(state.buffer.gap_start + 1) catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                         state.buffer.desired_offset = state.buffer.getLeftOffset();
//                     },
//                     .K => {
//                         state.buffer.moveGapUpByLine() catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     .J => {
//                         state.buffer.moveGapDownByLine() catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     .X => {
//                         state.buffer.deleteCharRight() catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     else => {},
//                 }
//             },
//             else => {},
//         },
//         .insert => switch (ev.*.type) {
//             .KEY_DOWN => {
//                 switch (ev.*.key_code) {
//                     .BACKSPACE => {
//                         if (state.buffer.hasRange()) {
//                             state.buffer.deleteRange() catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                             state.buffer.clearRange();
//                         } else {
//                             if (state.buffer.getBeforeGap().len > 0) {
//                                 state.buffer.deleteCharLeft() catch unreachable;
//                             }
//                         }
//                     },
//                     .ENTER => {
//                         if (state.buffer.hasRange()) {
//                             state.buffer.deleteRange() catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                             state.buffer.clearRange();
//                         }
//                         state.buffer.addChar('\n') catch unreachable;
//                     },
//                     .LEFT => {
//                         if (ev.*.modifiers == sapp.modifier_shift) {
//                             state.buffer.rangeLeft() catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                         } else {
//                             state.buffer.clearRange();
//                         }
//                         if (state.buffer.gap_start == 0) return;
//                         state.buffer.moveGap(state.buffer.gap_start - 1) catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     .RIGHT => {
//                         if (ev.*.modifiers == sapp.modifier_shift) {
//                             state.buffer.rangeRight() catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                         } else {
//                             state.buffer.clearRange();
//                         }
//                         state.buffer.moveGap(state.buffer.gap_start + 1) catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     .UP => {
//                         if (ev.*.modifiers == sapp.modifier_shift) {
//                             state.buffer.rangeUp() catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                         } else {
//                             state.buffer.clearRange();
//                         }
//                         state.buffer.moveGapUpByLine() catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     .DOWN => {
//                         if (ev.*.modifiers == sapp.modifier_shift) {
//                             state.buffer.rangeDown() catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                         } else {
//                             state.buffer.clearRange();
//                         }
//                         state.buffer.moveGapDownByLine() catch |err| {
//                             std.debug.print("{}\n", .{err});
//                         };
//                     },
//                     .C => {
//                         if (ev.*.modifiers == sapp.modifier_ctrl and !ev.*.key_repeat) {
//                             if (!state.buffer.hasRange()) return;
//                             const clipboard_buffer = allocator.alloc(u8, state.buffer.getRangeLength() + 1) catch unreachable;
//                             defer allocator.free(clipboard_buffer);
//                             state.buffer.getRangeText(clipboard_buffer) catch |err| {
//                                 std.debug.print("{}", .{err});
//                             };
//                             clipboard_buffer[clipboard_buffer.len - 1] = 0;
//                             sapp.setClipboardString(@as([:0]const u8, @ptrCast(@constCast(clipboard_buffer))));
//                         }
//                     },
//                     .X => {
//                         if (ev.*.modifiers == sapp.modifier_ctrl and !ev.*.key_repeat) {
//                             if (!state.buffer.hasRange()) return;
//                             const clipboard_buffer = allocator.alloc(u8, state.buffer.getRangeLength() + 1) catch unreachable;
//                             defer allocator.free(clipboard_buffer);
//                             state.buffer.getRangeText(clipboard_buffer) catch {};
//                             state.buffer.deleteRange() catch {};
//                             state.buffer.clearRange();
//                             clipboard_buffer[clipboard_buffer.len - 1] = 0;
//                             sapp.setClipboardString(@as([:0]const u8, @ptrCast(@constCast(clipboard_buffer))));
//                         }
//                     },
//                     .V => {
//                         if (ev.*.modifiers == sapp.modifier_ctrl) {
//                             if (state.buffer.hasRange()) {
//                                 state.buffer.deleteRange() catch {};
//                                 state.buffer.clearRange();
//                             }
//                             const clipboard_string = sapp.getClipboardString();
//                             state.buffer.addString(@ptrCast(clipboard_string)) catch |err| {
//                                 std.debug.print("{}\n", .{err});
//                             };
//                         }
//                     },
//                     else => {},
//                 }
//             },
//             .CHAR => {
//                 if (state.buffer.hasRange()) {
//                     state.buffer.deleteRange() catch |err| {
//                         std.debug.print("{}\n", .{err});
//                     };
//                     state.buffer.clearRange();
//                 }
//                 state.buffer.addChar(@intCast(ev.*.char_code)) catch |err| {
//                     std.debug.print("{}\n", .{err});
//                 };
//             },
//             else => {},
//         },
//         .visual => {},
//     }
// }
