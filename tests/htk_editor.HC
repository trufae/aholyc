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
"ok htk editor\n";
