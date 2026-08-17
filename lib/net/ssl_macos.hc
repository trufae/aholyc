#ifndef AHOLYC_LIB_SSL_MACOS_HC
#define AHOLYC_LIB_SSL_MACOS_HC

// dlopen/dlsym are part of libSystem on macOS; no link flag is needed.

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
  ssl_crypto_library =
    SslLibraryOpen("/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library =
      SslLibraryOpen("/usr/local/opt/openssl@3/lib/libcrypto.3.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library =
      SslLibraryOpen("/opt/local/libexec/openssl3/lib/libcrypto.3.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library =
      SslLibraryOpen("/opt/homebrew/lib/libcrypto.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library =
      SslLibraryOpen("/usr/local/lib/libcrypto.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("/opt/local/lib/libcrypto.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto.3.dylib");
  if (!ssl_crypto_library)
    ssl_crypto_library = SslLibraryOpen("libcrypto.dylib");

  ssl_library =
    SslLibraryOpen("/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib");
  if (!ssl_library)
    ssl_library =
      SslLibraryOpen("/usr/local/opt/openssl@3/lib/libssl.3.dylib");
  if (!ssl_library)
    ssl_library =
      SslLibraryOpen("/opt/local/libexec/openssl3/lib/libssl.3.dylib");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("/opt/homebrew/lib/libssl.dylib");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("/usr/local/lib/libssl.dylib");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("/opt/local/lib/libssl.dylib");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl.3.dylib");
  if (!ssl_library)
    ssl_library = SslLibraryOpen("libssl.dylib");
}

#endif
