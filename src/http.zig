const std = @import("std");

pub const Method = enum {
    GET,
    POST,
    PUT,
    PATCH,
    DELETE,
    HEAD,
    OPTIONS,
};

pub fn parseMethod(s: []const u8) ?Method {
    if (std.mem.eql(u8, s, "GET")) return .GET;
    if (std.mem.eql(u8, s, "POST")) return .POST;
    if (std.mem.eql(u8, s, "PUT")) return .PUT;
    if (std.mem.eql(u8, s, "PATCH")) return .PATCH;
    if (std.mem.eql(u8, s, "DELETE")) return .DELETE;
    if (std.mem.eql(u8, s, "HEAD")) return .HEAD;
    if (std.mem.eql(u8, s, "OPTIONS")) return .OPTIONS;
    return null;
}

pub const Header = struct {
    name: []const u8, // slices into the request buffer (no copies)
    value: []const u8,
};

pub const Request = struct {
    method: Method,
    path: []const u8,
    headers: []Header, // view of the parsed headers
};

pub fn parseRequestLine(line: []const u8) !Request {
    var it = std.mem.tokenizeAny(u8, line, " ");
    const method_tok = it.next() orelse return error.BadRequest;
    const path_tok = it.next() orelse return error.BadRequest;

    const method = parseMethod(method_tok) orelse return error.BadRequest;

    return .{
        .method = method,
        .path = path_tok,
        .headers = &[_]Header{}, // empty for now; caller fills later
    };
}

// Parse headers from a block like "Key: Value\r\nKey2: Value2\r\n"
pub fn parseHeaders(block: []const u8, out: []Header) !usize {
    var count: usize = 0;
    var start: usize = 0;

    while (start < block.len) {
        // find line end
        const crlf = std.mem.indexOfPos(u8, block, start, "\r\n") orelse block.len;
        const line = block[start..crlf];

        if (line.len == 0) break; // blank line (shouldn't happen; caller strips)

        const colon = std.mem.indexOf(u8, line, ":") orelse return error.BadRequest;
        const name = std.mem.trim(u8, line[0..colon], " ");
        const value_raw = if (colon + 1 < line.len) line[colon + 1 ..] else line[colon..];
        const value = std.mem.trim(u8, value_raw, " ");

        if (count >= out.len) return error.TooManyHeaders;
        out[count] = .{ .name = name, .value = value };
        count += 1;

        if (crlf == block.len) break;
        start = crlf + 2; // skip \r\n
    }
    return count;
}
