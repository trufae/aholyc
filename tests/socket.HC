#include "../lib/socket/socket.hc"

CSocketAddrInfo *addresses;
CSocketAddrInfo *address;
I64 count = 0;
I64 handle;

if (SocketResolve("127.0.0.1", 80, SOCKET_TCP, FALSE, &addresses)) {
  for (address = addresses; address && count < 16; address = address->next)
    count++;
  SocketNativeFreeAddrInfo(addresses);
}

handle = UdpBind(0, "127.0.0.1");
"socket=%d,%d\n", count > 0, handle != SOCKET_INVALID;
SocketClose(handle);
SocketFini;
