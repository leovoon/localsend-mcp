const std = @import("std");

pub const Config = struct {
    alias: []const u8,
    download_dir: []const u8,
};

pub fn certDir(alloc: std.mem.Allocator) ![]u8 {
    const home_raw = std.c.getenv("HOME") orelse "/tmp";
    const home = std.mem.span(home_raw);
    return std.fs.path.join(alloc, &.{ home, ".localsend-mcp" });
}

pub fn defaultDownloadDir(alloc: std.mem.Allocator) ![]u8 {
    const home_raw = std.c.getenv("HOME") orelse "/tmp";
    const home = std.mem.span(home_raw);
    return std.fs.path.join(alloc, &.{ home, "Downloads" });
}
