pub const packages = struct {
    pub const @"deps/mcp-zig" = struct {
        pub const build_root = "deps/mcp-zig";
        pub const build_zig = @import("deps/mcp-zig");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "mcp_zig", "deps/mcp-zig" },
};
