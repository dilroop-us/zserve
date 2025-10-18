const std = @import("std");
const router_mod = @import("router.zig");
const http = @import("http.zig");

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    try stdout.print("zServe (day3) on http://127.0.0.1:8080\n", .{});

    // Router with method+path matching
    var router = router_mod.Router(16).init();
    router.add(.GET, "/health", &healthHandler);
    router.add(.GET, "/json", &jsonHandler);
    router.add(.POST, "/json", &jsonHandler);

    const addr = try std.net.Address.parseIp4("127.0.0.1", 8080);
    var server = try addr.listen(.{});
    defer server.deinit();

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        var buf: [8192]u8 = undefined;
        var total: usize = 0;
        const reader = conn.stream.reader();

        // Read until end-of-headers
        var header_end_idx: ?usize = null;
        while (total < buf.len) {
            const n = try reader.read(buf[total..]);
            if (n == 0) break;
            total += n;

            if (header_end_idx == null) {
                if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n")) |pos| {
                    header_end_idx = pos;
                    break; // Day 3: stop after headers (body in Day 4)
                }
            }
        }
        if (header_end_idx == null) {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        }

        // First line
        const first_line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse total;
        const line = buf[0..first_line_end];

        var req = http.parseRequestLine(line) catch {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        };

        // Headers block (between first CRLF and CRLFCRLF)
        const hdr_end = header_end_idx.?;
        const hdr_block = if (first_line_end + 2 <= hdr_end)
            buf[first_line_end + 2 .. hdr_end]
        else
            buf[0..0];

        var hdr_store: [32]http.Header = undefined; // fixed-capacity, zero-alloc
        const hdr_count = http.parseHeaders(hdr_block, hdr_store[0..]) catch {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        };
        req.headers = hdr_store[0..hdr_count];

        // Route and handle
        const handler = router.match(req.method, req.path) orelse &notFoundHandler;
        try handler(&conn.stream, req);
    }
}

// ---------- Handlers ----------

fn healthHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    _ = req;
    try sendText(stream, 200, "ok");
}

fn jsonHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    // For now, ignore body and just show a tiny JSON payload.
    // (Day 4: read body for POST and echo something back)
    var out: [64]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&out);
    try fbs.writer().print("{{\"status\":\"ok\",\"path\":\"{s}\"}}", .{req.path});
    try sendJSON(stream, 200, fbs.getWritten());
}

fn notFoundHandler(stream: *std.net.Stream, req: http.Request) anyerror!void {
    _ = req;
    try sendText(stream, 404, "not found");
}

// ---------- Response helpers ----------

fn sendText(stream: *std.net.Stream, status: u16, body: []const u8) !void {
    const reason = switch (status) {
        200 => "OK",
        404 => "Not Found",
        400 => "Bad Request",
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
