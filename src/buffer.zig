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

pub fn moveGapUpByLine(self: *Self) !void {
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
                try self.moveGap(i + @min(off, upper_line_length));
                break;
            } else {
                // found the first \n
                byte_offset = self.gap_start - i;
            }
        } else if (i == 0 and byte_offset != null) {
            // byte offset is off by one if i = 0
            byte_offset.? -= 1;
            try self.moveGap(i + @min(byte_offset.?, upper_line_length));
        }
    }
}

pub fn moveGapDownByLine(self: *Self) !void {
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

    std.debug.print("offset: {}\n", .{byte_offset});

    var found_first_break = false;
    for (self.gap_end..self.data.len) |fidx| {
        if (found_first_break) {
            lower_line_length += 1;

            if (lower_line_length - 1 == byte_offset) {
                try self.moveGap(fidx - (self.gap_end - self.gap_start));
                return;
            }
        }
        if (self.data[fidx] == '\n') {
            if (!found_first_break) {
                found_first_break = true;
                continue;
            }

            if (lower_line_length == byte_offset) {
                try self.moveGap(fidx - (self.gap_end - self.gap_start));
                return;
            }
        }
    }
    try self.moveGap(self.data.len - (self.gap_end - self.gap_start));
}
