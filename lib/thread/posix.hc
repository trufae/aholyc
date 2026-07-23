// pthread backend shared by Linux and macOS.
// @ldflags=-pthread

extern I64 pthread_create(U8 **thread, U8 *attributes, U8 *entry, U8 *data);
extern I64 pthread_join(U8 *thread, U8 **value);
extern I64 pthread_detach(U8 *thread);
extern U64 pthread_self();
extern U0 pthread_exit(U8 *value);

extern I64 pthread_mutex_init(U8 *mutex, U8 *attributes);
extern I64 pthread_mutex_destroy(U8 *mutex);
extern I64 pthread_mutex_lock(U8 *mutex);
extern I64 pthread_mutex_trylock(U8 *mutex);
extern I64 pthread_mutex_unlock(U8 *mutex);

extern I64 pthread_cond_init(U8 *condition, U8 *attributes);
extern I64 pthread_cond_destroy(U8 *condition);
extern I64 pthread_cond_wait(U8 *condition, U8 *mutex);
extern I64 pthread_cond_signal(U8 *condition);

extern I64 pthread_key_create(U32 *key, U8 *destructor);
extern I64 pthread_key_delete(U32 key);
extern U8 *pthread_getspecific(U32 key);
extern I64 pthread_setspecific(U32 key, U8 *value);

extern I64 sched_yield();
extern I64 usleep(U32 microseconds);

Bool ThreadNativeCreate(CThread *thread, U8 *entry, U8 *data)
{
  return !pthread_create(&thread->handle, NULL, entry, data);
}

Bool ThreadNativeJoin(CThread *thread)
{
  return !pthread_join(thread->handle, NULL);
}

Bool ThreadNativeDetach(CThread *thread)
{
  return !pthread_detach(thread->handle);
}

U64 ThreadNativeID()
{
  return pthread_self;
}

U0 ThreadNativeYield()
{
  sched_yield;
}

U0 ThreadNativeSleep(I64 milliseconds)
{
  while (milliseconds >= 1000) {
    usleep(999000);
    milliseconds -= 999;
  }
  if (milliseconds)
    usleep(milliseconds * 1000);
}

U0 ThreadNativeExit()
{
  pthread_exit(NULL);
}

Bool ThreadNativeMutexInit(U64 *native)
{
  return !pthread_mutex_init(native, NULL);
}

Bool ThreadNativeMutexFini(U64 *native)
{
  return !pthread_mutex_destroy(native);
}

Bool ThreadNativeMutexLock(U64 *native)
{
  return !pthread_mutex_lock(native);
}

Bool ThreadNativeMutexTryLock(U64 *native)
{
  return !pthread_mutex_trylock(native);
}

Bool ThreadNativeMutexUnlock(U64 *native)
{
  return !pthread_mutex_unlock(native);
}

Bool ThreadNativeConditionInit(U64 *native)
{
  return !pthread_cond_init(native, NULL);
}

Bool ThreadNativeConditionFini(U64 *native)
{
  return !pthread_cond_destroy(native);
}

Bool ThreadNativeConditionWait(U64 *condition, U64 *mutex)
{
  return !pthread_cond_wait(condition, mutex);
}

Bool ThreadNativeConditionSignal(U64 *condition)
{
  return !pthread_cond_signal(condition);
}

Bool ThreadNativeTLSInit(CThreadTLS *tls, U8 *destructor)
{
  return !pthread_key_create(&tls->key, destructor);
}

Bool ThreadNativeTLSFini(CThreadTLS *tls)
{
  return !pthread_key_delete(tls->key);
}

U8 *ThreadNativeTLSGet(CThreadTLS *tls)
{
  return pthread_getspecific(tls->key);
}

Bool ThreadNativeTLSSet(CThreadTLS *tls, U8 *value)
{
  return !pthread_setspecific(tls->key, value);
}
