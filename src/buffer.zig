const std = @import("std");

pub const INITIAL_BUFFER_SIZE = 4096;

allocator: std.mem.Allocator,

data: []u8,
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
    };
}

pub fn deinit(self: *Self) void {
    self.allocator.free(self.data);
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

pub fn deleteCharLeft(self: *Self) !void {
    if (self.gap_start <= 0) return error.NoCharacterToRemove;

    self.gap_start -= 1;
}

pub fn deleteCharRight(self: *Self) !void {
    if (self.gap_end == self.data.len) return error.NoCharacterToRemove;

    self.gap_end += 1;
}

pub fn getLeftOffset(self: *const Self) usize {
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

pub fn moveGap(self: *Self, char_index: usize) !void {
    if (char_index > self.getTextLength() or char_index < 0) return error.IndexOutOfRange;

    if (char_index < self.gap_start) {
        std.mem.copyBackwards(
            u8,
            self.data[char_index + self.getGapLength() .. self.gap_end],
            self.data[char_index..self.gap_start],
        );
        self.gap_end = char_index + self.getGapLength();
        self.gap_start = char_index;
    } else {
        const offsetIndex = char_index + self.getGapLength();
        std.mem.copyForwards(
            u8,
            self.data[self.gap_start .. self.gap_start + offsetIndex - self.gap_end],
            self.data[self.gap_end..offsetIndex],
        );
        self.gap_end = char_index + self.getGapLength();
        self.gap_start = char_index;
    }
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
    return self.data.len - (self.gap_end - self.gap_start);
}

pub fn clearRange(self: *Self) void {
    self.range_start = null;
}

fn getColumnUpperLine(self: *const Self) usize {
    var in_upper_line = false;
    var i = self.gap_start;
    var upper_line_length: usize = 0;
    // move back from cursor
    while (i > 0) {
        i -= 1;
        if (in_upper_line) {
            // byte_offset != null = found the first \n
            upper_line_length += 1;
        }
        if (self.data[i] == '\n') {
            if (in_upper_line) {
                // move to either end of line above, or by offset
                return i + @min(self.desired_offset + 1, upper_line_length);
            } else {
                // found the first \n
                in_upper_line = true;
            }
        } else if (i == 0 and in_upper_line) {
            return i + @min(self.desired_offset + 1, upper_line_length);
        }
    }

    return 0;
}

fn getColumnLowerLine(self: *const Self) usize {
    var lower_line_length: usize = 0;

    var found_first_break = false;
    for (self.gap_end..self.data.len) |fidx| {
        if (found_first_break) {
            if (lower_line_length == self.desired_offset) {
                return fidx - (self.gap_end - self.gap_start);
            }

            lower_line_length += 1;
        }
        if (self.data[fidx] == '\n') {
            if (!found_first_break) {
                found_first_break = true;
                continue;
            }

            return fidx - (self.gap_end - self.gap_start);
        }
    }

    return self.data.len - (self.gap_end - self.gap_start);
}

pub fn moveGapUpByLine(self: *Self) !void {
    try self.moveGap(self.getColumnUpperLine());
}

pub fn moveGapDownByLine(self: *Self) !void {
    try self.moveGap(self.getColumnLowerLine());
}

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

pub fn charIndexToDataIndex(self: *const Self, char_index: usize) usize {
    if (char_index < self.gap_start) return char_index;
    return char_index + (self.gap_end - self.gap_start);
}

pub fn deleteRange(self: *Self) !void {
    if (self.range_start == null) return error.NoRange;

    const range_end_idx = self.charIndexToDataIndex(self.range_end);

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
