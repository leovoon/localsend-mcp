const std = @import("std");

pub const Peer = struct {
    alias: []const u8,
    ip: []const u8,
    port: u16,
};

/// Scan the local network for LocalSend peers via UDP multicast
/// (224.0.0.167:53317). Returns the list of discovered peers.
///
/// Multicast socket options are not exposed by std.Io.net in this Zig
/// version, so this is currently a stub that returns an empty list. The
/// signature is kept stable so callers can be wired up once the APIs land.
pub fn scan(alloc: std.mem.Allocator, io: std.Io, timeout_ms: u32) !std.ArrayList(Peer) {
    _ = io;
    _ = timeout_ms;
    // TODO: implement multicast discovery when socket options (IP_ADD_MEMBERSHIP,
    // SO_REUSEADDR, etc.) become available in std.Io.net.
    var result: std.ArrayList(Peer) = .empty;
    errdefer result.deinit(alloc);
    return result;
}
