const std = @import("std");

pub const INITIAL_BUFFER_SIZE = 4096;

allocator: std.mem.Allocator,

data: []u8,
gap_start: usize,
gap_end: usize,
range_start: ?usize = null,
range_end: usize = 0,
desired_offset: usize = 0,
line_lengths: std.ArrayList(usize),
line_length_cache: std.ArrayList(usize), // every 4000 lines
current_line: usize,

const Self = @This();

pub fn init(initial_size: usize, allocator: std.mem.Allocator) !Self {
    return .{
        .data = try allocator.alloc(u8, initial_size),
        .gap_start = 0,
        .gap_end = initial_size,
        .allocator = allocator,
        .line_lengths = try std.ArrayList(usize).initCapacity(allocator, 512),
        .line_length_cache = std.ArrayList(usize).init(allocator),
        .current_line = 1,
    };
}

pub fn initFromFile(file_path: []const u8, file_size: usize, buffer_size: usize, allocator: std.mem.Allocator) !Self {
    const cwd = std.fs.cwd();
    const content_buffer = try allocator.alloc(u8, buffer_size);
    _ = try cwd.readFile(file_path, content_buffer[buffer_size - file_size ..]);

    var buffer: Self = .{
        .data = content_buffer,
        .gap_start = 0,
        .gap_end = buffer_size - file_size,
        .allocator = allocator,
        .line_lengths = try std.ArrayList(usize).initCapacity(allocator, 512),
        .line_length_cache = std.ArrayList(usize).init(allocator),
        .current_line = 1,
    };

    var length: usize = 0;
    var cache_sum: usize = 0;
    for (content_buffer[buffer_size - file_size ..]) |c| {
        length += 1;
        if (c == '\n') {
            try buffer.line_lengths.append(length);
            cache_sum += length;
            length = 0;

            if (buffer.line_lengths.items.len % 4000 == 0) {
                try buffer.line_length_cache.append(cache_sum);
                cache_sum = 0;
            }
        }
    }

    return buffer;
}

pub fn deinit(self: *Self) void {
    self.line_lengths.deinit();
    self.line_length_cache.deinit();
    self.allocator.free(self.data);
}

pub fn getLineCount(self: *const Self) usize {
    return self.line_lengths.items.len;
}

pub fn getLineStart(self: *const Self, line_index: usize) usize {
    const cache_line = @divFloor(line_index, 4000);
    const start_index = line_index % 4000;

    var start_sum: usize = 0;
    if (cache_line > 0 and self.line_length_cache.items.len > cache_line) {
        start_sum = self.line_length_cache.items[cache_line];
    }

    const vector_len = std.simd.suggestVectorLength(u8) orelse 16;

    if (self.line_lengths.items.len < vector_len) {
        var line_start: usize = 0;
        for (self.line_lengths.items[0..line_index]) |line_length| {
            line_start += line_length;
        }
        return line_start;
    }

    var accumulator: @Vector(vector_len, usize) = @splat(0);

    var index = start_index;
    while (index + vector_len < line_index) : (index += vector_len) {
        const vector_ptr: *@Vector(vector_len, usize) = @ptrCast(@alignCast(self.line_lengths.items[index .. index + vector_len]));
        accumulator += vector_ptr.*;
    }

    var line_start = start_sum;
    inline for (0..vector_len) |i| {
        line_start += accumulator[i];
    }

    for (self.line_lengths.items[index..line_index]) |line_length| {
        line_start += line_length;
    }

    return line_start;
}

pub fn toBufferIndex(self: *const Self, char_index: usize) usize {
    if (char_index < self.gap_start) return char_index;
    return char_index + self.getGapLength();
}

pub fn toCharIndex(self: *const Self, buffer_index: usize) usize {
    if (buffer_index <= self.gap_start) return buffer_index;
    return buffer_index - self.getGapLength();
}

pub fn updateCurrentLine(self: *Self) void {
    var total: usize = 1;
    for (0..self.gap_start) |i| {
        if (self.data[i] == '\n') total += 1;
    }
    self.current_line = total;
}

pub fn setGapStart(self: *Self, buffer_index: usize) void {
    self.gap_start = buffer_index;
    self.updateCurrentLine();
}

pub fn addChar(self: *Self, char: u8) !void {
    if (self.gap_end - self.gap_start == 0) return error.NoGapSpace;

    if (char == '\n') {
        const prev_line_length = self.getCurrentLineOffset() + 1;
        const new_line_length = self.getCurrentLineOffsetFromEnd();
        self.data[self.gap_start] = char;
        self.gap_start += 1;
        self.line_lengths.items[self.current_line - 1] = prev_line_length;
        try self.line_lengths.insert(self.current_line, new_line_length);
        self.updateCurrentLine();
    } else {
        self.data[self.gap_start] = char;
        self.gap_start += 1;
        self.line_lengths.items[self.current_line - 1] += 1;
    }
}

pub fn addString(self: *Self, chars: []const u8) !void {
    if (self.gap_end - self.gap_start == 0) return error.NoGapSpace;

    std.mem.copyForwards(u8, self.data[self.gap_start .. self.gap_start + chars.len], chars);
    self.gap_start += chars.len;

    //self.updateLineOffsets(self.current_line);
}

pub fn deleteCharsLeft(self: *Self, amount: usize) !void {
    if (self.gap_start <= amount) return error.NoCharacterToRemove;

    const prev_line_index = self.current_line - 1;
    const prev_gap_start = self.gap_start;

    std.debug.print("gap start: {}\n", .{self.gap_start});
    self.gap_start -= amount;
    std.debug.print("gap start: {}\n", .{self.gap_start});
    self.updateCurrentLine();

    const curr_line_index = self.current_line - 1;
    const curr_gap_start = self.gap_start;

    const deleted_line_count = prev_line_index - curr_line_index;

    var buffer_index = curr_gap_start;
    var line_index = curr_line_index;
    while (buffer_index < prev_gap_start) : (buffer_index += 1) {
        self.line_lengths.items[line_index] -= 1;
        if (self.data[buffer_index] == '\n') {
            line_index += 1;
            std.debug.print("deleting from line: {}\n", .{line_index});
        }
    }

    if (deleted_line_count > 0) {
        std.debug.print("delete multiline\n", .{});
        self.line_lengths.items[curr_line_index] += self.line_lengths.items[prev_line_index];
        std.mem.copyForwards(
            usize,
            self.line_lengths.items[curr_line_index + 1 .. self.line_lengths.items.len],
            self.line_lengths.items[prev_line_index + 1 .. self.line_lengths.items.len],
        );
        try self.line_lengths.resize(self.line_lengths.items.len - deleted_line_count);
    }

    for (self.line_lengths.items, 0..) |l, i| {
        std.debug.print("line {}: {}\n", .{ i, l });
    }
    std.debug.print("\n", .{});
}

pub fn deleteCharsRight(self: *Self, amount: usize) !void {
    if (self.gap_end + amount == self.data.len) return error.NoCharacterToRemove;

    const curr_line_index = self.current_line - 1;
    const prev_gap_end = self.gap_end;

    self.gap_end += amount;

    var buffer_index = prev_gap_end;
    var line_index = curr_line_index;
    while (buffer_index < self.gap_end) : (buffer_index += 1) {
        std.debug.print("line length: {}\n", .{self.line_lengths.items[line_index]});
        self.line_lengths.items[line_index] -= 1;
        if (self.data[buffer_index] == '\n') {
            line_index += 1;
            std.debug.print("deleting from line: {}\n", .{line_index});
        }
    }

    const range_end_line_index = line_index;
    const deleted_line_count = range_end_line_index - curr_line_index;

    if (deleted_line_count > 0) {
        self.line_lengths.items[curr_line_index] += self.line_lengths.items[range_end_line_index];
        std.mem.copyForwards(
            usize,
            self.line_lengths.items[curr_line_index + 1 .. self.line_lengths.items.len],
            self.line_lengths.items[range_end_line_index + 1 .. self.line_lengths.items.len],
        );
        try self.line_lengths.resize(self.line_lengths.items.len - deleted_line_count);
    }

    for (self.line_lengths.items, 0..) |l, i| {
        std.debug.print("line {}: {}\n", .{ i, l });
    }
    std.debug.print("\n", .{});
}

pub fn getCurrentLineOffsetFromEnd(self: *const Self) usize {
    const start = self.getLineStart(self.current_line - 1);
    const end = start + self.line_lengths.items[self.current_line - 1];
    return end - self.gap_start;
}

pub fn getCurrentLineOffset(self: *const Self) usize {
    return self.gap_start - self.getLineStart(self.current_line - 1);
}

pub fn moveGap(self: *Self, buffer_index: usize) !void {
    if (buffer_index == self.gap_start) return;
    if (buffer_index > self.data.len or buffer_index < 0) return error.IndexOutOfRange;

    if (self.range_start) |range_start| {
        std.debug.assert(range_start <= self.range_end);

        if (range_start == self.toCharIndex(self.gap_start)) {
            if (buffer_index < self.toBufferIndex(self.range_end)) {
                self.range_start = self.toCharIndex(buffer_index);
            } else if (buffer_index > self.toBufferIndex(self.range_end)) {
                self.range_start = self.range_end - 1;
                self.range_end = self.toCharIndex(buffer_index);
            }
        } else if (self.range_end == self.toCharIndex(self.gap_end)) {
            if (buffer_index > self.toBufferIndex(range_start)) {
                self.range_end = self.toCharIndex(buffer_index);
            } else if (buffer_index < self.toBufferIndex(range_start)) {
                self.range_end = range_start;
                self.range_start = self.toCharIndex(buffer_index);
            }
        }
    }

    if (buffer_index < self.gap_start) {
        std.mem.copyBackwards(
            u8,
            self.data[buffer_index + self.getGapLength() .. self.gap_end],
            self.data[buffer_index..self.gap_start],
        );
        self.gap_end -= self.gap_start - buffer_index;
        self.setGapStart(buffer_index);
    } else {
        std.mem.copyForwards(
            u8,
            self.data[self.gap_start .. buffer_index - self.getGapLength()],
            self.data[self.gap_end..buffer_index],
        );
        self.setGapStart(self.gap_start + buffer_index - self.gap_end);
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
// INDEXED IN CHAR INDEX

pub fn deleteRange(self: *Self) !void {
    if (!self.hasRange()) return error.NoRange;

    if (self.range_start.? < self.gap_start) {
        std.debug.print("range len: {}\n", .{self.getRangeLength()});
        try self.deleteCharsLeft(self.getRangeLength());
    } else {
        try self.deleteCharsRight(self.getRangeLength());
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
