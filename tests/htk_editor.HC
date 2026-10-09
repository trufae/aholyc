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
HtkDestroy(editor); EditFini(&edit);
"ok htk editor\n";
