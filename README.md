# Integer overflow in `std.debug.SelfInfo` on gVisor with libc linked

## Bug

Any Zig program built in Debug mode that links libc panics with "integer
overflow" on gVisor. Without libc, the same code works.

## Environment

- Zig: `0.16.0-dev.2722+f16eb18ce` (also reproduces on `0.16.0-dev.2623+27eec9bd6`)
- OS: Linux (gVisor container, reports kernel 4.4.0)
- Arch: aarch64 (likely also x86_64)

## Reproduce

```bash
zig build run          # With libc → panic: integer overflow
zig build run-no-libc  # Without libc → OK
```

## Root cause

The overflow is in the stack trace capture code that DebugAllocator triggers 
on every allocation.

`std.debug.SelfInfo.Elf.DlIterContext.callback` (in `lib/std/debug/SelfInfo/Elf.zig`)
uses regular `+` for `info.addr + phdr.vaddr` when processing NOTE (line 458) and
GNU_EH_FRAME (line 470) segments:

```zig
// line 458 — NOTE segment
const segment_ptr: [*]const u8 = @ptrFromInt(info.addr + phdr.vaddr);

// line 470 — GNU_EH_FRAME segment
const segment_ptr: [*]const u8 = @ptrFromInt(info.addr + phdr.vaddr);
```

Line 495 (LOAD segments) already uses wrapping `+%` with an explicit comment:

```zig
// Overflowing addition handles VSDOs having p_vaddr = 0xffffffffff700000
.start = info.addr +% phdr.vaddr,
```

The NOTE and GNU_EH_FRAME cases were missed.

### Why gVisor, not regular Linux?

gVisor's VDSO ELF uses legacy vsyscall-style virtual addresses in its program
headers (`p_vaddr = 0xffffffffff700000`). The load offset (`info.addr`) is
computed as `mapped_addr - p_vaddr`, which wraps around. Adding them back
together wraps to the correct address — mathematically valid, but requires
wrapping arithmetic.

Real Linux's VDSO is position-independent with small `p_vaddr` values (near 0),
so `addr + vaddr` never wraps.

### Why libc, not without?

Without libc, Zig uses raw syscalls and doesn't call `dl_iterate_phdr` (a libc
function). The debug info resolution takes a different code path that reads
`/proc/self/maps` directly, bypassing the ELF program header walk entirely.
With libc linked, `dl_iterate_phdr` is available, so Zig uses it — and that's
where it encounters the VDSO's overflowing addresses.

### Evidence from `dl_iterate_phdr` dump on gVisor

```
module 2: addr=0x0000e085a65ee000 name=(vdso) phnum=3
  type=1 vaddr=0xffffffffff700000 memsz=0x0000000000001288 addr+vaddr=0x0000e085a5cee000 OVERFLOW!
  type=2 vaddr=0xffffffffff700370 memsz=0x0000000000000110 addr+vaddr=0x0000e085a5cee370 OVERFLOW!
  type=1685382480 vaddr=0xffffffffff700290 memsz=0x000000000000003c addr+vaddr=0x0000e085a5cee290 OVERFLOW!
```

## Fix

Two lines in `lib/std/debug/SelfInfo/Elf.zig` — change `+` to `+%`:

```diff
-                    const segment_ptr: [*]const u8 = @ptrFromInt(info.addr + phdr.vaddr);
+                    const segment_ptr: [*]const u8 = @ptrFromInt(info.addr +% phdr.vaddr);
```

(Both line 458 and line 470.)

## Impact

Any Zig program built in Debug mode that links libc (directly or via C
dependencies) will crash before `main()` on gVisor environments (Google Cloud
Shell, some CI containers, etc).

## Workaround

Build with `--release=safe`. In ReleaseSafe mode, `std.start` disables
DebugAllocator when libc is linked, so stack trace capture never runs.
