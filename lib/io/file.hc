#ifndef AHOLYC_LIB_IO_FILE_HC
#define AHOLYC_LIB_IO_FILE_HC

// Whole-file reads and writes on top of the C runtime's stdio, which every
// native backend links on Unix and Windows. Binary safe: sizes are explicit
// and FileRead NUL-terminates the returned buffer for text callers.
//
//   I64 size;
//   U8 *data = FileRead("image.png", &size);
//   if (data)
//     FileWrite("copy.png", data, size);
//   Free(data);

extern U8 *fopen(U8 *path, U8 *mode);
extern I64 fread(U8 *data, I64 size, I64 count, U8 *stream);
extern I64 fwrite(U8 *data, I64 size, I64 count, U8 *stream);
extern I64 fseek(U8 *stream, I64 offset, I64 whence);
extern I64 ftell(U8 *stream);
extern I64 fclose(U8 *stream);

#define FILE_SEEK_SET 0
#define FILE_SEEK_END 2

// Read a whole file into a new heap buffer (plus a trailing NUL). Returns
// NULL when the file cannot be opened or read.
U8 *FileRead(U8 *path, I64 *size=NULL)
{
  U8 *stream;
  U8 *data = NULL;
  I64 length;

  if (size)
    *size = 0;
  if (!path)
    return NULL;
  stream = fopen(path, "rb");
  if (!stream)
    return NULL;
  if (!fseek(stream, 0, FILE_SEEK_END)(I32)) {
    #ifdef IS_WINDOWS
    length = ftell(stream)(I32);  // long is 32-bit on Windows
    #else
    length = ftell(stream);
    #endif
    if (length >= 0 && !fseek(stream, 0, FILE_SEEK_SET)(I32)) {
      data = MAlloc(length + 1);
      if (fread(data, 1, length, stream) == length) {
        data[length] = 0;
        if (size)
          *size = length;
      } else {
        Free(data);
        data = NULL;
      }
    }
  }
  fclose(stream);
  return data;
}

// Create or truncate path and write size bytes; size=-1 writes a C string.
Bool FileWrite(U8 *path, U8 *data, I64 size=-1)
{
  U8 *stream;
  Bool ok;

  if (!path || !data)
    return FALSE;
  if (size < 0)
    size = StrLen(data);
  stream = fopen(path, "wb");
  if (!stream)
    return FALSE;
  ok = fwrite(data, 1, size, stream) == size;
  return !fclose(stream)(I32) && ok;
}

Bool FileExists(U8 *path)
{
  U8 *stream;

  if (!path)
    return FALSE;
  stream = fopen(path, "rb");
  if (!stream)
    return FALSE;
  fclose(stream);
  return TRUE;
}

#endif
