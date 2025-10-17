const std = @import("std");

// Use a function-pointer type with an explicit error set.
pub const Handler = *const fn (*std.net.Stream, []const u8) anyerror!void;

pub const Route = struct {
    path: []const u8,
    handler: Handler,
};

// Generic, fixed-capacity router that can be created at runtime.
pub fn Router(comptime max_routes: usize) type {
    return struct {
        routes: [max_routes]Route = undefined,
        count: usize = 0,

        pub fn init() Router(max_routes) {
            // We don't need to prefill routes; 'count' guards reads.
            return .{ .routes = undefined, .count = 0 };
        }

        pub fn add(self: *Router(max_routes), path: []const u8, handler: Handler) void {
            self.routes[self.count] = .{ .path = path, .handler = handler };
            self.count += 1;
        }

        pub fn match(self: *Router(max_routes), path: []const u8) ?Handler {
            var i: usize = 0;
            while (i < self.count) : (i += 1) {
                const r = self.routes[i];
                if (std.mem.eql(u8, r.path, path)) return r.handler;
            }
            return null;
        }
    };
}
