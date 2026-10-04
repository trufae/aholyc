#ifndef AHOLYC_LIB_IO_DIR_HC
#define AHOLYC_LIB_IO_DIR_HC

// Heap-free directory I/O over raw kernel records.
//
// The kernel (getdents64 on Linux, getdirentries64 on Darwin) or Win32
// (FindFirstFile/FindNextFile) fills caller-owned storage and entries are
// borrowed views into it: nothing here allocates, copies entry names, or
// builds full paths while listing. Every primitive returns 0 or a negative
// native error (-errno, or -GetLastError() on Windows) and DirRead returns
// 1 for an entry, 0 at the end of the directory, so end, error, and
// cancellation never blur into one another.
//
//   CDirBuf dir;                       // CDir plus DIR_BUFFER_SIZE bytes
//   CDirEntry entry;
//   if (DirOpen(&dir, "assets")) {
//     while (DirRead(&dir, &entry) > 0)
//       "%s%s\n", entry.name, entry.type == DIR_TYPE_DIR ? "/" : "";
//     DirClose(&dir);
//   }
//
// DirOpenBuf(&dir, path, scratch, size) lists into any caller buffer of at
// least DIR_SCRATCH_MIN bytes and never clears it. A view stays valid until
// the DirRead that refills the scratch, DirRewind, or DirClose; the path is
// borrowed for the life of the CDir. DirCreate(path, TRUE) is mkdir -p and
// DirRemove(path, TRUE) is rm -rf: POSIX removal walks by descriptor with
// O_NOFOLLOW and Windows removal deletes reparse points as leaves, so a link
// inside the tree can never lead outside it. DirCreateEx/DirRemoveEx return
// the native error the Bool wrappers hide.
//
// Backends: Linux (x86-64, arm64, riscv64) and Darwin call the kernel
// through lib/syscall when HAS_ASM is defined; with -fno-asm, or when
// DIR_LIBC is defined, the same calls go through libc's thin stubs. Windows
// uses the stable Win32 find/create/delete APIs. DIR_WINDOWS and DIR_POSIX
// override the compiler host for cross builds. The BSDs need per-kernel
// record adapters (doc/rfc/dir.md) and are rejected rather than guessed.

#ifdef DIR_WINDOWS
#ifdef DIR_POSIX
#error define only one of DIR_WINDOWS or DIR_POSIX
#endif
#else
#ifndef DIR_POSIX
#ifdef IS_WINDOWS
#define DIR_WINDOWS 1
#else
#ifdef IS_UNIX
#define DIR_POSIX 1
#else
#error lib/io/dir supports Linux, macOS, and Windows native targets
#endif
#endif
#endif
#endif

#ifdef DIR_POSIX
#ifndef IS_LINUX
#ifndef IS_DARWIN
#error lib/io/dir has record adapters for Linux and Darwin only (doc/rfc/dir.md)
#endif
#endif
#ifndef DIR_LIBC
#ifdef HAS_ASM
#ifdef IS_X86_64
#define DIR_SYSCALL 1
#endif
#ifdef IS_ARM_64
#define DIR_SYSCALL 1
#endif
#ifdef IS_RISCV
#define DIR_SYSCALL 1
#endif
#endif
#ifndef DIR_SYSCALL
#define DIR_LIBC 1
#endif
#endif
#endif

#define DIR_INVALID_HANDLE (-1)
#ifndef DIR_BUFFER_SIZE
#define DIR_BUFFER_SIZE 4096
#endif
#define DIR_SCRATCH_MIN 2048 // holds the largest native record everywhere
#define DIR_NAME_MAX 255
#define DIR_PATH_CAPACITY 4096 // Windows path workspace for create/remove

// Entry types use the POSIX d_type values on every backend.
#define DIR_TYPE_UNKNOWN 0
#define DIR_TYPE_FIFO 1
#define DIR_TYPE_CHAR 2
#define DIR_TYPE_DIR 4
#define DIR_TYPE_BLOCK 6
#define DIR_TYPE_FILE 8
#define DIR_TYPE_LINK 10
#define DIR_TYPE_SOCKET 12
#define DIR_TYPE_WHITEOUT 14

// Named native errors for the outcomes callers commonly branch on.
#ifdef DIR_WINDOWS
#define DIR_ERROR_INVALID (-87)    // ERROR_INVALID_PARAMETER
#define DIR_ERROR_NOT_FOUND (-2)   // ERROR_FILE_NOT_FOUND; -3 is PATH_NOT_FOUND
#define DIR_ERROR_EXISTS (-183)    // ERROR_ALREADY_EXISTS
#define DIR_ERROR_NOT_DIR (-267)   // ERROR_DIRECTORY
#define DIR_ERROR_NOT_EMPTY (-145) // ERROR_DIR_NOT_EMPTY
#define DIR_ERROR_CLOSED (-6)      // ERROR_INVALID_HANDLE
#define DIR_ERROR_TOO_LONG (-206)  // ERROR_FILENAME_EXCED_RANGE
#define DIR_ERROR_RECORD (-13)     // ERROR_INVALID_DATA
#else
#define DIR_ERROR_INVALID (-22)    // EINVAL
#define DIR_ERROR_NOT_FOUND (-2)   // ENOENT
#define DIR_ERROR_EXISTS (-17)     // EEXIST
#define DIR_ERROR_NOT_DIR (-20)    // ENOTDIR
#define DIR_ERROR_CLOSED (-9)      // EBADF
#ifdef IS_DARWIN
#define DIR_ERROR_NOT_EMPTY (-66)  // ENOTEMPTY
#define DIR_ERROR_TOO_LONG (-63)   // ENAMETOOLONG
#define DIR_ERROR_RECORD (-94)     // EBADMSG
#else
#define DIR_ERROR_NOT_EMPTY (-39)
#define DIR_ERROR_TOO_LONG (-36)
#define DIR_ERROR_RECORD (-74)
#endif
#endif

class CDirEntry
{
  U8 *name;        // borrowed NUL-terminated view
  I64 name_length;
  I64 type;        // DIR_TYPE_*
  I64 inode;       // 0 where the backend has none (Windows)
};

#ifdef DIR_WINDOWS
// WIN32_FIND_DATAA is 320 bytes on x64 and FindFirstFileA writes all of it,
// including the alternate-name tail after cFileName.
class CDirFindData
{
  U32 attributes;
  $$ = 28;
  U32 size_high;
  U32 size_low;
  U32 reparse_tag;
  $$ = 44;
  U8 name[260];
  U8 alternate[14];
  $$ = 320;
};
#endif

class CDir
{
  I64 handle;       // descriptor or Win32 HANDLE; DIR_INVALID_HANDLE when closed
  I64 error;        // last negative error, 0 otherwise
  U8 *path;         // borrowed from DirOpenBuf
  U8 *scratch;      // caller-owned; never cleared here
  I64 scratch_size;
  I64 cursor;       // next unread byte (POSIX); first result consumed (Windows)
  I64 end;          // valid bytes in scratch
  I64 position;     // Darwin getdirentries64 base offset
  I64 eof;
  #ifdef DIR_WINDOWS
  CDirFindData find;
  #endif
};

class CDirBuf : CDir
{
  U8 buffer[DIR_BUFFER_SIZE];
};

Bool DirNameIsSpecial(U8 *name)
{
  return name[0] == '.' && (!name[1] || (name[1] == '.' && !name[2]));
}

I64 DirNameLength(U8 *name, I64 limit)
{
  I64 length = 0;

  while (length < limit && name[length])
    length++;
  return length;
}

U0 DirInit(CDir *dir, I64 handle, U8 *path, U8 *scratch, I64 scratch_size)
{
  dir->handle = handle;
  dir->error = 0;
  dir->path = path;
  dir->scratch = scratch;
  dir->scratch_size = scratch_size;
  dir->cursor = 0;
  dir->end = 0;
  dir->position = 0;
  dir->eof = FALSE;
}

#ifdef DIR_WINDOWS

#define DIR_WIN_ATTRIBUTE_DIRECTORY 0x10
#define DIR_WIN_ATTRIBUTE_NORMAL 0x80
#define DIR_WIN_ATTRIBUTE_REPARSE_POINT 0x400
#define DIR_WIN_INVALID_ATTRIBUTES 0xFFFFFFFF
#define DIR_WIN_ERROR_FILE_NOT_FOUND 2
#define DIR_WIN_ERROR_ACCESS_DENIED 5
#define DIR_WIN_ERROR_NO_MORE_FILES 18

extern I64 FindFirstFileA(U8 *pattern, CDirFindData *data);
extern I64 FindNextFileA(I64 handle, CDirFindData *data);
extern I64 FindClose(I64 handle);
extern I64 CreateDirectoryA(U8 *path, U0 *attributes);
extern I64 RemoveDirectoryA(U8 *path);
extern I64 DeleteFileA(U8 *path);
extern I64 SetFileAttributesA(U8 *path, U32 attributes);
extern U32 GetFileAttributesA(U8 *path);
extern U32 GetLastError();

I64 DirWinError()
{
  I64 error = GetLastError();

  if (!error)
    return DIR_ERROR_INVALID;
  return -error;
}

Bool DirIsSeparator(U8 c)
{
  return c == '/' || c == '\\';
}

// Write "path\*" into scratch, appending in place when path is the scratch.
I64 DirWinPattern(U8 *scratch, I64 capacity, U8 *path)
{
  I64 length = StrLen(path);

  if (length + 3 > capacity)
    return DIR_ERROR_TOO_LONG;
  if (path != scratch)
    MemCpy(scratch, path, length);
  if (length && !DirIsSeparator(scratch[length - 1]))
    scratch[length++] = '\\';
  scratch[length] = '*';
  scratch[length + 1] = 0;
  return 0;
}

I64 DirWinFindOpen(CDir *dir)
{
  U32 attributes = GetFileAttributesA(dir->path);
  I64 error;

  if (attributes == DIR_WIN_INVALID_ATTRIBUTES)
    return DirWinError();
  if (!(attributes & DIR_WIN_ATTRIBUTE_DIRECTORY))
    return DIR_ERROR_NOT_DIR;
  error = DirWinPattern(dir->scratch, dir->scratch_size, dir->path);
  if (error < 0)
    return error;
  dir->handle = FindFirstFileA(dir->scratch, &dir->find);
  if (dir->handle != DIR_INVALID_HANDLE)
    return 0;
  error = GetLastError();
  if (error == DIR_WIN_ERROR_FILE_NOT_FOUND) {
    dir->eof = TRUE; // a root directory without even dot entries
    return 0;
  }
  return -error;
}

#else

#ifdef IS_DARWIN
#define DIR_AT_FDCWD (-2)
#define DIR_AT_REMOVEDIR 0x80
#define DIR_O_DIRECTORY 0x100000
#define DIR_O_NOFOLLOW 0x100
#define DIR_O_CLOEXEC 0x1000000
#define DIR_RECORD_NAMELEN 18
#define DIR_RECORD_TYPE 20
#define DIR_RECORD_NAME 21
#else
#define DIR_AT_FDCWD (-100)
#define DIR_AT_REMOVEDIR 0x200
#define DIR_O_CLOEXEC 0x80000
// arm kernels keep their historical open flags; x86-64, riscv64, s390x and
// mips use the asm-generic values.
#ifdef IS_ARM_64
#define DIR_O_DIRECTORY 0x4000
#define DIR_O_NOFOLLOW 0x8000
#else
#ifdef IS_ARM_32
#define DIR_O_DIRECTORY 0x4000
#define DIR_O_NOFOLLOW 0x8000
#else
#define DIR_O_DIRECTORY 0x10000
#define DIR_O_NOFOLLOW 0x20000
#endif
#endif
#define DIR_RECORD_TYPE 18
#define DIR_RECORD_NAME 19
#endif
#define DIR_RECORD_RECLEN 16
#define DIR_OPEN_FLAGS (DIR_O_DIRECTORY | DIR_O_CLOEXEC)
#define DIR_OPEN_NOFOLLOW_FLAGS (DIR_O_DIRECTORY | DIR_O_NOFOLLOW | DIR_O_CLOEXEC)
#define DIR_MODE 0x1ff // rwxrwxrwx before umask; HolyC has no octal literals

#ifdef DIR_SYSCALL

#include "../syscall/syscall.hc"

I64 DirSysOpen(I64 directory, U8 *path, I64 flags)
{
  return Syscall3(SYS_openat, directory, path, flags);
}

I64 DirSysClose(I64 fd)
{
  return Syscall1(SYS_close, fd);
}

I64 DirSysRewind(I64 fd)
{
  return Syscall3(SYS_lseek, fd, 0, 0);
}

I64 DirSysMkdir(I64 directory, U8 *name)
{
  return Syscall3(SYS_mkdirat, directory, name, DIR_MODE);
}

I64 DirSysUnlink(I64 directory, U8 *name, I64 flags)
{
  return Syscall3(SYS_unlinkat, directory, name, flags);
}

I64 DirSysRead(CDir *dir)
{
  #ifdef IS_DARWIN
  return Syscall4(SYS_getdirentries64, dir->handle, dir->scratch,
    dir->scratch_size, &dir->position);
  #else
  return Syscall3(SYS_getdents64, dir->handle, dir->scratch,
    dir->scratch_size);
  #endif
}

#else

// libc's stubs for the same kernel calls; int results are narrowed before
// the sign test because extern returns are widened to 64 bits.
extern I64 openat(I64 directory, U8 *path, I64 flags);
extern I64 close(I64 fd);
extern I64 lseek(I64 fd, I64 offset, I64 whence);
extern I64 mkdirat(I64 directory, U8 *path, I64 mode);
extern I64 unlinkat(I64 directory, U8 *path, I64 flags);
#ifdef IS_DARWIN
extern I32 *__error();
extern I64 __getdirentries64(I64 fd, U8 *buffer, I64 size, I64 *base);
#else
extern I32 *__errno_location();
extern I64 getdents64(I64 fd, U8 *buffer, I64 size);
#endif

I64 DirLibcErrno()
{
  #ifdef IS_DARWIN
  return -(*__error());
  #else
  return -(*__errno_location());
  #endif
}

I64 DirLibcInt(I64 result)
{
  if (result(I32) < 0)
    return DirLibcErrno();
  return result(I32);
}

I64 DirSysOpen(I64 directory, U8 *path, I64 flags)
{
  return DirLibcInt(openat(directory, path, flags));
}

I64 DirSysClose(I64 fd)
{
  return DirLibcInt(close(fd));
}

I64 DirSysRewind(I64 fd)
{
  if (lseek(fd, 0, 0) < 0)
    return DirLibcErrno();
  return 0;
}

I64 DirSysMkdir(I64 directory, U8 *name)
{
  return DirLibcInt(mkdirat(directory, name, DIR_MODE));
}

I64 DirSysUnlink(I64 directory, U8 *name, I64 flags)
{
  return DirLibcInt(unlinkat(directory, name, flags));
}

I64 DirSysRead(CDir *dir)
{
  I64 result;

  #ifdef IS_DARWIN
  result = __getdirentries64(dir->handle, dir->scratch, dir->scratch_size,
    &dir->position);
  #else
  result = getdents64(dir->handle, dir->scratch, dir->scratch_size);
  #endif
  if (result < 0)
    return DirLibcErrno();
  return result;
}

#endif
#endif

// Open path for listing into caller scratch. Returns 0 or a negative error.
I64 DirOpenBuf(CDir *dir, U8 *path, U8 *scratch, I64 scratch_size)
{
  I64 result;

  if (!dir)
    return DIR_ERROR_INVALID;
  DirInit(dir, DIR_INVALID_HANDLE, path, scratch, scratch_size);
  if (!path || !path[0] || !scratch || scratch_size < DIR_SCRATCH_MIN) {
    dir->error = DIR_ERROR_INVALID;
    return dir->error;
  }
  #ifdef DIR_WINDOWS
  result = DirWinFindOpen(dir);
  #else
  result = DirSysOpen(DIR_AT_FDCWD, path, DIR_OPEN_FLAGS);
  if (result >= 0) {
    dir->handle = result;
    result = 0;
  }
  #endif
  if (result < 0)
    dir->error = result;
  return result;
}

// Convenience form using the buffer embedded in a CDirBuf.
Bool DirOpen(CDirBuf *dir, U8 *path)
{
  if (!dir)
    return FALSE;
  return !DirOpenBuf(dir, path, dir->buffer, DIR_BUFFER_SIZE);
}

// Next entry other than "." and "..": 1 with entry filled, 0 at the end of
// the directory, or a negative error (also kept in dir->error).
I64 DirRead(CDir *dir, CDirEntry *entry)
{
  I64 result;

  if (!dir || !entry)
    return DIR_ERROR_INVALID;
  #ifdef DIR_WINDOWS
  if (dir->eof)
    return 0;
  if (dir->handle == DIR_INVALID_HANDLE) {
    dir->error = DIR_ERROR_CLOSED;
    return dir->error;
  }
  while (TRUE) {
    if (dir->cursor) {
      if (!FindNextFileA(dir->handle, &dir->find)(I32)) {
        result = GetLastError();
        if (result == DIR_WIN_ERROR_NO_MORE_FILES) {
          dir->eof = TRUE;
          return 0;
        }
        dir->error = -result;
        return dir->error;
      }
    } else
      dir->cursor = 1;
    if (!DirNameIsSpecial(dir->find.name)) {
      entry->name = dir->find.name;
      entry->name_length = DirNameLength(dir->find.name,
        sizeof(dir->find.name));
      if (dir->find.attributes & DIR_WIN_ATTRIBUTE_REPARSE_POINT)
        entry->type = DIR_TYPE_LINK;
      else if (dir->find.attributes & DIR_WIN_ATTRIBUTE_DIRECTORY)
        entry->type = DIR_TYPE_DIR;
      else
        entry->type = DIR_TYPE_FILE;
      entry->inode = 0;
      return 1;
    }
  }
  #else
  U8 *record;
  I64 limit, reclen, length;

  if (dir->handle == DIR_INVALID_HANDLE) {
    dir->error = DIR_ERROR_CLOSED;
    return dir->error;
  }
  while (TRUE) {
    if (dir->cursor >= dir->end) {
      // The end flag only applies once the buffered records are consumed.
      if (dir->eof)
        return 0;
      result = DirSysRead(dir);
      if (result <= 0) {
        if (result < 0)
          dir->error = result;
        else
          dir->eof = TRUE;
        return result;
      }
      dir->cursor = 0;
      dir->end = result;
      #ifdef IS_DARWIN
      // Given at least 1 KiB the kernel keeps the final four bytes for
      // flags; bit 0 announces the end and saves the closing call.
      if (dir->scratch[dir->scratch_size - 4] & 1)
        dir->eof = TRUE;
      #endif
    }
    record = dir->scratch + dir->cursor;
    limit = dir->end - dir->cursor;
    if (limit <= DIR_RECORD_NAME) {
      dir->error = DIR_ERROR_RECORD;
      return dir->error;
    }
    reclen = record[DIR_RECORD_RECLEN] | (record[DIR_RECORD_RECLEN + 1] << 8);
    if (reclen <= DIR_RECORD_NAME || reclen > limit) {
      dir->error = DIR_ERROR_RECORD;
      return dir->error;
    }
    dir->cursor += reclen;
    #ifdef IS_DARWIN
    length = record[DIR_RECORD_NAMELEN] | (record[DIR_RECORD_NAMELEN + 1] << 8);
    if (DIR_RECORD_NAME + length >= reclen || record[DIR_RECORD_NAME + length]) {
      dir->error = DIR_ERROR_RECORD;
      return dir->error;
    }
    #else
    length = DirNameLength(record + DIR_RECORD_NAME, reclen - DIR_RECORD_NAME);
    if (length >= reclen - DIR_RECORD_NAME) {
      dir->error = DIR_ERROR_RECORD;
      return dir->error;
    }
    #endif
    MemCpy(&entry->inode, record, 8);
    if (entry->inode && !DirNameIsSpecial(record + DIR_RECORD_NAME)) {
      entry->name = record + DIR_RECORD_NAME;
      entry->name_length = length;
      entry->type = record[DIR_RECORD_TYPE];
      return 1;
    }
  }
  #endif
}

// Name of the next entry, or NULL at the end or on error (see dir->error).
U8 *DirNext(CDir *dir)
{
  CDirEntry entry;

  if (DirRead(dir, &entry) > 0)
    return entry.name;
  return NULL;
}

// Restart enumeration; every earlier view becomes invalid.
I64 DirRewind(CDir *dir)
{
  I64 result;

  if (!dir)
    return DIR_ERROR_INVALID;
  if (dir->handle == DIR_INVALID_HANDLE && !dir->eof) {
    dir->error = DIR_ERROR_CLOSED;
    return dir->error;
  }
  dir->cursor = 0;
  dir->end = 0;
  dir->position = 0;
  dir->eof = FALSE;
  #ifdef DIR_WINDOWS
  if (dir->handle != DIR_INVALID_HANDLE) {
    FindClose(dir->handle);
    dir->handle = DIR_INVALID_HANDLE;
  }
  result = DirWinFindOpen(dir);
  #else
  result = DirSysRewind(dir->handle);
  #endif
  if (result < 0)
    dir->error = result;
  return result;
}

// Release the handle. Idempotent; a close failure is still reported.
I64 DirClose(CDir *dir)
{
  I64 result = 0;

  if (!dir)
    return DIR_ERROR_INVALID;
  if (dir->handle != DIR_INVALID_HANDLE) {
    #ifdef DIR_WINDOWS
    if (!FindClose(dir->handle)(I32))
      result = DirWinError();
    #else
    result = DirSysClose(dir->handle);
    #endif
    dir->handle = DIR_INVALID_HANDLE;
  }
  dir->cursor = 0;
  dir->end = 0;
  dir->eof = FALSE;
  if (result < 0)
    dir->error = result;
  return result;
}

// TRUE when path names a directory the caller may open. Symbolic links to
// directories qualify. Metadata beyond that belongs to a stat API.
Bool DirIsDir(U8 *path)
{
  if (!path || !path[0])
    return FALSE;
  #ifdef DIR_WINDOWS
  U32 attributes = GetFileAttributesA(path);

  return attributes != DIR_WIN_INVALID_ATTRIBUTES &&
    (attributes & DIR_WIN_ATTRIBUTE_DIRECTORY) != 0;
  #else
  I64 fd = DirSysOpen(DIR_AT_FDCWD, path, DIR_OPEN_FLAGS);

  if (fd < 0)
    return FALSE;
  DirSysClose(fd);
  return TRUE;
  #endif
}

Bool DirExists(U8 *path)
{
  return DirIsDir(path);
}

// Visit every entry below path with borrowed path and entry views. Returns
// 1 after the last entry, 0 when the callback returned FALSE, or a negative
// error from open, read, or close.
I64 DirForEach(U8 *path,
  Bool (*callback)(U8 *path, CDirEntry *entry, U0 *user), U0 *user=NULL)
{
  CDirBuf dir;
  CDirEntry entry;
  I64 status = 1;
  I64 result;

  if (!callback)
    return DIR_ERROR_INVALID;
  result = DirOpenBuf(&dir, path, dir.buffer, DIR_BUFFER_SIZE);
  if (result < 0)
    return result;
  while (TRUE) {
    result = DirRead(&dir, &entry);
    if (result < 0) {
      status = result;
      break;
    }
    if (!result)
      break;
    if (!callback(path, &entry, user)) {
      status = 0;
      break;
    }
  }
  result = DirClose(&dir);
  if (result < 0 && status >= 0)
    status = result;
  return status;
}

#ifdef DIR_WINDOWS

I64 DirWinCreate(U8 *path)
{
  if (CreateDirectoryA(path, NULL)(I32))
    return 0;
  return DirWinError();
}

I64 DirWinRemove(U8 *path)
{
  if (RemoveDirectoryA(path)(I32))
    return 0;
  return DirWinError();
}

// Delete a file, clearing the read-only attribute if that is what refused.
I64 DirWinDelete(U8 *path)
{
  I64 error;

  if (DeleteFileA(path)(I32))
    return 0;
  error = DirWinError();
  if (error != -DIR_WIN_ERROR_ACCESS_DENIED)
    return error;
  if (!SetFileAttributesA(path, DIR_WIN_ATTRIBUTE_NORMAL)(I32) ||
    !DeleteFileA(path)(I32))
    return DirWinError();
  return 0;
}

// Bytes of root that DirCreate never tries to create: "X:", "\\server\share",
// "\\?\X:", "\\?\UNC\server\share" and the "\\.\" device form.
I64 DirWinRootLength(U8 *path, I64 length)
{
  I64 i = 0;
  I64 components = 0;

  if (length >= 2 && DirIsSeparator(path[0]) && DirIsSeparator(path[1])) {
    i = 2;
    components = 2;
    if (length >= 4 && (path[2] == '?' || path[2] == '.') &&
      DirIsSeparator(path[3])) {
        i = 4;
        components = 0;
        if (length >= 8 && (path[4] == 'U' || path[4] == 'u') &&
          (path[5] == 'N' || path[5] == 'n') &&
          (path[6] == 'C' || path[6] == 'c') && DirIsSeparator(path[7])) {
            i = 8;
            components = 2;
          } else if (length >= 6 && path[5] == ':')
          i = 6;
      }
  } else if (length >= 2 && path[1] == ':')
    i = 2;
  while (components > 0) {
    components--;
    while (i < length && DirIsSeparator(path[i]))
      i++;
    while (i < length && !DirIsSeparator(path[i]))
      i++;
  }
  return i;
}

// Create path; with recursive=TRUE also its missing parents, accepting
// components that already exist. The final path must end up a directory.
I64 DirCreateEx(U8 *path, Bool recursive=FALSE)
{
  U8 copy[DIR_PATH_CAPACITY];
  I64 length, i, start;
  I64 result = 0;

  if (!path || !path[0])
    return DIR_ERROR_INVALID;
  if (!recursive)
    return DirWinCreate(path);
  length = StrLen(path);
  if (length >= DIR_PATH_CAPACITY)
    return DIR_ERROR_TOO_LONG;
  MemCpy(copy, path, length + 1);
  start = DirWinRootLength(copy, length);
  for (i = start; i <= length; i++) {
    if (DirIsSeparator(copy[i]) || !copy[i]) {
      if (i > start && !(i - start == 1 && copy[start] == '.')) {
        copy[i] = 0;
        result = DirWinCreate(copy);
        copy[i] = path[i];
        if (result < 0 && result != DIR_ERROR_EXISTS)
          return result;
      }
      start = i + 1;
    }
  }
  if (result == DIR_ERROR_EXISTS && !DirIsDir(path))
    return result;
  return 0;
}

// Empty the directory whose path fills work[0..length). Child names are
// appended and restored in place; each level owns only its find state.
// Reparse points are removed as leaves and never entered.
I64 DirWinRemoveChildren(U8 *work, I64 length, I64 capacity)
{
  CDir dir;
  CDirEntry entry;
  I64 result, child;

  result = DirOpenBuf(&dir, work, work, capacity);
  work[length] = 0;
  if (result < 0)
    return result;
  while (TRUE) {
    result = DirRead(&dir, &entry);
    if (result <= 0)
      break;
    child = length + 1 + entry.name_length;
    if (child + 3 > capacity) {
      result = DIR_ERROR_TOO_LONG;
      break;
    }
    work[length] = '\\';
    MemCpy(work + length + 1, entry.name, entry.name_length + 1);
    if (entry.type == DIR_TYPE_DIR) {
      result = DirWinRemoveChildren(work, child, capacity);
      if (result >= 0)
        result = DirWinRemove(work);
    } else if (dir.find.attributes & DIR_WIN_ATTRIBUTE_DIRECTORY)
      result = DirWinRemove(work);
    else
      result = DirWinDelete(work);
    work[length] = 0;
    if (result < 0)
      break;
  }
  child = DirClose(&dir);
  if (child < 0 && result >= 0)
    result = child;
  return result;
}

// Remove an empty directory, or with force=TRUE everything below it first.
// A directory link or junction is removed itself, never its target.
I64 DirRemoveEx(U8 *path, Bool force=FALSE)
{
  U8 work[DIR_PATH_CAPACITY];
  I64 length, result;

  if (!path || !path[0])
    return DIR_ERROR_INVALID;
  result = DirWinRemove(path);
  if (!result || !force || result != DIR_ERROR_NOT_EMPTY)
    return result;
  length = StrLen(path);
  while (length > 1 && DirIsSeparator(path[length - 1]))
    length--;
  if (length + 3 >= DIR_PATH_CAPACITY)
    return DIR_ERROR_TOO_LONG;
  MemCpy(work, path, length);
  work[length] = 0;
  result = DirWinRemoveChildren(work, length, DIR_PATH_CAPACITY);
  if (result < 0)
    return result;
  return DirWinRemove(path);
}

#else

// Create path; with recursive=TRUE also its missing parents, accepting
// components that already exist. Components are created relative to the
// previous directory's descriptor, so only one name is ever copied.
I64 DirCreateEx(U8 *path, Bool recursive=FALSE)
{
  U8 name[DIR_NAME_MAX + 1];
  I64 directory = DIR_AT_FDCWD;
  I64 result = 0;
  I64 i = 0;
  I64 start, length, next;
  Bool last;

  if (!path || !path[0])
    return DIR_ERROR_INVALID;
  if (!recursive)
    return DirSysMkdir(DIR_AT_FDCWD, path);
  if (path[0] == '/') {
    directory = DirSysOpen(DIR_AT_FDCWD, "/", DIR_OPEN_FLAGS);
    if (directory < 0)
      return directory;
  }
  while (path[i]) {
    // Skip separators and lone "." components.
    while (path[i] == '/' ||
      (path[i] == '.' && (path[i + 1] == '/' || !path[i + 1])))
      i++;
    start = i;
    while (path[i] && path[i] != '/')
      i++;
    length = i - start;
    if (!length)
      break;
    if (length > DIR_NAME_MAX) {
      result = DIR_ERROR_TOO_LONG;
      break;
    }
    MemCpy(name, path + start, length);
    name[length] = 0;
    next = i;
    while (path[next] == '/')
      next++;
    last = !path[next];
    result = DirSysMkdir(directory, name);
    if (!result && last)
      break;
    if (result < 0 && result != DIR_ERROR_EXISTS)
      break;
    // Descend, which also verifies that an existing component is a directory.
    next = DirSysOpen(directory, name, DIR_OPEN_FLAGS);
    if (next < 0) {
      result = next;
      break;
    }
    if (directory != DIR_AT_FDCWD)
      DirSysClose(directory);
    directory = next;
    result = 0;
  }
  if (directory != DIR_AT_FDCWD)
    DirSysClose(directory);
  return result;
}

// Unlink everything below an open directory. Returns the number of unlinks
// and descents made at this level, so a caller can tell a directory that is
// still not empty from one that made no progress, or a negative error. One
// scratch serves every level: once a child has been emptied this level
// restarts, and the child, now empty, is unlinked on that pass.
// Subdirectories are opened with O_NOFOLLOW and their type comes from the
// record, so links are always unlinked as leaves.
I64 DirRemoveChildren(I64 directory, U8 *scratch, I64 scratch_size)
{
  CDir dir;
  CDirEntry entry;
  I64 result, child;
  I64 progress = 0;

  DirInit(&dir, directory, NULL, scratch, scratch_size);
  while (TRUE) {
    result = DirRead(&dir, &entry);
    if (result < 0)
      return result;
    if (!result)
      return progress;
    if (entry.type == DIR_TYPE_DIR || entry.type == DIR_TYPE_UNKNOWN) {
      result = DirSysUnlink(directory, entry.name, DIR_AT_REMOVEDIR);
      if (result == DIR_ERROR_NOT_DIR)
        result = DirSysUnlink(directory, entry.name, 0);
      else if (result == DIR_ERROR_NOT_EMPTY || result == DIR_ERROR_EXISTS) {
        child = DirSysOpen(directory, entry.name, DIR_OPEN_NOFOLLOW_FLAGS);
        if (child < 0)
          return child;
        result = DirRemoveChildren(child, scratch, scratch_size);
        DirSysClose(child);
        if (result < 0)
          return result;
        if (!result)
          return DIR_ERROR_NOT_EMPTY;
        // The child overwrote the scratch: restart this level.
        result = DirRewind(&dir);
      }
    } else
      result = DirSysUnlink(directory, entry.name, 0);
    if (result < 0)
      return result;
    progress++;
  }
}

// Remove an empty directory, or with force=TRUE everything below it first.
// A symbolic link is not a directory and is refused with DIR_ERROR_NOT_DIR.
I64 DirRemoveEx(U8 *path, Bool force=FALSE)
{
  U8 scratch[DIR_BUFFER_SIZE];
  I64 directory, progress, result;

  if (!path || !path[0])
    return DIR_ERROR_INVALID;
  result = DirSysUnlink(DIR_AT_FDCWD, path, DIR_AT_REMOVEDIR);
  if (!result || !force ||
    (result != DIR_ERROR_NOT_EMPTY && result != DIR_ERROR_EXISTS))
    return result;
  while (TRUE) {
    directory = DirSysOpen(DIR_AT_FDCWD, path, DIR_OPEN_NOFOLLOW_FLAGS);
    if (directory < 0)
      return directory;
    progress = DirRemoveChildren(directory, scratch, DIR_BUFFER_SIZE);
    DirSysClose(directory);
    if (progress < 0)
      return progress;
    result = DirSysUnlink(DIR_AT_FDCWD, path, DIR_AT_REMOVEDIR);
    if (!progress ||
      (result != DIR_ERROR_NOT_EMPTY && result != DIR_ERROR_EXISTS))
      return result;
  }
}

#endif

Bool DirCreate(U8 *path, Bool recursive=FALSE)
{
  return !DirCreateEx(path, recursive);
}

Bool DirRemove(U8 *path, Bool force=FALSE)
{
  return !DirRemoveEx(path, force);
}

#endif
