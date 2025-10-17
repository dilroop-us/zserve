const std = @import("std");
const router_mod = @import("router.zig");
const http_mod = @import("http.zig");

pub fn main() !void {
    var stdout = std.io.getStdOut().writer();
    try stdout.print("zServe (day2) on http://127.0.0.1:8080\n", .{});

    var router = router_mod.Router(8).init();
    router.add("/health", &healthHandler);

    const addr = try std.net.Address.parseIp4("127.0.0.1", 8080);
    var server = try addr.listen(.{});
    defer server.deinit();

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        var buf: [4096]u8 = undefined;
        var total: usize = 0;
        var reader = conn.stream.reader();

        while (total < buf.len) {
            const n = try reader.read(buf[total..]);
            if (n == 0) break;
            total += n;
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n")) |_| break;
        }

        const first_line_end = std.mem.indexOf(u8, buf[0..total], "\r\n") orelse total;
        const line = buf[0..first_line_end];

        const req = http_mod.parseRequestLine(line) catch {
            try sendText(&conn.stream, 400, "bad request");
            continue;
        };

        const handler = router.match(req.path) orelse &notFoundHandler;
        try handler(&conn.stream, req.path);
    }
}

// --- handlers ---

fn healthHandler(stream: *std.net.Stream, _: []const u8) anyerror!void {
    try sendText(stream, 200, "ok");
}

fn notFoundHandler(stream: *std.net.Stream, _: []const u8) anyerror!void {
    try sendText(stream, 404, "not found");
}

// --- response helper ---

fn sendText(stream: *std.net.Stream, status: u16, body: []const u8) !void {
    const reason = switch (status) {
        200 => "OK",
        404 => "Not Found",
        400 => "Bad Request",
        else => "Error",
    };

    // Write EXACT bytes, line by line (no concatenation).
    var w = stream.writer();

    // Status line must be: HTTP/1.1 <code> <reason>\r\n
    try w.print("HTTP/1.1 {d} {s}\r\n", .{ status, reason });
    try w.writeAll("Content-Type: text/plain\r\n");
    try w.writeAll("Connection: close\r\n");
    try w.print("Content-Length: {d}\r\n", .{body.len});
    try w.writeAll("\r\n");
    try w.writeAll(body);
}
