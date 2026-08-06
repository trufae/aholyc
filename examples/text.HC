#include "lib/text/encoding.HC"
#include "lib/json/decode.hc"
#include "lib/json/encode.hc"

I64 failures = 0;

U0 Check(Bool condition, U8 *name)
{
  if (!condition) {
    "FAIL %s\n", name;
    failures++;
  }
}

U8 sample[11] = {
  'A', 0, 0xC3, 0xB1, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80
};
U8 encoded[8];
U8 converted[32];
U8 short_output[2] = {0xCC, 0xCC};
U8 overlong[2] = {0xC0, 0x80};
U8 surrogate[3] = {0xED, 0xA0, 0x80};
U8 utf16le[6] = {0x41, 0, 0x3D, 0xD8, 0, 0xDE};
U8 utf16be_emoji[4] = {0xD8, 0x3D, 0xDE, 0};
U8 utf16_bad[2] = {0, 0xDC};
U8 utf32be_euro[4] = {0, 0, 0x20, 0xAC};
U8 utf32_bad[4] = {0, 0x11, 0, 0};
U8 latin1[1] = {0xE9};
U8 eacute_utf8[2] = {0xC3, 0xA9};
U8 ebcdic[5] = {0xC8, 0x85, 0x93, 0x93, 0x96};
U8 pascal[4] = {3, 'a', 0, 'b'};
U8 pascal_output[8];
U8 ascii_bad[1] = {0x80};
U8 json_text[6] = {'"', 0xF0, 0x9F, 0x98, 0x80, '"'};
U8 json_bad[4] = {'"', 0xC0, 0x80, '"'};
U8 json_output[32];
U8 embedded[3] = {'a', 0, 'b'};
U8 emoji[4] = {0xF0, 0x9F, 0x98, 0x80};
CText text;
CText other;
CJsonDecoder decoder;
CJsonEncoder encoder;
CJsonValue value;
I64 count;
I64 decoded;
I64 i;
I64 j;
I64 rune;
I64 length;
I64 rune_cases[10] = {
  0, 0x7F, 0x80, 0x7FF, 0x800, 0xD7FF, 0xE000, 0xFFFF, 0x10000, 0x10FFFF
};
I64 unicode_encodings[5] = {
  TEXT_ENCODING_UTF8, TEXT_ENCODING_UTF16_LE, TEXT_ENCODING_UTF16_BE,
    TEXT_ENCODING_UTF32_LE, TEXT_ENCODING_UTF32_BE
};
Bool roundtrip = TRUE;

Check(Utf8Valid(sample, sizeof(sample), &count) && count == 5,
  "utf8 explicit length/count");
Check(!Utf8Valid(overlong, sizeof(overlong)), "utf8 rejects overlong");
Check(!Utf8Valid(surrogate, sizeof(surrogate)), "utf8 rejects surrogate");
Check(Utf8DecodeRune(sample + 7, 4, &rune) == 4 && rune == 0x1F600,
  "utf8 decode rune");
Check(Utf8EncodeRune(0x1F600, encoded) == 4 &&
  !MemCmp(encoded, emoji, 4), "utf8 encode rune");

Check(TextInit(&text, sample, sizeof(sample)) &&
  TextValid(&text, &count) && count == 5, "text slice with embedded nul");
Check(TextInit(&text, "hello") && text.length == 5,
  "nul-terminated adapter");

Check(TextInit(&text, utf16le, sizeof(utf16le), TEXT_ENCODING_UTF16_LE) &&
  TextValid(&text, &count) && count == 2, "utf16 validation");
Check(TextConvert(&text, TEXT_ENCODING_UTF8, converted,
    sizeof(converted)) == 5 && converted[0] == 'A' &&
  !MemCmp(converted + 1, emoji, 4), "utf16 to utf8");
Check(TextConvert(&text, TEXT_ENCODING_UTF8, short_output,
    sizeof(short_output)) == 5 && short_output[0] == 'A' &&
  short_output[1] == 0xCC, "conversion does not split runes");
Check(TextEncodeRune(0x1F600, TEXT_ENCODING_UTF16_BE, encoded) == 4 &&
  !MemCmp(encoded, utf16be_emoji, 4), "utf16be encode");
Check(TextDecodeRune(utf32be_euro, 4, TEXT_ENCODING_UTF32_BE,
    &rune) == 4 && rune == 0x20AC, "utf32be decode");
Check(!TextDecodeRune(utf16_bad, sizeof(utf16_bad),
    TEXT_ENCODING_UTF16_LE, &rune), "utf16 rejects lone surrogate");
Check(!TextDecodeRune(utf32_bad, sizeof(utf32_bad),
    TEXT_ENCODING_UTF32_BE, &rune), "utf32 rejects large rune");
for (i = 0; i < 5 && roundtrip; i++) {
  for (j = 0; j < 10; j++) {
    length = TextEncodeRune(rune_cases[j], unicode_encodings[i], encoded);
    if (!length || TextDecodeRune(encoded, length, unicode_encodings[i],
        &decoded) != length || decoded != rune_cases[j]) {
          roundtrip = FALSE;
          break;
        }
  }
}
Check(roundtrip, "unicode boundary roundtrips");

Check(TextInit(&text, latin1, 1, TEXT_ENCODING_LATIN1) &&
  TextConvert(&text, TEXT_ENCODING_UTF8, converted, sizeof(converted)) == 2 &&
  !MemCmp(converted, eacute_utf8, 2), "latin1 conversion");
Check(TextConvert(&text, TEXT_ENCODING_ASCII, converted,
    sizeof(converted)) == -1, "ascii representability");
Check(TextInit(&other, ascii_bad, 1, TEXT_ENCODING_ASCII) &&
  !TextValid(&other), "ascii validation");

Check(TextInit(&text, ebcdic, sizeof(ebcdic),
    TEXT_ENCODING_EBCDIC_037) && TextConvert(&text, TEXT_ENCODING_UTF8,
    converted, sizeof(converted)) == 5 && !MemCmp(converted, "Hello", 5),
  "ebcdic conversion");
Check(TextInit(&other, "Hello") && TextConvert(&other,
    TEXT_ENCODING_EBCDIC_037, converted, sizeof(converted)) == 5 &&
  !MemCmp(converted, ebcdic, 5), "ebcdic encoding");
roundtrip = TRUE;
for (i = 0; i < 256; i++) {
  encoded[0] = i;
  if (TextDecodeRune(encoded, 1, TEXT_ENCODING_EBCDIC_037, &rune) != 1 ||
    TextEncodeRune(rune, TEXT_ENCODING_EBCDIC_037, encoded + 1, 1) != 1 ||
    encoded[1] != i) {
      roundtrip = FALSE;
      break;
    }
}
Check(roundtrip, "ebcdic full codepage roundtrip");

Check(TextFromPascal(&text, pascal, sizeof(pascal)) && text.length == 3 &&
  TextValid(&text, &count) && count == 3, "pascal embedded nul");
Check(!TextFromPascal(&other, pascal, 3), "pascal bounds");
length = TextWritePascal(&text, pascal_output, sizeof(pascal_output));
Check(length == sizeof(pascal) && !MemCmp(pascal_output, pascal, length),
  "pascal write");
length = TextWritePascal(&text, pascal_output, sizeof(pascal_output), 2, TRUE);
Check(length == 5 && pascal_output[0] == 0 && pascal_output[1] == 3 &&
  !MemCmp(pascal_output + 2, pascal + 1, 3), "pascal16be write");

JsonDecoderInit(&decoder, json_text, sizeof(json_text));
Check(JsonDecode(&decoder, &value) && value.type == JSON_TYPE_STRING,
  "json utf8 decode");
Check(JsonValueCopyString(&value, converted, sizeof(converted), &length) &&
  length == 4 && !MemCmp(converted, emoji, 4), "json rune copy");
JsonDecoderInit(&decoder, json_bad, sizeof(json_bad));
Check(!JsonDecode(&decoder, &value) &&
  decoder.error == JSON_DECODE_INVALID_UTF8, "json rejects invalid utf8");

JsonEncoderInit(&encoder, json_output, sizeof(json_output));
JsonEncodeStringN(&encoder, embedded, sizeof(embedded));
length = JsonEncoderFinish(&encoder);
Check(length == 10 && !MemCmp(json_output, "\"a\\u0000b\"", 10),
  "json explicit-length string");

if (failures)
  Exit(1);
"text ok\n";
