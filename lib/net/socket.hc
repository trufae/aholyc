#ifndef AHOLYC_LIB_SOCKET_HC
#define AHOLYC_LIB_SOCKET_HC

// Portable blocking TCP/UDP sockets for aholyc's native backends.
//
// High-level API:
//   Bool SocketInit();
//   U0   SocketFini();
//   I64  TcpListen(port, host=NULL, backlog=128);
//   I64  TcpAccept(server);
//   I64  TcpConnect(host, port);
//   I64  TcpConnectTimeout(host, port, milliseconds);
//   I64  UdpBind(port, host=NULL);
//   I64  UdpConnect(host, port);
//   I64  UdpSendTo(socket, host, port, bytes, size);
//   I64  UdpRecvFrom(socket, bytes, capacity, source_address);
//   I64  UdpSendAddress(socket, source_address, bytes, size);
//   I64  UdpRecv(socket, bytes, capacity);
//   I64  SocketSend/SocketRecv(socket, bytes, size);
//   Bool SocketSendAll(socket, bytes, size);
//   U0   SocketShutdown/SocketClose(socket);
//   I64  SocketLastError();
//
// Socket handles are I64 values.  Every data operation takes an explicit byte
// count, so embedded NUL bytes are preserved.

#define SOCKET_INVALID -1
#define SOCKET_TCP     1
#define SOCKET_UDP     2
#define SOCKET_AF_ANY  0
#define SOCKET_AF_INET 2

#ifdef IS_WINDOWS
#define SOCKET_AF_INET6       23
#define SOCKET_SOL_SOCKET     0xFFFF
#define SOCKET_SO_REUSEADDR   4
#define SOCKET_SO_ERROR       0x1007
#define SOCKET_MSG_NOSIGNAL   0
#define SOCKET_AI_PASSIVE     1
#define SOCKET_CONNECT_TIMEOUT 10060
#else
#ifdef IS_MACOS
#define SOCKET_AF_INET6       30
#define SOCKET_SOL_SOCKET     0xFFFF
#define SOCKET_SO_REUSEADDR   4
#define SOCKET_SO_ERROR       0x1007
#define SOCKET_SO_NOSIGPIPE   0x1022
#define SOCKET_MSG_NOSIGNAL   0
#define SOCKET_AI_PASSIVE     1
#define SOCKET_CONNECT_TIMEOUT 60
#else
#define SOCKET_AF_INET6       10
#define SOCKET_SOL_SOCKET     1
#define SOCKET_SO_REUSEADDR   2
#define SOCKET_SO_ERROR       4
#define SOCKET_MSG_NOSIGNAL   0x4000
#define SOCKET_AI_PASSIVE     1
#define SOCKET_CONNECT_TIMEOUT 110
#endif
#endif

// addrinfo is almost portable, except Linux places ai_addr before
// ai_canonname.  Explicit cursors reproduce each C ABI without relying on
// HolyC's packed default layout.
class CSocketAddrInfo
{
  I32 flags;
  I32 family;
  I32 socket_type;
  I32 protocol;
  #ifdef IS_WINDOWS
  U64 address_length;
  U8 *canonical_name;
  U8 *address;
  #else
  U32 address_length;
  $$ = 24;
  #ifdef IS_LINUX
  U8 *address;
  U8 *canonical_name;
  #else
  U8 *canonical_name;
  U8 *address;
  #endif
  #endif
  CSocketAddrInfo *next;
};

// Opaque enough for sockaddr_in, sockaddr_in6, and their platform variants.
// Preserve one returned by UdpRecvFrom to reply with UdpSendAddress.
class CSocketAddress
{
  U8 bytes[128];
  U32 length;
};

I64 socket_last_error;

#ifdef IS_WINDOWS

extern U8 *LoadLibraryA(U8 *name);
extern U8 *GetProcAddress(U8 *library, U8 *name);
extern I64 FreeLibrary(U8 *library);

U8 *socket_winsock_library;
Bool socket_winsock_started;

// Store a winsock symbol into a typed function-pointer slot.
U0 SocketLoad(U8 *name, U8 **slot)
{
  *slot = GetProcAddress(socket_winsock_library, name);
}

I64 (*socket_WSAStartup)(I64 version, U8 *data);
I64 (*socket_WSACleanup)();
I64 (*socket_WSAGetLastError)();
I64 (*socket_socket)(I64 family, I64 type, I64 protocol);
I64 (*socket_bind)(I64 socket, U8 *address, I64 address_length);
I64 (*socket_listen)(I64 socket, I64 backlog);
I64 (*socket_accept)(I64 socket, U8 *address, U8 *address_length);
I64 (*socket_connect)(I64 socket, U8 *address, I64 address_length);
I64 (*socket_send)(I64 socket, U8 *data, I64 size, I64 flags);
I64 (*socket_recv)(I64 socket, U8 *data, I64 size, I64 flags);
I64 (*socket_recvfrom)(I64 socket, U8 *data, I64 size, I64 flags,
  U8 *address, U8 *address_length);
I64 (*socket_sendto)(I64 socket, U8 *data, I64 size, I64 flags,
  U8 *address, I64 address_length);
I64 (*socket_shutdown)(I64 socket, I64 how);
I64 (*socket_closesocket)(I64 socket);
I64 (*socket_setsockopt)(I64 socket, I64 level, I64 option,
  U8 *value, I64 value_size);
I64 (*socket_getsockopt)(I64 socket, I64 level, I64 option,
  U8 *value, I32 *value_size);
I64 (*socket_ioctlsocket)(I64 socket, U64 command, U32 *value);
I64 (*socket_WSAPoll)(U8 *fds, U64 count, I32 timeout);
I64 (*socket_getaddrinfo)(U8 *host, U8 *service, CSocketAddrInfo *hints,
  CSocketAddrInfo **result);
U0 (*socket_freeaddrinfo)(CSocketAddrInfo *result);

class CSocketPollFD
{
  U64 handle;
  I16 events;
  I16 revents;
};

Bool SocketInit()
{
  U8 startup_data[512];

  if (socket_winsock_started)
    return TRUE;
  socket_winsock_library = LoadLibraryA("ws2_32.dll");
  if (!socket_winsock_library) {
    socket_last_error = -1;
    return FALSE;
  }

  SocketLoad("WSAStartup", &socket_WSAStartup);
  SocketLoad("WSACleanup", &socket_WSACleanup);
  SocketLoad("WSAGetLastError", &socket_WSAGetLastError);
  SocketLoad("socket", &socket_socket);
  SocketLoad("bind", &socket_bind);
  SocketLoad("listen", &socket_listen);
  SocketLoad("accept", &socket_accept);
  SocketLoad("connect", &socket_connect);
  SocketLoad("send", &socket_send);
  SocketLoad("recv", &socket_recv);
  SocketLoad("recvfrom", &socket_recvfrom);
  SocketLoad("sendto", &socket_sendto);
  SocketLoad("shutdown", &socket_shutdown);
  SocketLoad("closesocket", &socket_closesocket);
  SocketLoad("setsockopt", &socket_setsockopt);
  SocketLoad("getsockopt", &socket_getsockopt);
  SocketLoad("ioctlsocket", &socket_ioctlsocket);
  SocketLoad("WSAPoll", &socket_WSAPoll);
  SocketLoad("getaddrinfo", &socket_getaddrinfo);
  SocketLoad("freeaddrinfo", &socket_freeaddrinfo);

  if (!socket_WSAStartup || !socket_WSACleanup ||
    !socket_WSAGetLastError || !socket_socket || !socket_bind ||
    !socket_listen || !socket_accept || !socket_connect ||
    !socket_send || !socket_recv || !socket_recvfrom || !socket_sendto ||
    !socket_shutdown || !socket_closesocket || !socket_setsockopt ||
    !socket_getsockopt || !socket_ioctlsocket || !socket_WSAPoll ||
    !socket_getaddrinfo || !socket_freeaddrinfo) {
      FreeLibrary(socket_winsock_library);
      socket_winsock_library = NULL;
      socket_last_error = -1;
      return FALSE;
    }

  MemSet(startup_data, 0, sizeof(startup_data));
  socket_last_error = socket_WSAStartup(0x0202, startup_data)(I32);
  if (socket_last_error) {
    FreeLibrary(socket_winsock_library);
    socket_winsock_library = NULL;
    return FALSE;
  }
  socket_winsock_started = TRUE;
  return TRUE;
}

U0 SocketFini()
{
  if (!socket_winsock_started)
    return;
  socket_WSACleanup;
  socket_winsock_started = FALSE;
  FreeLibrary(socket_winsock_library);
  socket_winsock_library = NULL;
}

I64 SocketNativeError()
{
  if (!socket_WSAGetLastError)
    return socket_last_error;
  return socket_WSAGetLastError()(I32);
}

I64 SocketNativeOpen(I64 family, I64 type, I64 protocol)
{
  return socket_socket(family, type, protocol);
}

I64 SocketNativeBind(I64 handle, U8 *address, I64 address_length)
{
  return socket_bind(handle, address, address_length)(I32);
}

I64 SocketNativeListen(I64 handle, I64 backlog)
{
  return socket_listen(handle, backlog)(I32);
}

I64 SocketNativeAccept(I64 handle)
{
  return socket_accept(handle, NULL, NULL);
}

I64 SocketNativeConnect(I64 handle, U8 *address, I64 address_length)
{
  return socket_connect(handle, address, address_length)(I32);
}

I64 SocketNativeSend(I64 handle, U8 *data, I64 size)
{
  return socket_send(handle, data, size, 0)(I32);
}

I64 SocketNativeRecv(I64 handle, U8 *data, I64 size)
{
  return socket_recv(handle, data, size, 0)(I32);
}

I64 SocketNativeRecvFrom(I64 handle, U8 *data, I64 size,
  U8 *address, U8 *address_length)
{
  return socket_recvfrom(handle, data, size, 0, address,
    address_length)(I32);
}

I64 SocketNativeSendTo(I64 handle, U8 *data, I64 size,
  U8 *address, I64 address_length)
{
  return socket_sendto(handle, data, size, 0, address, address_length)(I32);
}

I64 SocketNativeSetOption(I64 handle, I64 level, I64 option,
  U8 *value, I64 value_size)
{
  return socket_setsockopt(handle, level, option, value, value_size)(I32);
}

Bool SocketNativeSetNonBlocking(I64 handle, Bool enabled)
{
  U32 value = enabled;

  return !socket_ioctlsocket(handle, 0x8004667e, &value);
}

I64 SocketNativeWaitConnect(I64 handle, I64 milliseconds)
{
  CSocketPollFD pollfd;

  pollfd.handle = handle;
  pollfd.events = 0x10;
  pollfd.revents = 0;
  return socket_WSAPoll(&pollfd, 1, milliseconds)(I32);
}

I64 SocketNativeConnectError(I64 handle)
{
  I32 error = 0;
  I32 size = sizeof(error);

  if (socket_getsockopt(handle, SOCKET_SOL_SOCKET, SOCKET_SO_ERROR,
      &error, &size))
    return SocketNativeError;
  return error;
}

Bool SocketNativeConnectPending(I64 error)
{
  return error == 10035 || error == 10036 || error == 10037;
}

I64 SocketNativeGetAddrInfo(U8 *host, U8 *service,
  CSocketAddrInfo *hints, CSocketAddrInfo **result)
{
  return socket_getaddrinfo(host, service, hints, result)(I32);
}

U0 SocketNativeFreeAddrInfo(CSocketAddrInfo *result)
{
  socket_freeaddrinfo(result);
}

U0 SocketNativeShutdown(I64 handle)
{
  socket_shutdown(handle, 2);
}

U0 SocketNativeClose(I64 handle)
{
  socket_closesocket(handle);
}

#else

extern I64 socket(I64 family, I64 type, I64 protocol);
extern I64 bind(I64 socket, U8 *address, I64 address_length);
extern I64 listen(I64 socket, I64 backlog);
extern I64 accept(I64 socket, U8 *address, U8 *address_length);
extern I64 connect(I64 socket, U8 *address, I64 address_length);
extern I64 send(I64 socket, U8 *data, I64 size, I64 flags);
extern I64 recv(I64 socket, U8 *data, I64 size, I64 flags);
extern I64 recvfrom(I64 socket, U8 *data, I64 size, I64 flags,
  U8 *address, U8 *address_length);
extern I64 sendto(I64 socket, U8 *data, I64 size, I64 flags,
  U8 *address, I64 address_length);
extern I64 shutdown(I64 socket, I64 how);
extern I64 close(I64 socket);
extern I64 setsockopt(I64 socket, I64 level, I64 option,
  U8 *value, I64 value_size);
extern I64 getsockopt(I64 socket, I64 level, I64 option,
  U8 *value, U64 *value_size);
extern I64 fcntl(I64 descriptor, I64 command, I64 value);
extern I64 poll(U8 *fds, U64 count, I64 timeout);
extern I64 getaddrinfo(U8 *host, U8 *service, CSocketAddrInfo *hints,
  CSocketAddrInfo **result);
extern U0 freeaddrinfo(CSocketAddrInfo *result);

#ifdef IS_MACOS
extern I32 *__error();
#else
extern I32 *__errno_location();
#endif

Bool SocketInit()
{
  return TRUE;
}

U0 SocketFini()
{
}

I64 SocketNativeError()
{
  #ifdef IS_MACOS
  return *__error();
  #else
  return *__errno_location();
  #endif
}

I64 SocketNativeOpen(I64 family, I64 type, I64 protocol)
{
  return socket(family, type, protocol)(I32);
}

I64 SocketNativeBind(I64 handle, U8 *address, I64 address_length)
{
  return bind(handle, address, address_length)(I32);
}

I64 SocketNativeListen(I64 handle, I64 backlog)
{
  return listen(handle, backlog)(I32);
}

I64 SocketNativeAccept(I64 handle)
{
  return accept(handle, NULL, NULL)(I32);
}

I64 SocketNativeConnect(I64 handle, U8 *address, I64 address_length)
{
  return connect(handle, address, address_length)(I32);
}

I64 SocketNativeSend(I64 handle, U8 *data, I64 size)
{
  return send(handle, data, size, SOCKET_MSG_NOSIGNAL);
}

I64 SocketNativeRecv(I64 handle, U8 *data, I64 size)
{
  return recv(handle, data, size, 0);
}

I64 SocketNativeRecvFrom(I64 handle, U8 *data, I64 size,
  U8 *address, U8 *address_length)
{
  return recvfrom(handle, data, size, 0, address, address_length);
}

I64 SocketNativeSendTo(I64 handle, U8 *data, I64 size,
  U8 *address, I64 address_length)
{
  return sendto(handle, data, size, SOCKET_MSG_NOSIGNAL,
    address, address_length);
}

I64 SocketNativeSetOption(I64 handle, I64 level, I64 option,
  U8 *value, I64 value_size)
{
  return setsockopt(handle, level, option, value, value_size)(I32);
}

I64 SocketNativeGetAddrInfo(U8 *host, U8 *service,
  CSocketAddrInfo *hints, CSocketAddrInfo **result)
{
  return getaddrinfo(host, service, hints, result)(I32);
}

U0 SocketNativeFreeAddrInfo(CSocketAddrInfo *result)
{
  freeaddrinfo(result);
}

U0 SocketNativeShutdown(I64 handle)
{
  shutdown(handle, 2);
}

U0 SocketNativeClose(I64 handle)
{
  close(handle);
}

class CSocketPollFD
{
  I32 handle;
  I16 events;
  I16 revents;
};

Bool SocketNativeSetNonBlocking(I64 handle, Bool enabled)
{
  I64 flags = fcntl(handle, 3, 0);

  if (flags < 0)
    return FALSE;
  #ifdef IS_MACOS
  if (enabled)
    flags |= 4;
  else
    flags &= ~4;
  #else
  if (enabled)
    flags |= 0x800;
  else
    flags &= ~0x800;
  #endif
  return !fcntl(handle, 4, flags);
}

I64 SocketNativeWaitConnect(I64 handle, I64 milliseconds)
{
  CSocketPollFD pollfd;

  pollfd.handle = handle;
  pollfd.events = 4;
  pollfd.revents = 0;
  return poll(&pollfd, 1, milliseconds)(I32);
}

I64 SocketNativeConnectError(I64 handle)
{
  I32 error = 0;
  U64 size = sizeof(error);

  if (getsockopt(handle, SOCKET_SOL_SOCKET, SOCKET_SO_ERROR,
      &error, &size))
    return SocketNativeError;
  return error;
}

Bool SocketNativeConnectPending(I64 error)
{
  #ifdef IS_MACOS
  return error == 35 || error == 36 || error == 37;
  #else
  return error == 11 || error == 114 || error == 115;
  #endif
}

#endif

I64 SocketLastError()
{
  return socket_last_error;
}

U0 SocketRememberNativeError()
{
  socket_last_error = SocketNativeError;
}

I64 SocketSystemType(I64 type)
{
  if (type == SOCKET_UDP)
    return 2;
  return 1;
}

I64 SocketSystemProtocol(I64 type)
{
  if (type == SOCKET_UDP)
    return 17;
  return 6;
}

Bool SocketResolve(U8 *host, I64 port, I64 type, Bool passive,
  CSocketAddrInfo **result)
{
  CSocketAddrInfo hints;
  U8 *service;
  I64 error;

  *result = NULL;
  if (port < 0 || port > 65535) {
    socket_last_error = -1;
    return FALSE;
  }
  if (!SocketInit)
    return FALSE;

  MemSet(&hints, 0, sizeof(hints));
  hints.family = SOCKET_AF_ANY;
  hints.socket_type = SocketSystemType(type);
  hints.protocol = SocketSystemProtocol(type);
  if (passive)
    hints.flags = SOCKET_AI_PASSIVE;

  service = MStrPrint("%d", port);
  if (host && !*host)
    host = NULL;
  error = SocketNativeGetAddrInfo(host, service, &hints, result);
  Free(service);
  if (error) {
    socket_last_error = error;
    return FALSE;
  }
  socket_last_error = 0;
  return TRUE;
}

U0 SocketConfigure(I64 handle)
{
  #ifdef IS_MACOS
  I32 one = 1;
  SocketNativeSetOption(handle, SOCKET_SOL_SOCKET, SOCKET_SO_NOSIGPIPE,
    &one, sizeof(one));
  #endif
}

I64 SocketListen(I64 port, U8 *host=NULL, I64 type=SOCKET_TCP,
  I64 backlog=128)
{
  CSocketAddrInfo *addresses;
  CSocketAddrInfo *address;
  I64 handle = SOCKET_INVALID;
  I32 one = 1;

  if (!SocketResolve(host, port, type, TRUE, &addresses))
    return SOCKET_INVALID;

  address = addresses;
  while (address && handle == SOCKET_INVALID) {
    handle = SocketNativeOpen(address->family, address->socket_type,
      address->protocol);
    if (handle != SOCKET_INVALID) {
      SocketNativeSetOption(handle, SOCKET_SOL_SOCKET, SOCKET_SO_REUSEADDR,
        &one, sizeof(one));
      SocketConfigure(handle);
      if (SocketNativeBind(handle, address->address,
          address->address_length) < 0) {
            SocketRememberNativeError;
            SocketNativeClose(handle);
            handle = SOCKET_INVALID;
          } else if (type == SOCKET_TCP &&
        SocketNativeListen(handle, backlog) < 0) {
          SocketRememberNativeError;
          SocketNativeClose(handle);
          handle = SOCKET_INVALID;
        }
    } else {
      SocketRememberNativeError;
    }
    address = address->next;
  }
  SocketNativeFreeAddrInfo(addresses);
  return handle;
}

I64 TcpListen(I64 port, U8 *host=NULL, I64 backlog=128)
{
  return SocketListen(port, host, SOCKET_TCP, backlog);
}

I64 UdpBind(I64 port, U8 *host=NULL)
{
  return SocketListen(port, host, SOCKET_UDP, 0);
}

I64 SocketAccept(I64 server)
{
  I64 client = SocketNativeAccept(server);

  if (client == SOCKET_INVALID) {
    SocketRememberNativeError;
    return SOCKET_INVALID;
  }
  SocketConfigure(client);
  socket_last_error = 0;
  return client;
}

I64 TcpAccept(I64 server)
{
  return SocketAccept(server);
}

I64 SocketConnectTimeout(U8 *host, I64 port, I64 milliseconds,
  I64 type=SOCKET_TCP)
{
  CSocketAddrInfo *addresses;
  CSocketAddrInfo *address;
  I64 handle = SOCKET_INVALID;
  I64 result;
  I64 wait;
  I64 error;

  if (!host || !*host) {
    socket_last_error = -1;
    return SOCKET_INVALID;
  }
  if (!SocketResolve(host, port, type, FALSE, &addresses))
    return SOCKET_INVALID;

  address = addresses;
  while (address && handle == SOCKET_INVALID) {
    handle = SocketNativeOpen(address->family, address->socket_type,
      address->protocol);
    if (handle != SOCKET_INVALID) {
      SocketConfigure(handle);
      if (milliseconds >= 0) {
        if (!SocketNativeSetNonBlocking(handle, TRUE)) {
          SocketRememberNativeError;
          SocketNativeClose(handle);
          handle = SOCKET_INVALID;
        }
      }
      if (handle != SOCKET_INVALID) {
        result = SocketNativeConnect(handle, address->address,
          address->address_length);
        if (result < 0) {
          error = SocketNativeError;
          if (milliseconds >= 0 && SocketNativeConnectPending(error)) {
            wait = SocketNativeWaitConnect(handle, milliseconds);
            if (!wait)
              error = SOCKET_CONNECT_TIMEOUT;
            else if (wait < 0)
              error = SocketNativeError;
            else
              error = SocketNativeConnectError(handle);
          }
          if (error) {
            socket_last_error = error;
            SocketNativeClose(handle);
            handle = SOCKET_INVALID;
          }
        }
      }
      if (handle != SOCKET_INVALID && milliseconds >= 0 &&
          !SocketNativeSetNonBlocking(handle, FALSE)) {
            SocketRememberNativeError;
            SocketNativeClose(handle);
            handle = SOCKET_INVALID;
          }
    } else {
      SocketRememberNativeError;
    }
    address = address->next;
  }
  SocketNativeFreeAddrInfo(addresses);
  return handle;
}

I64 SocketConnect(U8 *host, I64 port, I64 type=SOCKET_TCP)
{
  return SocketConnectTimeout(host, port, -1, type);
}

I64 TcpConnect(U8 *host, I64 port)
{
  return SocketConnect(host, port, SOCKET_TCP);
}

I64 TcpConnectTimeout(U8 *host, I64 port, I64 milliseconds)
{
  return SocketConnectTimeout(host, port, milliseconds, SOCKET_TCP);
}

I64 UdpConnect(U8 *host, I64 port)
{
  return SocketConnect(host, port, SOCKET_UDP);
}

I64 SocketSend(I64 handle, U8 *data, I64 size)
{
  I64 result;

  if (!data || size < 0) {
    socket_last_error = -1;
    return -1;
  }
  result = SocketNativeSend(handle, data, size);
  if (result < 0)
    SocketRememberNativeError;
  else
    socket_last_error = 0;
  return result;
}

Bool SocketSendAll(I64 handle, U8 *data, I64 size)
{
  I64 sent;
  I64 total = 0;

  if (!data || size < 0) {
    socket_last_error = -1;
    return FALSE;
  }
  while (total < size) {
    sent = SocketSend(handle, data + total, size - total);
    if (sent <= 0)
      return FALSE;
    total += sent;
  }
  return TRUE;
}

I64 SocketRecv(I64 handle, U8 *data, I64 capacity)
{
  I64 result;

  if (!data || capacity < 0) {
    socket_last_error = -1;
    return -1;
  }
  result = SocketNativeRecv(handle, data, capacity);
  if (result < 0)
    SocketRememberNativeError;
  else
    socket_last_error = 0;
  return result;
}

I64 UdpSendTo(I64 handle, U8 *host, I64 port, U8 *data, I64 size)
{
  CSocketAddrInfo *addresses;
  CSocketAddrInfo *address;
  I64 result = -1;

  if (!data || size < 0 || !SocketResolve(host, port, SOCKET_UDP,
      FALSE, &addresses))
    return -1;

  address = addresses;
  while (address && result < 0) {
    result = SocketNativeSendTo(handle, data, size, address->address,
      address->address_length);
    if (result < 0)
      SocketRememberNativeError;
    address = address->next;
  }
  SocketNativeFreeAddrInfo(addresses);
  if (result >= 0)
    socket_last_error = 0;
  return result;
}

I64 UdpRecv(I64 handle, U8 *data, I64 capacity)
{
  return SocketRecv(handle, data, capacity);
}

I64 UdpRecvFrom(I64 handle, U8 *data, I64 capacity,
  CSocketAddress *source)
{
  I64 result;

  if (!source)
    return UdpRecv(handle, data, capacity);
  if (!data || capacity < 0) {
    socket_last_error = -1;
    return -1;
  }

  MemSet(source, 0, sizeof(CSocketAddress));
  source->length = sizeof(source->bytes);
  result = SocketNativeRecvFrom(handle, data, capacity, source->bytes,
    &source->length);
  if (result < 0)
    SocketRememberNativeError;
  else
    socket_last_error = 0;
  return result;
}

I64 UdpSendAddress(I64 handle, CSocketAddress *destination,
  U8 *data, I64 size)
{
  I64 result;

  if (!destination || !destination->length || !data || size < 0) {
    socket_last_error = -1;
    return -1;
  }
  result = SocketNativeSendTo(handle, data, size, destination->bytes,
    destination->length);
  if (result < 0)
    SocketRememberNativeError;
  else
    socket_last_error = 0;
  return result;
}

U0 SocketShutdown(I64 handle)
{
  if (handle != SOCKET_INVALID)
    SocketNativeShutdown(handle);
}

U0 SocketClose(I64 handle)
{
  if (handle != SOCKET_INVALID)
    SocketNativeClose(handle);
}

#endif
