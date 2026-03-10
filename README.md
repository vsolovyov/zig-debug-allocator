# DebugAllocator integer overflow on gVisor with libc linked

## Bug

`std.heap.DebugAllocator` panics with "integer overflow" when libc is linked
and running on gVisor (Linux kernel 4.4.0 emulation). Without libc, the same
code works fine.

## Environment

- Zig: `0.16.0-dev.2623+27eec9bd6`
- OS: Linux (gVisor container, reports kernel 4.4.0)
- Arch: x86_64

## Reproduce

```bash
zig build run          # With libc → panic: integer overflow
zig build run-no-libc  # Without libc → OK
```

## Expected

Both variants print "OK" and exit 0.

## Actual

The libc variant panics before reaching user code:

```
thread XXXXX panic: integer overflow
```

No stack trace is produced (stack trace resolution also appears broken on gVisor).

## Analysis

- `DebugAllocator` uses `page_allocator` (mmap) as backing allocator
- Linking libc changes the memory layout — likely mmap returns addresses that
  cause integer overflow in DebugAllocator's bucket/slot address calculations
- The crash occurs on the **first allocation** (42 bytes)
- `std.start` also hits this: in Debug mode, `use_debug_allocator = true`
  regardless of `link_libc` (start.zig:668), so any program using
  `std.process.Init` will crash

## Workaround

Build with `--release=safe`. In ReleaseSafe mode, `std.start` disables
DebugAllocator when libc is linked (start.zig:670):

```zig
.ReleaseSafe => !builtin.link_libc,
```

## Impact

Any Zig program built in Debug mode that links libc (directly or via C
dependencies like raylib) will crash before main() on gVisor environments
(Google Cloud Shell, some CI containers, etc).
