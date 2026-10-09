// Bounded Markdown links and a deliberately small, non-executing HTML subset.
// Included by markdown.hc after the basic style helpers.
U0 MdInline(CMarkdown *md, CStrs *text);

Bool MdStarts(U8 *a, U8 *b, U8 *literal)
{
  I64 n = StrLen(literal);

  return b - a >= n && !MemCmp(a, literal, n);
}

U8 *MdFind(U8 *a, U8 *b, U8 *literal)
{
  return MemMem(a, b - a, literal, StrLen(literal));
}

Bool MdAttr(CStrs *tag, U8 *name, CStrs *value)
{
  U8 *p = tag->a, *start;
  I64 quote, n = StrLen(name);

  while (p < tag->b) {
    if ((*p == ' ' || *p == '\t') && MdStarts(p + 1, tag->b, name)) {
      p += n + 1;
      while (p < tag->b && *p == ' ')
        p++;
      if (p == tag->b || *p++ != '=')
        goto next_attr;
      while (p < tag->b && *p == ' ')
        p++;
      if (p == tag->b)
        break;
      quote = *p;
      if (quote != '\'' && quote != '"')
        goto next_attr;
      start = ++p;
      while (p < tag->b && *p != quote)
        p++;
      if (p == tag->b)
        break;
      StrsInit(value, start, p);
      return TRUE;
    }
    next_attr:;
    if (p < tag->b) p++;
  }
  return FALSE;
}

I64 MdHex(I64 c)
{
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}

// CSS #rgb/#rrggbb plus the basic HTML color names.
I64 MdColor(CStrs *value)
{
  I64 i, digit, rgb = 0, n;
  CStrs v = *value;
  U8 *names[16] = {"black", "silver", "gray", "white", "maroon", "red",
    "purple", "fuchsia", "green", "lime", "olive", "yellow", "navy", "blue",
    "teal", "aqua"};
  I64 colors[16] = {0, 0xC0C0C0, 0x808080, 0xFFFFFF, 0x800000, 0xFF0000,
    0x800080, 0xFF00FF, 0x8000, 0xFF00, 0x808000, 0xFFFF00, 0x80, 0xFF,
    0x8080, 0xFFFF};

  StrsTrim(&v);
  n = StrsLen(&v);
  if (n > 0 && v.a[0] == '#' && (n == 4 || n == 7)) {
    for (i = 1; i < n; i++) {
      digit = MdHex(v.a[i]);
      if (digit < 0)
        return 0;
      if (n == 4)
        rgb = (rgb << 8) | digit * 17;
      else
        rgb = (rgb << 4) | digit;
    }
    return rgb + 1;
  }
  for (i = 0; i < 16; i++)
    if (n == StrLen(names[i]) && !MemCmp(v.a, names[i], n))
      return colors[i] + 1;
  return 0;
}

// Balanced destinations permit relative filenames containing parentheses.
Bool MdLink(U8 *a, U8 *end, CStrs *label, CStrs *target, U8 **after)
{
  U8 *p = a;
  I64 depth = 1;

  if (p < end && *p == '!') p++;
  if (p == end || *p++ != '[') return FALSE;
  label->a = p;
  while (p < end && *p != '\n') {
    if (*p == '\\' && p + 1 < end) { p += 2; goto next_label; }
    if (*p == '[') depth++;
    if (*p == ']' && !--depth) break;
    p++;
    next_label:;
  }
  if (p + 1 >= end || p[0] != ']' || p[1] != '(') return FALSE;
  label->b = p;
  p += 2;
  target->a = p;
  depth = 1;
  while (p < end && *p != '\n') {
    if (*p == '\\' && p + 1 < end) { p += 2; goto next_target; }
    if (*p == '(') depth++;
    if (*p == ')' && !--depth) break;
    p++;
    next_target:;
  }
  if (p == end || *p != ')') return FALSE;
  target->b = p;
  StrsTrim(target);
  if (StrsLen(target) >= 2 && *target->a == '<' && target->b[-1] == '>') {
    target->a++;
    target->b--;
  }
  *after = p + 1;
  return TRUE;
}

U0 MdLinked(CMarkdown *md, U8 *a, U8 *after, CStrs *label, CStrs *target,
  Bool image)
{
  CStrs prior = md->target;
  U8 *start = md->link_start, *end = md->link_end;
  I64 style = MD_STYLE_LINK;

  if (image) style = MD_STYLE_IMAGE;
  md->target = *target;
  md->link_start = a;
  md->link_end = after;
  MdStyle(md, style, 1);
  md->depth++;
  if (image) MdText(md, label->a, label->b);
  else MdInline(md, label);
  md->depth--;
  MdStyle(md, style, 0);
  md->target = prior;
  md->link_start = start;
  md->link_end = end;
}

I64 MdRich(CMarkdown *md, U8 *a)
{
  CStrs label, target, tag, css, part, value;
  U8 *p, *q, *after, *name, *close;
  I64 n, saved_fg = md->fg, saved_bg = md->bg;
  I64 style = 0, nesting;
  Bool image = *a == '!';

  if (md->depth >= 16)
    return 0;
  if (*a == '\\' && a + 1 < md->end && a[1] >= '!' && a[1] <= '~') {
    MdText(md, a + 1, a + 2);
    md->col++;
    return 2;
  }
  if (!md->link_start && (*a == '[' || image) && MdLink(a, md->end, &label, &target, &after)) {
    MdLinked(md, a, after, &label, &target, image);
    md->col += MdWidth(&label);
    return after - a;
  }
  if (MdStarts(a, md->end, "<!--")) {
    p = MdFind(a + 4, md->end, "-->");
    if (!p) return 0;
    if (MdStarts(a, p, "<!-- table-border: ")) {
      if (MdStarts(a + 19, p, "round")) md->table_border = 1;
      else if (MdStarts(a + 19, p, "ascii")) md->table_border = 2;
      else if (MdStarts(a + 19, p, "none")) md->table_border = 3;
      else md->table_border = 0;
    }
    return p + 3 - a;
  }
  if (*a == '&') {
    U8 *entities[5] = {"&amp;", "&lt;", "&gt;", "&quot;", "&#39;"};
    U8 *values[5] = {"&", "<", ">", "\"", "'"};
    for (n = 0; n < 5; n++)
      if (MdStarts(a, md->end, entities[n])) {
        MdTextS(md, values[n]);
        md->col++;
        return StrLen(entities[n]);
      }
  }
  if (*a != '<') return 0;
  p = MemChr(a, '>', md->end - a);
  if (!p) return 0;
  StrsInit(&tag, a, p);
  if (MdStarts(a, p + 1, "<br>") || MdStarts(a, p + 1, "<br/>")) {
    MdTextS(md, "\n");
    md->col = 0;
    return p + 1 - a;
  }
  if (MdStarts(a, p, "<img ") && MdAttr(&tag, "src", &target)) {
    if (!MdAttr(&tag, "alt", &label)) StrsInitS(&label, "[image]");
    MdLinked(md, a, p + 1, &label, &target, TRUE);
    md->col += MdWidth(&label);
    return p + 1 - a;
  }
  if (MdStarts(a, p, "<span ")) { name = "<span"; close = "</span>"; }
  else if (MdStarts(a, p, "<a ")) { name = "<a "; close = "</a>"; }
  else if (MdStarts(a, p + 1, "<u>")) {
    name = "<u>"; close = "</u>"; style = MD_STYLE_UNDERLINE;
  } else return 0;
  q = p + 1;
  nesting = 1;
  while (q < md->end) {
    if (MdStarts(q, md->end, close) && !--nesting) break;
    if (MdStarts(q, md->end, name)) nesting++;
    q++;
  }
  if (q == md->end) return 0;
  after = q + StrLen(close);
  StrsInit(&label, p + 1, q);
  if (*name == '<' && name[1] == 'a') {
    if (!MdAttr(&tag, "href", &target)) return 0;
    MdLinked(md, a, after, &label, &target, FALSE);
  } else {
    if (style) MdStyle(md, style, 1);
    if (MdAttr(&tag, "style", &css)) {
      while (css.a < css.b) {
        q = MemChr(css.a, ';', css.b - css.a);
        if (!q) q = css.b;
        StrsInit(&part, css.a, q);
        StrsTrim(&part);
        p = MemChr(part.a, ':', part.b - part.a);
        if (p) {
          StrsInit(&value, p + 1, part.b);
          n = MdColor(&value);
          part.b = p;
          StrsTrim(&part);
          if (StrsLen(&part) == 5 && MdStarts(part.a, part.b, "color"))
            md->fg = n;
          if (StrsLen(&part) == 16 && MdStarts(part.a, part.b, "background-color"))
            md->bg = n;
        }
        css.a = q;
        if (q < css.b) css.a++;
      }
      MdStyle(md, MD_STYLE_FG, md->fg);
      MdStyle(md, MD_STYLE_BG, md->bg);
    }
    md->depth++;
    MdInline(md, &label);
    md->depth--;
    if (style) MdStyle(md, style, 0);
    md->fg = saved_fg;
    md->bg = saved_bg;
    MdStyle(md, MD_STYLE_FG, saved_fg);
    MdStyle(md, MD_STYLE_BG, saved_bg);
  }
  md->col += MdWidth(&label);
  return after - a;
}
