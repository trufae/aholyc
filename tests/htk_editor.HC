#define HTK_NODESK
#include "../lib/htk/markdown.hc"

// The Markdown widget must also build without opting into Vim support.
CEdit edit;
HtkCtl *editor;
CTermEvent event;

EditInit(&edit);
editor = HtkMarkdownNew(&edit);
HtkMarkdownMode(editor, HTK_MD_SOURCE);
event.type = TERM_EVENT_KEY; event.mods = 0;
event.key = 'V'; HtkMdKey(editor, &event);
event.key = 'J'; HtkMdKey(editor, &event);
event.key = 0xE9; HtkMdKey(editor, &event);
if (StrsLen(&edit.text) != 4 || MemCmp(edit.text.a, "VJé", 4) || edit.cursor != 4) {
  "FAIL Markdown input without Vim\n"; Exit(1);
}
EditFini(&edit); EditInit(&edit); StrBufPutS(&edit.text, "- [ ] task é😀\n");
editor->w = 40; editor->h = 8;
HtkMarkdownMode(editor, HTK_MD_READ); edit.cursor = 9;
event.key = ' '; HtkMdKey(editor, &event);
if (edit.text.a[3] != 'x' || !edit.readonly || edit.cursor != 9 || edit.revision != 1) {
  "FAIL task toggle without Vim\n"; Exit(1);
}
HtkMarkdownMode(editor, HTK_MD_SOURCE_READ);
HtkMdRender(editor->data); edit.cursor = 3;
HtkMdRender(editor->data);
editor->mouse_x = editor->data(CHtkMarkdown *)->caret_x;
editor->mouse_y = editor->data(CHtkMarkdown *)->caret_y;
editor->mouse_button = TERM_MOUSE_LEFT; editor->mouse_pressed = TRUE;
HtkMdMouse(editor); editor->mouse_pressed = FALSE; HtkMdMouse(editor);
if (edit.text.a[3] != ' ' || !edit.readonly) {
  "FAIL task click without Vim\n"; Exit(1);
}
HtkDestroy(editor); EditFini(&edit);

// A canvas that scrolls itself must consume the wheel before an enclosing
// scroll container gets a second chance to apply the same report.
term_width = 40; term_height = 12; TermBuffersAlloc; HtkThemeDefault;
HtkCtl *window = HtkWindowNew("Nested scroll", 32, 8);
HtkCtl *scroll = HtkNew(HTK_SCROLL);
I64 i;
EditInit(&edit);
for (i = 0; i < 30; i++) StrBufPutS(&edit.text, "row\n");
editor = HtkMarkdownNew(&edit);
HtkMarkdownMode(editor, HTK_MD_SOURCE);
HtkAdd(scroll, editor); HtkAdd(window, scroll);
HtkWindowLayout(window); HtkSetFocus(editor); HtkRedraw;
MemSet(&event, 0, sizeof(CTermEvent));
event.type = TERM_EVENT_MOUSE; event.button = TERM_MOUSE_WHEEL_DOWN; event.pressed = TRUE;
event.x = editor->x + 3; event.y = editor->y + 2;
HtkMouse(&event); HtkRedraw;
if (editor->top != 1 || scroll->top || !editor->mouse_handled) {
  "FAIL nested Markdown wheel scrolls twice\n"; Exit(1);
}
event.button = TERM_MOUSE_WHEEL_UP; HtkMouse(&event); HtkRedraw;
if (editor->top || scroll->top) {
  "FAIL nested Markdown wheel reverses incorrectly\n"; Exit(1);
}
// An unhandled canvas wheel still reaches its parent, with no stale flag.
editor->changed = NULL; editor->scrollfn = NULL;
event.button = TERM_MOUSE_WHEEL_DOWN; HtkMouse(&event);
if (scroll->top != 1 || editor->mouse_handled) {
  "FAIL unhandled canvas wheel does not scroll its parent\n"; Exit(1);
}
HtkWindowClose(window); HtkDestroy(window); EditFini(&edit);
Free(term_back); Free(term_front);

"ok htk editor\n";
