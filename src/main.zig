const std = @import("std");

pub fn main() !void {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    var stdout = std.io.getStdOut().writer();
    try stdout.print("zServe (day1) starting on http://127.0.0.1:8080 ...\n", .{});

    const addr = try std.net.Address.parseIp4("127.0.0.1", 8080);
    var server = try addr.listen(.{});
    defer server.deinit();

    while (true) {
        var conn = try server.accept();
        defer conn.stream.close();

        var buf: [8192]u8 = undefined;
        var total: usize = 0;

        var reader = conn.stream.reader();
        while (total < buf.len) {
            const n = try reader.read(buf[total..]);
            if (n == 0) break;
            total += n;
            if (std.mem.indexOf(u8, buf[0..total], "\r\n\r\n")) |_| break;
        }

        if (std.mem.indexOf(u8, buf[0..total], "\r\n")) |eol| {
            const first_line = buf[0..eol];
            try stdout.print("[req] {s}\n", .{first_line});
        }

        const body = "OK";
        const response_prefix =
            "HTTP/1.1 200 OK\r\n" ++
            "Content-Type: text/plain\r\n" ++
            "Connection: close\r\n";

        var tmp = std.ArrayList(u8).init(gpa);
        defer tmp.deinit();

        try tmp.writer().print("{s}Content-Length: {d}\r\n\r\n{s}", .{
            response_prefix, body.len, body,
        });

        try conn.stream.writeAll(tmp.items);
    }
}
