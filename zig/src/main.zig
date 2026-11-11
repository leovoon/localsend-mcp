const std = @import("std");
const mcp = @import("mcp");
const cfg = @import("config.zig");
const discovery = @import("discovery.zig");

var g_io: std.Io = undefined;

const status_schema =
    \\{"name":"localsend_status","description":"Show local network info and config.","inputSchema":{"type":"object","properties":{}}}
;

fn status(alloc: std.mem.Allocator, args: *const std.json.ObjectMap, out: *std.ArrayList(u8)) void {
    _ = args;
    const dd = cfg.defaultDownloadDir(alloc) catch "unknown";
    out.appendSlice(alloc, "download_dir=") catch {};
    out.appendSlice(alloc, dd) catch {};
    out.appendSlice(alloc, "\n") catch {};
}

const devices_schema =
    \\{"name":"localsend_devices","description":"Scan the local network for LocalSend peers.","inputSchema":{"type":"object","properties":{"timeout_ms":{"type":"integer"}}}}
;

fn devices(alloc: std.mem.Allocator, args: *const std.json.ObjectMap, out: *std.ArrayList(u8)) void {
    var timeout_ms: u32 = 3000;
    if (args.get("timeout_ms")) |v| {
        if (v == .integer) timeout_ms = @intCast(v.integer);
    }
    var peers = discovery.scan(alloc, g_io, timeout_ms) catch |err| {
        out.appendSlice(alloc, "error=") catch {};
        out.appendSlice(alloc, @errorName(err)) catch {};
        out.appendSlice(alloc, "\n") catch {};
        return;
    };
    defer peers.deinit(alloc);
    if (peers.items.len == 0) {
        out.appendSlice(alloc, "no devices found\n") catch {};
        return;
    }
    for (peers.items) |p| {
        out.appendSlice(alloc, p.alias) catch {};
        out.appendSlice(alloc, " ") catch {};
        out.appendSlice(alloc, p.ip) catch {};
        out.appendSlice(alloc, ":") catch {};
        var buf: [16]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{p.port}) catch "?";
        out.appendSlice(alloc, s) catch {};
        out.appendSlice(alloc, "\n") catch {};
    }
}

const tools = mcp.registry.Registry(&.{
    .{ .name = "localsend_status", .handler = status, .schema = status_schema },
    .{ .name = "localsend_devices", .handler = devices, .schema = devices_schema },
});

pub fn main(init: std.process.Init) !void {
    g_io = init.io;
    mcp.runWithRegistry(init.arena.allocator(), init.io, tools);
}
