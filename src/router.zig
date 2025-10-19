const std = @import("std");
const http = @import("http.zig");

pub const Handler = *const fn (*std.net.Stream, http.Request) anyerror!void;

pub const Route = struct {
    method: http.Method,
    path: []const u8,
    handler: Handler,
};

pub fn Router(comptime max_routes: usize) type {
    return struct {
        routes: [max_routes]Route = undefined,
        count: usize = 0,

        pub fn init() Router(max_routes) {
            return .{ .routes = undefined, .count = 0 };
        }

        pub fn add(self: *Router(max_routes), method: http.Method, path: []const u8, handler: Handler) void {
            self.routes[self.count] = .{ .method = method, .path = path, .handler = handler };
            self.count += 1;
        }

        pub fn match(self: *Router(max_routes), method: http.Method, path: []const u8) ?Handler {
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                const r = self.routes[i];
                if (r.method == method and std.mem.eql(u8, r.path, path)) return r.handler;
            }
            return null;
        }
    };
}
