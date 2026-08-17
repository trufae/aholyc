// Tiling layout containers: box (linear), grid, split (two panes), and
// scroll (viewport).  Measure is bottom-up into pw/ph, layout is top-down
// from the assigned x/y/w/h rect.

#define HTK_GRID_MAX 64

U0 HtkBoxMeasure(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 n = 0;

  c->pw = 0;
  c->ph = 0;
  while (k) {
    HtkMeasureCtl(k);
    if (!k->hidden) {
      if (c->vertical) {
        if (k->pw > c->pw)
          c->pw = k->pw;
        c->ph += k->ph;
      } else {
        c->pw += k->pw;
        if (k->ph > c->ph)
          c->ph = k->ph;
        n++;
      }
    }
    k = k->sib;
  }
  if (!c->vertical && n > 1)
    c->pw += n - 1;  // one column of air between horizontal kids
}

U0 HtkBoxLayout(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 fixed = 0, stretchy = 0, extra, at;

  while (k) {
    if (!k->hidden) {
      if (c->vertical)
        fixed += k->ph;
      else
        fixed += k->pw + 1;
      if (k->expand)
        stretchy++;
    }
    k = k->sib;
  }
  if (!c->vertical && fixed)
    fixed--;
  if (c->vertical)
    extra = c->h - fixed;
  else
    extra = c->w - fixed;
  if (extra < 0)
    extra = 0;
  if (c->vertical)
    at = c->y;
  else
    at = c->x;
  k = c->kids;
  while (k) {
    if (!k->hidden) {
      if (c->vertical) {
        k->x = c->x;
        k->y = at;
        k->w = c->w;
        k->h = k->ph;
      } else {
        k->x = at;
        k->y = c->y;
        k->w = k->pw;
        k->h = c->h;
      }
      if (k->expand && stretchy) {
        if (c->vertical)
          k->h += extra / stretchy;
        else
          k->w += extra / stretchy;
      }
      if (c->vertical)
        at += k->h;
      else
        at += k->w + 1;
      HtkLayoutCtl(k);
    }
    k = k->sib;
  }
}

U0 HtkGridMeasure(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 cols[HTK_GRID_MAX];
  I64 rows[HTK_GRID_MAX];
  I64 i, ncols = 0, nrows = 0;

  MemSet(cols, 0, sizeof(cols));
  MemSet(rows, 0, sizeof(rows));
  while (k) {
    HtkMeasureCtl(k);
    if (!k->hidden && k->col < HTK_GRID_MAX && k->row < HTK_GRID_MAX) {
      if (k->pw > cols[k->col])
        cols[k->col] = k->pw;
      if (k->ph > rows[k->row])
        rows[k->row] = k->ph;
      if (k->col >= ncols)
        ncols = k->col + 1;
      if (k->row >= nrows)
        nrows = k->row + 1;
    }
    k = k->sib;
  }
  c->pw = 0;
  c->ph = 0;
  for (i = 0; i < ncols; i++)
    c->pw += cols[i] + 1;
  if (ncols)
    c->pw--;
  for (i = 0; i < nrows; i++)
    c->ph += rows[i];
}

U0 HtkGridLayout(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 cols[HTK_GRID_MAX];
  I64 rows[HTK_GRID_MAX];
  I64 i, x, y;
  Bool grow[HTK_GRID_MAX];
  I64 ncols = 0, used = 0, stretchy = 0;

  MemSet(cols, 0, sizeof(cols));
  MemSet(rows, 0, sizeof(rows));
  MemSet(grow, 0, sizeof(grow));
  while (k) {
    if (!k->hidden && k->col < HTK_GRID_MAX && k->row < HTK_GRID_MAX) {
      if (k->pw > cols[k->col])
        cols[k->col] = k->pw;
      if (k->ph > rows[k->row])
        rows[k->row] = k->ph;
      if (k->expand)
        grow[k->col] = TRUE;
      if (k->col >= ncols)
        ncols = k->col + 1;
    }
    k = k->sib;
  }
  // Columns holding an expanding kid share the spare width.
  for (i = 0; i < ncols; i++) {
    used += cols[i] + 1;
    if (grow[i])
      stretchy++;
  }
  if (ncols)
    used--;
  for (i = 0; i < ncols && stretchy && used < c->w; i++)
    if (grow[i])
      cols[i] += (c->w - used) / stretchy;
  k = c->kids;
  while (k) {
    if (!k->hidden) {
      x = c->x;
      for (i = 0; i < k->col; i++)
        x += cols[i] + 1;
      y = c->y;
      for (i = 0; i < k->row; i++)
        y += rows[i];
      k->x = x;
      k->y = y;
      k->w = cols[k->col];
      k->h = rows[k->row];
      HtkLayoutCtl(k);
    }
    k = k->sib;
  }
}

U0 HtkSplitMeasure(HtkCtl *c)
{
  HtkBoxMeasure(c);
  if (c->vertical)
    c->ph++;
  else
    c->pw++;
}

// First pane keeps its preferred size, the second takes the rest.
U0 HtkSplitLayout(HtkCtl *c)
{
  HtkCtl *one = c->kids;
  HtkCtl *two;
  I64 keep;

  if (!one)
    return;
  two = one->sib;
  one->x = c->x;
  one->y = c->y;
  if (c->vertical) {
    keep = one->ph;
    if (keep > c->h - 2)
      keep = c->h / 2;
    one->w = c->w;
    one->h = keep;
    if (two) {
      two->x = c->x;
      two->y = c->y + keep + 1;
      two->w = c->w;
      two->h = c->h - keep - 1;
    }
  } else {
    keep = one->pw;
    if (keep > c->w - 2)
      keep = c->w / 2;
    one->w = keep;
    one->h = c->h;
    if (two) {
      two->x = c->x + keep + 1;
      two->y = c->y;
      two->w = c->w - keep - 1;
      two->h = c->h;
    }
  }
  HtkLayoutCtl(one);
  if (two)
    HtkLayoutCtl(two);
}

U0 HtkSplitDraw(HtkCtl *c)
{
  HtkCtl *one = c->kids;
  I64 i;

  if (!one)
    return;
  if (c->vertical)
    for (i = c->x; i < c->x + c->w; i++)
      HtkChr(i, c->y + one->h, HTK_R_H, HTK_C_DIM, HTK_C_BG);
  else
    for (i = c->y; i < c->y + c->h; i++)
      HtkChr(c->x + one->w, i, HTK_R_V, HTK_C_DIM, HTK_C_BG);
}

U0 HtkScrollMeasure(HtkCtl *c)
{
  if (c->kids)
    HtkMeasureCtl(c->kids);
  c->pw = 10;
  c->ph = 4;
}

U0 HtkScrollLayout(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 span;

  if (!k)
    return;
  span = k->ph - c->h;
  if (span < 0)
    span = 0;
  if (c->top > span)
    c->top = span;
  k->x = c->x;
  k->y = c->y - c->top;
  k->w = c->w - 1;  // leave room for the scrollbar
  k->h = k->ph;
  if (k->h < c->h)  // short content still fills the viewport
    k->h = c->h;
  HtkLayoutCtl(k);
}

U0 HtkScrollDraw(HtkCtl *c)
{
  HtkCtl *k = c->kids;
  I64 i, at, bar;
  I64 ox = htk_clip_x, oy = htk_clip_y, ox2 = htk_clip_x2, oy2 = htk_clip_y2;

  if (!k)
    return;
  HtkClipSet(c->x, c->y, c->w - 1, c->h);
  HtkDrawCtl(k);
  htk_clip_x = ox;
  htk_clip_y = oy;
  htk_clip_x2 = ox2;
  htk_clip_y2 = oy2;
  for (i = 0; i < c->h; i++)
    HtkChr(c->x + c->w - 1, c->y + i, HTK_R_LIGHT, HTK_C_DIM, HTK_C_BG);
  if (k->ph > c->h) {
    bar = c->h * c->h / k->ph;
    if (bar < 1)
      bar = 1;
    at = c->top * (c->h - bar) / (k->ph - c->h);
    for (i = 0; i < bar; i++)
      HtkChr(c->x + c->w - 1, c->y + at + i, HTK_R_MED, HTK_C_FG, HTK_C_BG);
  }
}

Bool HtkScrollKey(HtkCtl *c, CTermEvent *e)
{
  I64 was = c->top;
  I64 page = c->h - 1;

  if (e->key == TERM_KEY_UP)
    c->top--;
  else if (e->key == TERM_KEY_DOWN)
    c->top++;
  else if (e->key == TERM_KEY_PGUP)
    c->top -= page;
  else if (e->key == TERM_KEY_PGDN)
    c->top += page;
  else if (e->key == TERM_KEY_HOME)
    c->top = 0;
  else
    return FALSE;
  if (c->top < 0)
    c->top = 0;
  htk_dirty = TRUE;
  return c->top != was || TRUE;
}
