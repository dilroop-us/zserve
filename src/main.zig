const std = @import("std");
const router_mod = @import("router.zig");
const http = @import("http.zig");

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    try stdout.print("zServe (day4) on http://127.0.0.1:8080\n", .{});

    var router = router_mod.Router(32).init();
    router.add(.GET, "/health", &healthHandler);
    router.add(.GET, "/json", &jsonHandler);
    router.add(.POST, "/json", &jsonHandler);
    router.add(.GET, "/echo", &echoQueryHandler);
    router.add(.POST, "/echo", &echoBodyHandler);

    const addr = try std.net.Address.parseIp4("127.0.0.1", 8080);
    var server = try addr.listen(.{});
    defer server.deinit();

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        var buf: [16384]u8 = undefined; // headers + small bodies
        var total: usize = 0;
        const reader = conn.stream.reader();

        // read until end-of-headers
        var hdr_end_opt: ?usize = null;
        while (total < buf.len) {
            const n = try reader.read(buf[total..]);
            if (n == 0) break;
            total += n;

            if (hdr_end_opt == null) {
                if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n")) |pos| {
                    hdr_end_opt = pos;
                    break;
                }
            }
        }
        if (hdr_end_opt == null) {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        }
        const hdr_end = hdr_end_opt.?;

        // parse request line
        const first_line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse total;
        const line = buf[0..first_line_end];

        var req = http.parseRequestLine(line) catch {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        };

        // parse headers
        const hdr_block = if (first_line_end + 2 <= hdr_end)
            buf[first_line_end + 2 .. hdr_end]
        else
            buf[0..0];

        var hdr_store: [32]http.Header = undefined;
        const hdr_count = http.parseHeaders(hdr_block, hdr_store[0..]) catch {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        };
        req.headers = hdr_store[0..hdr_count];

        // parse query into req.query
        var query_store: [16]http.QueryParam = undefined;
        const qcount = http.parseQuery(req.query_raw, query_store[0..]);
        req.query = query_store[0..qcount];

        // body via Content-Length (no chunked yet)
        const cl = blk: {
            const hv = http.findHeader(req.headers, "Content-Length");
            if (hv) |s| {
                const v = std.fmt.parseInt(usize, s, 10) catch 0;
                break :blk v;
            }
            break :blk 0;
        };

        if (cl > 0) {
            const already = total - (hdr_end + 4);
            if (already < cl) {
                if (hdr_end + 4 + cl > buf.len) {
                    try sendText(&conn.stream, 413, "payload too large");
                    continue;
                }
                var needed = cl - already;
                while (needed > 0) {
                    const n = try reader.read(buf[total..]);
                    if (n == 0) break;
                    total += n;
                    needed -= n;
                }
            }
            if (hdr_end + 4 + cl <= total) {
                req.body = buf[hdr_end + 4 .. hdr_end + 4 + cl];
            } else {
                try sendText(&conn.stream, 400, "bad request");
                continue;
            }
        } else {
            req.body = &[_]u8{};
        }

        // route + middleware wrapper (logger + recover)
        const handler = router.match(req.method, req.path) orelse &notFoundHandler;
        try handleWithMiddlewares(&conn.stream, req, handler);
    }
}

// ----------- middleware-ish wrapper: logger + recovery -----------

fn handleWithMiddlewares(stream: *std.net.Stream, req: http.Request, handler: router_mod.Handler) !void {
    const start = std.time.nanoTimestamp();

    // recover: convert handler error to 500 and log; swallow sendText failure
    const call_res = handler(stream, req) catch |e| {
        sendText(stream, 500, "internal server error") catch {};
        std.log.err("handler error: {any}", .{e});
        return;
    };
    _ = call_res;

    const dur_ns = std.time.nanoTimestamp() - start;
    const micros: i128 = @divTrunc(dur_ns, std.time.ns_per_us);
    std.log.info("{s} {s} -> done ({d} us)", .{ @tagName(req.method), req.path, @as(i64, @intCast(micros)) });
}

// -------------------------- handlers --------------------------

fn healthHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    _ = req;
    try sendText(stream, 200, "ok");
}

fn jsonHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    var out: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out);
    try fbs.writer().print("{{\"status\":\"ok\",\"path\":\"{s}\"}}", .{req.path});
    try sendJSON(stream, 200, fbs.getWritten());
}

fn echoQueryHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    var out: [512]u8 = undefined;

    var fbs = std.io.fixedBufferStream(&out); // mutable, then writer()
    var w = fbs.writer();

    try w.writeAll("{");
    var i: usize = 0;
    while (i < req.query.len) : (i += 1) {
        if (i > 0) try w.writeAll(",");
        try w.print("\"{s}\":\"{s}\"", .{ req.query[i].key, req.query[i].value });
    }
    try w.writeAll("}");

    const json = fbs.getWritten();
    try sendJSON(stream, 200, json);
}

fn echoBodyHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    if (req.body.len == 0) {
        try sendText(stream, 200, "(empty)");
    } else {
        try sendText(stream, 200, req.body);
    }
}

fn notFoundHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    _ = req;
    try sendText(stream, 404, "not found");
}

// ----------------------- response helpers -----------------------

fn sendText(stream: *std.net.Stream, status: u16, body: []const u8) !void {
    const reason = switch (status) {
        200 => "OK",
        404 => "Not Found",
        400 => "Bad Request",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        else => "Error",
    };

    var w = stream.writer();
    try w.print("HTTP/1.1 {d} {s}\r\n", .{ status, reason });
    try w.writeAll("Content-Type: text/plain\r\n");
    try w.writeAll("Connection: close\r\n");
    try w.print("Content-Length: {d}\r\n", .{body.len});
    try w.writeAll("\r\n");
    try w.writeAll(body);
}

fn sendJSON(stream: *std.net.Stream, status: u16, body: []const u8) !void {
    const reason = switch (status) {
        200 => "OK",
        404 => "Not Found",
        400 => "Bad Request",
        413 => "Payload Too Large",
        500 => "Internal Server Error",
        else => "Error",
    };

    var w = stream.writer();
    try w.print("HTTP/1.1 {d} {s}\r\n", .{ status, reason });
    try w.writeAll("Content-Type: application/json\r\n");
    try w.writeAll("Connection: close\r\n");
    try w.print("Content-Length: {d}\r\n", .{body.len});
    try w.writeAll("\r\n");
    try w.writeAll(body);
}
