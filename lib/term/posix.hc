// termios backend shared by Linux and macOS.
//
// SIGINT and SIGWINCH handlers only set flags, radare2's r_cons style: the
// application polls TermInterrupted, and resizes surface as events from the
// next TermPollEvent or TermCommit.  Keeping ISIG on in raw mode means ^C
// always reaches the SIGINT handler instead of arriving as a key.

// These return C int, so every result below is narrowed with (I32): the
// upper half of the returned register is undefined and would otherwise turn
// -1 into a large positive value.  read and write return ssize_t.
extern I64 read(I64 fd, U8 *buffer, I64 count);
extern I64 write(I64 fd, U8 *buffer, I64 count);
// ioctl is variadic in libc: on arm64 Darwin variadic arguments travel on
// the stack, so a fixed prototype loses the argument pointer.
extern I64 ioctl(I64 fd, U64 request, ...);
extern I64 tcgetattr(I64 fd, U8 *state);
extern I64 tcsetattr(I64 fd, I64 actions, U8 *state);
U0 TermPosixHandler(I64 number); // signal handler shape
extern U8 *signal(I64 number, TermPosixHandler *handler);
extern I64 poll(U8 *fds, U64 count, I64 timeout);
extern I64 isatty(I64 fd);
extern I64 clock_gettime(I64 clock, U8 *timespec);

#ifdef IS_MACOS
#define TERM_CLOCK_MONOTONIC 6
#else
#define TERM_CLOCK_MONOTONIC 1
#endif

I64 TermNativeMs()
{
  I64 stamp[2];

  if (clock_gettime(TERM_CLOCK_MONOTONIC, stamp)(I32))
    return 0;
  return stamp[0] * 1000 + stamp[1] / 1000000;
}

#define TERM_SIGINT   2
#define TERM_SIGWINCH 28
#define TERM_POLLIN   1

// struct termios layout: flag words first, then the control characters.
#ifdef IS_MACOS
#define TERM_FLAG U64
#define TERM_TIOCGWINSZ 0x40087468
#define TERM_ICANON 0x100
#define TERM_ECHO   0x8
#define TERM_IEXTEN 0x400
#define TERM_IXON   0x200
#define TERM_ICRNL  0x100
#define TERM_INLCR  0x40
#define TERM_CC     32
#define TERM_VMIN   16
#define TERM_VTIME  17
#else
#define TERM_FLAG U32
#define TERM_TIOCGWINSZ 0x5413
#define TERM_ICANON 0x2
#define TERM_ECHO   0x8
#define TERM_IEXTEN 0x8000
#define TERM_IXON   0x400
#define TERM_ICRNL  0x100
#define TERM_INLCR  0x40
#define TERM_CC     17
#define TERM_VMIN   6
#define TERM_VTIME  5
#endif

// Waiting this long after ESC separates the key from escape sequences.
#define TERM_ESC_TIMEOUT 25

// Blocking waits poll in slices this long: the kernel restarts poll after
// our SIGINT handler runs, so ^C and resizes are noticed between slices.
#define TERM_WAIT_SLICE 100

U8 term_posix_saved[128];
Bool term_posix_raw;
U8 *term_posix_old_int;
U8 *term_posix_old_winch;
U8 term_posix_queue[8];
I64 term_posix_queued;

U0 TermPosixInterrupt(I64 number)
{
  term_interrupted = TRUE;
}

U0 TermPosixResize(I64 number)
{
  term_resize_pending = TRUE;
}

Bool TermNativeInit()
{
  if (!isatty(0)(I32) || !isatty(1)(I32))
    return FALSE;
  term_posix_raw = FALSE;
  term_posix_queued = 0;
  term_posix_old_int = signal(TERM_SIGINT, &TermPosixInterrupt);
  term_posix_old_winch = signal(TERM_SIGWINCH, &TermPosixResize);
  return TRUE;
}

U0 TermNativeFini()
{
  signal(TERM_SIGINT, term_posix_old_int(TermPosixHandler *));
  signal(TERM_SIGWINCH, term_posix_old_winch(TermPosixHandler *));
}

Bool TermNativeSize(I64 *width, I64 *height)
{
  U8 window[8];
  U16 *sizes = window;

  MemSet(window, 0, 8);
  if (ioctl(1, TERM_TIOCGWINSZ, window)(I32) || !sizes[0] || !sizes[1]) {
    *width = 80;
    *height = 25;
    return TRUE;
  }
  *height = sizes[0];
  *width = sizes[1];
  return TRUE;
}

Bool TermNativeRawOn()
{
  U8 state[128];
  TERM_FLAG *flags = state;

  if (term_posix_raw)
    return TRUE;
  if (tcgetattr(0, term_posix_saved)(I32))
    return FALSE;
  MemCpy(state, term_posix_saved, 128);
  flags[0] &= ~(TERM_IXON | TERM_ICRNL | TERM_INLCR);
  flags[3] &= ~(TERM_ICANON | TERM_ECHO | TERM_IEXTEN);
  state[TERM_CC + TERM_VMIN] = 1;
  state[TERM_CC + TERM_VTIME] = 0;
  if (tcsetattr(0, 0, state)(I32))
    return FALSE;
  term_posix_raw = TRUE;
  return TRUE;
}

Bool TermNativeRawOff()
{
  if (!term_posix_raw)
    return TRUE;
  if (tcsetattr(0, 0, term_posix_saved)(I32))
    return FALSE;
  term_posix_raw = FALSE;
  return TRUE;
}

U0 TermNativeWrite(U8 *bytes, I64 count)
{
  I64 written;
  I64 retries = 8;

  while (count > 0) {
    written = write(1, bytes, count);
    if (written < 0) {
      // Signals interrupt write; anything more persistent is fatal.
      retries--;
      if (retries < 0)
        return;
    } else if (!written) {
      return;
    } else {
      bytes += written;
      count -= written;
    }
  }
}

U0 TermNativeMouse(Bool enable)
{
  U8 *sequence;

  if (enable)
    sequence = "\x1B[?1002h\x1B[?1006h";
  else
    sequence = "\x1B[?1006l\x1B[?1002l";
  TermNativeWrite(sequence, StrLen(sequence));
}

Bool TermNativeLegacy()
{
  return FALSE;
}

U0 TermNativeAltScreen(Bool enable)
{
}

U0 TermNativeBlit(I64 x, I64 y, U64 *cells, I64 count)
{
}

U0 TermNativeCursor(I64 x, I64 y, Bool visible)
{
}

// One byte of input, honoring the pushback queue; FALSE on timeout,
// interrupt, or pending resize.
Bool TermPosixByte(I64 *byte, I64 timeout)
{
  U8 one;
  U8 pollfd[8];
  I16 *shorts = pollfd;
  I64 i, slice, ready;

  if (term_posix_queued) {
    *byte = term_posix_queue[0];
    term_posix_queued--;
    for (i = 0; i < term_posix_queued; i++)
      term_posix_queue[i] = term_posix_queue[i + 1];
    return TRUE;
  }
  MemSet(pollfd, 0, 8);
  shorts[2] = TERM_POLLIN;
  while (TRUE) {
    slice = TERM_WAIT_SLICE;
    if (timeout >= 0 && timeout < slice)
      slice = timeout;
    ready = poll(pollfd, 1, slice)(I32);
    if (ready > 0)
      break;
    if (term_interrupted || term_resize_pending)
      return FALSE;
    if (timeout >= 0) {
      timeout -= slice;
      if (timeout <= 0)
        return FALSE;
    }
  }
  if (read(0, &one, 1) != 1)
    return FALSE;
  *byte = one;
  return TRUE;
}

U0 TermPosixUnByte(I64 byte)
{
  if (term_posix_queued < 8)
    term_posix_queue[term_posix_queued++] = byte;
}

I64 TermPosixTildeKey(I64 code)
{
  if (code == 1 || code == 7)
    return TERM_KEY_HOME;
  if (code == 2)
    return TERM_KEY_INSERT;
  if (code == 3)
    return TERM_KEY_DELETE;
  if (code == 4 || code == 8)
    return TERM_KEY_END;
  if (code == 5)
    return TERM_KEY_PGUP;
  if (code == 6)
    return TERM_KEY_PGDN;
  if (code >= 11 && code <= 15)
    return TERM_KEY_F1 + code - 11;
  if (code >= 17 && code <= 21)
    return TERM_KEY_F6 + code - 17;
  if (code == 23 || code == 24)
    return TERM_KEY_F11 + code - 23;
  return 0;
}

I64 TermPosixFinalKey(I64 final)
{
  if (final == 'A')
    return TERM_KEY_UP;
  if (final == 'B')
    return TERM_KEY_DOWN;
  if (final == 'C')
    return TERM_KEY_RIGHT;
  if (final == 'D')
    return TERM_KEY_LEFT;
  if (final == 'H')
    return TERM_KEY_HOME;
  if (final == 'F')
    return TERM_KEY_END;
  return 0;
}

// SGR 1006 mouse report: ESC [ < button ; column ; row (M|m).
U0 TermPosixMouse(CTermEvent *event, I64 *params, I64 final)
{
  I64 button = params[0];
  I64 base = button & 3;

  event->type = TERM_EVENT_MOUSE;
  event->x = params[1] - 1;
  event->y = params[2] - 1;
  if (button & 4)
    event->mods |= TERM_MOD_SHIFT;
  if (button & 8)
    event->mods |= TERM_MOD_ALT;
  if (button & 16)
    event->mods |= TERM_MOD_CTRL;
  if (button & 64) {
    event->button = TERM_MOUSE_WHEEL_UP + (button & 1);
    event->pressed = TRUE;
    return;
  }
  if (base < 3)
    event->button = base + 1;
  event->pressed = final == 'M' && base < 3;
  event->motion = (button & 32) != 0;
}

// ESC [ params final, after the "ESC [" prefix has been consumed.
Bool TermPosixCsi(CTermEvent *event)
{
  I64 params[4];
  I64 count = 0;
  I64 value = 0;
  I64 byte, key;
  Bool mouse = FALSE;

  params[0] = 0;
  params[1] = 0;
  params[2] = 0;
  params[3] = 0;
  while (TRUE) {
    if (!TermPosixByte(&byte, TERM_ESC_TIMEOUT))
      return FALSE;
    if (byte >= '0' && byte <= '9') {
      value = value * 10 + byte - '0';
    } else if (byte == ';') {
      if (count < 4)
        params[count] = value;
      count++;
      value = 0;
    } else if (byte == '<') {
      mouse = TRUE;
    } else if (byte >= 0x40) {
      if (count < 4)
        params[count] = value;
      count++;
      break;
    }
    // Anything else is an intermediate byte; skip it.
  }
  if (mouse && (byte == 'M' || byte == 'm')) {
    TermPosixMouse(event, params, byte);
    return TRUE;
  }
  if (byte == '~') {
    key = TermPosixTildeKey(params[0]);
    if (count >= 2 && params[1] > 0)
      event->mods = params[1] - 1;
  } else if (byte == 'Z') {
    key = TERM_KEY_TAB;
    event->mods = TERM_MOD_SHIFT;
  } else {
    key = TermPosixFinalKey(byte);
    if (count >= 2 && params[1] > 0)
      event->mods = params[1] - 1;
  }
  if (!key)
    return FALSE;
  event->type = TERM_EVENT_KEY;
  event->key = key;
  return TRUE;
}

Bool TermPosixEscape(CTermEvent *event)
{
  I64 byte, key;

  if (!TermPosixByte(&byte, TERM_ESC_TIMEOUT)) {
    event->type = TERM_EVENT_KEY;
    event->key = TERM_KEY_ESCAPE;
    return TRUE;
  }
  if (byte == '[')
    return TermPosixCsi(event);
  if (byte == 'O') {
    if (!TermPosixByte(&byte, TERM_ESC_TIMEOUT))
      return FALSE;
    if (byte >= 'P' && byte <= 'S')
      key = TERM_KEY_F1 + byte - 'P';
    else
      key = TermPosixFinalKey(byte);
    if (!key)
      return FALSE;
    event->type = TERM_EVENT_KEY;
    event->key = key;
    return TRUE;
  }
  // ESC prefix acts as an Alt modifier on the following key.
  TermPosixUnByte(byte);
  event->mods = TERM_MOD_ALT;
  return FALSE;
}

Bool TermPosixKey(CTermEvent *event, I64 byte)
{
  U8 bytes[4];
  I64 need, i, rune;

  if (byte == 0x1B)
    return TermPosixEscape(event);
  event->type = TERM_EVENT_KEY;
  if (byte == '\r' || byte == '\n') {
    event->key = TERM_KEY_ENTER;
    return TRUE;
  }
  if (byte == 8 || byte == 127) {
    event->key = TERM_KEY_BACKSPACE;
    return TRUE;
  }
  if (byte == '\t') {
    event->key = TERM_KEY_TAB;
    return TRUE;
  }
  if (byte > 0 && byte < 27) {
    event->key = 'a' + byte - 1;
    event->mods |= TERM_MOD_CTRL;
    return TRUE;
  }
  if (byte < 0x80) {
    event->key = byte;
    return TRUE;
  }
  bytes[0] = byte;
  need = 1;
  if (byte >= 0xF0)
    need = 3;
  else if (byte >= 0xE0)
    need = 2;
  for (i = 0; i < need; i++) {
    if (!TermPosixByte(&byte, TERM_ESC_TIMEOUT))
      return FALSE;
    bytes[i + 1] = byte;
  }
  if (!Utf8DecodeRune(bytes, need + 1, &rune))
    rune = RUNE_REPLACEMENT;
  event->key = rune;
  return TRUE;
}

Bool TermNativePoll(CTermEvent *event, I64 timeout_ms)
{
  I64 byte;

  if (term_resize_pending) {
    event->type = TERM_EVENT_RESIZE;
    return TRUE;
  }
  if (!TermPosixByte(&byte, timeout_ms)) {
    // A signal may have interrupted the wait.
    if (term_resize_pending) {
      event->type = TERM_EVENT_RESIZE;
      return TRUE;
    }
    return FALSE;
  }
  if (TermPosixKey(event, byte))
    return TRUE;
  // An Alt prefix left the real key queued; read it as its own event.
  if (event->mods & TERM_MOD_ALT && TermPosixByte(&byte, 0))
    return TermPosixKey(event, byte);
  return FALSE;
}

// One cooked byte from standard input; -1 on end of input or interrupt.
// Works without TermNativeInit, so pipes and files feed line input too.
I64 TermNativeReadByte()
{
  U8 one;
  I64 got;

  while (TRUE) {
    got = read(0, &one, 1);
    if (got == 1)
      return one;
    if (got >= 0 || term_interrupted)
      return -1;
    // Signals interrupt reads; retry.
  }
}

I64 TermNativeReadLine(U8 *buffer, I64 capacity)
{
  Bool was_raw = term_posix_raw;
  I64 length = 0;
  I64 got;
  U8 one;

  if (was_raw)
    TermNativeRawOff;
  while (TRUE) {
    got = read(0, &one, 1);
    if (got < 0) {
      // Interrupted reads retry unless the user hit ^C.
      if (term_interrupted)
        break;
    } else if (!got || one == '\n') {
      break;
    } else if (length < capacity - 1) {
      buffer[length++] = one;
    }
  }
  buffer[length] = 0;
  if (was_raw)
    TermNativeRawOn;
  if (!got && !length)
    return -1;
  return length;
}
