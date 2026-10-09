// Run the target's model/layout code on the host, without native API calls.
// Print C assertions using HolyC's offsets, for compilation against the NDK.
#include "../lib/ui/ui.hc"

U0 Check(Bool condition) { if (!condition) throw('UiAmiga'); }

UiCtl *box = UiBoxNew, *row = UiBoxNew(FALSE);
UiCtl *label = UiLabelNew("A"), *a = UiButtonNew("A"), *b = UiButtonNew("B");
UiBoxAdd(box, label); UiBoxAdd(row, a); UiBoxAdd(row, b); UiBoxAdd(box, row);
UiCtl *window = UiWindowNew("model");
UiWindowSetChild(window, box);
Check(UiAmiga(a)->owner == window && UiAmiga(a)->parent == row);
UiAmigaMeasure(box);
Check(UiAmiga(box)->w == 54 && UiAmiga(box)->h == 38);
UiAmigaPlace(box, 10, 20, 200, 100);
Check(UiAmiga(label)->w == 200 && UiAmiga(row)->y == 38);
Check(UiAmiga(a)->x == 10 && UiAmiga(b)->x == 40);
UiSetVisible(a, FALSE); UiAmigaMeasure(box); UiAmigaPlace(box, 10, 20, 200, 100);
Check(!UiAmigaVisible(a) && UiAmiga(b)->x == 10);
Check(UiAmiga(box)->w == 200); // allocated width after Place
UiExpand(row, TRUE); UiAmigaMeasure(box); UiAmigaPlace(box, 10, 20, 200, 100);
Check(UiAmiga(row)->h == 82);

ui_amiga_window = NULL;
UiCtl *group = UiGroupNew("group"), *child = UiEntryNew("old");
UiGroupSetChild(group, child); UiBoxAdd(box, group);
Check(UiAmiga(child)->owner == window);
UiEntrySetText(child, "new");
U8 *text = UiEntryText(child); Check(StrCmp(text, "new") == 0); Free(text);
UiEnable(group, FALSE); Check(UiAmiga(child)->disabled);

UiCtl *tabs = UiTabNew, *one = UiBoxNew, *two = UiBoxNew;
UiCtl *first = UiLabelNew("first"), *second = UiLabelNew("second");
UiBoxAdd(one, first); UiBoxAdd(two, second);
UiTabAdd(tabs, "one", one); UiTabAdd(tabs, "two", two);
Check(UiAmigaVisible(first) && !UiAmigaVisible(second));
UiAmiga(tabs)->value = 1;
Check(!UiAmigaVisible(first) && UiAmigaVisible(second));

U0 Offset(U8 *type, U8 *field, I64 holy)
{
  "_Static_assert(offsetof(struct %s, %s) == %d, \"%s.%s\");\n", type, field, holy, type, field;
}
U0 Size(U8 *type, I64 holy)
{
  "_Static_assert(sizeof(struct %s) == %d, \"sizeof %s\");\n", type, holy, type;
}
"#include <stddef.h>\n#include <intuition/intuition.h>\n#include <libraries/gadtools.h>\n#include <libraries/asl.h>\n";
Size("TagItem", sizeof(UiAmigaTag));
Size("NewGadget", sizeof(UiAmigaNewGadget));
Size("NewMenu", sizeof(UiAmigaNewMenu));
Size("EasyStruct", sizeof(UiAmigaEasy));
Size("List", sizeof(UiAmigaList));
Offset("Window", "Width", offset(UiAmigaWindow.width));
Offset("Window", "Height", offset(UiAmigaWindow.height));
Offset("Window", "WScreen", offset(UiAmigaWindow.screen));
Offset("Window", "RPort", offset(UiAmigaWindow.port));
Offset("Window", "BorderLeft", offset(UiAmigaWindow.left));
Offset("Window", "BorderTop", offset(UiAmigaWindow.top));
Offset("Window", "BorderRight", offset(UiAmigaWindow.right));
Offset("Window", "BorderBottom", offset(UiAmigaWindow.bottom));
Offset("Window", "UserPort", offset(UiAmigaWindow.messages));
Offset("Screen", "Font", offset(UiAmigaScreen.font));
"_Static_assert(offsetof(struct Screen, ViewPort) + offsetof(struct ViewPort, ColorMap) == %d, \"Screen.ColorMap\");\n", offset(UiAmigaScreen.colors);
Offset("MsgPort", "mp_SigBit", offset(UiAmigaPort.signal));
Offset("IntuiMessage", "Class", offset(UiAmigaMessage.event));
Offset("IntuiMessage", "Code", offset(UiAmigaMessage.code));
Offset("IntuiMessage", "Qualifier", offset(UiAmigaMessage.qualifier));
Offset("IntuiMessage", "IAddress", offset(UiAmigaMessage.address));
Offset("IntuiMessage", "MouseX", offset(UiAmigaMessage.x));
Offset("IntuiMessage", "MouseY", offset(UiAmigaMessage.y));
Offset("Gadget", "Flags", offset(UiAmigaGadget.flags));
Offset("Gadget", "SpecialInfo", offset(UiAmigaGadget.special));
Offset("Gadget", "GadgetID", offset(UiAmigaGadget.id));
Offset("Gadget", "UserData", offset(UiAmigaGadget.user));
Offset("StringInfo", "Buffer", offset(UiAmigaString.buffer));
Offset("StringInfo", "LongInt", offset(UiAmigaString.number));
Offset("NewGadget", "ng_LeftEdge", offset(UiAmigaNewGadget.x));
Offset("NewGadget", "ng_TopEdge", offset(UiAmigaNewGadget.y));
Offset("NewGadget", "ng_Width", offset(UiAmigaNewGadget.w));
Offset("NewGadget", "ng_Height", offset(UiAmigaNewGadget.h));
Offset("NewGadget", "ng_GadgetText", offset(UiAmigaNewGadget.text));
Offset("NewGadget", "ng_TextAttr", offset(UiAmigaNewGadget.font));
Offset("NewGadget", "ng_GadgetID", offset(UiAmigaNewGadget.id));
Offset("NewGadget", "ng_Flags", offset(UiAmigaNewGadget.flags));
Offset("NewGadget", "ng_VisualInfo", offset(UiAmigaNewGadget.visual));
Offset("NewGadget", "ng_UserData", offset(UiAmigaNewGadget.user));
Offset("NewMenu", "nm_Type", offset(UiAmigaNewMenu.type));
Offset("NewMenu", "nm_Label", offset(UiAmigaNewMenu.label));
Offset("NewMenu", "nm_CommKey", offset(UiAmigaNewMenu.key));
Offset("NewMenu", "nm_Flags", offset(UiAmigaNewMenu.flags));
Offset("NewMenu", "nm_MutualExclude", offset(UiAmigaNewMenu.exclude));
Offset("NewMenu", "nm_UserData", offset(UiAmigaNewMenu.user));
Offset("MenuItem", "NextSelect", offset(UiAmigaMenuItem.next));
"_Static_assert(sizeof(struct MenuItem) == %d, \"GadTools MenuItem user data\");\n", offset(UiAmigaMenuItem.user);
Offset("EasyStruct", "es_StructSize", offset(UiAmigaEasy.size));
Offset("EasyStruct", "es_Flags", offset(UiAmigaEasy.flags));
Offset("EasyStruct", "es_Title", offset(UiAmigaEasy.title));
Offset("EasyStruct", "es_TextFormat", offset(UiAmigaEasy.body));
Offset("EasyStruct", "es_GadgetFormat", offset(UiAmigaEasy.buttons));
Offset("FileRequester", "fr_File", offset(UiAmigaFile.file));
Offset("FileRequester", "fr_Drawer", offset(UiAmigaFile.drawer));
Offset("List", "lh_Head", offset(UiAmigaList.head));
Offset("List", "lh_Tail", offset(UiAmigaList.tail));
Offset("List", "lh_TailPred", offset(UiAmigaList.previous));
Offset("Node", "ln_Succ", offset(UiAmigaNode.next));
Offset("Node", "ln_Pred", offset(UiAmigaNode.previous));
Offset("Node", "ln_Type", offset(UiAmigaNode.type));
Offset("Node", "ln_Pri", offset(UiAmigaNode.priority));
Offset("Node", "ln_Name", offset(UiAmigaNode.name));
