const std = @import("std");
const mcp = @import("mcp");

const status_schema =
    \\{"name":"localsend_status","description":"Show local network info.","inputSchema":{"type":"object","properties":{}}}
;

fn status(alloc: std.mem.Allocator, args: *const std.json.ObjectMap, out: *std.ArrayList(u8)) void {
    _ = args;
    out.appendSlice(alloc, "localsend-mcp zig build ok") catch {};
}

const tools = mcp.registry.Registry(&.{
    .{ .name = "localsend_status", .handler = status, .schema = status_schema },
});

pub fn main(init: std.process.Init) !void {
    mcp.runWithRegistry(init.arena.allocator(), init.io, tools);
}
