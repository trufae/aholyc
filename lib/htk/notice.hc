// Desktop notifications: right-aligned cards above the window bar.  They are
// intentionally independent of windows, so background work can post one
// without constructing a dialog or stealing keyboard focus.

U0 HtkNoticeFree(HtkNotice *n)
{
  Free(n->text);
  Free(n);
}

U0 HtkNoticeClose(HtkNotice *n)
{
  HtkNotice **at = &htk_notices;

  if (!n || n->closed)
    return;
  while (*at && *at != n)
    at = &(*at)->next;
  if (*at == n)
    *at = n->next;
  n->closed = TRUE;
  htk_dirty = TRUE;
  // A timed notice stays allocated until its already-queued hook fires.
  if (!n->timer)
    HtkNoticeFree(n);
}

U0 HtkNoticeExpire(I64 notice, I64 unused)
{
  HtkNotice *n = notice;

  n->timer = FALSE;
  if (n->closed)
    HtkNoticeFree(n);
  else
    HtkNoticeClose(n);
}

// Post text at the lower-right corner.  dismiss_ms == 0 keeps it visible
// until its [x] is clicked; otherwise it disappears after that many ms.
HtkNotice *HtkNotify(U8 *text, I64 dismiss_ms=0)
{
  HtkNotice *n = CAlloc(sizeof(HtkNotice));
  I64 max_w = TermWidth - 2;

  if (max_w < 8)
    max_w = 8;
  n->text = StrNew(text);
  n->w = HtkRunes(text) + 7;  // padding, [x], and borders
  if (n->w < 20)
    n->w = 20;
  if (n->w > max_w)
    n->w = max_w;
  n->h = 3;
  n->next = htk_notices;
  htk_notices = n;
  if (dismiss_ms > 0) {
    n->timer = TRUE;
    HtkHookAdd(dismiss_ms, 0, &HtkNoticeExpire, n, 0);
  }
  htk_dirty = TRUE;
  return n;
}

U0 HtkNoticesDraw()
{
  HtkNotice *n = htk_notices;
  I64 y = TermHeight - HtkTaskbarHeight - 3;

  while (n) {
    n->x = TermWidth - n->w - 1;
    if (n->x < 0)
      n->x = 0;
    n->y = y;
    if (y >= 0) {
      HtkRect(n->x, y, n->w, n->h, ' ', HTK_C_FG, HTK_C_BG);
      HtkFrame(n->x, y, n->w, n->h, FALSE, HTK_C_FRAME, HTK_C_BG);
      HtkClipPush;
      HtkClipSet(n->x + 2, y + 1, n->w - 7, 1);
      HtkStr(n->x + 2, y + 1, n->text, HTK_C_FG, HTK_C_BG);
      HtkClipPop;
      HtkStr(n->x + n->w - 4, y + 1, "[x]", HTK_C_BTN_BG, HTK_C_BG);
    }
    y -= n->h + 1;
    n = n->next;
  }
}

// Notifications sit above windows and consume clicks, so their close button
// cannot activate the window underneath.
Bool HtkNoticesMouse(CTermEvent *e)
{
  HtkNotice *n = htk_notices;

  while (n) {
    if (e->x >= n->x && e->x < n->x + n->w &&
      e->y >= n->y && e->y < n->y + n->h) {
      if (e->pressed && !e->motion && e->button == TERM_MOUSE_LEFT &&
        e->x >= n->x + n->w - 4 && e->y == n->y + 1)
        HtkNoticeClose(n);
      return TRUE;
    }
    n = n->next;
  }
  return FALSE;
}
