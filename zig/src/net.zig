const std = @import("std");

const c = @cImport({
    @cInclude("ifaddrs.h");
    @cInclude("net/if.h");
    @cInclude("netinet/in.h");
    @cInclude("arpa/inet.h");
    @cInclude("sys/socket.h");
});

pub fn localAddresses(alloc: std.mem.Allocator) ![][]u8 {
    var ifap: ?*c.struct_ifaddrs = null;
    if (c.getifaddrs(&ifap) != 0) return error.GetIfAddrsFailed;
    defer c.freeifaddrs(ifap);

    var result: std.ArrayList([]u8) = .empty;
    var cur = ifap;
    while (cur) |ifa| {
        defer cur = ifa.ifa_next;
        const addr = ifa.ifa_addr orelse continue;
        const sa: *const c.struct_sockaddr = @ptrCast(addr);
        if (sa.sa_family != c.AF_INET) continue;
        // skip loopback/internal
        const flags = ifa.ifa_flags;
        if (flags & c.IFF_LOOPBACK != 0) continue;
        if (flags & c.IFF_UP == 0) continue;

        var buf: [128]u8 = undefined;
        const sin: *c.struct_sockaddr_in = @ptrCast(@alignCast(addr));
        _ = c.inet_ntop(c.AF_INET, @ptrCast(&sin.sin_addr), &buf, buf.len);
        const ip = std.mem.span(@as([*:0]const u8, @ptrCast(&buf)));
        if (ip.len == 0) continue;
        if (std.mem.eql(u8, ip, "127.0.0.1")) continue;
        const dup = try alloc.dupe(u8, ip);
        try result.append(alloc, dup);
    }
    return result.toOwnedSlice(alloc);
}

pub fn safeFileName(alloc: std.mem.Allocator, raw: []const u8) ![]u8 {
    // strip dirs
    var s = raw;
    // replace backslashes
    // find last slash
    var i: usize = s.len;
    while (i > 0) : (i -= 1) {
        if (s[i - 1] == '/' or s[i - 1] == '\\') break;
    }
    s = s[i..];

    // remove control chars
    var buf: std.ArrayList(u8) = .empty;
    for (s) |ch| {
        if (ch < 0x20 or ch == 0x7f) continue;
        try buf.append(alloc, ch);
    }
    // trim
    var start: usize = 0;
    var end: usize = buf.items.len;
    while (start < end and (buf.items[start] == ' ' or buf.items[start] == '\t')) start += 1;
    while (end > start and (buf.items[end - 1] == ' ' or buf.items[end - 1] == '\t')) end -= 1;
    const cleaned = buf.items[start..end];

    if (cleaned.len == 0 or std.mem.eql(u8, cleaned, ".") or std.mem.eql(u8, cleaned, "..")) {
        // all dots?
        var all_dots = cleaned.len > 0;
        for (cleaned) |ch| { if (ch != '.') { all_dots = false; break; } }
        if (cleaned.len == 0 or all_dots) {
            return try std.fmt.allocPrint(alloc, "file-0", .{});
        }
    }

    if (cleaned.len > 200) {
        // ext
        const ext = extension(cleaned);
        const keep = 200 - ext.len;
        var out = try alloc.alloc(u8, 200);
        @memcpy(out[0..keep], cleaned[0..keep]);
        @memcpy(out[keep..], ext);
        return out;
    }
    return try alloc.dupe(u8, cleaned);
}

fn timestampMs() i64 {
    return std.time.milliTimestamp();
}

fn extension(name: []const u8) []const u8 {
    var i: usize = name.len;
    while (i > 0) : (i -= 1) {
        if (name[i - 1] == '.') {
            return name[i - 1 ..];
        }
        if (name[i - 1] == '/' or name[i - 1] == '\\') break;
    }
    return "";
}

pub fn expandPath(alloc: std.mem.Allocator, input: []const u8) ![]u8 {
    var raw = input;
    // trim
    while (raw.len > 0 and (raw[0] == ' ' or raw[0] == '\t' or raw[0] == '\n')) raw = raw[1..];
    while (raw.len > 0 and (raw[raw.len - 1] == ' ' or raw[raw.len - 1] == '\t' or raw[raw.len - 1] == '\n')) raw = raw[0 .. raw.len - 1];

    if (std.mem.eql(u8, raw, "~")) {
        const home = std.c.getenv("HOME") orelse "/tmp";
        return try alloc.dupe(u8, std.mem.span(home));
    }
    if (raw.len >= 2 and raw[0] == '~' and (raw[1] == '/' or raw[1] == '\\')) {
        const home = std.c.getenv("HOME") orelse "/tmp";
        const home_span = std.mem.span(home);
        return try std.fs.path.join(alloc, &.{ home_span, raw[2..] });
    }
    // resolve relative to cwd
    if (std.fs.path.isAbsolute(raw)) {
        return try alloc.dupe(u8, raw);
    }
    var cwd_buf: [4096]u8 = undefined;
    const cwd_ptr = std.c.getcwd(&cwd_buf, cwd_buf.len) orelse "/tmp";
    const cwd = std.mem.span(@as([*:0]const u8, @ptrCast(cwd_ptr)));
    return try std.fs.path.join(alloc, &.{ cwd, raw });
}

pub fn guessFileType(name: []const u8) []const u8 {
    const ext = extension(name);
    // lowercase copy
    var lower_buf: [64]u8 = undefined;
    const n = @min(ext.len, lower_buf.len);
    for (ext[0..n], 0..) |ch, idx| {
        lower_buf[idx] = if (ch >= 'A' and ch <= 'Z') ch + 32 else ch;
    }
    const lower = lower_buf[0..n];

    const table = [_]struct { ext: []const u8, mime: []const u8 }{
        .{ .ext = ".txt", .mime = "text/plain" },
        .{ .ext = ".md", .mime = "text/markdown" },
        .{ .ext = ".json", .mime = "application/json" },
        .{ .ext = ".csv", .mime = "text/csv" },
        .{ .ext = ".html", .mime = "text/html" },
        .{ .ext = ".css", .mime = "text/css" },
        .{ .ext = ".js", .mime = "text/javascript" },
        .{ .ext = ".ts", .mime = "text/plain" },
        .{ .ext = ".pdf", .mime = "application/pdf" },
        .{ .ext = ".zip", .mime = "application/zip" },
        .{ .ext = ".gz", .mime = "application/gzip" },
        .{ .ext = ".tar", .mime = "application/x-tar" },
        .{ .ext = ".png", .mime = "image/png" },
        .{ .ext = ".jpg", .mime = "image/jpeg" },
        .{ .ext = ".jpeg", .mime = "image/jpeg" },
        .{ .ext = ".gif", .mime = "image/gif" },
        .{ .ext = ".webp", .mime = "image/webp" },
        .{ .ext = ".svg", .mime = "image/svg+xml" },
        .{ .ext = ".mp3", .mime = "audio/mpeg" },
        .{ .ext = ".wav", .mime = "audio/wav" },
        .{ .ext = ".m4a", .mime = "audio/mp4" },
        .{ .ext = ".mp4", .mime = "video/mp4" },
        .{ .ext = ".mov", .mime = "video/quicktime" },
        .{ .ext = ".webm", .mime = "video/webm" },
        .{ .ext = ".doc", .mime = "application/msword" },
        .{ .ext = ".docx", .mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document" },
        .{ .ext = ".xls", .mime = "application/vnd.ms-excel" },
        .{ .ext = ".xlsx", .mime = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" },
        .{ .ext = ".ppt", .mime = "application/vnd.ms-powerpoint" },
        .{ .ext = ".pptx", .mime = "application/vnd.openxmlformats-officedocument.presentationml.presentation" },
    };
    for (table) |e| {
        if (std.mem.eql(u8, lower, e.ext)) return e.mime;
    }
    return "application/octet-stream";
}
