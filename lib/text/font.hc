#ifndef AHOLYC_LIB_TEXT_FONT_HC
#define AHOLYC_LIB_TEXT_FONT_HC

// Unicode text styles from utfmt. These replace ASCII letters and, where
// Unicode defines them, digits with styled characters. They do not choose an
// installed font. Other valid UTF-8 runes pass through unchanged.
//
// FontConvert and FontFormatTags return the required byte count, or -1 for an
// invalid style, UTF-8 input, slice, capacity, or size overflow. Pass NULL as
// output to measure first. A short buffer receives only complete styled
// characters (including an underline/strike combining mark). Output is not
// NUL-terminated; reserve one extra byte if a C string is needed. Input and
// output must not overlap.

#include "strs.hc"
#include "utf8.HC"

#define FONT_STYLE_NONE 0
#define FONT_STYLE_BOLD 1
#define FONT_STYLE_ITALIC 2
#define FONT_STYLE_SCRIPT 3
#define FONT_STYLE_DOUBLESTRUCK 4
#define FONT_STYLE_UNDERLINE 5
#define FONT_STYLE_STRIKETHROUGH 6
#define FONT_STYLE_FRAKTUR 7
#define FONT_STYLE_BOLDITALIC 8
#define FONT_STYLE_SANSSERIF 9
#define FONT_STYLE_SANSSERIFITALIC 10
#define FONT_STYLE_MONOSPACE 11
#define FONT_STYLE_BOLDSCRIPT 12
#define FONT_STYLE_BOLDFRAKTUR 13
#define FONT_STYLE_SANSSERIFBOLD 14
#define FONT_STYLE_SANSSERIFBOLDITALIC 15
#define FONT_STYLE_OPENFACE 16
#define FONT_STYLE_SMALLCAPS 17
#define FONT_STYLE_COUNT 18

I64 FontAsciiLower(I64 c)
{
  if (c >= 'A' && c <= 'Z')
    return c + 'a' - 'A';
  return c;
}

Bool FontNameEquals(CStrs *a, CStrs *b)
{
  I64 i;
  I64 length = StrsLen(a);

  if (length != StrsLen(b))
    return FALSE;
  for (i = 0; i < length; i++) {
    if (FontAsciiLower(a->a[i]) != FontAsciiLower(b->a[i]))
      return FALSE;
  }
  return TRUE;
}

U8 *FontStyleName(I64 style)
{
  U8 *names[FONT_STYLE_COUNT] = {
    "none", "bold", "italic", "script", "doublestruck", "underline",
    "strikethrough", "fraktur", "bolditalic", "sansserif",
    "sansserifitalic", "monospace", "boldscript", "boldfraktur",
    "sansserifbold", "sansserifbolditalic", "openface", "smallcaps"
  };

  if (style < 0 || style >= FONT_STYLE_COUNT)
    return NULL;
  return names[style];
}

I64 FontStyleFromName(CStrs *name)
{
  CStrs candidate;
  I64 i;

  if (!StrsValid(name))
    return -1;
  for (i = 0; i < FONT_STYLE_COUNT; i++) {
    StrsInitS(&candidate, FontStyleName(i));
    if (FontNameEquals(name, &candidate))
      return i;
  }
  // utfmt originally published this misspelling; accept it as an alias.
  StrsInitS(&candidate, "sansseribbold");
  if (FontNameEquals(name, &candidate))
    return FONT_STYLE_SANSSERIFBOLD;
  return -1;
}

I64 FontStyleFromNameS(U8 *name)
{
  CStrs slice;

  if (!name)
    return -1;
  StrsInitS(&slice, name);
  return FontStyleFromName(&slice);
}

I64 FontMapRune(I64 rune, I64 style, I64 *combining)
{
  I64 i;
  I64 smallcaps[26] = {
    0x1D00, 0x299, 0x1D04, 0x1D05, 0x1D07, 0x493, 0x262, 0x29C,
    0x26A, 0x1D0A, 0x1D0B, 0x29F, 0x1D0D, 0x274, 0x1D0F, 0x1D18,
    0x1EB, 0x280, 's', 0x1D1B, 0x1D1C, 0x1D20, 0x1D21, 'x', 0x28F, 0x1D22
  };

  *combining = 0;
  if (style == FONT_STYLE_UNDERLINE || style == FONT_STYLE_STRIKETHROUGH) {
    if (rune >= 'A' && rune <= 'Z' || rune >= 'a' && rune <= 'z' ||
      rune >= '0' && rune <= '9') {
      if (style == FONT_STYLE_UNDERLINE)
        *combining = 0x332;
      else
        *combining = 0x335;
    }
    return rune;
  }
  if (rune >= 'A' && rune <= 'Z') {
    i = rune - 'A';
    switch (style) {
    case FONT_STYLE_BOLD: return 0x1D400 + i;
    case FONT_STYLE_ITALIC: return 0x1D434 + i;
    case FONT_STYLE_SCRIPT:
      switch (rune) {
      case 'B': return 0x212C;
      case 'E': return 0x2130;
      case 'F': return 0x2131;
      case 'H': return 0x210B;
      case 'I': return 0x2110;
      case 'L': return 0x2112;
      case 'M': return 0x2133;
      case 'R': return 0x211B;
      }
      return 0x1D49C + i;
    case FONT_STYLE_DOUBLESTRUCK:
    case FONT_STYLE_OPENFACE:
      switch (rune) {
      case 'C': return 0x2102;
      case 'H': return 0x210D;
      case 'N': return 0x2115;
      case 'P': return 0x2119;
      case 'Q': return 0x211A;
      case 'R': return 0x211D;
      case 'Z': return 0x2124;
      }
      return 0x1D538 + i;
    case FONT_STYLE_FRAKTUR:
      switch (rune) {
      case 'C': return 0x212D;
      case 'H': return 0x210C;
      case 'I': return 0x2111;
      case 'R': return 0x211C;
      case 'Z': return 0x2128;
      }
      return 0x1D504 + i;
    case FONT_STYLE_BOLDITALIC: return 0x1D468 + i;
    case FONT_STYLE_SANSSERIF: return 0x1D5A0 + i;
    case FONT_STYLE_SANSSERIFITALIC: return 0x1D608 + i;
    case FONT_STYLE_MONOSPACE: return 0x1D670 + i;
    case FONT_STYLE_BOLDSCRIPT: return 0x1D4D0 + i;
    case FONT_STYLE_BOLDFRAKTUR: return 0x1D56C + i;
    case FONT_STYLE_SANSSERIFBOLD: return 0x1D5D4 + i;
    case FONT_STYLE_SANSSERIFBOLDITALIC: return 0x1D63C + i;
    }
  } else if (rune >= 'a' && rune <= 'z') {
    i = rune - 'a';
    switch (style) {
    case FONT_STYLE_BOLD: return 0x1D41A + i;
    case FONT_STYLE_ITALIC:
      if (rune == 'h')
        return 0x210E;
      return 0x1D44E + i;
    case FONT_STYLE_SCRIPT:
      switch (rune) {
      case 'e': return 0x212F;
      case 'g': return 0x210A;
      case 'o': return 0x2134;
      }
      return 0x1D4B6 + i;
    case FONT_STYLE_DOUBLESTRUCK:
    case FONT_STYLE_OPENFACE: return 0x1D552 + i;
    case FONT_STYLE_FRAKTUR: return 0x1D51E + i;
    case FONT_STYLE_BOLDITALIC: return 0x1D482 + i;
    case FONT_STYLE_SANSSERIF: return 0x1D5BA + i;
    case FONT_STYLE_SANSSERIFITALIC: return 0x1D622 + i;
    case FONT_STYLE_MONOSPACE: return 0x1D68A + i;
    case FONT_STYLE_BOLDSCRIPT: return 0x1D4EA + i;
    case FONT_STYLE_BOLDFRAKTUR: return 0x1D586 + i;
    case FONT_STYLE_SANSSERIFBOLD: return 0x1D5EE + i;
    case FONT_STYLE_SANSSERIFBOLDITALIC: return 0x1D656 + i;
    case FONT_STYLE_SMALLCAPS: return smallcaps[i];
    }
  } else if (rune >= '0' && rune <= '9') {
    i = rune - '0';
    switch (style) {
    case FONT_STYLE_BOLD: return 0x1D7CE + i;
    case FONT_STYLE_DOUBLESTRUCK: return 0x1D7D8 + i;
    case FONT_STYLE_SANSSERIF: return 0x1D7E2 + i;
    case FONT_STYLE_SANSSERIFBOLD: return 0x1D7EC + i;
    case FONT_STYLE_MONOSPACE: return 0x1D7F6 + i;
    }
  }
  return rune;
}

I64 FontConvert(CStrs *input, I64 style, U8 *output, I64 capacity)
{
  U8 bytes[8];
  U8 *p;
  I64 rune;
  I64 combining;
  I64 consumed;
  I64 produced;
  I64 extra;
  I64 total = 0;

  if (!StrsValid(input) || style < 0 || style >= FONT_STYLE_COUNT ||
    capacity < 0)
    return -1;
  if (StrsEmpty(input))
    return 0;
  p = input->a;
  while (p < input->b) {
    consumed = Utf8DecodeRune(p, input->b - p, &rune);
    if (!consumed)
      return -1;
    rune = FontMapRune(rune, style, &combining);
    produced = Utf8EncodeRune(rune, bytes);
    if (!produced)
      return -1;
    if (combining) {
      extra = Utf8EncodeRune(combining, bytes + produced);
      if (!extra)
        return -1;
      produced += extra;
    }
    if (total > I64_MAX - produced)
      return -1;
    if (output && total <= capacity && produced <= capacity - total)
      MemCpy(output + total, bytes, produced);
    total += produced;
    p += consumed;
  }
  return total;
}

// utfmt-style non-nested tags: <bold>Hello</bold>. Unknown paired tags lose
// their wrapper but retain their content; unmatched tags remain literal.
I64 FontFormatTags(CStrs *input, U8 *output, I64 capacity)
{
  CStrs name;
  CStrs close_name;
  CStrs part;
  U8 *p;
  U8 *q;
  U8 *body;
  U8 *close;
  U8 *next;
  U8 *destination;
  I64 style;
  I64 size;
  I64 available;
  I64 total = 0;

  if (!StrsValid(input) || capacity < 0)
    return -1;
  if (StrsEmpty(input))
    return 0;
  p = input->a;
  while (p < input->b) {
    next = p;
    while (next < input->b && *next != '<')
      next++;
    if (next > p) {
      StrsInit(&part, p, next);
      destination = NULL;
      available = 0;
      if (output && total < capacity) {
        destination = output + total;
        available = capacity - total;
      }
      size = FontConvert(&part, FONT_STYLE_NONE, destination, available);
      if (size < 0 || total > I64_MAX - size)
        return -1;
      total += size;
      p = next;
      goto font_next;
    }
    q = p + 1;
    while (q < input->b && (FontAsciiLower(*q) >= 'a' &&
      FontAsciiLower(*q) <= 'z'))
      q++;
    if (q > p + 1 && q < input->b && *q == '>') {
      StrsInit(&name, p + 1, q);
      body = q + 1;
      close = body;
      while (close < input->b) {
        if (*close == '<' && input->b - close >= StrsLen(&name) + 3 &&
          close[1] == '/' && close[StrsLen(&name) + 2] == '>') {
          StrsInit(&close_name, close + 2,
            close + 2 + StrsLen(&name));
          if (FontNameEquals(&name, &close_name))
            break;
        }
        close++;
      }
      if (close < input->b) {
        style = FontStyleFromName(&name);
        if (style < 0)
          style = FONT_STYLE_NONE;
        StrsInit(&part, body, close);
        destination = NULL;
        available = 0;
        if (output && total < capacity) {
          destination = output + total;
          available = capacity - total;
        }
        size = FontConvert(&part, style, destination, available);
        if (size < 0 || total > I64_MAX - size)
          return -1;
        total += size;
        p = close + StrsLen(&name) + 3;
        goto font_next;
      }
    }
    // This '<' did not start a paired tag.
    if (total == I64_MAX)
      return -1;
    if (output && total < capacity)
      output[total] = *p;
    total++;
    p++;
font_next:;
  }
  return total;
}

#endif
