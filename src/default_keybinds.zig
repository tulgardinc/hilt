const CommandHandler = @import("command_handler.zig");
const Commands = @import("commands.zig");

pub fn setDefaultBinds(command_handler: *CommandHandler) !void {
    try command_handler.addCommand("h", .normal, Commands.moveLeft);
    try command_handler.addCommand("j", .normal, Commands.moveDown);
    try command_handler.addCommand("k", .normal, Commands.moveUp);
    try command_handler.addCommand("l", .normal, Commands.moveRight);

    try command_handler.addCommand("<left>", .normal, Commands.moveLeft);
    try command_handler.addCommand("<up>", .normal, Commands.moveUp);
    try command_handler.addCommand("<down>", .normal, Commands.moveDown);
    try command_handler.addCommand("<right>", .normal, Commands.moveRight);
    try command_handler.addCommand("<left>", .insert, Commands.moveLeft);
    try command_handler.addCommand("<up>", .insert, Commands.moveUp);
    try command_handler.addCommand("<down>", .insert, Commands.moveDown);
    try command_handler.addCommand("<right>", .insert, Commands.moveRight);

    try command_handler.addCommand("zz", .normal, Commands.centerLine);

    try command_handler.addCommand("x", .normal, Commands.deleteAtPoint);
    try command_handler.addCommand("gg", .normal, Commands.moveTop);
    try command_handler.addCommand("G", .normal, Commands.moveBottom);
    try command_handler.addCommand("w", .normal, Commands.moveWordStartRight);
    try command_handler.addCommand("e", .normal, Commands.moveWordEndRight);
    try command_handler.addCommand("b", .normal, Commands.moveWordStartLeft);
    try command_handler.addCommand("<C-u>", .normal, Commands.upByHalf);
    try command_handler.addCommand("<C-d>", .normal, Commands.downByHalf);
    try command_handler.addCommand("i", .normal, Commands.switchToInsertMode);
    try command_handler.addCommand("a", .normal, Commands.switchToInsertModeRight);
    try command_handler.addCommand("<escape>", .insert, Commands.switchToNormalMode);
    try command_handler.addCommand("<backspace>", .insert, Commands.deleteLeft);
}
