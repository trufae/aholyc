#ifndef AHOLYC_LIB_THREAD_HC
#define AHOLYC_LIB_THREAD_HC

// Portable hosted threads for aholyc's native backends.
//
// The public classes contain only stable HolyC fields.  Native pthread and
// Win32 objects live in private, aligned allocations so their platform ABI
// never leaks into application code.

#define THREAD_NATIVE_BYTES 64

class CThread
{
  U8 *handle;
  Bool joinable;
};

class CThreadStart
{
  U8 *entry;
  U8 *data;
};

class CThreadMutex
{
  U64 *native;
};

class CThreadCondition
{
  U64 *native;
};

class CThreadSemaphore
{
  CThreadMutex mutex;
  CThreadCondition condition;
  I64 value;
  I64 maximum;
};

// Compatibility spelling used by the older holyc-lang thread helper.
#define ThreadSemaphore CThreadSemaphore

// TempleOS normally builds spin locks from LBts/LBtr.  Keep the same model:
// this is a one-bit, non-recursive spin lock, not a sleeping mutex.
class CThreadLock
{
  U8 taken;
};

class CThreadTLS
{
  U64 key;
  Bool valid;
};

// THREAD_WINDOWS/THREAD_POSIX let cross-builds override the compiler host.
#ifdef THREAD_WINDOWS
#ifdef THREAD_POSIX
#error define only one of THREAD_WINDOWS or THREAD_POSIX
#endif
#include "windows.hc"
#else
#ifdef THREAD_POSIX
#include "posix.hc"
#else
#ifdef IS_WINDOWS
#include "windows.hc"
#else
#ifdef IS_UNIX
#include "posix.hc"
#else
#error lib/thread supports Linux, macOS, and Windows native targets
#endif
#endif
#endif
#endif

I64 ThreadMain(CThreadStart *start)
{
  U0 (*entry)(U8 *argument);
  U8 *data;

  entry = start->entry;
  data = start->data;
  Free(start);
  entry(data);
  return 0;
}

public Bool ThreadCreate(CThread *thread, U8 *entry, U8 *data = NULL)
{
  CThreadStart *start;

  if (!thread || !entry)
    return FALSE;
  MemSet(thread, 0, sizeof(CThread));
  start = MAlloc(sizeof(CThreadStart));
  if (!start)
    return FALSE;
  start->entry = entry;
  start->data = data;
  if (!ThreadNativeCreate(thread, &ThreadMain, start)) {
    Free(start);
    return FALSE;
  }
  thread->joinable = TRUE;
  return TRUE;
}

public Bool ThreadJoin(CThread *thread)
{
  if (!thread || !thread->joinable)
    return FALSE;
  if (!ThreadNativeJoin(thread))
    return FALSE;
  thread->handle = NULL;
  thread->joinable = FALSE;
  return TRUE;
}

public Bool ThreadDetach(CThread *thread)
{
  if (!thread || !thread->joinable)
    return FALSE;
  if (!ThreadNativeDetach(thread))
    return FALSE;
  thread->handle = NULL;
  thread->joinable = FALSE;
  return TRUE;
}

// Names close to TempleOS's Spawn/TaskWait without claiming CTask semantics.
public Bool ThreadSpawn(CThread *thread, U8 *entry, U8 *data = NULL)
{
  return ThreadCreate(thread, entry, data);
}

public Bool ThreadWait(CThread *thread)
{
  return ThreadJoin(thread);
}

public U64 ThreadID()
{
  return ThreadNativeID;
}

public U0 ThreadYield()
{
  ThreadNativeYield;
}

public U0 ThreadSleep(I64 milliseconds)
{
  if (milliseconds <= 0) {
    ThreadYield;
    return;
  }
  ThreadNativeSleep(milliseconds);
}

public U0 ThreadExit()
{
  ThreadNativeExit;
}

// TempleOS source commonly uses these two names directly.  Macros avoid
// exporting a symbol named Sleep, which would collide with Kernel32.
#define Yield ThreadYield
#define Sleep ThreadSleep

public Bool ThreadMutexInit(CThreadMutex *mutex)
{
  if (!mutex)
    return FALSE;
  MemSet(mutex, 0, sizeof(CThreadMutex));
  mutex->native = CAlloc(THREAD_NATIVE_BYTES);
  if (!mutex->native)
    return FALSE;
  if (!ThreadNativeMutexInit(mutex->native)) {
    Free(mutex->native);
    mutex->native = NULL;
    return FALSE;
  }
  return TRUE;
}

public Bool ThreadMutexFini(CThreadMutex *mutex)
{
  if (!mutex || !mutex->native)
    return FALSE;
  if (!ThreadNativeMutexFini(mutex->native))
    return FALSE;
  Free(mutex->native);
  mutex->native = NULL;
  return TRUE;
}

public Bool ThreadMutexLock(CThreadMutex *mutex)
{
  return mutex && mutex->native &&
    ThreadNativeMutexLock(mutex->native);
}

public Bool ThreadMutexTryLock(CThreadMutex *mutex)
{
  return mutex && mutex->native &&
    ThreadNativeMutexTryLock(mutex->native);
}

public Bool ThreadMutexUnlock(CThreadMutex *mutex)
{
  return mutex && mutex->native &&
    ThreadNativeMutexUnlock(mutex->native);
}

Bool ThreadConditionInit(CThreadCondition *condition)
{
  MemSet(condition, 0, sizeof(CThreadCondition));
  condition->native = CAlloc(THREAD_NATIVE_BYTES);
  if (!condition->native)
    return FALSE;
  if (!ThreadNativeConditionInit(condition->native)) {
    Free(condition->native);
    condition->native = NULL;
    return FALSE;
  }
  return TRUE;
}

Bool ThreadConditionFini(CThreadCondition *condition)
{
  if (!condition || !condition->native)
    return FALSE;
  if (!ThreadNativeConditionFini(condition->native))
    return FALSE;
  Free(condition->native);
  condition->native = NULL;
  return TRUE;
}

public Bool ThreadSemaphoreInit(CThreadSemaphore *semaphore,
  I64 initial = 0, I64 maximum = I64_MAX)
{
  if (!semaphore || initial < 0 || maximum <= 0 || initial > maximum)
    return FALSE;
  MemSet(semaphore, 0, sizeof(CThreadSemaphore));
  if (!ThreadMutexInit(&semaphore->mutex))
    return FALSE;
  if (!ThreadConditionInit(&semaphore->condition)) {
    ThreadMutexFini(&semaphore->mutex);
    return FALSE;
  }
  semaphore->value = initial;
  semaphore->maximum = maximum;
  return TRUE;
}

public Bool ThreadSemaphoreFini(CThreadSemaphore *semaphore)
{
  if (!semaphore)
    return FALSE;
  if (!ThreadConditionFini(&semaphore->condition))
    return FALSE;
  if (!ThreadMutexFini(&semaphore->mutex))
    return FALSE;
  semaphore->value = 0;
  semaphore->maximum = 0;
  return TRUE;
}

public Bool ThreadSemaphoreWait(CThreadSemaphore *semaphore)
{
  if (!semaphore || !ThreadMutexLock(&semaphore->mutex))
    return FALSE;
  while (!semaphore->value) {
    if (!ThreadNativeConditionWait(semaphore->condition.native,
        semaphore->mutex.native)) {
          ThreadMutexUnlock(&semaphore->mutex);
          return FALSE;
        }
  }
  semaphore->value--;
  return ThreadMutexUnlock(&semaphore->mutex);
}

public Bool ThreadSemaphoreTryWait(CThreadSemaphore *semaphore)
{
  Bool acquired = FALSE;

  if (!semaphore || !ThreadMutexLock(&semaphore->mutex))
    return FALSE;
  if (semaphore->value) {
    semaphore->value--;
    acquired = TRUE;
  }
  if (!ThreadMutexUnlock(&semaphore->mutex))
    return FALSE;
  return acquired;
}

public Bool ThreadSemaphorePost(CThreadSemaphore *semaphore, I64 count = 1)
{
  I64 i;
  Bool ok = TRUE;

  if (!semaphore || count <= 0 ||
    !ThreadMutexLock(&semaphore->mutex))
    return FALSE;
  if (count > semaphore->maximum - semaphore->value) {
    ThreadMutexUnlock(&semaphore->mutex);
    return FALSE;
  }
  semaphore->value += count;
  for (i = 0; i < count; i++)
    if (!ThreadNativeConditionSignal(semaphore->condition.native))
      ok = FALSE;
  if (!ThreadMutexUnlock(&semaphore->mutex))
    ok = FALSE;
  return ok;
}

public Bool ThreadSemaphoreSignal(CThreadSemaphore *semaphore)
{
  return ThreadSemaphorePost(semaphore);
}

public I64 ThreadSemaphoreValue(CThreadSemaphore *semaphore)
{
  I64 value;

  if (!semaphore || !ThreadMutexLock(&semaphore->mutex))
    return -1;
  value = semaphore->value;
  if (!ThreadMutexUnlock(&semaphore->mutex))
    return -1;
  return value;
}

public U0 ThreadLockInit(CThreadLock *spin)
{
  if (spin)
    spin->taken = 0;
}

public Bool ThreadLockTry(CThreadLock *spin)
{
  return spin && !LBts(&spin->taken, 0);
}

public Bool ThreadLockLock(CThreadLock *spin)
{
  if (!spin)
    return FALSE;
  while (LBts(&spin->taken, 0))
    ThreadYield;
  return TRUE;
}

public Bool ThreadLockUnlock(CThreadLock *spin)
{
  if (!spin)
    return FALSE;
  return LBtr(&spin->taken, 0);
}

public Bool ThreadTLSInit(CThreadTLS *tls, U8 *destructor = NULL)
{
  if (!tls)
    return FALSE;
  MemSet(tls, 0, sizeof(CThreadTLS));
  if (!ThreadNativeTLSInit(tls, destructor))
    return FALSE;
  tls->valid = TRUE;
  return TRUE;
}

public Bool ThreadTLSFini(CThreadTLS *tls)
{
  if (!tls || !tls->valid)
    return FALSE;
  if (!ThreadNativeTLSFini(tls))
    return FALSE;
  tls->key = 0;
  tls->valid = FALSE;
  return TRUE;
}

public U8 *ThreadTLSGet(CThreadTLS *tls)
{
  if (!tls || !tls->valid)
    return NULL;
  return ThreadNativeTLSGet(tls);
}

public Bool ThreadTLSSet(CThreadTLS *tls, U8 *value)
{
  return tls && tls->valid && ThreadNativeTLSSet(tls, value);
}

#endif
