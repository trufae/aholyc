#include "../lib/thread/thread.hc"

#define THREAD_TEST_THREADS 2
#define THREAD_TEST_LOOPS   4000

class CThreadTestArgs
{
  I64 id;
  Bool tls_ok;
};

CThreadMutex thread_test_mutex;
CThreadLock thread_test_lock;
CThreadSemaphore thread_test_start;
CThreadSemaphore thread_test_detached_done;
CThreadTLS thread_test_tls;
I64 thread_test_mutex_counter;
I64 thread_test_lock_counter;
I64 thread_test_tls_destructors;

U0 ThreadTestTLSDestroy(U8 *value)
{
  ThreadMutexLock(&thread_test_mutex);
  thread_test_tls_destructors++;
  ThreadMutexUnlock(&thread_test_mutex);
}

U0 ThreadTestWorker(CThreadTestArgs *args)
{
  I64 i;

  args->tls_ok = ThreadTLSSet(&thread_test_tls, args) &&
    ThreadTLSGet(&thread_test_tls) == args;
  ThreadSemaphoreWait(&thread_test_start);
  for (i = 0; i < THREAD_TEST_LOOPS; i++) {
    ThreadMutexLock(&thread_test_mutex);
    thread_test_mutex_counter++;
    ThreadMutexUnlock(&thread_test_mutex);

    ThreadLockLock(&thread_test_lock);
    thread_test_lock_counter++;
    ThreadLockUnlock(&thread_test_lock);
  }
  ThreadExit;
}

U0 ThreadTestDetached(U8 *unused)
{
  ThreadSemaphorePost(&thread_test_detached_done);
}

CThread threads[THREAD_TEST_THREADS], detached;
CThreadTestArgs args[THREAD_TEST_THREADS];
I64 i;
Bool ok = TRUE;

ok = ok && ThreadMutexInit(&thread_test_mutex);
ThreadLockInit(&thread_test_lock);
ok = ok && ThreadSemaphoreInit(&thread_test_start, 0, THREAD_TEST_THREADS);
ok = ok && ThreadSemaphoreInit(&thread_test_detached_done, 0, 1);
ok = ok && ThreadTLSInit(&thread_test_tls, &ThreadTestTLSDestroy);
ok = ok && !ThreadSemaphoreTryWait(&thread_test_start);
ok = ok && ThreadMutexTryLock(&thread_test_mutex);
ok = ok && ThreadMutexUnlock(&thread_test_mutex);
ok = ok && ThreadLockTry(&thread_test_lock);
ok = ok && ThreadLockUnlock(&thread_test_lock);

for (i = 0; i < THREAD_TEST_THREADS; i++) {
  args[i].id = i + 1;
  args[i].tls_ok = FALSE;
  ok = ok && ThreadSpawn(&threads[i], &ThreadTestWorker, &args[i]);
}
ok = ok && ThreadSemaphorePost(&thread_test_start, THREAD_TEST_THREADS);
for (i = 0; i < THREAD_TEST_THREADS; i++)
  ok = ok && ThreadWait(&threads[i]);
ok = ok && thread_test_tls_destructors == THREAD_TEST_THREADS;

ok = ok && ThreadCreate(&detached, &ThreadTestDetached);
ok = ok && ThreadDetach(&detached);
ok = ok && ThreadSemaphoreWait(&thread_test_detached_done);
Yield;
Sleep(1);

for (i = 0; i < THREAD_TEST_THREADS; i++)
  ok = ok && args[i].tls_ok;
ok = ok && thread_test_mutex_counter ==
  THREAD_TEST_THREADS * THREAD_TEST_LOOPS;
ok = ok && thread_test_lock_counter ==
  THREAD_TEST_THREADS * THREAD_TEST_LOOPS;
ok = ok && ThreadSemaphoreValue(&thread_test_start) == 0;

ok = ok && ThreadTLSFini(&thread_test_tls);
ok = ok && ThreadSemaphoreFini(&thread_test_detached_done);
ok = ok && ThreadSemaphoreFini(&thread_test_start);
ok = ok && ThreadMutexFini(&thread_test_mutex);

"thread api: %d counter=%d tls=%d\n", ok, thread_test_lock_counter,
  args[0].tls_ok && args[1].tls_ok;
