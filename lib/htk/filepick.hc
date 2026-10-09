#ifndef AHOLYC_LIB_HTK_FILEPICK_HC
#define AHOLYC_LIB_HTK_FILEPICK_HC

#include "htk.hc"

class CHtkFilePick
{
  HtkCtl *window;
  HtkCtl *entry;
  HtkCtl *tree;
  U8 *directory;
  U8 *result;
};

#ifdef IS_WINDOWS
class CHtkFindData
{
  U32 attributes;
  U64 created, accessed, written;
  U32 size_high, size_low, reserved0, reserved1;
  U8 name[260];
  U8 alternate[14];
  U16 padding;
};
extern I64 FindFirstFileA(U8 *pattern, CHtkFindData *data);
extern I64 FindNextFileA(I64 handle, CHtkFindData *data);
extern I64 FindClose(I64 handle);
extern I64 GetFileAttributesA(U8 *path);
#else
extern U8 *opendir(U8 *path);
extern I64 closedir(U8 *dir);
extern U8 *readdir(U8 *dir);
#endif

Bool HtkFileIsDir(U8 *path)
{
  #ifdef IS_WINDOWS
  I64 attr = GetFileAttributesA(path)(I32);

  return attr != -1 && (attr & 16);
  #else
  U8 *dir = opendir(path);

  if (!dir) return FALSE;
  closedir(dir);
  return TRUE;
  #endif
}

U0 HtkFileChoose(HtkCtl *tree)
{
  CHtkFilePick *pick = tree->user;
  U8 *path;

  if (tree->link) {
    path = MStrPrint("%s/%s", pick->directory, tree->link->text);
    HtkSetText(pick->entry, path);
    pick->entry->cursor = StrLen(path);
    Free(path);
  }
}

U0 HtkFileFill(CHtkFilePick *pick, U8 *path)
{
  HtkCtl *node, *next;
  U8 *name, *owned = StrNew(path);
  #ifdef IS_WINDOWS
  CHtkFindData entry;
  U8 *pattern = MStrPrint("%s/*", path);
  I64 handle = FindFirstFileA(pattern, &entry);

  Free(pattern);
  #else
  U8 *handle = opendir(path), *entry;
  #endif

  node = pick->tree->kids;
  while (node) { next = node->sib; HtkDestroy(node); node = next; }
  pick->tree->kids = NULL;
  pick->tree->link = NULL;
  pick->tree->top = 0;
  Free(pick->directory);
  pick->directory = owned;
  HtkSetText(pick->entry, owned);
  pick->entry->cursor = StrLen(owned);
  #ifdef IS_WINDOWS
  if (handle == -1) return;
  do {
    name = entry.name;
    #else
    if (!handle) return;
    while (entry = readdir(handle)) {
      #ifdef IS_MACOS
      name = entry + 21; // Darwin dirent: ino64, seekoff64, reclen16, namlen16, type8
      #else
      name = entry + 19; // Linux dirent64: ino64, off64, reclen16, type8
      #endif
      #endif
      if (StrCmp(name, ".")) HtkTreeAdd(pick->tree, NULL, name);
      #ifdef IS_WINDOWS
    } while (FindNextFileA(handle, &entry)(I32));
    FindClose(handle);
    #else
  }
  closedir(handle);
  #endif
  pick->tree->link = NULL;
}

U0 HtkFileAccept(HtkCtl *from)
{
  CHtkFilePick *pick = from->user;
  U8 *path = StrNew(pick->entry->text);

  if (HtkFileIsDir(path)) HtkFileFill(pick, path);
  else if (*path) {
    pick->result = StrNew(path);
    HtkWindowClose(pick->window);
  }
  Free(path);
}

Bool HtkFileKey(HtkCtl *tree, CTermEvent *event)
{
  if (event->key != TERM_KEY_ENTER) return FALSE;
  HtkFileChoose(tree);
  HtkFileAccept(tree);
  return TRUE;
}

// Browsing picker; paths stay process-relative and never change the cwd.
U8 *HtkFilePickFor(HtkCtl *owner, U8 *directory=".")
{
  CHtkFilePick pick;
  HtkCtl *box = HtkNew(HTK_BOX), *button;

  box->vertical = TRUE;
  pick.entry = HtkEntryNew(directory);
  pick.entry->user = &pick;
  pick.entry->submit = &HtkFileAccept;
  pick.entry->expand = FALSE;
  HtkAdd(box, pick.entry);
  pick.tree = HtkTreeNew;
  pick.tree->user = &pick;
  pick.tree->changed = &HtkFileChoose;
  pick.tree->keyfn = &HtkFileKey;
  HtkAdd(box, pick.tree);
  button = HtkButtonNew("Open file / enter folder");
  button->user = &pick;
  button->changed = &HtkFileAccept;
  HtkAdd(box, button);
  pick.window = HtkWindowNew("Open Markdown - Enter opens, Esc cancels", 60, 18);
  pick.window->low = TRUE;
  HtkWindowSetControls(pick.window, HTK_WINDOW_CLOSE);
  HtkAdd(pick.window, box);
  HtkFileFill(&pick, directory);
  HtkSetFocus(pick.tree);
  HtkModalFor(pick.window, owner);
  Free(pick.directory);
  HtkDestroy(pick.window);
  return pick.result;
}

#endif
