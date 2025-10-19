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
    name: []const u8, // slices into the request buffer
    value: []const u8,
};

pub const QueryParam = struct {
    key: []const u8, // slices into request line
    value: []const u8,
};

pub const Request = struct {
    method: Method,
    path: []const u8, // "/echo"
    query_raw: []const u8, // "x=1&y=2"
    headers: []Header,
    query: []QueryParam,
    body: []const u8,
};

/// Parse "METHOD /path?query HTTP/1.1"
pub fn parseRequestLine(line: []const u8) !Request {
    var it = std.mem.tokenizeAny(u8, line, " ");
    const method_tok = it.next() orelse return error.BadRequest;
    const target_tok = it.next() orelse return error.BadRequest;

    const method = parseMethod(method_tok) orelse return error.BadRequest;

    const qpos = std.mem.indexOf(u8, target_tok, "?");
    const path = if (qpos) |i| target_tok[0..i] else target_tok;
    const query = if (qpos) |i|
        (if (i + 1 <= target_tok.len) target_tok[i + 1 ..] else target_tok[0..0])
    else
        target_tok[0..0];

    return .{
        .method = method,
        .path = path,
        .query_raw = query,
        .headers = &[_]Header{},
        .query = &[_]QueryParam{},
        .body = &[_]u8{},
    };
}

/// Parse headers from "Key: Value\r\nKey2: Value2\r\n"
pub fn parseHeaders(block: []const u8, out: []Header) !usize {
    var count: usize = 0;
    var start: usize = 0;

    while (start < block.len) {
        const crlf = std.mem.indexOfPos(u8, block, start, "\r\n") orelse block.len;
        const line = block[start..crlf];
        if (line.len == 0) break;

        const colon = std.mem.indexOf(u8, line, ":") orelse return error.BadRequest;
        const name = std.mem.trim(u8, line[0..colon], " ");
        const value_raw = if (colon + 1 < line.len) line[colon + 1 ..] else line[colon..];
        const value = std.mem.trim(u8, value_raw, " ");

        if (count >= out.len) return error.TooManyHeaders;
        out[count] = .{ .name = name, .value = value };
        count += 1;

        if (crlf == block.len) break;
        start = crlf + 2;
    }
    return count;
}

/// Case-insensitive header lookup
pub fn findHeader(headers: []const Header, name_lower: []const u8) ?[]const u8 {
    for (headers) |h| {
        if (std.ascii.eqlIgnoreCase(h.name, name_lower)) return h.value;
    }
    return null;
}

/// Parse "a=1&b=2" into out[]; returns count.
pub fn parseQuery(src: []const u8, out: []QueryParam) usize {
    if (src.len == 0) return 0;
    var count: usize = 0;
    var start: usize = 0;

    while (start <= src.len) : (start += 1) {
        const amp = std.mem.indexOfPos(u8, src, start, "&") orelse src.len;
        const pair = src[start..amp];

        if (pair.len > 0) {
            const eq = std.mem.indexOf(u8, pair, "=");
            const key = std.mem.trim(u8, if (eq) |i| pair[0..i] else pair, " ");
            const value = std.mem.trim(u8, if (eq) |i|
                (if (i + 1 <= pair.len) pair[i + 1 ..] else pair[0..0])
            else
                pair[0..0], " ");
            if (count < out.len) {
                out[count] = .{ .key = key, .value = value };
                count += 1;
            }
        }

        if (amp == src.len) break;
        start = amp;
    }
    return count;
}
