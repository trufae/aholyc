#include "lib/text/font.hc"

I64 failures;

U0 Check(Bool ok, U8 *name)
{
  if (!ok) {
    "FAIL %s\n", name;
    failures++;
  }
}

U0 CheckStyle(U8 *source, I64 style, U8 *expected, U8 *name)
{
  CStrs input;
  U8 output[128];
  I64 needed;

  StrsInitS(&input, source);
  needed = FontConvert(&input, style, NULL, 0);
  Check(needed == StrLen(expected) && needed < sizeof(output), name);
  if (needed >= 0 && needed < sizeof(output)) {
    Check(FontConvert(&input, style, output, needed) == needed &&
      !MemCmp(output, expected, needed), name);
  }
}

U8 output[128];
U8 short_output[8] = {0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC, 0xCC};
U8 invalid[2] = {0xC0, 0x80};
U8 binary[3] = {'A', 0, 'z'};
CStrs input;
CStrs empty;
I64 needed;
I64 i;
Bool names_ok = TRUE;

CheckStyle("Ab3", FONT_STYLE_BOLD, "𝐀𝐛𝟑", "bold");
CheckStyle("Bh", FONT_STYLE_ITALIC, "𝐵ℎ", "italic exception");
CheckStyle("Beg", FONT_STYLE_SCRIPT, "ℬℯℊ", "script exceptions");
CheckStyle("CH9", FONT_STYLE_DOUBLESTRUCK, "ℂℍ𝟡", "double struck");
CheckStyle("A1", FONT_STYLE_UNDERLINE, "A̲1̲", "underline");
CheckStyle("A1", FONT_STYLE_STRIKETHROUGH, "A̵1̵", "strike");
CheckStyle("CHz", FONT_STYLE_FRAKTUR, "ℭℌ𝔷", "fraktur exceptions");
CheckStyle("Az", FONT_STYLE_BOLDITALIC, "𝑨𝒛", "bold italic");
CheckStyle("Az9", FONT_STYLE_SANSSERIF, "𝖠𝗓𝟫", "sans serif");
CheckStyle("Az", FONT_STYLE_SANSSERIFITALIC, "𝘈𝘻", "sans italic");
CheckStyle("Az9", FONT_STYLE_MONOSPACE, "𝙰𝚣𝟿", "monospace");
CheckStyle("Az", FONT_STYLE_BOLDSCRIPT, "𝓐𝔃", "bold script");
CheckStyle("Az", FONT_STYLE_BOLDFRAKTUR, "𝕬𝖟", "bold fraktur");
CheckStyle("Az9", FONT_STYLE_SANSSERIFBOLD, "𝗔𝘇𝟵", "sans bold");
CheckStyle("Az", FONT_STYLE_SANSSERIFBOLDITALIC, "𝘼𝙯", "sans bold italic");
CheckStyle("Cz", FONT_STYLE_OPENFACE, "ℂ𝕫", "open face");
CheckStyle("Absz", FONT_STYLE_SMALLCAPS, "Aʙsᴢ", "small caps");
CheckStyle("ñ😀 A", FONT_STYLE_BOLD, "ñ😀 𝐀", "Unicode passthrough");

for (i = 0; i < FONT_STYLE_COUNT; i++) {
  if (FontStyleFromNameS(FontStyleName(i)) != i)
    names_ok = FALSE;
}
Check(names_ok && FontStyleFromNameS("BOLD") == FONT_STYLE_BOLD &&
  FontStyleFromNameS("sansseribbold") == FONT_STYLE_SANSSERIFBOLD &&
  FontStyleFromNameS("missing") == -1, "style names and alias");

StrsInitS(&input, "A1");
Check(FontConvert(&input, FONT_STYLE_UNDERLINE, short_output, 3) ==
  StrLen("A̲1̲") && !MemCmp(short_output, "A̲", 3) &&
  short_output[3] == 0xCC, "short buffer keeps combining mark together");
StrsInitN(&input, binary, sizeof(binary));
Check(FontConvert(&input, FONT_STYLE_BOLD, output, sizeof(output)) == 9 &&
  !MemCmp(output, "𝐀\0𝐳", 9), "embedded NUL");
StrsInitN(&input, invalid, sizeof(invalid));
Check(FontConvert(&input, FONT_STYLE_BOLD, output, sizeof(output)) == -1,
  "invalid UTF-8");
StrsInitS(&input, "A");
Check(FontConvert(&input, FONT_STYLE_COUNT, NULL, 0) == -1,
  "invalid style");
StrsInitN(&empty, NULL, 0);
Check(FontConvert(&empty, FONT_STYLE_BOLD, NULL, 0) == 0 &&
  FontFormatTags(&empty, NULL, 0) == 0, "empty slice");

StrsInitS(&input, "<bold>Hi</bold> <monospace>A1</monospace> <odd>x</odd>!");
needed = FontFormatTags(&input, NULL, 0);
Check(needed == StrLen("𝐇𝐢 𝙰𝟷 x!") && needed < sizeof(output),
  "tag sizing");
Check(FontFormatTags(&input, output, sizeof(output)) == needed &&
  !MemCmp(output, "𝐇𝐢 𝙰𝟷 x!", needed), "tag formatting");
StrsInitS(&input, "<BOLD>Ab</bold>");
Check(FontFormatTags(&input, output, sizeof(output)) ==
  StrLen("𝐀𝐛") && !MemCmp(output, "𝐀𝐛", StrLen("𝐀𝐛")),
  "case-insensitive tags");
StrsInitS(&input, "<bold>open");
Check(FontFormatTags(&input, output, sizeof(output)) == StrLen(input.a) &&
  !MemCmp(output, input.a, StrLen(input.a)), "unmatched tag literal");

if (failures)
  Exit(1);
"font ok\n";
