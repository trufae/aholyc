#include "../lib/net/socket.hc"
#include "../lib/thread/thread.hc"

#define SOCKET_TEST_PORT 31337

CThread socket_test_server_thread;
I64 socket_test_server;
Bool socket_test_sent;

U0 SocketTestServer(U8 *unused)
{
  I64 client;
  U8 value = 'x';

  client = TcpAccept(socket_test_server);
  if (client != SOCKET_INVALID) {
    Sleep(20);
    socket_test_sent = SocketSend(client, &value, 1) == 1;
    SocketClose(client);
  }
}

I64 client;
U8 value;
Bool ok;

socket_test_server = TcpListen(SOCKET_TEST_PORT, "127.0.0.1");
ok = socket_test_server != SOCKET_INVALID &&
  ThreadCreate(&socket_test_server_thread, &SocketTestServer);
if (ok) {
  client = TcpConnectTimeout("127.0.0.1", SOCKET_TEST_PORT, 1000);
  ok = client != SOCKET_INVALID && SocketRecv(client, &value, 1) == 1 &&
    value == 'x';
  SocketClose(client);
  ok = ThreadJoin(&socket_test_server_thread) && socket_test_sent && ok;
}
if (socket_test_server != SOCKET_INVALID)
  SocketClose(socket_test_server);
SocketFini;

"socket timeout: %d\n", ok;
