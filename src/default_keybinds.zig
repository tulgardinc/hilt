const CommandHandler = @import("command_handler.zig");
const Commands = @import("commands.zig");

pub fn setDefaultBinds(command_handler: *CommandHandler) !void {
    try command_handler.addCommand("h", &.{ .normal, .visual }, Commands.moveLeft);
    try command_handler.addCommand("j", &.{ .normal, .visual }, Commands.moveDown);
    try command_handler.addCommand("k", &.{ .normal, .visual }, Commands.moveUp);
    try command_handler.addCommand("l", &.{ .normal, .visual }, Commands.moveRight);

    try command_handler.addCommand("<left>", &.{ .normal, .visual, .insert }, Commands.moveLeft);
    try command_handler.addCommand("<up>", &.{ .normal, .visual, .insert }, Commands.moveUp);
    try command_handler.addCommand("<down>", &.{ .normal, .visual, .insert }, Commands.moveDown);
    try command_handler.addCommand("<right>", &.{ .normal, .visual, .insert }, Commands.moveRight);

    try command_handler.addCommand("zz", &.{ .normal, .visual }, Commands.centerLine);

    try command_handler.addCommand("x", &.{.normal}, Commands.deleteAtPoint);
    try command_handler.addCommand("x", &.{.visual}, Commands.deleteRange);

    try command_handler.addCommand("gg", &.{ .normal, .visual }, Commands.moveTop);
    try command_handler.addCommand("G", &.{ .normal, .visual }, Commands.moveBottom);
    try command_handler.addCommand("w", &.{ .normal, .visual }, Commands.moveWordStartRight);
    try command_handler.addCommand("e", &.{ .normal, .visual }, Commands.moveWordEndRight);
    try command_handler.addCommand("b", &.{ .normal, .visual }, Commands.moveWordStartLeft);
    try command_handler.addCommand("<C-u>", &.{ .normal, .visual }, Commands.upByHalf);
    try command_handler.addCommand("<C-d>", &.{ .normal, .visual }, Commands.downByHalf);

    try command_handler.addCommand("i", &.{.normal}, Commands.switchToInsertMode);
    try command_handler.addCommand("a", &.{.normal}, Commands.switchToInsertModeRight);
    try command_handler.addCommand("v", &.{.normal}, Commands.switchToVisualMode);

    try command_handler.addCommand("<escape>", &.{.visual}, Commands.switchToNormalMode);

    try command_handler.addCommand("<escape>", &.{.insert}, Commands.switchToNormalMode);
    try command_handler.addCommand("<backspace>", &.{.insert}, Commands.deleteLeft);
    try command_handler.addCommand("<enter>", &.{.insert}, Commands.breakLine);
}
