/// Minimal repro: DebugAllocator panics with "integer overflow" on gVisor
/// when libc is linked.
///
/// The same code works without libc. DebugAllocator uses page_allocator
/// (mmap) as backing. Linking libc presumably changes the memory layout
/// or mmap behavior on gVisor, causing integer overflow in DebugAllocator's
/// bucket/slot address arithmetic.
///
/// Zig version: 0.16.0-dev.2623+27eec9bd6
/// OS: Linux (gVisor kernel 4.4.0)
/// Arch: x86_64
const std = @import("std");

fn msg(s: []const u8) void {
    _ = std.os.linux.write(2, s.ptr, s.len);
}

pub fn main() void {
    var da: std.heap.DebugAllocator(.{}) = .init;
    const alloc = da.allocator();

    // Single alloc is enough to trigger the crash
    const slice = alloc.alloc(u8, 42) catch {
        msg("FAIL: alloc returned error\n");
        return;
    };
    alloc.free(slice);

    msg("OK: DebugAllocator alloc+free succeeded\n");
}
