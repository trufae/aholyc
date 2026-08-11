#ifndef AHOLYC_LIB_REGEX_REGEX_HC
#define AHOLYC_LIB_REGEX_REGEX_HC

#include "../text/utf8.HC"

// Small UTF-8 regular-expression engine. Positions and lengths are bytes;
// pattern atoms and input characters are Unicode code points.
//
// Compile once with RegexCompile, reuse with RegexMatch/RegexFullMatch, then
// release with RegexFini. Matching uses a Thompson NFA: runtime is bounded by
// O(pattern states * input bytes) and does not catastrophically backtrack.

#define REGEX_OK 0
#define REGEX_ERROR_ARGUMENT 1
#define REGEX_ERROR_MEMORY 2
#define REGEX_ERROR_SYNTAX 3
#define REGEX_ERROR_PAREN 4
#define REGEX_ERROR_CLASS 5
#define REGEX_ERROR_ESCAPE 6
#define REGEX_ERROR_REPEAT 7
#define REGEX_ERROR_UTF8 8

#define REGEX_OP_RUNE 1
#define REGEX_OP_ANY 2
#define REGEX_OP_CLASS 3
#define REGEX_OP_SPLIT 4
#define REGEX_OP_JUMP 5
#define REGEX_OP_BOL 6
#define REGEX_OP_EOL 7
#define REGEX_OP_MATCH 8

class CRegexInstruction
{
  I64 op;
  I64 x;
  I64 y;
  I64 rune;
  I64 range_index;
  I64 range_count;
  Bool negate;
};

class CRegexRange
{
  I64 first;
  I64 last;
};

class CRegexPatch
{
  I64 instruction;
  I64 field;
  I64 next;
};

class CRegexFragment
{
  I64 start;
  I64 head;
  I64 tail;
};

class CRegex
{
  CRegexInstruction *instructions;
  I64 instruction_count;
  I64 instruction_capacity;
  I64 start;
  I64 error;
  I64 error_offset;
  CRegexRange *ranges;
  I64 range_count;
  I64 range_capacity;
  I64 *list_a;
  I64 *list_b;
  I64 *origin_a;
  I64 *origin_b;
  I64 *seen;
  I64 generation;
};

class CRegexMatch
{
  I64 start;
  I64 end;
};

class CRegexCompiler
{
  CRegex *regex;
  U8 *pattern;
  I64 length;
  I64 offset;
  CRegexPatch *patches;
  I64 patch_count;
  I64 patch_capacity;
};

U0 RegexInit(CRegex *regex)
{
  if (regex)
    MemSet(regex, 0, sizeof(CRegex));
}

U0 RegexFini(CRegex *regex)
{
  if (!regex)
    return;
  Free(regex->instructions);
  Free(regex->ranges);
  Free(regex->list_a);
  Free(regex->list_b);
  Free(regex->origin_a);
  Free(regex->origin_b);
  Free(regex->seen);
  RegexInit(regex);
}

Bool RegexCompileFail(CRegexCompiler *compiler, I64 error, I64 position)
{
  if (!compiler->regex->error) {
    compiler->regex->error = error;
    compiler->regex->error_offset = position;
  }
  return FALSE;
}

I64 RegexEmit(CRegexCompiler *compiler, I64 op)
{
  CRegexInstruction *instruction;
  I64 index = compiler->regex->instruction_count;

  if (index >= compiler->regex->instruction_capacity) {
    RegexCompileFail(compiler, REGEX_ERROR_MEMORY, compiler->offset);
    return -1;
  }
  instruction = compiler->regex->instructions + index;
  MemSet(instruction, 0, sizeof(CRegexInstruction));
  instruction->op = op;
  instruction->x = -1;
  instruction->y = -1;
  compiler->regex->instruction_count++;
  return index;
}

I64 RegexPatchNew(CRegexCompiler *compiler, I64 instruction, I64 field)
{
  I64 index = compiler->patch_count;

  if (index >= compiler->patch_capacity) {
    RegexCompileFail(compiler, REGEX_ERROR_MEMORY, compiler->offset);
    return -1;
  }
  compiler->patches[index].instruction = instruction;
  compiler->patches[index].field = field;
  compiler->patches[index].next = -1;
  compiler->patch_count++;
  return index;
}

U0 RegexFragmentOne(CRegexCompiler *compiler, I64 start, I64 field,
  CRegexFragment *fragment)
{
  fragment->start = start;
  fragment->head = RegexPatchNew(compiler, start, field);
  fragment->tail = fragment->head;
}

U0 RegexPatchJoin(CRegexCompiler *compiler, CRegexFragment *left,
  CRegexFragment *right)
{
  if (left->head < 0) {
    left->head = right->head;
    left->tail = right->tail;
  } else if (right->head >= 0) {
    compiler->patches[left->tail].next = right->head;
    left->tail = right->tail;
  }
}

U0 RegexPatchTo(CRegexCompiler *compiler, CRegexFragment *fragment,
  I64 target)
{
  CRegexInstruction *instruction;
  I64 patch = fragment->head;

  while (patch >= 0) {
    instruction = compiler->regex->instructions +
      compiler->patches[patch].instruction;
    if (compiler->patches[patch].field)
      instruction->y = target;
    else
      instruction->x = target;
    patch = compiler->patches[patch].next;
  }
  fragment->head = -1;
  fragment->tail = -1;
}

U0 RegexEmptyFragment(CRegexCompiler *compiler, CRegexFragment *fragment)
{
  I64 instruction = RegexEmit(compiler, REGEX_OP_JUMP);
  RegexFragmentOne(compiler, instruction, 0, fragment);
}

I64 RegexHexDigit(U8 ch)
{
  if (ch >= '0' && ch <= '9')
    return ch - '0';
  if (ch >= 'a' && ch <= 'f')
    return ch - 'a' + 10;
  if (ch >= 'A' && ch <= 'F')
    return ch - 'A' + 10;
  return -1;
}

Bool RegexReadPatternRune(CRegexCompiler *compiler, I64 *rune)
{
  I64 consumed;

  consumed = Utf8DecodeRune(compiler->pattern + compiler->offset,
    compiler->length - compiler->offset, rune);
  if (!consumed)
    return RegexCompileFail(compiler, REGEX_ERROR_UTF8, compiler->offset);
  compiler->offset += consumed;
  return TRUE;
}

I64 RegexRangeAdd(CRegexCompiler *compiler, I64 first, I64 last)
{
  I64 index = compiler->regex->range_count;

  if (index >= compiler->regex->range_capacity) {
    RegexCompileFail(compiler, REGEX_ERROR_MEMORY, compiler->offset);
    return -1;
  }
  compiler->regex->ranges[index].first = first;
  compiler->regex->ranges[index].last = last;
  compiler->regex->range_count++;
  return index;
}

U0 RegexClassKind(CRegexCompiler *compiler, I64 kind)
{
  if (kind == 'd') {
    RegexRangeAdd(compiler, '0', '9');
  } else if (kind == 'w') {
    RegexRangeAdd(compiler, '0', '9');
    RegexRangeAdd(compiler, 'A', 'Z');
    RegexRangeAdd(compiler, 'a', 'z');
    RegexRangeAdd(compiler, '_', '_');
  } else {
    RegexRangeAdd(compiler, '\t', '\r');
    RegexRangeAdd(compiler, ' ', ' ');
  }
}

Bool RegexReadEscape(CRegexCompiler *compiler, I64 *value, I64 *kind)
{
  I64 ch;
  I64 consumed;
  I64 high;
  I64 low;

  if (compiler->offset >= compiler->length)
    return RegexCompileFail(compiler, REGEX_ERROR_ESCAPE,
      compiler->offset);
  consumed = Utf8DecodeRune(compiler->pattern + compiler->offset,
    compiler->length - compiler->offset, &ch);
  if (!consumed)
    return RegexCompileFail(compiler, REGEX_ERROR_UTF8, compiler->offset);
  compiler->offset += consumed;
  *kind = 0;
  if (ch == 'd' || ch == 'w' || ch == 's') {
    *kind = ch;
    *value = 0;
  } else if (ch == 'n')
    *value = '\n';
  else if (ch == 'r')
    *value = '\r';
  else if (ch == 't')
    *value = '\t';
  else if (ch == 'f')
    *value = '\f';
  else if (ch == 'v')
    *value = '\v';
  else if (ch == 'x') {
    if (compiler->offset + 2 > compiler->length)
      return RegexCompileFail(compiler, REGEX_ERROR_ESCAPE,
        compiler->offset - 2);
    high = RegexHexDigit(compiler->pattern[compiler->offset]);
    low = RegexHexDigit(compiler->pattern[compiler->offset + 1]);
    if (high < 0 || low < 0)
      return RegexCompileFail(compiler, REGEX_ERROR_ESCAPE,
        compiler->offset - 2);
    compiler->offset += 2;
    *value = high * 16 + low;
  } else
    *value = ch;
  return TRUE;
}

U0 RegexParseAlternative(CRegexCompiler *compiler,
  CRegexFragment *fragment);

U0 RegexParseClass(CRegexCompiler *compiler, CRegexFragment *fragment)
{
  CRegexInstruction *instruction;
  I64 index = RegexEmit(compiler, REGEX_OP_CLASS);
  I64 value;
  I64 kind;
  I64 previous = -1;
  I64 previous_range = -1;
  I64 range_end;
  Bool negate = FALSE;
  Bool any = FALSE;
  I64 range_start;

  fragment->start = -1;
  fragment->head = -1;
  fragment->tail = -1;
  if (index < 0)
    return;
  instruction = compiler->regex->instructions + index;
  range_start = compiler->regex->range_count;
  if (compiler->offset < compiler->length &&
    compiler->pattern[compiler->offset] == '^') {
      negate = TRUE;
      compiler->offset++;
    }
  while (compiler->offset < compiler->length &&
    compiler->pattern[compiler->offset] != ']') {
      kind = 0;
      if (compiler->pattern[compiler->offset] == '\\') {
        compiler->offset++;
        if (!RegexReadEscape(compiler, &value, &kind))
          return;
      } else if (!RegexReadPatternRune(compiler, &value))
        return;
      if (kind) {
        RegexClassKind(compiler, kind);
        previous = -1;
        previous_range = -1;
        any = TRUE;
      } else if (value == '-' && previous >= 0 &&
        compiler->offset < compiler->length &&
        compiler->pattern[compiler->offset] != ']') {
          kind = 0;
          if (compiler->pattern[compiler->offset] == '\\') {
            compiler->offset++;
            if (!RegexReadEscape(compiler, &range_end, &kind))
              return;
          } else if (!RegexReadPatternRune(compiler, &range_end))
            return;
          if (kind || range_end < previous) {
            RegexCompileFail(compiler, REGEX_ERROR_CLASS,
              compiler->offset - 1);
            return;
          }
          compiler->regex->ranges[previous_range].last = range_end;
          previous = -1;
          previous_range = -1;
          any = TRUE;
        } else {
          previous_range = RegexRangeAdd(compiler, value, value);
          if (previous_range < 0)
            return;
          previous = value;
          any = TRUE;
        }
    }
  if (compiler->offset >= compiler->length || !any) {
    RegexCompileFail(compiler, REGEX_ERROR_CLASS, compiler->offset);
    return;
  }
  compiler->offset++;
  instruction->range_index = range_start;
  instruction->range_count = compiler->regex->range_count - range_start;
  instruction->negate = negate;
  RegexFragmentOne(compiler, index, 0, fragment);
}

U0 RegexParseAtom(CRegexCompiler *compiler, CRegexFragment *fragment)
{
  CRegexInstruction *instruction;
  I64 index;
  I64 value;
  I64 kind;
  U8 ch;

  fragment->start = -1;
  fragment->head = -1;
  fragment->tail = -1;
  if (compiler->offset >= compiler->length) {
    RegexEmptyFragment(compiler, fragment);
    return;
  }
  ch = compiler->pattern[compiler->offset];
  if (ch == '*' || ch == '+' || ch == '?') {
    RegexCompileFail(compiler, REGEX_ERROR_REPEAT, compiler->offset);
    return;
  }
  compiler->offset++;
  if (ch == '(') {
    RegexParseAlternative(compiler, fragment);
    if (compiler->regex->error)
      return;
    if (compiler->offset >= compiler->length ||
      compiler->pattern[compiler->offset] != ')') {
        RegexCompileFail(compiler, REGEX_ERROR_PAREN, compiler->offset);
        return;
      }
    compiler->offset++;
    return;
  }
  if (ch == '[') {
    RegexParseClass(compiler, fragment);
    return;
  }
  if (ch == '.')
    index = RegexEmit(compiler, REGEX_OP_ANY);
  else if (ch == '^')
    index = RegexEmit(compiler, REGEX_OP_BOL);
  else if (ch == '$')
    index = RegexEmit(compiler, REGEX_OP_EOL);
  else if (ch == '\\') {
    if (!RegexReadEscape(compiler, &value, &kind))
      return;
    if (kind) {
      index = RegexEmit(compiler, REGEX_OP_CLASS);
      if (index >= 0) {
        instruction = compiler->regex->instructions + index;
        instruction->range_index = compiler->regex->range_count;
        RegexClassKind(compiler, kind);
        instruction->range_count = compiler->regex->range_count -
          instruction->range_index;
      }
    } else {
      index = RegexEmit(compiler, REGEX_OP_RUNE);
      if (index >= 0)
        compiler->regex->instructions[index].rune = value;
    }
  } else {
    compiler->offset--;
    if (!RegexReadPatternRune(compiler, &value))
      return;
    index = RegexEmit(compiler, REGEX_OP_RUNE);
    if (index >= 0)
      compiler->regex->instructions[index].rune = value;
  }
  if (index < 0)
    return;
  RegexFragmentOne(compiler, index, 0, fragment);
}

U0 RegexParseRepeat(CRegexCompiler *compiler, CRegexFragment *fragment)
{
  CRegexFragment extra;
  I64 split;
  U8 ch;

  RegexParseAtom(compiler, fragment);
  if (compiler->regex->error)
    return;
  if (compiler->offset >= compiler->length)
    return;
  ch = compiler->pattern[compiler->offset];
  if (ch != '*' && ch != '+' && ch != '?')
    return;
  compiler->offset++;
  split = RegexEmit(compiler, REGEX_OP_SPLIT);
  if (split < 0)
    return;
  if (ch == '*') {
    compiler->regex->instructions[split].x = fragment->start;
    RegexPatchTo(compiler, fragment, split);
    RegexFragmentOne(compiler, split, 1, fragment);
  } else if (ch == '+') {
    compiler->regex->instructions[split].x = fragment->start;
    RegexPatchTo(compiler, fragment, split);
    RegexFragmentOne(compiler, split, 1, fragment);
    fragment->start = compiler->regex->instructions[split].x;
  } else {
    compiler->regex->instructions[split].x = fragment->start;
    RegexFragmentOne(compiler, split, 1, &extra);
    RegexPatchJoin(compiler, fragment, &extra);
    fragment->start = split;
  }
  if (compiler->offset < compiler->length) {
    ch = compiler->pattern[compiler->offset];
    if (ch == '*' || ch == '+' || ch == '?')
      RegexCompileFail(compiler, REGEX_ERROR_REPEAT, compiler->offset);
  }
}

Bool RegexAtomBegins(CRegexCompiler *compiler)
{
  U8 ch;

  if (compiler->offset >= compiler->length)
    return FALSE;
  ch = compiler->pattern[compiler->offset];
  return ch != ')' && ch != '|';
}

U0 RegexParseSequence(CRegexCompiler *compiler, CRegexFragment *result)
{
  CRegexFragment next;

  if (!RegexAtomBegins(compiler)) {
    RegexEmptyFragment(compiler, result);
    return;
  }
  RegexParseRepeat(compiler, result);
  while (!compiler->regex->error && RegexAtomBegins(compiler)) {
    RegexParseRepeat(compiler, &next);
    RegexPatchTo(compiler, result, next.start);
    result->head = next.head;
    result->tail = next.tail;
  }
}

U0 RegexParseAlternative(CRegexCompiler *compiler,
  CRegexFragment *result)
{
  CRegexFragment right;
  I64 split;

  RegexParseSequence(compiler, result);
  while (!compiler->regex->error && compiler->offset < compiler->length &&
    compiler->pattern[compiler->offset] == '|') {
      compiler->offset++;
      RegexParseSequence(compiler, &right);
      split = RegexEmit(compiler, REGEX_OP_SPLIT);
      if (split < 0)
        return;
      compiler->regex->instructions[split].x = result->start;
      compiler->regex->instructions[split].y = right.start;
      RegexPatchJoin(compiler, result, &right);
      result->start = split;
    }
}

Bool RegexCompileN(CRegex *regex, U8 *pattern, I64 length)
{
  CRegexCompiler compiler;
  CRegexFragment fragment;
  I64 match;
  I64 capacity;

  if (!regex)
    return FALSE;
  RegexFini(regex);
  if (!pattern || length < 0) {
    regex->error = REGEX_ERROR_ARGUMENT;
    return FALSE;
  }
  if (length > (I64_MAX - 8) / 4) {
    regex->error = REGEX_ERROR_MEMORY;
    return FALSE;
  }
  capacity = length * 4 + 8;
  if (capacity > I64_MAX / sizeof(CRegexInstruction) ||
    capacity > I64_MAX / (2 * sizeof(CRegexPatch)) ||
    capacity > I64_MAX / sizeof(CRegexRange)) {
      regex->error = REGEX_ERROR_MEMORY;
      return FALSE;
    }
  regex->instructions = MAlloc(capacity * sizeof(CRegexInstruction));
  regex->ranges = MAlloc(capacity * sizeof(CRegexRange));
  compiler.patches = MAlloc(capacity * 2 * sizeof(CRegexPatch));
  if (!regex->instructions || !regex->ranges || !compiler.patches) {
    Free(compiler.patches);
    regex->error = REGEX_ERROR_MEMORY;
    return FALSE;
  }
  regex->instruction_capacity = capacity;
  regex->range_capacity = capacity;
  compiler.regex = regex;
  compiler.pattern = pattern;
  compiler.length = length;
  compiler.offset = 0;
  compiler.patch_count = 0;
  compiler.patch_capacity = capacity * 2;
  RegexParseAlternative(&compiler, &fragment);
  if (!regex->error && compiler.offset != length)
    RegexCompileFail(&compiler, REGEX_ERROR_PAREN, compiler.offset);
  if (!regex->error) {
    match = RegexEmit(&compiler, REGEX_OP_MATCH);
    if (match >= 0) {
      RegexPatchTo(&compiler, &fragment, match);
      regex->start = fragment.start;
    }
  }
  Free(compiler.patches);
  if (regex->error)
    return FALSE;
  regex->list_a = MAlloc(regex->instruction_count * sizeof(I64));
  regex->list_b = MAlloc(regex->instruction_count * sizeof(I64));
  regex->origin_a = MAlloc(regex->instruction_count * sizeof(I64));
  regex->origin_b = MAlloc(regex->instruction_count * sizeof(I64));
  regex->seen = MAlloc(regex->instruction_count * sizeof(I64));
  if (!regex->list_a || !regex->list_b || !regex->origin_a ||
    !regex->origin_b || !regex->seen) {
      regex->error = REGEX_ERROR_MEMORY;
      return FALSE;
    }
  MemSet(regex->seen, 0, regex->instruction_count * sizeof(I64));
  regex->generation = 1;
  return TRUE;
}

Bool RegexCompile(CRegex *regex, U8 *pattern)
{
  if (!pattern) {
    if (regex) {
      RegexFini(regex);
      regex->error = REGEX_ERROR_ARGUMENT;
    }
    return FALSE;
  }
  return RegexCompileN(regex, pattern, StrLen(pattern));
}

I64 RegexNextGeneration(CRegex *regex)
{
  if (regex->generation == I64_MAX) {
    MemSet(regex->seen, 0, regex->instruction_count * sizeof(I64));
    regex->generation = 1;
  } else
    regex->generation++;
  return regex->generation;
}

Bool RegexInstructionMatches(CRegex *regex, CRegexInstruction *instruction,
  I64 rune)
{
  CRegexRange *range;
  Bool found = FALSE;
  I64 i;

  if (instruction->op == REGEX_OP_RUNE)
    return instruction->rune == rune;
  if (instruction->op == REGEX_OP_ANY)
    return TRUE;
  if (instruction->op != REGEX_OP_CLASS)
    return FALSE;
  range = regex->ranges + instruction->range_index;
  for (i = 0; i < instruction->range_count; i++) {
    if (rune >= range[i].first && rune <= range[i].last) {
      found = TRUE;
      break;
    }
  }
  if (instruction->negate)
    return !found;
  return found;
}

Bool RegexUtf8Boundary(U8 *text, I64 length, I64 position)
{
  if (position <= 0 || position >= length)
    return TRUE;
  return text[position] < 0x80 || text[position] > 0xBF;
}

U0 RegexAddState(CRegex *regex, I64 *list, I64 *origins, I64 *count,
  I64 state, I64 origin, I64 position, I64 length, I64 generation)
{
  CRegexInstruction *instruction;

  if (state < 0 || regex->seen[state] == generation)
    return;
  regex->seen[state] = generation;
  instruction = regex->instructions + state;
  if (instruction->op == REGEX_OP_SPLIT) {
    RegexAddState(regex, list, origins, count, instruction->x, origin,
      position, length, generation);
    RegexAddState(regex, list, origins, count, instruction->y, origin,
      position, length, generation);
  } else if (instruction->op == REGEX_OP_JUMP) {
    RegexAddState(regex, list, origins, count, instruction->x, origin,
      position, length, generation);
  } else if (instruction->op == REGEX_OP_BOL) {
    if (!position)
      RegexAddState(regex, list, origins, count, instruction->x, origin,
        position, length, generation);
  } else if (instruction->op == REGEX_OP_EOL) {
    if (position == length)
      RegexAddState(regex, list, origins, count, instruction->x, origin,
        position, length, generation);
  } else {
    list[*count] = state;
    origins[*count] = origin;
    (*count)++;
  }
}

I64 RegexRunAt(CRegex *regex, U8 *text, I64 length, I64 start)
{
  CRegexInstruction *instruction;
  I64 *current = regex->list_a;
  I64 *next = regex->list_b;
  I64 *swap;
  I64 current_count = 0;
  I64 next_count;
  I64 position = start;
  I64 accepted = -1;
  I64 generation;
  I64 consumed;
  I64 rune;
  I64 i;

  generation = RegexNextGeneration(regex);
  RegexAddState(regex, current, regex->origin_a, &current_count,
    regex->start, start, position, length, generation);
  for (;;) {
    for (i = 0; i < current_count; i++) {
      instruction = regex->instructions + current[i];
      if (instruction->op == REGEX_OP_MATCH)
        accepted = position;
    }
    if (position >= length || !current_count)
      break;
    consumed = Utf8DecodeRune(text + position, length - position, &rune);
    if (!consumed)
      break;
    next_count = 0;
    generation = RegexNextGeneration(regex);
    for (i = 0; i < current_count; i++) {
      instruction = regex->instructions + current[i];
      if (RegexInstructionMatches(regex, instruction, rune))
        RegexAddState(regex, next, regex->origin_b, &next_count,
          instruction->x, start, position + consumed, length, generation);
    }
    position += consumed;
    swap = current;
    current = next;
    next = swap;
    current_count = next_count;
  }
  return accepted;
}

Bool RegexMatchFromN(CRegex *regex, U8 *text, I64 length, I64 from,
  CRegexMatch *match)
{
  CRegexInstruction *instruction;
  I64 *current;
  I64 *next;
  I64 *current_origins;
  I64 *next_origins;
  I64 *swap;
  I64 current_count = 0;
  I64 next_count;
  I64 position = from;
  I64 best_start = -1;
  I64 best_end = -1;
  I64 generation;
  I64 origin;
  I64 consumed;
  I64 rune;
  I64 i;
  Bool valid;

  if (!regex || regex->error || !regex->instructions || !text ||
    length < 0 || from < 0 || from > length || !match)
    return FALSE;
  for (; from < length && !RegexUtf8Boundary(text, length, from);)
    from++;
  position = from;
  current = regex->list_a;
  next = regex->list_b;
  current_origins = regex->origin_a;
  next_origins = regex->origin_b;
  generation = RegexNextGeneration(regex);
  RegexAddState(regex, current, current_origins, &current_count,
    regex->start, from, position, length, generation);
  for (;;) {
    for (i = 0; i < current_count; i++) {
      instruction = regex->instructions + current[i];
      origin = current_origins[i];
      if (instruction->op == REGEX_OP_MATCH &&
        (best_start < 0 || origin < best_start ||
          origin == best_start && position > best_end)) {
            best_start = origin;
            best_end = position;
          }
    }
    if (position >= length || best_start >= 0 && !current_count)
      break;
    consumed = Utf8DecodeRune(text + position, length - position, &rune);
    valid = consumed != 0;
    if (!valid)
      consumed = 1;
    next_count = 0;
    generation = RegexNextGeneration(regex);
    for (i = 0; i < current_count; i++) {
      origin = current_origins[i];
      if (best_start < 0 || origin == best_start) {
        instruction = regex->instructions + current[i];
        if (valid && RegexInstructionMatches(regex, instruction, rune))
          RegexAddState(regex, next, next_origins, &next_count,
            instruction->x, origin, position + consumed, length, generation);
      }
    }
    position += consumed;
    swap = current;
    current = next;
    next = swap;
    swap = current_origins;
    current_origins = next_origins;
    next_origins = swap;
    current_count = next_count;
    if (best_start < 0 && RegexUtf8Boundary(text, length, position))
      RegexAddState(regex, current, current_origins, &current_count,
        regex->start, position, position, length, generation);
    if (best_start >= 0 && !current_count)
      break;
  }
  if (best_start < 0)
    return FALSE;
  match->start = best_start;
  match->end = best_end;
  return TRUE;
}

Bool RegexMatchN(CRegex *regex, U8 *text, I64 length, CRegexMatch *match)
{
  return RegexMatchFromN(regex, text, length, 0, match);
}

Bool RegexMatch(CRegex *regex, U8 *text, CRegexMatch *match)
{
  if (!text)
    return FALSE;
  return RegexMatchN(regex, text, StrLen(text), match);
}

Bool RegexFullMatchN(CRegex *regex, U8 *text, I64 length)
{
  if (!regex || regex->error || !regex->instructions || !text || length < 0)
    return FALSE;
  return RegexRunAt(regex, text, length, 0) == length;
}

Bool RegexFullMatch(CRegex *regex, U8 *text)
{
  if (!text)
    return FALSE;
  return RegexFullMatchN(regex, text, StrLen(text));
}

Bool RegexReplaceAdd(I64 *total, I64 amount)
{
  if (amount < 0 || *total > I64_MAX - amount)
    return FALSE;
  *total += amount;
  return TRUE;
}

I64 RegexReplacementLength(U8 *replacement, I64 length, I64 match_length)
{
  I64 total = 0;
  I64 i = 0;

  while (i < length) {
    if (replacement[i] == '$' && i + 1 < length &&
      replacement[i + 1] == '0') {
        if (!RegexReplaceAdd(&total, match_length))
          return -1;
        i += 2;
      } else {
        if (!RegexReplaceAdd(&total, 1))
          return -1;
        if (replacement[i] == '$' && i + 1 < length &&
          replacement[i + 1] == '$')
          i += 2;
        else
          i++;
      }
  }
  return total;
}

U0 RegexWriteReplacement(U8 *output, I64 *at, U8 *replacement,
  I64 length, U8 *matched, I64 match_length)
{
  I64 i = 0;

  while (i < length) {
    if (replacement[i] == '$' && i + 1 < length &&
      replacement[i + 1] == '0') {
        if (match_length)
          MemCpy(output + *at, matched, match_length);
        *at += match_length;
        i += 2;
      } else {
        output[(*at)++] = replacement[i];
        if (replacement[i] == '$' && i + 1 < length &&
          replacement[i + 1] == '$')
          i += 2;
        else
          i++;
      }
  }
}

I64 RegexReplaceN(CRegex *regex, U8 *text, I64 text_length,
  U8 *replacement, I64 replacement_length, U8 *output, I64 capacity,
  I64 limit=-1)
{
  CRegexMatch match;
  I64 search = 0;
  I64 copied = 0;
  I64 count = 0;
  I64 needed = 0;
  I64 part;
  I64 at = 0;

  if (!regex || regex->error || !text || text_length < 0 || !replacement ||
    replacement_length < 0 || capacity < 0 || limit < -1)
    return -1;
  for (; search <= text_length;) {
    if (limit >= 0 && count >= limit)
      break;
    if (!RegexMatchFromN(regex, text, text_length, search, &match))
      break;
    if (!RegexReplaceAdd(&needed, match.start - copied))
      return -1;
    part = RegexReplacementLength(replacement, replacement_length,
      match.end - match.start);
    if (part < 0 || !RegexReplaceAdd(&needed, part))
      return -1;
    copied = match.end;
    count++;
    if (match.end == match.start) {
      if (match.end == text_length)
        break;
      search = match.end + 1;
    } else
      search = match.end;
  }
  if (!RegexReplaceAdd(&needed, text_length - copied))
    return -1;
  if (!output || needed == I64_MAX || capacity <= needed)
    return needed;

  search = 0;
  copied = 0;
  count = 0;
  for (; search <= text_length;) {
    if (limit >= 0 && count >= limit)
      break;
    if (!RegexMatchFromN(regex, text, text_length, search, &match))
      break;
    if (match.start > copied) {
      MemCpy(output + at, text + copied, match.start - copied);
      at += match.start - copied;
    }
    RegexWriteReplacement(output, &at, replacement, replacement_length,
      text + match.start, match.end - match.start);
    copied = match.end;
    count++;
    if (match.end == match.start) {
      if (match.end == text_length)
        break;
      search = match.end + 1;
    } else
      search = match.end;
  }
  if (copied < text_length) {
    MemCpy(output + at, text + copied, text_length - copied);
    at += text_length - copied;
  }
  output[at] = 0;
  return needed;
}

I64 RegexReplace(CRegex *regex, U8 *text, U8 *replacement, U8 *output,
  I64 capacity, I64 limit=-1)
{
  if (!text || !replacement)
    return -1;
  return RegexReplaceN(regex, text, StrLen(text), replacement,
    StrLen(replacement), output, capacity, limit);
}

U8 *RegexErrorName(I64 error)
{
  if (error == REGEX_OK)
    return "ok";
  if (error == REGEX_ERROR_ARGUMENT)
    return "invalid argument";
  if (error == REGEX_ERROR_MEMORY)
    return "out of memory";
  if (error == REGEX_ERROR_SYNTAX)
    return "invalid syntax";
  if (error == REGEX_ERROR_PAREN)
    return "unmatched parenthesis";
  if (error == REGEX_ERROR_CLASS)
    return "invalid character class";
  if (error == REGEX_ERROR_ESCAPE)
    return "invalid escape";
  if (error == REGEX_ERROR_REPEAT)
    return "invalid repetition";
  if (error == REGEX_ERROR_UTF8)
    return "invalid UTF-8";
  return "unknown error";
}

#endif
