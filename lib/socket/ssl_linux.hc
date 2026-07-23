#ifndef AHOLYC_LIB_SSL_LINUX_LOADER_HC
#define AHOLYC_LIB_SSL_LINUX_LOADER_HC

// Linux keeps dlopen/dlsym in libdl on systems older than glibc 2.34.
// @ldflags=-ldl

extern U8 *dlopen(U8 *path, I64 mode);
extern U8 *dlsym(U8 *library, U8 *name);
extern I64 dlclose(U8 *library);

U8 *SslLibraryOpen(U8 *name)
{
  return dlopen(name, 2);
}

U8 *SslLibrarySymbol(U8 *library, U8 *name)
{
  return dlsym(library, name);
}

U0 SslLibraryClose(U8 *library)
{
  if (library)
    dlclose(library);
}

U0 SslOpenLibraries()
{
  ssl_crypto_library = SslLibraryOpen("libcrypto.so.3");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto.so.1.1");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto.so");

  ssl_library = SslLibraryOpen("libssl.so.3");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl.so.1.1");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl.so");
}

#endif
