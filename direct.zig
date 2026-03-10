/// Minimal repro: DebugAllocator panics with "integer overflow" on gVisor
/// when libc is linked.
const std = @import("std");

fn msg(s: []const u8) void {
    _ = std.os.linux.write(2, s.ptr, s.len);
}

fn hexByte(b: u8) [2]u8 {
    const hex = "0123456789abcdef";
    return .{ hex[b >> 4], hex[b & 0xf] };
}

fn printHex(val: u64) void {
    var buf: [18]u8 = undefined;
    buf[0] = '0';
    buf[1] = 'x';
    inline for (0..8) |i| {
        const b: u8 = @truncate(val >> @intCast((7 - i) * 8));
        const h = hexByte(b);
        buf[2 + i * 2] = h[0];
        buf[2 + i * 2 + 1] = h[1];
    }
    msg(&buf);
}

fn printDec(val: u64) void {
    if (val == 0) {
        msg("0");
        return;
    }
    var buf: [20]u8 = undefined;
    var n = val;
    var i: usize = 20;
    while (n > 0) {
        i -= 1;
        buf[i] = '0' + @as(u8, @intCast(n % 10));
        n /= 10;
    }
    msg(buf[i..20]);
}

pub const std_options: std.Options = .{
    .logFn = struct {
        fn f(
            comptime message_level: std.log.Level,
            comptime scope: @TypeOf(.enum_literal),
            comptime format: []const u8,
            args: anytype,
        ) void {
            _ = message_level;
            _ = scope;
            _ = format;
            _ = args;
        }
    }.f,
};

pub fn panic(panic_msg: []const u8, st: ?*std.builtin.StackTrace, ret: ?usize) noreturn {
    _ = st;
    _ = ret;
    msg("PANIC: ");
    msg(panic_msg);
    msg("\n");
    std.os.linux.exit_group(42);
    unreachable;
}

pub fn main() void {
    // Dump dl_iterate_phdr data to see what gVisor reports
    msg("=== dl_iterate_phdr dump ===\n");
    const native_endian = std.builtin.Endian.little;
    _ = native_endian;

    var count: usize = 0;
    std.posix.dl_iterate_phdr(&count, error{OutOfMemory}, struct {
        fn callback(info: *std.posix.dl_phdr_info, size: usize, ctx: *usize) error{OutOfMemory}!void {
            _ = size;
            msg("module ");
            printDec(ctx.*);
            msg(": addr=");
            printHex(info.addr);
            msg(" name=");
            const name = std.mem.sliceTo(info.name, 0) orelse "";
            if (name.len > 0) msg(name) else msg("(main)");
            msg(" phnum=");
            printDec(info.phnum);
            msg("\n");

            for (info.phdr[0..info.phnum]) |phdr| {
                msg("  type=");
                printDec(@intFromEnum(phdr.type));
                msg(" vaddr=");
                printHex(phdr.vaddr);
                msg(" memsz=");
                printHex(phdr.memsz);

                // Check if addr + vaddr would overflow
                const result = @addWithOverflow(info.addr, phdr.vaddr);
                msg(" addr+vaddr=");
                printHex(result[0]);
                if (result[1] != 0) {
                    msg(" OVERFLOW!");
                }
                msg("\n");
            }
            ctx.* += 1;
        }
    }.callback) catch {};

    msg("\n=== now trying DebugAllocator ===\n");
    var da: std.heap.DebugAllocator(.{}) = .init;
    const alloc = da.allocator();
    const slice = alloc.alloc(u8, 42) catch {
        msg("FAIL: alloc returned error\n");
        return;
    };
    alloc.free(slice);
    msg("OK: DebugAllocator alloc+free succeeded\n");
}
