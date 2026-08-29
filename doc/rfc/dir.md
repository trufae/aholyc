# DIRPLAN: heap-free directory I/O and HolyC compatibility

Status: proposed implementation plan, based on the current uncommitted
[`lib/io/dir.hc`](lib/io/dir.hc), syscall commit `0ac8cc4`, the bundled
TempleOS sources, and the bundled holyc-lang sources. This document does not
change the implementation.

## Re-evaluated direction

`lib/syscall` is a good foundation for a fast directory implementation on its
supported native targets, but it is not a complete portable backend and it is
not yet copy-minimal. The directory work should be reorganized around these
decisions:

1. `lib/io/dir.hc` is a strict, streaming, caller-owned core. It does not call
   `MAlloc`, `CAlloc`, `Free`, `malloc`, or an opaque iterator such as
   `opendir` that allocates internally.
2. Linux and selected Darwin targets use raw, caller-buffered enumeration.
   Windows uses caller-owned Win32 structures. BSD uses verified low-level
   libc wrappers until `lib/syscall` has a correct per-BSD ABI.
3. Names are views into the enumeration buffer. Listing does not copy names or
   construct full paths.
4. Recursive operations use directory-relative handles on Unix and explicit
   caller-owned workspace. Windows uses a single mutable path workspace plus
   per-level find state. No recursive function may place a 4 KiB or 32 KiB
   path array in every stack frame.
5. HolyC compatibility is layered over the core. Heap-free TempleOS contracts
   can be supported directly; owning contracts such as `FilesFind` cannot be
   called exactly compatible while also promising no heap.
6. Error, end-of-directory, cancellation, insufficient workspace, and partial
   failure are distinct outcomes. Boolean/`NULL` convenience wrappers must not
   erase the underlying error.

## Meaning of “no heap” and “zero copy”

The core guarantee is about the application and AHolyC runtime heap:

- No allocation or deallocation is performed directly or indirectly by the
  core.
- The caller owns iterator buffers, traversal frames, path workspaces, and any
  result storage.
- The library never silently falls back to `opendir`, `fdopendir`, `scandir`,
  formatted-string allocation, or a global growable buffer.
- Input paths are borrowed. Entry names are borrowed views valid until the
  next refill of that iterator, seek/reset, or close.
- Kernel objects and Win32 handles necessarily consume operating-system
  resources. The guarantee cannot mean that the kernel or Win32 implementation
  performs no internal allocation.
- “Zero copy” applies to enumeration records and entry names. A copy is still
  necessary when an OS requires a NUL-terminated component or a mutable full
  path. Those copies must be bounded, caller-owned, and performed once rather
  than rebuilding every ancestor prefix.

The scratch passed to a hot-path API must not be cleared by the library. This
matters because AHolyC zeroes every local aggregate on function entry
([`doc/memory.md`](doc/memory.md)); embedding a large buffer in `CDir` or a
recursive local would cause a full write immediately before the kernel
overwrites it.

## Assessment of the current uncommitted implementation

### Good parts to retain

| Property | Why it is worth keeping |
|---|---|
| Borrowed path and entry-name lifetime is documented | This maps directly to a kernel-filled scratch buffer and avoids per-entry allocation. |
| `DirNext` skips `.` and `..` without building a path | Correct fast-path behavior. |
| Listing and callbacks receive base names | A descriptor-relative backend can consume these names without copying them. |
| Handles are closed on normal callback exit and cancellation | The cleanup shape is sound. |
| `DirPathJoin` checks capacity and includes the terminator | The bounded helper is useful for APIs that truly require a path. |
| The public surface is small | It can be preserved as wrappers while the backend and result model are made precise. |

### Problems that must be resolved before merge

| Priority | Current problem | Required correction |
|---|---|---|
| P0 | POSIX `opendir` owns an opaque allocation, so the “nothing allocates” claim is false. | Replace it with `openat` plus `getdents64`, `getdirentries64`, or a verified low-level BSD adapter that writes into caller scratch. |
| P0 | The Windows `CDirFindData` is 304 bytes while `WIN32_FIND_DATAA` is 320 bytes. `FindFirstFileA` can overwrite it. | Model the complete ABI, including the alternate-name tail and explicit packed offsets, and add size/offset assertions. |
| P0 | Recursive deletion follows a directory symlink and can delete entries outside the requested tree. | Use descriptor-relative, no-follow traversal; treat POSIX symlinks and Windows reparse points as leaves. |
| P0 | `mkdir(path, 0777)` is wrong in AHolyC because the leading-zero literal is decimal. | Use hexadecimal `0x1ff`, subject to the process umask. |
| P0 | [`tests/io_dir.HC`](tests/io_dir.HC) defines `Main` but never calls it; [`tests/run.sh`](tests/run.sh) only executes the resulting no-op program. | Make the test call `Main(argc, argv)` before trusting any current pass. |
| P1 | One generic hand-written `dirent` name offset is used for unsupported BSD ABIs, and Darwin libc symbol details are brittle. | Parse an explicit record layout for each backend; never use the generic `$$ = 20` fallback. |
| P1 | `DirNext == NULL` conflates EOF, malformed records, and an OS read error. | Add a tri-state primitive and retain the exact negative native error. |
| P1 | `DirExists` really means “`opendir` succeeded,” so permissions and other open errors are reported as nonexistence. | Add explicit `DirIsDir`/`IsDir` and metadata primitives with defined follow/no-follow semantics. |
| P1 | Forced removal first tries `rmdir` on every path, then probes it as a directory, then tries `unlink`. | Classify from the entry record and use one no-follow fallback when the type is unknown. |
| P1 | Recursive removal constructs and clears a 4 KiB path on every POSIX level and a 32 KiB path on every Windows level. | Use `*at` operations on Unix; use one append/restore path buffer on Windows; keep traversal frames in caller workspace. |
| P1 | Recursive creation copies the entire path and treats backslash as a POSIX separator; Windows root, UNC, and device-prefix cases are incomplete. | Use an OS-specific root parser. POSIX recognizes only `/`; Windows recognizes drive, UNC, and `\\?\` roots. |
| P1 | Callback cancellation is reported as generic failure, and cleanup errors are lost. | Give cancellation and close/read failures separate result codes. |
| P2 | The README currently describes portability and allocation guarantees that the code does not meet. | Publish the support matrix and lifetime/error contracts only after their tests pass. |

## `lib/syscall` fit and prerequisite work

The required syscall numbers already exist for Linux x86-64, arm64, and
riscv64, and for Darwin x86-64 and arm64. The fixed `Syscall0` through
`Syscall6` functions also provide a useful normalized `-errno` convention.

They are not yet the fastest possible call path. Every current `Syscall1`
through `Syscall6` creates a local `arguments[]`, AHolyC clears that aggregate,
and the initializer then copies each argument into it. Inline assembly reloads
those copies. This conflicts with the “no unnecessary memory copies” goal.

Before benchmarking the directory layer:

1. Refactor fixed-arity syscall assembly to load the already-spilled named
   parameters directly instead of building `arguments[]`.
2. Keep the public `SyscallN` signatures and normalized error convention
   unchanged.
3. Do not use the variadic `Syscall` form in directory code.
4. Add runtime coverage for every arity and generated C/LLVM or disassembly
   checks that the argument array has disappeared.
5. Keep filesystem policy and record parsing in `lib/io`; do not turn
   `lib/syscall` into a directory abstraction.

### Backend matrix

| Target | Heap-free primitive backend | Initial status and policy |
|---|---|---|
| Linux x86-64 | `openat`, `getdents64`, `close`, `mkdirat`, `unlinkat`, `newfstatat`/`statx` | All numbers exist now. This is the first reference backend. |
| Linux arm64/riscv64 | Same operations using the asm-generic numbers | All numbers exist now and Linux `dirent64` layout is common across these 64-bit targets. Test natively or under QEMU. |
| Darwin x86-64/arm64 | `openat`, `getdirentries64`, `close`, `mkdirat`, `unlinkat`, `fstatat64` | Numbers exist and the arm64 call works on the current host, but Darwin direct syscalls are a private ABI. Keep this backend isolated and gated. |
| FreeBSD | Low-level libc `openat`/`getdirentries`/`close`/`mkdirat`/`unlinkat`/`fstatat` with caller storage | `lib/syscall` has no support. Validate allocation behavior and the exact versioned record layout before enabling. |
| OpenBSD | Low-level libc adapter | Do not issue direct inline syscalls; pinsyscalls and ABI policy make that unsafe. |
| NetBSD | Low-level libc adapter | Do not guess versioned `__getdents` structures or symbol ABIs. |
| Windows x86-64/arm64 | Stable Win32 find/create/delete APIs with complete caller-owned structures | Do not add raw NT syscall numbers. They are private and build-dependent. Never descend into a reparse point. |
| Native `-fno-asm` | Verified low-level libc adapter, where available | Either provide this explicitly or emit a clear compile-time unsupported diagnostic. Never fall back to `opendir`. |
| JavaScript | None | Remain deliberately unsupported unless a separate host filesystem bridge is designed. |

`lib/syscall/numbers.hc` must be included only inside supported Linux/Darwin
branches; unconditional inclusion would break Windows and BSD builds.

## Proposed core design

Exact spelling should be frozen in phase 0, but the primitive contract should
look like this:

```holyc
class CDirEntryView
{
  U8 *name;          // Borrowed; no copy.
  I64 name_length;
  I64 type;          // DT_UNKNOWN, DT_REG, DT_DIR, DT_LNK, ...
  I64 inode;         // Zero/unknown where the backend has none.
};

class CDir
{
  I64 handle;        // -1 is invalid; descriptor 0 is valid.
  I64 error;
  U8 *path;          // Borrowed, for diagnostics/convenience only.
  U8 *scratch;       // Caller-owned and never cleared by the library.
  I64 scratch_size;
  I64 cursor;
  I64 end;
  I64 position;      // Needed by Darwin; harmless elsewhere.
};

I64 DirOpenBuf(CDir *dir, U8 *path, U8 *scratch, I64 scratch_size);
I64 DirNextEx(CDir *dir, CDirEntryView *entry); // 1 entry, 0 EOF, <0 error
I64 DirCloseEx(CDir *dir);                      // 0 or <0 error
I64 DirError(CDir *dir);
```

Rules:

- `CDir` stays small. Do not embed a 4–32 KiB buffer in it.
- `DirOpenBuf` rejects missing or undersized scratch and never substitutes a
  heap or global buffer.
- `DirNextEx` validates every record length, name boundary, and terminator
  before exposing a view. It skips inode-zero records and `.`/`..`.
- `d_type == DT_UNKNOWN` remains unknown during plain enumeration. Operations
  that require a type use a no-follow descriptor-relative probe.
- A refill invalidates all views returned from that iterator. The conservative
  `DirNext` wrapper may continue documenting validity only until the next call.
- Closing is idempotent, but any real close failure remains observable.
- `DirOpen`, `DirNext`, `DirClose`, and `DirForEach` may remain convenience
  names over these primitives, but the hot path must expose caller scratch and
  tri-state results.
- No global scratch is permitted: simultaneous iterators, nested callbacks,
  and threads must be independent.

Buffer size is a benchmarked policy, not an ABI constant. Start with 16 KiB and
32 KiB for flat Linux enumeration, test Darwin’s minimum buffer requirements,
and allow callers to reuse a larger buffer. The public API must report a small
buffer precisely rather than spin or report false EOF.

### Native record parsing

- Linux `dirent64`: inode at 0, offset at 8, record length at 16, type at 18,
  and name at 19.
- Current Darwin 64-bit directory record: inode at 0, seek offset at 8, record
  length at 16, name length at 18, type at 20, and name at 21.
- BSD layouts are separate files and separate tests. FreeBSD/OpenBSD and
  NetBSD must not share the current fallback layout.
- AHolyC classes are packed. Kernel records should therefore be decoded using
  explicit byte offsets or exact `$$` offsets, never assumed C padding.
- Windows must assert the complete find-data size and every field used by the
  implementation.

## Operation algorithms

### Listing

1. Open the directory handle once.
2. Ask the OS to fill caller scratch directly.
3. Walk records in place and return borrowed name/type views.
4. Refill only when the current batch is exhausted.
5. Preserve EOF separately from the native negative error.

There is no path concatenation, name copy, metadata syscall for a known entry
type, or heap activity on this path.

### Existence and metadata

- Keep `PathExists`, `FileExists`, and `DirIsDir`/`IsDir` semantically
  distinct.
- On Unix, prefer `openat(..., O_DIRECTORY)` plus `close` when only directory
  usability is required. Use `statx`/`fstatat64` only when metadata or
  follow/no-follow classification is required.
- Expose follow/no-follow as an explicit flag in the metadata primitive.
- Map Windows attributes and portable `DT_*` types without pretending that
  POSIX mode bits are TempleOS `RS_ATTR_*` values.

### Creation

- Nonrecursive creation is one `mkdirat(AT_FDCWD, path, 0x1ff)` or the Win32
  equivalent.
- Recursive POSIX creation walks components relative to a directory handle.
  It copies only the current component into one reusable `NAME_MAX + 1`
  scratch area because `mkdirat` requires a NUL-terminated name.
- POSIX accepts only `/` as a separator. A backslash is a valid filename byte.
- Windows copies the root path once into caller workspace, recognizes drive,
  UNC, and device roots, and temporarily terminates each prefix in place.
- `DirCreate(path, TRUE)` keeps modern mkdir-p semantics. TempleOS `DirMk`
  remains a different, nonrecursive API whose existing-directory result is
  `FALSE`.

### Recursive removal

Unix removal is postorder and descriptor-relative:

1. Open the requested root without following a final symlink. A root symlink
   is unlinked as a leaf.
2. Enumerate a directory by descriptor.
3. Use `d_type` for the fast path. For `DT_UNKNOWN`, attempt a no-follow
   directory open or no-follow metadata check.
4. Descend only through a verified directory handle.
5. Remove files/symlinks with `unlinkat(parent_fd, name, 0)` and directories
   with `unlinkat(parent_fd, name, AT_REMOVEDIR)`.
6. On any error, unwind and close every live handle while retaining the first
   operation error and any cleanup error.

One independent enumeration state is required per live depth; reusing one
buffer would overwrite the parent’s unread batch. The caller therefore passes
a traversal workspace containing frames and buffer arena. Exhaustion returns a
specific `DIR_ERROR_WORKSPACE`/required-size result. The implementation must
not switch to heap allocation, enormous zeroed locals, or unsafe path-based
recursion.

Windows uses per-level find handles/data, a single caller-owned mutable path,
and append/restore lengths. Entries with `FILE_ATTRIBUTE_REPARSE_POINT` are
deleted as leaves and never traversed. A later Unicode/long-path phase may use
wide APIs with caller-provided conversion storage; it must not hide converted
heap strings.

## HolyC and TempleOS compatibility boundary

TempleOS has no public streaming `DirOpen`/`DirNext`/`DirClose` API. Those are
AHolyC extensions. Its main directory APIs are declared in
[`KernelC.HH`](third_party/TempleOS/Kernel/KernelC.HH), and many deliberately
return owned allocations. Compatibility must be stated per API:

| API | Plan |
|---|---|
| `DirMk(path, entry_cnt=0)` | Add a heap-free wrapper with TempleOS’s nonrecursive semantics. Existing directory returns `FALSE`; ignore and document the filesystem-specific preallocation hint. |
| `IsDir(path)` | Add as a heap-free directory check; do not use it as generic path existence. |
| `FilesFindMatch(name, mask, flags=0)` | Reimplement without allocation using slices. Support `*`, `?`, semicolon alternatives, and `!` exclusions before claiming compatibility. |
| `Del(mask, make_mask=FALSE, del_dir=FALSE, print_msg=TRUE)` | Implement as nonrecursive streaming wildcard deletion returning the TempleOS count. Do not alias it to `DirRemove(path, force)`. |
| `DelTree(mask, fu_flags=NULL)` | Implement observable postorder deletion over the safe traversal core and explicit workspace. Never follow hosted symlinks. |
| `FileFind(name, NULL, flags)` | The boolean-only form can be heap-free, including dir/file filters. Add a separate caller-buffer metadata form. |
| `FileFind(name, &entry, flags)` | Not exactly compatible in the strict core because TempleOS allocates `entry.full_name`. Do not fake ownership or return a short-lived pointer. |
| `Dir(mask="*", full=FALSE)` | Streaming printing and the return count are possible. Exact TempleOS ordering requires caller sort storage or repeated scans; document the selected policy before exposing the name. |
| `FilesFind(mask, flags=0)` | Exclude from the strict core. TempleOS eagerly allocates a sorted linked tree and absolute `full_name` for each node, then requires `DirEntryDel*`/`DirTreeDel*`. The exact signature and arbitrary lifetime cannot be heap-free. |
| `DirEntryDel*` / `DirTreeDel*` | These free the in-memory `FilesFind` result; they never delete disk directories. Reserve the names for an optional owning compatibility module only. |
| `DirCur`, `DirNameAbs`, `FileNameAbs`, `DirFile` | Exact forms return new allocated strings. Provide `...To(buffer, capacity, ...)` core alternatives instead. |
| `DirContextNew` / `DirContextDel` | Exact form allocates a context and saved paths. Provide caller-owned context init/fini functions instead. |
| Runtime `Cd` | Keep outside the minimal core. TempleOS cwd is per task, hosted `chdir` is process-wide, and AHolyC already consumes constant top-level `Cd(...)` as a compile-time virtual-cwd directive. |

Define compatible `FUF_*`, `FUf_*`, `FUG_*`, `RS_ATTR_DIR`, and `DT_*`
constants where source compatibility benefits, but reject unsupported flags
instead of silently inventing cluster ordering or RedSea metadata. Hosted
names may exceed TempleOS’s 37-byte `CDirEntry.name` payload.

The bundled holyc-lang API is a second compatibility reference, not the same
contract. Its raw `opendir` signature provides no caller storage and therefore
does not belong in the strict core. `MkDir(path, mode, recurse)` can be a thin
wrapper after semantics are tested. Its allocating/sorting `Dir` and current
path-building recursive remove implementation should not be copied.

Recommended file boundary:

| File | Responsibility |
|---|---|
| `lib/io/dir.hc` | Strict heap-free views, iterators, metadata, create/remove primitives, and workspaces. |
| `lib/io/dir_native_*.hc` | Explicit Linux, Darwin, BSD, and Windows ABI adapters selected by platform macros. |
| `lib/io/dir_temple.hc` | Heap-free compatible constants, masks, `DirMk`, `IsDir`, boolean `FileFind`, `Del`, and `DelTree`. |
| `lib/io/dir_temple_alloc.hc` | Optional, separately included owning compatibility for `FilesFind` and allocated path APIs, only if exact allocation compatibility is later approved. The strict core never depends on it. |

## Implementation phases and gates

### Phase 0 — freeze contracts and make tests real

- Decide the three open questions at the end of this document.
- Fix the `tests/io_dir.HC` entrypoint before using it as evidence.
- Record current API semantics, error/lifetime rules, supported targets, and
  deliberately unsupported backends.
- Add compile-time ABI size/offset checks for every native record.
- Capture a performance baseline from the current libc iterator and a small C
  native reference.

Gate: tests demonstrably execute and fail when an assertion is inverted.

### Phase 1 — remove syscall-layer copies

- Refactor `Syscall1` through `Syscall6` to address named parameters directly.
- Test return/error normalization and all arities on C and LLVM backends.
- Inspect generated code to ensure `arguments[]` clears/copies are gone.

Gate: directory code can use a fixed-arity syscall without an avoidable local
argument array.

### Phase 2 — iterator and error model

- Implement small caller-scratch iterator state and `CDirEntryView`.
- Implement Linux first, then current macOS, with strict record validation.
- Add `DirNextEx` tri-state behavior and compatibility wrappers.
- Prove descriptor 0 works and close/cancellation paths release resources.

Gate: zero allocator calls, zero name/path copies per entry, correct multi-refill
listing, and EOF distinguishable from error.

### Phase 3 — safe metadata, create, and remove

- Add explicit follow/no-follow metadata primitives.
- Implement nonrecursive and component-wise creation with correct mode/root
  parsing.
- Implement postorder descriptor-relative removal with caller workspace.
- Preserve an external-directory sentinel through root and nested symlink
  deletion tests and symlink-swap race tests.

Gate: no full path is constructed for a POSIX child and no link/reparse point
is traversed.

### Phase 4 — Windows backend

- Replace the undersized find-data class and assert its ABI.
- Implement independent iterator state, reparse-point-safe removal, and one
  append/restore path workspace.
- Test drive roots, UNC roots, device prefixes, maximum names, deep trees, and
  handle cleanup. Add wide/long-path support only with explicit caller scratch.

Gate: no 32 KiB local exists per recursion level and no find API can overwrite
the modeled structure.

### Phase 5 — Darwin release policy and BSD adapters

- Decide whether Darwin direct syscalls are opt-in or the tested default.
- Validate a public caller-buffered Darwin fallback if long-lived Apple ABI
  stability is required.
- Add FreeBSD/OpenBSD/NetBSD low-level libc adapters one at a time with native
  ABI tests and allocator trapping. Do not copy syscall numbers into
  `lib/syscall` as a shortcut.

Gate: every advertised target has native CI evidence; otherwise it remains a
clear compile-time unsupported target.

### Phase 6 — compatibility layer

- Add `DT_*` and the portable TempleOS constants first.
- Implement allocation-free mask matching.
- Add `DirMk`, `IsDir`, boolean `FileFind`, `Del`, and workspace-driven
  `DelTree`, preserving their distinct defaults and return values.
- Compile representative bundled TempleOS examples for the supported subset.
- Keep allocated result-tree/path/context APIs out of the strict header.

Gate: the compatibility table above is converted into executable conformance
tests, with every intentional deviation documented.

### Phase 7 — documentation and stabilization

- Replace the premature README guarantees with the measured support matrix.
- Document buffer lifetime, workspace sizing, error handling, cancellation,
  symlink policy, and concurrency.
- Run sanitizer, allocation-trap, descriptor-leak, and performance suites.

Gate: all definition-of-done checks below pass.

## Test and benchmark plan

### Correctness and safety

- Empty, one-entry, dotfile, spaces, non-ASCII bytes, maximum-length names,
  and thousands of entries crossing many refills.
- Two simultaneous iterators, nested callbacks, multiple threads, callback
  cancellation, idempotent close, descriptor 0, and error after partial reads.
- Synthetic truncated records, zero/oversized record length, missing NUL,
  invalid name length, inode zero, and `DT_UNKNOWN`.
- Relative/absolute creation, repeated/trailing separators, existing directory,
  file collision, umask behavior, and all Windows root forms.
- Empty/nonempty, wide/deep trees; broken links; links to an external sentinel;
  root links; FIFOs/sockets; permission failures; concurrent rename/link swaps;
  insufficient depth and scratch workspaces.
- TempleOS masks with positive alternatives, exclusions, recurse/type flags,
  counts, and the semantic distinction among `Del`, `DelTree`, `DirTreeDel`,
  `DirMk`, and `DirCreate`.

### Heap and memory traffic

- Interpose/count allocators around each core operation; the required count and
  allocated bytes are zero.
- Inspect generated C/LLVM call graphs for `MAlloc`, `malloc`, `opendir`,
  `fdopendir`, formatting allocators, and hidden convenience fallbacks.
- Inspect generated code for large local clears. Record bytes cleared/copied
  per open, entry, component, and recursion depth.
- Record peak caller workspace and peak call stack separately.

### Performance

Compare the current libc implementation, a small native C reference, and each
new backend using 0, 1, 16, 256, 4K, and 100K entries; short and near-maximum
names; flat-wide and deep trees; warm and cold caches.

Record:

- nanoseconds per entry and entries per second;
- syscalls per entry and buffer refill count;
- allocator calls/bytes, which must remain zero;
- bytes cleared/copied;
- peak stack/workspace per depth;
- open handles after success, cancellation, and error.

Timing is informational in shared CI. Structural properties—zero allocations,
bounded copies, valid record parsing, safe links, and complete cleanup—are hard
gates.

Target coverage: Linux x86-64 C/LLVM; Linux arm64 and riscv64 natively or under
QEMU; macOS arm64 and x86-64; Windows x86-64 then arm64; each retained BSD on
native CI. Add negative compile tests for JS and `-fno-asm` unless an explicit
fallback is implemented.

## Definition of done

- The strict core has no allocator call path and does not use an opaque
  allocating directory iterator.
- Flat enumeration exposes kernel/Win32 names without copying or constructing
  full paths.
- Syscall wrappers used by the core do not build redundant argument arrays.
- EOF, cancellation, malformed data, OS errors, insufficient buffer, and
  insufficient traversal workspace are distinguishable.
- POSIX removal is descriptor-relative and no-follow; Windows removal never
  enters a reparse point.
- Recursive resource use is caller-bounded and failure closes every handle.
- `0x1ff` creation mode and platform root/separator rules are tested.
- Every advertised platform has record-layout assertions and native evidence.
- The README describes only guarantees proven by tests.
- Each exposed HolyC-compatible name matches its documented defaults,
  ownership, return value, and mask behavior, or is explicitly labeled a
  hosted deviation.

## Required review lenses

| Reviewer expertise | Required sign-off |
|---|---|
| Kernel/ABI | Syscall arity/numbers, flags, record layouts, error convention, Darwin/BSD policy. |
| Filesystem security | No-follow traversal, replacement races, partial-failure cleanup, Windows reparse behavior. |
| HolyC compatibility | TempleOS signatures/defaults/ownership, mask grammar, counts, and compile-time versus runtime `Cd`. |
| Performance/compiler backend | Generated clears/copies, syscall wrapper codegen, buffer sizes, stack/workspace measurements. |

## Three decisions to confirm

1. Does “TempleOS compatible” mean a strict heap-free source-compatible subset,
   or must it include the exact owning `FilesFind`/allocated-path contracts?
   Recommendation: keep the core and `dir_temple.hc` heap-free, and defer the
   optional allocator-backed module so the main library has no heap dependency.
2. May recursive operations require caller-provided frame/buffer workspace?
   Recommendation: yes. Return an exact workspace/depth error instead of using
   an arbitrary hidden depth limit, a large zeroed stack object, or the heap.
3. Should Darwin/BSD prioritize direct syscalls or stable public ABI?
   Recommendation: use direct syscalls by default only for tested Linux;
   isolate Darwin raw calls behind a policy switch, and use verified
   caller-buffered libc adapters for BSD and long-lived Apple support.
