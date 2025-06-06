const std = @import("std");

pub const INITIAL_BUFFER_SIZE = 4096;

allocator: std.mem.Allocator,

data: []u8,
current_line: usize,
gap_start: usize,
gap_end: usize,
range_start: ?usize = null,
range_end: usize = 0,
desired_offset: usize = 0,

const Self = @This();

pub fn init(initial_size: usize, allocator: std.mem.Allocator) !Self {
    return .{
        .data = try allocator.alloc(u8, initial_size),
        .gap_start = 0,
        .gap_end = initial_size,
        .allocator = allocator,
        .current_line = 1,
    };
}

pub fn initFromFile(file_path: []const u8, file_size: usize, buffer_size: usize, allocator: std.mem.Allocator) !Self {
    const cwd = std.fs.cwd();
    const content_buffer = try allocator.alloc(u8, buffer_size);
    _ = try cwd.readFile(file_path, content_buffer[buffer_size - file_size ..]);

    return .{
        .data = content_buffer,
        .gap_start = 0,
        .gap_end = buffer_size - file_size,
        .allocator = allocator,
        .current_line = 1,
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.data);
}

pub fn toBufferIndex(self: *const Self, char_index: usize) usize {
    if (char_index < self.gap_start) return char_index;
    return char_index + self.getGapLength();
}

pub fn toCharIndex(self: *const Self, buffer_index: usize) usize {
    if (buffer_index < self.gap_start) return buffer_index;
    return buffer_index - self.getGapLength();
}

pub fn addChar(self: *Self, char: u8) !void {
    if (self.gap_end - self.gap_start == 0) return error.NoGapSpace;

    self.data[self.gap_start] = char;
    self.gap_start += 1;
}

pub fn addString(self: *Self, chars: []const u8) !void {
    if (self.gap_end - self.gap_start == 0) return error.NoGapSpace;

    std.mem.copyForwards(u8, self.data[self.gap_start .. self.gap_start + chars.len], chars);
    self.gap_start += chars.len;
}

pub fn deleteCharsLeft(self: *Self, amount: usize) !void {
    if (self.gap_start - amount <= 0) return error.NoCharacterToRemove;

    self.gap_start -= amount;
}

pub fn deleteCharsRight(self: *Self, amount: usize) !void {
    if (self.gap_end + amount == self.data.len) return error.NoCharacterToRemove;

    self.gap_end += amount;
}

pub fn getLineOffset(self: *const Self) usize {
    var i: usize = self.gap_start;
    while (i > 0) {
        i -= 1;
        if (self.data[i] == '\n') {
            i += 1;
            break;
        }
    }
    return self.gap_start - i;
}

pub fn moveGap(self: *Self, buffer_index: usize) !void {
    if (buffer_index == self.gap_start) return;
    if (buffer_index > self.data.len or buffer_index < 0) return error.IndexOutOfRange;

    if (buffer_index < self.gap_start) {
        self.current_line -= self.getLineDelta(buffer_index, self.gap_start);
        std.mem.copyBackwards(
            u8,
            self.data[buffer_index + self.getGapLength() .. self.gap_end],
            self.data[buffer_index..self.gap_start],
        );
        self.gap_end -= self.gap_start - buffer_index;
        self.gap_start = buffer_index;
    } else {
        self.current_line += self.getLineDelta(self.gap_end, buffer_index);
        std.mem.copyForwards(
            u8,
            self.data[self.gap_start .. buffer_index - self.getGapLength()],
            self.data[self.gap_end..buffer_index],
        );
        self.gap_start += buffer_index - self.gap_end;
        self.gap_end = buffer_index;
    }
}

pub fn getLineDelta(self: *const Self, start_index: usize, end_index: usize) usize {
    std.debug.assert(start_index <= end_index);
    var line_count: usize = 0;
    var index: usize = start_index;
    while (index < end_index) {
        if (self.data[index] == '\n') {
            line_count += 1;
        }
        if (index == self.gap_start) {
            index = self.gap_end;
        } else {
            index += 1;
        }
    }

    return line_count;
}

pub fn getGapLength(self: *const Self) usize {
    return self.gap_end - self.gap_start;
}

pub fn getBeforeGap(self: *const Self) []const u8 {
    return self.data[0..self.gap_start];
}

pub fn getAfterGap(self: *const Self) []const u8 {
    return self.data[self.gap_end..];
}

pub fn getTextLength(self: *const Self) usize {
    return self.data.len - self.getGapLength();
}

pub fn clearRange(self: *Self) void {
    self.range_start = null;
}

/// Returns buffer index of the begining of a line
/// Starts search from current line
pub fn getLine(self: *const Self, target_line_number: usize) usize {
    if (target_line_number < self.current_line) {
        var i = self.gap_start;
        var current_line = self.current_line;
        while (i > 0) {
            i -= 1;
            if (self.data[i] == '\n') {
                if (current_line == target_line_number) {
                    return i + 1;
                } else {
                    current_line -= 1;
                }
            }
        }
        return i;
    } else {
        var i = self.gap_end;
        var current_line = self.current_line;
        while (current_line != target_line_number and i < self.data.len) : (i += 1) {
            if (self.data[i] == '\n') {
                current_line += 1;
            }
        }
        return i;
    }
}

pub fn getDesiredOffsetOnLine(self: *const Self, line_start_index: usize) usize {
    var i: usize = line_start_index;
    while (i < line_start_index + self.desired_offset and i < self.data.len) : (i += 1) {
        if (self.data[i] == '\n') {
            return i;
        }
    }
    return i;
}

pub fn moveGapUpByLine(self: *Self) !void {
    if (self.current_line == 0) return;
    const line_start = self.getLine(self.current_line - 1);
    const desired = self.getDesiredOffsetOnLine(line_start);
    try self.moveGap(desired);
}

pub fn moveGapDownByLine(self: *Self) !void {
    if (self.gap_end == self.data.len) return;
    const line_start = self.getLine(self.current_line + 1);
    const desired = self.getDesiredOffsetOnLine(line_start);
    try self.moveGap(desired);
}

// === RANGE ===

pub fn rangeRight(self: *Self) !void {
    if (self.gap_end == self.data.len) return error.IndexOutOfRange;
    if (self.range_start) |*range_start| {
        if (range_start.* < self.gap_start) {
            self.range_end += 1;
        } else {
            range_start.* += 1;
            if (self.range_end == range_start.*) {
                self.range_start = null;
            }
        }
    } else {
        self.range_start = self.gap_start;
        self.range_end = self.gap_start + 1;
    }
}

pub fn rangeLeft(self: *Self) !void {
    if (self.gap_start == 0) return error.IndexOutOfRange;
    if (self.range_start) |*range_start| {
        if (range_start.* < self.gap_start) {
            self.range_end -= 1;
        } else {
            range_start.* -= 1;
            if (self.range_end == range_start.*) {
                self.range_start = null;
            }
        }
    } else {
        self.range_start = self.gap_start - 1;
        self.range_end = self.gap_start;
    }
}

pub fn rangeUp(self: *Self) !void {
    const new_pos = self.getColumnUpperLine();
    if (self.range_start) |range_start| {
        if (range_start < self.gap_start) {
            if (new_pos > range_start) {
                self.range_end = new_pos;
            } else {
                self.range_end = range_start;
                self.range_start = new_pos;
            }
        }
    } else {
        self.range_end = self.gap_start;
    }
    self.range_start = new_pos;

    if (self.range_start == self.range_end) self.clearRange();
}

pub fn rangeDown(self: *Self) !void {
    const new_pos = self.getColumnLowerLine();
    if (self.range_start) |range_start| {
        if (range_start > self.gap_start) {
            if (new_pos > self.range_end) {
                self.range_start = self.range_end;
                self.range_end = new_pos;
            } else {
                self.range_start = new_pos;
            }
        }
    } else {
        self.range_start = self.gap_start;
    }
    self.range_end = new_pos;

    if (self.range_start == self.range_end) self.clearRange();
}

pub fn deleteRange(self: *Self) !void {
    if (self.range_start == null) return error.NoRange;

    const range_end_idx = self.toBufferIndex(self.range_end);

    self.gap_start = self.range_start.?;

    if (range_end_idx > self.gap_end) {
        self.gap_end = range_end_idx;
    }
}

pub fn hasRange(self: *const Self) bool {
    return self.range_start != null;
}

pub fn getRangeLength(self: *const Self) usize {
    if (!self.hasRange()) return 0;
    return self.range_end - self.range_start.?;
}

pub fn getRangeText(self: *const Self, str_buffer: []u8) !void {
    if (!self.hasRange()) return error.NoRange;
    const range_start = self.range_start.?;
    var partial_idx: usize = 0;

    if (self.gap_start >= range_start) {
        const end = if (self.gap_start == range_start) self.range_end else @min(self.range_end, self.gap_start);
        partial_idx = end - range_start;
        std.mem.copyForwards(u8, str_buffer[0..partial_idx], self.data[range_start..end]);
    }

    if (self.gap_end <= self.range_end) {
        std.mem.copyForwards(u8, str_buffer[partial_idx..], self.data[self.gap_end..self.range_end]);
    }
}
