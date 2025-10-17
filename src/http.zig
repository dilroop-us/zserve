const std = @import("std");

pub const Request = struct {
    method: []const u8,
    path: []const u8,
};

pub fn parseRequestLine(line: []const u8) !Request {
    var it = std.mem.tokenizeAny(u8, line, " ");
    const method = it.next() orelse return error.BadRequest;
    const path = it.next() orelse return error.BadRequest;
    return .{ .method = method, .path = path };
}
