// pmap: quickly list hosts on 192.168.1.0/24 with SSH (TCP/22) open.
//
// Run with: ./aholyc run examples/pmap.hc

#include "../lib/net/socket.hc"
#include "../lib/thread/thread.hc"

#define PMAP_WORKERS 64

class CPmap
{
  CThreadMutex next_lock;
  CThreadMutex output_lock;
  I64 next_host;
};

U0 PmapWorker(CPmap *pmap)
{
  I64 host;
  I64 socket;
  U8 address[16];

  while (TRUE) {
    ThreadMutexLock(&pmap->next_lock);
    host = pmap->next_host++;
    ThreadMutexUnlock(&pmap->next_lock);
    if (host > 254)
      break;

    StrPrint(address, "192.168.1.%d", host);
    socket = TcpConnectTimeout(address, 22, 1000);
    if (socket != SOCKET_INVALID) {
      ThreadMutexLock(&pmap->output_lock);
      "%s\n", address;
      ThreadMutexUnlock(&pmap->output_lock);
      SocketClose(socket);
    }
  }
}

U0 Main()
{
  CPmap pmap;
  CThread workers[PMAP_WORKERS];
  I64 i;

  pmap.next_host = 1;
  if (!ThreadMutexInit(&pmap.next_lock) ||
    !ThreadMutexInit(&pmap.output_lock))
      return;

  for (i = 0; i < PMAP_WORKERS; i++) {
    if (!ThreadCreate(&workers[i], &PmapWorker, &pmap))
      break;
  }
  while (i--)
    ThreadJoin(&workers[i]);

  ThreadMutexFini(&pmap.output_lock);
  ThreadMutexFini(&pmap.next_lock);
  SocketFini;
}

Main;
