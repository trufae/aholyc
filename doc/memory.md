# Memory in ahc

How ahc lays out data, manages the heap, and isolates per-thread state —
across all three backends. TempleOS ran everything in one identity-mapped
physical address space where every object had an address you could poke;
ahc keeps that worldview and maps it onto each target as directly as it
can.

## The HolyC view of memory

* Every scalar loads into a 64-bit value (or an `F64`); the declared
  type only decides the width and signedness of loads and stores.
* A pointer is a byte address. Pointer arithmetic scales by the element
  size (`I64 *p; p + 1` advances 8 bytes), `p1 - p2` yields an element
  count, and indexing is sugar for scaled deref. `U0 *` advances 1 byte
  per step in ahc (TempleOS adds 0; Terry's guidelines say don't use it).
* Everything is little-endian, so casting a `U8*` into an `I64*` and
  peeking at bytes behaves identically on every backend — including JS.
* Multi-char constants pack little-endian: `'ABC'` == `0x434241`.

## Object layout

* `I8/U8` take 1 byte, `I16/U16` 2, `I32/U32` 4, `I64/U64/F64` and
  pointers 8. `U0` is size **zero**.
* Class members are laid out in declaration order, packed back to back
  with **no alignment and no padding**, exactly like TempleOS; `$$ = n;`
  places the next member at an explicit offset (see `doc/struct.md`).
  `offset(Class.member)` and `sizeof()` are compile-time constants over
  exactly this layout.
* Single inheritance places the parent's members first: a child's first
  own member starts at `sizeof(parent)`. A `CDog*` therefore *is* a
  valid `CAnimal*` at the byte level — no adjustments, ever.
* `union` members all start at the union base (offset 0, movable with
  `$$ = n;`); the union takes the size of its widest member.
* Strings are NUL-terminated `U8*` byte runs. String *literals* should
  be treated as read-only: the LLVM backend puts them in constant data,
  so writing into one may fault there while silently working elsewhere.

The layout algorithm lives in one place (`parse_class()` in
`src/parse.c`) and every backend consumes the computed offsets, which is
why struct-shaped code is byte-portable across `c`, `llvm` and `js`.

## Storage classes

| storage | native backends | JS backend |
|---|---|---|
| globals | zero-initialized data segment (`static`/`internal`, unless `public`) | fixed addresses in the data segment, from 64 up |
| locals | stack (C locals / LLVM allocas), zeroed on entry | frame in linear memory: `fp+offset`, zeroed on entry |
| parameters | full 64-bit slots (spilled so `&param` works) | 8-byte slots in the frame |
| string literals | private constant arrays | interned into the data segment at startup |
| heap | libc `malloc` behind `MAlloc` | bump allocator region |

Global initializers are not static data: they run as startup code, in
source order, exactly like any other top-level statement.

### Varargs are memory, not registers

A call to a variadic function materializes the extra arguments as an
array of 8-byte slots (stack alloca natively, the dedicated arg-stack
region in JS) and passes `(named..., I64 argc, I64 *argv)`. `F64`
values are bit-copied into their slot, which is why `Print`'s `%f`
can reinterpret a slot the formatter decides is a float. Inside a
variadic function, `argv` is an ordinary pointer into that memory — you
can index it, take its address, or pass it along.

## Heap management

The allocator API mirrors TempleOS:

```holyc
U8 *p = MAlloc(100);   // uninitialized
U8 *z = CAlloc(100);   // zeroed
n = MSize(p);          // the size you asked for
Free(p);               // Free(NULL) is fine
```

* `MAlloc` prefixes each block with a 16-byte header holding the
  requested size, so `MSize()` works; the returned pointer is
  16-byte-aligned right after the header. An allocation failure throws
  the `'NOMEM'` exception rather than returning NULL.
* Ownership conventions in the runtime: `StrNew`, `MStrPrint`, and
  `GetStr` return `MAlloc`'d buffers the caller must `Free`.
* **Native backends** sit on libc `malloc`/`free` — thread-safe,
  growable, the usual rules. `Free` really releases memory.
* **JS backend**: the heap is the tail of the 64 MB linear memory with a
  bump pointer. `MAlloc`/`MSize` behave identically (same header
  scheme), but `Free` is a **no-op** — fine for scripts and tests,
  wrong for a long-running allocation-heavy loop. Exhausting the region
  throws `'NOMEM'`.

## The JS linear address space

JavaScript has no addressable memory, so the JS backend simulates the
machine: one `ArrayBuffer(64 MB)` is all of RAM, a pointer is a byte
offset carried as a JS number, and a `DataView` does typed little-endian
loads/stores. The map:

```
0          reserved: address 0 is NULL and stays invalid
16..31     CTask       { except_ch @16, catch_except @24 }
32         the cell backing the `Fs` global (holds 16)
64...      data segment: string literals, then globals — addresses
           assigned at compile time, bytes poured in by D() at startup
─ page-aligned after data ─
+8 MB      stack: function frames (bump pointer FP)
+1 MB      vararg slots (bump pointer ASP)
rest       heap (bump pointer HP)
```

Every function allocates a frame (`const fp = FP; FP += size`) and
restores it in a `finally`, so returns *and* exceptions unwind
correctly. A variable reference compiles to a load like `lds2(fp+24)`;
`&x` is just `fp+24`. This is what makes pointer tricks, `MemCpy` over
class values, unions and sub-byte access work bit-for-bit like the
native backends.

Two things intentionally live outside linear memory:

* **Function pointers** — `&Foo` is an index into a function table
  (`FT`), offset by 1 so NULL stays falsy. Indirect calls compile to
  `FT[v-1](...)`.
* **JS strings** — memory bytes are the truth; `cstr()`/`wstr()`
  translate (latin1, byte-exact) only at the runtime boundary, e.g.
  inside `Print`.

Caveat: values are JS numbers, exact to 53 bits. 64-bit bitwise ops
route through BigInt helpers, but arithmetic beyond 2^53 loses
precision. See [backends.md](backends.md).

## Thread-local state

TempleOS kept per-task state behind `Fs` — a segment register pointing
at the current `CTask`. ahc's portable equivalent is C thread-local
storage: on native backends, `Fs` and the whole exception machinery are
**per host thread**.

What is thread-local in the runtime (`runtime/rt.c`):

* `Fs` itself, pointing at a per-thread `CTask` (`except_ch`,
  `catch_except`);
* the `try` frame stack (`jmp_buf` array and its depth counter).

So two threads can `throw` and `catch` concurrently without seeing each
other's exception state or handler stacks — `tests/tls_threads.HC`
proves this by synchronizing two throwing threads inside both the `try`
and the `catch`.

Mechanics worth knowing:

* A TLS pointer can't be statically initialized with the address of
  another TLS object, so `Fs` starts NULL and `__hc_fs()` lazily binds
  it to the thread's `CTask` on first use. Generated code never reads
  the raw `Fs` symbol: the C backend emits `__hc_fs()` calls and the
  LLVM backend declares `@Fs` as `thread_local` and fetches it via
  `@__hc_fs()`. Your HolyC code just says `Fs->except_ch` and gets the
  right thread's task.
* The TLS spelling is picked per compiler (`_Thread_local`, `__thread`,
  `__declspec(thread)`), see `HC_TLS` in `runtime/rt.c`.
* ahc has no thread-spawning API of its own. The supported pattern is
  library interop: mark a HolyC function `public`, hand it to
  `pthread_create` from a small C shim, link with `-lpthread` — see
  `tests/tls_threads.c` / `tests/tls_threads.HC`. Each new thread gets
  fresh exception state automatically.

What is *not* per-thread or protected:

* Your globals — shared, unsynchronized. `lock{}` compiles its body
  without atomicity; bring your own mutex (via a C shim).
* The PRNG state behind `Seed`/`RandI64`/`Rand` — shared and racy.
* Heap blocks are handed out thread-safely (libc `malloc`), but nothing
  stops two threads from stomping the same buffer.
* Stdio: each `Print` flushes, and single writes are atomic-ish, but
  interleaving between threads is unspecified.
* The **JS backend** is single-threaded by design: `TASK` at address 16
  simply is "the" task, and none of the above applies.

## Related reading

* [language.md](language.md) — types, classes, and the exception model
  as seen from HolyC.
* [backends.md](backends.md) — how each backend realizes this model.
* [internals.md](internals.md) — compiler pipeline and calling
  convention.
