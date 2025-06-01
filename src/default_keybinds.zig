const CommandHandler = @import("command_handler.zig");
const Commands = @import("commands.zig");

pub fn setDefaultBinds(command_handler: *CommandHandler) !void {
    try command_handler.addCommand("l", .normal, Commands.moveRight);
    try command_handler.addCommand("h", .normal, Commands.moveLeft);
    try command_handler.addCommand("j", .normal, Commands.moveDown);
    try command_handler.addCommand("k", .normal, Commands.moveUp);
    try command_handler.addCommand("x", .normal, Commands.deleteAtPoint);
    try command_handler.addCommand("gg", .normal, Commands.moveTop);
    try command_handler.addCommand("G", .normal, Commands.moveBottom);
}
