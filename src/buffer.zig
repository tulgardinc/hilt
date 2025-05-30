const std = @import("std");

pub const INITIAL_BUFFER = 4096;

allocator: std.mem.Allocator,

data: []u8,
gap_start: usize,
gap_end: usize,
range_start: ?usize = null,
range_end: usize = 0,

const Self = @This();

pub fn init(initial_size: usize, allocator: std.mem.Allocator) !Self {
    return .{
        .data = try allocator.alloc(u8, initial_size),
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
    var byte_offset: ?usize = null;
    var i = self.gap_start;
    var upper_line_length: usize = 0;
    // move back from cursor
    while (i > 0) {
        i -= 1;
        if (byte_offset != null) {
            // byte_offset != null = found the first \n
            upper_line_length += 1;
        }
        if (self.data[i] == '\n') {
            if (byte_offset) |off| {
                // move to either end of line above, or by offset
                return i + @min(off, upper_line_length);
            } else {
                // found the first \n
                byte_offset = self.gap_start - i;
            }
        } else if (i == 0 and byte_offset != null) {
            // byte offset is off by one if i = 0
            byte_offset.? -= 1;
            return i + @min(byte_offset.?, upper_line_length);
        }
    }

    return 0;
}

fn getColumnLowerLine(self: *const Self) usize {
    var byte_offset: usize = 0;
    var bidx = self.gap_start;
    var lower_line_length: usize = 0;
    while (bidx > 0) {
        bidx -= 1;
        if (self.data[bidx] == '\n') {
            byte_offset = self.gap_start - bidx - 1;
            break;
        }
        if (bidx == 0) {
            byte_offset = self.gap_start - bidx;
        }
    }

    var found_first_break = false;
    for (self.gap_end..self.data.len) |fidx| {
        if (found_first_break) {
            lower_line_length += 1;

            if (lower_line_length - 1 == byte_offset) {
                return fidx - (self.gap_end - self.gap_start);
            }
        }
        if (self.data[fidx] == '\n') {
            if (!found_first_break) {
                found_first_break = true;
                continue;
            }

            if (lower_line_length == byte_offset) {
                return fidx - (self.gap_end - self.gap_start);
            }
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
