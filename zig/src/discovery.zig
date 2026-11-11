const std = @import("std");

pub const Peer = struct {
    alias: []const u8,
    ip: []const u8,
    port: u16,
};

/// Scan the local network for LocalSend peers.
/// Not yet implemented in Zig: std.Io.net (0.17) does not expose multicast
/// socket options (IP_ADD_MEMBERSHIP, SO_REUSEADDR) required by the
/// LocalSend discovery protocol. Use the Node implementation for now.
pub fn scan(alloc: std.mem.Allocator, io: std.Io, timeout_ms: u32) !std.ArrayList(Peer) {
    _ = io;
    _ = timeout_ms;
    var result: std.ArrayList(Peer) = .empty;
    errdefer result.deinit(alloc);
    return result;
}
