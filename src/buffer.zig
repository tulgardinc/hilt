const std = @import("std");

pub const INITIAL_BUFFER = 4096;

allocator: std.mem.Allocator,

data: []u8,
data_length: usize,
gap_start: usize,
gap_end: usize,

const Self = @This();

pub fn init(initial_size: usize, allocator: std.mem.Allocator) !Self {
    return .{
        .data = try allocator.alloc(u8, initial_size),
        .data_length = initial_size,
        .gap_start = 0,
        .gap_end = initial_size,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.data);
}

pub fn addChar(self: *Self, char: u8) !void {
    if (self.gap_end - self.gap_start <= 0) return error.NoGapSpace;

    self.data[self.gap_start] = char;
    self.gap_start += 1;
}

pub fn deleteChar(self: *Self) !void {
    if (self.gap_start <= 0) return error.NoCharacterToRemove;

    self.gap_start -= 1;
}

pub fn moveGap(self: *Self, char_index: usize) !void {
    if (char_index > self.getTextLength() or char_index < 0) return error.IndexOutOfRange;

    if (char_index < self.gap_start) {
        std.mem.copyForwards(
            u8,
            self.data[char_index + (self.gap_end - self.gap_start) .. self.gap_end],
            self.data[char_index..self.gap_start],
        );
    } else {
        const offsetIndex = char_index + self.gap_end - self.gap_start;
        std.mem.copyBackwards(
            u8,
            self.data[self.gap_start .. self.gap_start + (self.gap_end - self.gap_start)],
            self.data[self.gap_end..offsetIndex],
        );
    }
    self.gap_end = char_index + self.gap_end - self.gap_start;
    self.gap_start = char_index;
}

pub fn getBeforeGap(self: *const Self) []const u8 {
    return self.data[0..self.gap_start];
}

pub fn getAfterGap(self: *const Self) []const u8 {
    return self.data[self.gap_end..];
}

pub fn getTextLength(self: *const Self) usize {
    return self.gap_start + self.data_length - self.gap_end;
}
