#ifndef AHOLYC_LIB_SSL_WINDOWS_HC
#define AHOLYC_LIB_SSL_WINDOWS_HC

// kernel32 is always present; OpenSSL itself remains a runtime dependency.

extern U8 *LoadLibraryA(U8 *name);
extern U8 *GetProcAddress(U8 *library, U8 *name);
extern I64 FreeLibrary(U8 *library);

U8 *SslLibraryOpen(U8 *name)
{
  return LoadLibraryA(name);
}

U8 *SslLibrarySymbol(U8 *library, U8 *name)
{
  if (!library)
    return NULL;
  return GetProcAddress(library, name);
}

U0 SslLibraryClose(U8 *library)
{
  if (library)
    FreeLibrary(library);
}

U0 SslOpenLibraries()
{
  ssl_crypto_library = SslLibraryOpen("libcrypto-3-x64.dll");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto-3.dll");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto-1_1-x64.dll");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto-1_1.dll");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libeay32.dll");

  ssl_library = SslLibraryOpen("libssl-3-x64.dll");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl-3.dll");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl-1_1-x64.dll");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl-1_1.dll");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("ssleay32.dll");
}

#endif
