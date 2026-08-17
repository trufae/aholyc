#ifndef AHOLYC_LIB_SSL_HC
#define AHOLYC_LIB_SSL_HC

// OpenSSL client-side TLS loaded entirely at runtime.
//
// No OpenSSL import is linked into the executable.  SslInit tries common
// OpenSSL 3.x and 1.1 library names/locations, resolves the needed symbols,
// and returns FALSE when OpenSSL is unavailable.
//
// CSsl *tls = SslConnect(connected_socket, "example.com");
// SslWriteAll(tls, bytes, size);
// size = SslRead(tls, buffer, capacity);
// SslClose(tls);       // does not close the underlying socket
// SslFini();           // call after every CSsl has been closed
//
// SslSetCaLocations(file, directory) may be called before SslConnect when
// OpenSSL's compiled-in CA location is not suitable (commonly on Windows).

#define SSL_VERIFY_PEER             1
#define SSL_VERIFY_OK               0
#define SSL_ERROR_WANT_READ         2
#define SSL_ERROR_WANT_WRITE        3
#define SSL_ERROR_ZERO_RETURN       6
#define SSL_CTRL_SET_TLSEXT_HOSTNAME 55
#define SSL_CTRL_SET_MIN_PROTO_VERSION 123
#define SSL_TLSEXT_NAMETYPE_HOST_NAME 0
#define SSL_TLS1_2_VERSION 0x0303

class CSsl
{
  U8 *context;
  U8 *session;
  I64 socket;
};

U8 *ssl_library;
U8 *ssl_crypto_library;
U8 *ssl_ca_file;
U8 *ssl_ca_path;
I64 ssl_state;
U8 ssl_last_error[256];

#ifdef IS_WINDOWS
#include "ssl_windows.hc"
#else
#ifdef IS_MACOS
#include "ssl_macos.hc"
#else
#ifdef IS_LINUX
#include "ssl_linux.hc"
#endif
#endif
#endif

I64 (*ssl_OPENSSL_init_ssl)(I64 options, U8 *settings);
U8 *(*ssl_TLS_client_method)();
U8 *(*ssl_SSL_CTX_new)(U8 *method);
U0 (*ssl_SSL_CTX_free)(U8 *context);
I64 (*ssl_SSL_CTX_set_default_verify_paths)(U8 *context);
I64 (*ssl_SSL_CTX_load_verify_locations)(U8 *context, U8 *file,
  U8 *directory);
U0 (*ssl_SSL_CTX_set_verify)(U8 *context, I64 mode, U8 *callback);
I64 (*ssl_SSL_CTX_ctrl)(U8 *context, I64 command, I64 value, U8 *pointer);
U8 *(*ssl_SSL_new)(U8 *context);
U0 (*ssl_SSL_free)(U8 *session);
I64 (*ssl_SSL_set_fd)(U8 *session, I64 socket);
I64 (*ssl_SSL_ctrl)(U8 *session, I64 command, I64 value, U8 *pointer);
I64 (*ssl_SSL_set1_host)(U8 *session, U8 *hostname);
I64 (*ssl_SSL_connect)(U8 *session);
I64 (*ssl_SSL_read)(U8 *session, U8 *data, I64 size);
I64 (*ssl_SSL_write)(U8 *session, U8 *data, I64 size);
I64 (*ssl_SSL_get_error)(U8 *session, I64 result);
I64 (*ssl_SSL_get_verify_result)(U8 *session);
I64 (*ssl_SSL_shutdown)(U8 *session);
I64 (*ssl_ERR_get_error)();
U0 (*ssl_ERR_error_string_n)(I64 error, U8 *buffer, I64 capacity);

U0 SslSetError(U8 *message)
{
  I64 size;

  if (!message)
    message = "unknown TLS error";
  size = StrLen(message);
  if (size > sizeof(ssl_last_error) - 1)
    size = sizeof(ssl_last_error) - 1;
  MemCpy(ssl_last_error, message, size);
  ssl_last_error[size] = 0;
}

U0 SslRememberError(U8 *fallback)
{
  I64 error = 0;

  if (ssl_ERR_get_error)
    error = ssl_ERR_get_error();
  if (error && ssl_ERR_error_string_n) {
    ssl_ERR_error_string_n(error, ssl_last_error, sizeof(ssl_last_error));
    ssl_last_error[sizeof(ssl_last_error) - 1] = 0;
  } else {
    SslSetError(fallback);
  }
}

U8 *SslLastError()
{
  return ssl_last_error;
}

U0 SslSetCaLocations(U8 *file=NULL, U8 *directory=NULL)
{
  Free(ssl_ca_file);
  Free(ssl_ca_path);
  ssl_ca_file = NULL;
  ssl_ca_path = NULL;
  if (file && *file)
    ssl_ca_file = StrNew(file);
  if (directory && *directory)
    ssl_ca_path = StrNew(directory);
}

Bool SslInit()
{
  if (ssl_state > 0)
    return TRUE;
  if (ssl_state < 0)
    return FALSE;

  SslOpenLibraries;
  if (!ssl_library) {
    SslSetError("OpenSSL shared library not found");
    ssl_state = -1;
    SslLibraryClose(ssl_crypto_library);
    ssl_crypto_library = NULL;
    return FALSE;
  }

  ssl_OPENSSL_init_ssl =
    SslLibrarySymbol(ssl_library, "OPENSSL_init_ssl");
  ssl_TLS_client_method =
    SslLibrarySymbol(ssl_library, "TLS_client_method");
  ssl_SSL_CTX_new = SslLibrarySymbol(ssl_library, "SSL_CTX_new");
  ssl_SSL_CTX_free = SslLibrarySymbol(ssl_library, "SSL_CTX_free");
  ssl_SSL_CTX_set_default_verify_paths =
    SslLibrarySymbol(ssl_library, "SSL_CTX_set_default_verify_paths");
  ssl_SSL_CTX_load_verify_locations =
    SslLibrarySymbol(ssl_library, "SSL_CTX_load_verify_locations");
  ssl_SSL_CTX_set_verify =
    SslLibrarySymbol(ssl_library, "SSL_CTX_set_verify");
  ssl_SSL_CTX_ctrl = SslLibrarySymbol(ssl_library, "SSL_CTX_ctrl");
  ssl_SSL_new = SslLibrarySymbol(ssl_library, "SSL_new");
  ssl_SSL_free = SslLibrarySymbol(ssl_library, "SSL_free");
  ssl_SSL_set_fd = SslLibrarySymbol(ssl_library, "SSL_set_fd");
  ssl_SSL_ctrl = SslLibrarySymbol(ssl_library, "SSL_ctrl");
  ssl_SSL_set1_host = SslLibrarySymbol(ssl_library, "SSL_set1_host");
  ssl_SSL_connect = SslLibrarySymbol(ssl_library, "SSL_connect");
  ssl_SSL_read = SslLibrarySymbol(ssl_library, "SSL_read");
  ssl_SSL_write = SslLibrarySymbol(ssl_library, "SSL_write");
  ssl_SSL_get_error = SslLibrarySymbol(ssl_library, "SSL_get_error");
  ssl_SSL_get_verify_result =
    SslLibrarySymbol(ssl_library, "SSL_get_verify_result");
  ssl_SSL_shutdown = SslLibrarySymbol(ssl_library, "SSL_shutdown");

  if (ssl_crypto_library) {
    ssl_ERR_get_error =
      SslLibrarySymbol(ssl_crypto_library, "ERR_get_error");
    ssl_ERR_error_string_n =
      SslLibrarySymbol(ssl_crypto_library, "ERR_error_string_n");
  }

  if (!ssl_TLS_client_method || !ssl_SSL_CTX_new || !ssl_SSL_CTX_free ||
    !ssl_SSL_CTX_set_default_verify_paths ||
    !ssl_SSL_CTX_load_verify_locations || !ssl_SSL_CTX_set_verify ||
    !ssl_SSL_CTX_ctrl || !ssl_SSL_new || !ssl_SSL_free ||
    !ssl_SSL_set_fd || !ssl_SSL_ctrl || !ssl_SSL_set1_host ||
    !ssl_SSL_connect || !ssl_SSL_read || !ssl_SSL_write ||
    !ssl_SSL_get_error || !ssl_SSL_get_verify_result ||
    !ssl_SSL_shutdown) {
      SslSetError("OpenSSL is missing a required TLS 1.1+ symbol");
      SslLibraryClose(ssl_library);
      SslLibraryClose(ssl_crypto_library);
      ssl_library = NULL;
      ssl_crypto_library = NULL;
      ssl_state = -1;
      return FALSE;
    }

  if (ssl_OPENSSL_init_ssl && !ssl_OPENSSL_init_ssl(0, NULL)(I32)) {
    SslRememberError("OPENSSL_init_ssl failed");
    SslLibraryClose(ssl_library);
    SslLibraryClose(ssl_crypto_library);
    ssl_library = NULL;
    ssl_crypto_library = NULL;
    ssl_state = -1;
    return FALSE;
  }

  ssl_state = 1;
  ssl_last_error[0] = 0;
  return TRUE;
}

Bool SslAvailable()
{
  return SslInit;
}

U0 SslFini()
{
  if (ssl_state > 0) {
    SslLibraryClose(ssl_library);
    SslLibraryClose(ssl_crypto_library);
  }
  ssl_library = NULL;
  ssl_crypto_library = NULL;
  SslSetCaLocations;
  ssl_state = 0;
}

CSsl *SslConnect(I64 socket, U8 *hostname)
{
  CSsl *tls;
  U8 *method;

  if (!hostname || !*hostname) {
    SslSetError("TLS hostname is empty");
    return NULL;
  }
  if (!SslInit)
    return NULL;

  tls = CAlloc(sizeof(CSsl));
  tls->socket = socket;
  method = ssl_TLS_client_method();
  if (!method) {
    SslRememberError("TLS_client_method failed");
    Free(tls);
    return NULL;
  }

  tls->context = ssl_SSL_CTX_new(method);
  if (!tls->context) {
    SslRememberError("SSL_CTX_new failed");
    Free(tls);
    return NULL;
  }
  if (ssl_SSL_CTX_ctrl(tls->context, SSL_CTRL_SET_MIN_PROTO_VERSION,
      SSL_TLS1_2_VERSION, NULL) <= 0) {
        SslRememberError("cannot require TLS 1.2 or newer");
        ssl_SSL_CTX_free(tls->context);
        Free(tls);
        return NULL;
      }
  if ((ssl_ca_file || ssl_ca_path) &&
    !ssl_SSL_CTX_load_verify_locations(tls->context, ssl_ca_file,
      ssl_ca_path)(I32) ||
    !ssl_ca_file && !ssl_ca_path &&
    !ssl_SSL_CTX_set_default_verify_paths(tls->context)(I32)) {
      SslRememberError("cannot load the system CA certificates");
      ssl_SSL_CTX_free(tls->context);
      Free(tls);
      return NULL;
    }
  ssl_SSL_CTX_set_verify(tls->context, SSL_VERIFY_PEER, NULL);

  tls->session = ssl_SSL_new(tls->context);
  if (!tls->session) {
    SslRememberError("SSL_new failed");
    ssl_SSL_CTX_free(tls->context);
    Free(tls);
    return NULL;
  }
  if (ssl_SSL_set_fd(tls->session, socket)(I32) != 1) {
    SslRememberError("SSL_set_fd failed");
    ssl_SSL_free(tls->session);
    ssl_SSL_CTX_free(tls->context);
    Free(tls);
    return NULL;
  }
  if (ssl_SSL_ctrl(tls->session, SSL_CTRL_SET_TLSEXT_HOSTNAME,
      SSL_TLSEXT_NAMETYPE_HOST_NAME, hostname) <= 0) {
        SslRememberError("cannot set TLS SNI hostname");
        ssl_SSL_free(tls->session);
        ssl_SSL_CTX_free(tls->context);
        Free(tls);
        return NULL;
      }
  if (ssl_SSL_set1_host(tls->session, hostname)(I32) != 1) {
    SslRememberError("cannot enable TLS hostname verification");
    ssl_SSL_free(tls->session);
    ssl_SSL_CTX_free(tls->context);
    Free(tls);
    return NULL;
  }
  if (ssl_SSL_connect(tls->session)(I32) != 1) {
    SslRememberError("TLS handshake failed");
    ssl_SSL_free(tls->session);
    ssl_SSL_CTX_free(tls->context);
    Free(tls);
    return NULL;
  }
  if (ssl_SSL_get_verify_result(tls->session) != SSL_VERIFY_OK) {
    SslSetError("TLS certificate verification failed");
    ssl_SSL_shutdown(tls->session);
    ssl_SSL_free(tls->session);
    ssl_SSL_CTX_free(tls->context);
    Free(tls);
    return NULL;
  }

  ssl_last_error[0] = 0;
  return tls;
}

I64 SslRead(CSsl *tls, U8 *data, I64 capacity)
{
  I64 result;
  I64 error;

  if (!tls || !data || capacity < 0) {
    SslSetError("invalid SSL read");
    return -1;
  }
  if (capacity > 0x7FFFFFFF)
    capacity = 0x7FFFFFFF;

ssl_read_again:
  result = ssl_SSL_read(tls->session, data, capacity)(I32);
  if (result > 0)
    return result;
  error = ssl_SSL_get_error(tls->session, result)(I32);
  if (error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE)
    goto ssl_read_again;
  if (error == SSL_ERROR_ZERO_RETURN)
    return 0;
  SslRememberError("SSL_read failed");
  return -1;
}

I64 SslWrite(CSsl *tls, U8 *data, I64 size)
{
  I64 result;
  I64 error;

  if (!tls || !data || size < 0) {
    SslSetError("invalid SSL write");
    return -1;
  }
  if (size > 0x7FFFFFFF)
    size = 0x7FFFFFFF;

ssl_write_again:
  result = ssl_SSL_write(tls->session, data, size)(I32);
  if (result > 0)
    return result;
  error = ssl_SSL_get_error(tls->session, result)(I32);
  if (error == SSL_ERROR_WANT_READ || error == SSL_ERROR_WANT_WRITE)
    goto ssl_write_again;
  SslRememberError("SSL_write failed");
  return -1;
}

Bool SslWriteAll(CSsl *tls, U8 *data, I64 size)
{
  I64 sent;
  I64 total = 0;

  if (!tls || !data || size < 0) {
    SslSetError("invalid SSL write");
    return FALSE;
  }
  while (total < size) {
    sent = SslWrite(tls, data + total, size - total);
    if (sent <= 0)
      return FALSE;
    total += sent;
  }
  return TRUE;
}

U0 SslClose(CSsl *tls)
{
  if (!tls)
    return;
  if (tls->session) {
    ssl_SSL_shutdown(tls->session);
    ssl_SSL_free(tls->session);
  }
  if (tls->context)
    ssl_SSL_CTX_free(tls->context);
  Free(tls);
}

#endif
