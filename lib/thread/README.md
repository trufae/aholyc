# Portable threads

`thread.hc` is a small native thread library for aholyc on Linux, macOS, and
Windows. It exposes one HolyC API and keeps `pthread`/Win32 layouts out of
application classes.

```holyc
#include "lib/thread/thread.hc"

CThread thread;
CThreadMutex mutex;

U0 Worker(U8 *data)
{
  ThreadMutexLock(&mutex);
  "worker: %s\n", data;
  ThreadMutexUnlock(&mutex);
}

ThreadMutexInit(&mutex);
ThreadCreate(&thread, &Worker, "hello");
ThreadJoin(&thread);
ThreadMutexFini(&mutex);
```

The public API consists of:

- Threads: `ThreadCreate`, `ThreadJoin`, `ThreadDetach`, `ThreadID`,
  `ThreadYield`, `ThreadSleep`, and `ThreadExit`.
- Mutexes: `ThreadMutexInit`, `ThreadMutexFini`, `ThreadMutexLock`,
  `ThreadMutexTryLock`, and `ThreadMutexUnlock`.
- Counting semaphores: `ThreadSemaphoreInit`, `ThreadSemaphoreFini`,
  `ThreadSemaphoreWait`, `ThreadSemaphoreTryWait`, `ThreadSemaphorePost`,
  `ThreadSemaphoreSignal`, and `ThreadSemaphoreValue`. `ThreadSemaphore` is
  accepted as a compatibility spelling of `CThreadSemaphore`.
- Spin locks: `ThreadLockInit`, `ThreadLockLock`, `ThreadLockTry`, and
  `ThreadLockUnlock`.
- Thread-local storage: `ThreadTLSInit`, `ThreadTLSFini`, `ThreadTLSGet`, and
  `ThreadTLSSet`. `ThreadTLSInit` accepts an optional destructor callback.

All constructors and operations that can fail return `Bool`. A `CThread`
must be joined or detached exactly once. Destroy mutexes and semaphores only
after every user has stopped, and destroy a TLS key only after its threads
have stopped. Thread entry functions use the portable `U0 Fn(U8 *data)`
shape; an internal trampoline supplies the native pthread/Win32 return value.

## TempleOS correspondence

Hosted OS threads cannot reproduce TempleOS `CTask` fields, core selection,
or parent-task ownership. The close, portable mappings are:

| TempleOS idiom | Hosted API |
| --- | --- |
| `Spawn(&Fn, data)` | `ThreadSpawn(&thread, &Fn, data)` |
| `TaskWait(task)` | `ThreadWait(&thread)` |
| `Yield` / `Sleep(ms)` | Same names, or `ThreadYield` / `ThreadSleep` |
| `while (LBts(&flag, bit)) Yield` | `CThreadLock` |
| `LBtr(&flag, bit)` | `ThreadLockUnlock` |
| `Fs` task-local state | `CThreadTLS` |

`CThreadLock` deliberately follows TempleOS's `LBts`/`LBtr` spin-lock style.
Use it only for very short critical sections. `CThreadMutex` is a sleeping,
non-recursive mutex and is preferable around blocking or longer work.

The older `third_party/holyc-lang` implementation directly mirrors libc
`pthread` structures. This library instead allocates opaque, aligned native
storage, which avoids depending on glibc or Darwin private layouts and makes
the application-facing classes identical on every target.

## Cross-building

Normal native builds select the backend from aholyc's `IS_WINDOWS` and
`IS_UNIX` macros. When the compiler host differs from the target, define
exactly one override:

```console
CC=demos/windows/ccwin.sh ./aholyc -b c -DTHREAD_WINDOWS app.hc -o app.exe
```

`THREAD_POSIX` is the corresponding override for a Linux or macOS target.
The JavaScript backend is not supported because it has no native threads or
foreign-symbol loader.
