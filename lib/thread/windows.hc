// Win32 backend.  SRW locks are non-recursive like default pthread mutexes,
// and condition variables let the generic semaphore avoid polling.

#define THREAD_WAIT_OBJECT_0 0
#define THREAD_INFINITE      0xFFFFFFFF
#define THREAD_FLS_INVALID   0xFFFFFFFF

extern U8 *CreateThread(U8 *attributes, U64 stack_size, U8 *entry,
  U8 *data, U32 flags, U32 *thread_id);
extern U32 WaitForSingleObject(U8 *handle, U32 milliseconds);
extern Bool CloseHandle(U8 *handle);
extern U32 GetCurrentThreadId();
extern Bool SwitchToThread();
extern U32 SleepEx(U32 milliseconds, Bool alertable);
extern U0 ExitThread(U32 exit_code);

extern U0 InitializeSRWLock(U8 *srw);
extern U0 AcquireSRWLockExclusive(U8 *srw);
extern Bool TryAcquireSRWLockExclusive(U8 *srw);
extern U0 ReleaseSRWLockExclusive(U8 *srw);

extern U0 InitializeConditionVariable(U8 *condition);
extern Bool SleepConditionVariableSRW(U8 *condition, U8 *srw,
  U32 milliseconds, U32 flags);
extern U0 WakeConditionVariable(U8 *condition);

extern U32 FlsAlloc(U8 *destructor);
extern Bool FlsFree(U32 key);
extern U8 *FlsGetValue(U32 key);
extern Bool FlsSetValue(U32 key, U8 *value);

Bool ThreadNativeCreate(CThread *thread, U8 *entry, U8 *data)
{
  thread->handle = CreateThread(NULL, 0, entry, data, 0, NULL);
  return thread->handle != NULL;
}

Bool ThreadNativeJoin(CThread *thread)
{
  if (WaitForSingleObject(thread->handle, THREAD_INFINITE) !=
    THREAD_WAIT_OBJECT_0)
    return FALSE;
  return CloseHandle(thread->handle);
}

Bool ThreadNativeDetach(CThread *thread)
{
  return CloseHandle(thread->handle);
}

U64 ThreadNativeID()
{
  return GetCurrentThreadId;
}

U0 ThreadNativeYield()
{
  SwitchToThread;
}

U0 ThreadNativeSleep(I64 milliseconds)
{
  while (milliseconds > 0xFFFFFFFE) {
    SleepEx(0xFFFFFFFE, FALSE);
    milliseconds -= 0xFFFFFFFE;
  }
  SleepEx(milliseconds, FALSE);
}

U0 ThreadNativeExit()
{
  ExitThread(0);
}

Bool ThreadNativeMutexInit(U64 *native)
{
  InitializeSRWLock(native);
  return TRUE;
}

Bool ThreadNativeMutexFini(U64 *native)
{
  return native != NULL;
}

Bool ThreadNativeMutexLock(U64 *native)
{
  AcquireSRWLockExclusive(native);
  return TRUE;
}

Bool ThreadNativeMutexTryLock(U64 *native)
{
  return TryAcquireSRWLockExclusive(native);
}

Bool ThreadNativeMutexUnlock(U64 *native)
{
  ReleaseSRWLockExclusive(native);
  return TRUE;
}

Bool ThreadNativeConditionInit(U64 *native)
{
  InitializeConditionVariable(native);
  return TRUE;
}

Bool ThreadNativeConditionFini(U64 *native)
{
  return native != NULL;
}

Bool ThreadNativeConditionWait(U64 *condition, U64 *mutex)
{
  return SleepConditionVariableSRW(condition, mutex, THREAD_INFINITE, 0);
}

Bool ThreadNativeConditionSignal(U64 *condition)
{
  WakeConditionVariable(condition);
  return TRUE;
}

Bool ThreadNativeTLSInit(CThreadTLS *tls, U8 *destructor)
{
  tls->key = FlsAlloc(destructor);
  return tls->key != THREAD_FLS_INVALID;
}

Bool ThreadNativeTLSFini(CThreadTLS *tls)
{
  return FlsFree(tls->key);
}

U8 *ThreadNativeTLSGet(CThreadTLS *tls)
{
  return FlsGetValue(tls->key);
}

Bool ThreadNativeTLSSet(CThreadTLS *tls, U8 *value)
{
  return FlsSetValue(tls->key, value);
}
