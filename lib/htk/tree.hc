// Tree of HTK_TREENODE kids; value on a node is its expanded flag, link on
// the tree points at the selected node.

HtkCtl *HtkTreeNew()
{
  HtkCtl *c = HtkNew(HTK_TREE);

  c->focusable = TRUE;
  c->expand = TRUE;
  return c;
}

HtkCtl *HtkTreeAdd(HtkCtl *tree, HtkCtl *parent, U8 *label)
{
  HtkCtl *node = HtkNew(HTK_TREENODE);

  HtkSetText(node, label);
  node->value = TRUE;  // expanded
  if (!parent)
    parent = tree;
  HtkAdd(parent, node);
  if (!tree->link)
    tree->link = node;
  htk_dirty = TRUE;
  return node;
}

// Depth-first walk of visible nodes; returns the node at target (counting
// from zero) and reports the total through count.
HtkCtl *HtkTreeWalk(HtkCtl *at, I64 depth, I64 target, I64 *count,
  I64 *depth_out)
{
  HtkCtl *k = at->kids;
  HtkCtl *hit;

  while (k) {
    if (*count == target) {
      if (depth_out)
        *depth_out = depth;
      return k;
    }
    (*count)++;
    if (k->value && k->kids) {
      hit = HtkTreeWalk(k, depth + 1, target, count, depth_out);
      if (hit)
        return hit;
    }
    k = k->sib;
  }
  return NULL;
}

I64 HtkTreeCount(HtkCtl *tree)
{
  I64 count = 0;

  HtkTreeWalk(tree, 0, -1, &count, NULL);
  return count;
}

I64 HtkTreeIndexOf(HtkCtl *tree, HtkCtl *node)
{
  I64 count = HtkTreeCount(tree);
  I64 i, probe;
  HtkCtl *hit;

  for (i = 0; i < count; i++) {
    probe = 0;
    hit = HtkTreeWalk(tree, 0, i, &probe, NULL);
    if (hit == node)
      return i;
  }
  return -1;
}

U0 HtkTreeMeasure(HtkCtl *c)
{
  c->pw = 16;
  c->ph = 6;
}

U0 HtkTreeDraw(HtkCtl *c)
{
  I64 total = HtkTreeCount(c);
  I64 i, probe, depth, fg, bg, mark;
  I64 sel = HtkTreeIndexOf(c, c->link);
  HtkCtl *node;

  if (sel >= 0 && sel < c->top)
    c->top = sel;
  if (sel >= c->top + c->h)
    c->top = sel - c->h + 1;
  for (i = c->top; i < total && i - c->top < c->h; i++) {
    probe = 0;
    depth = 0;
    node = HtkTreeWalk(c, 0, i, &probe, &depth);
    if (!node)
      return;
    fg = HTK_C_FG;
    bg = HTK_C_BG;
    if (node == c->link) {
      bg = HTK_C_FOCUS_BG;
      if (!HtkFocused(c))
        bg = HTK_C_DIM;
    }
    HtkRect(c->x, c->y + i - c->top, c->w, 1, ' ', fg, bg);
    if (node->kids) {
      mark = HTK_R_RIGHT;
      if (node->value)
        mark = HTK_R_OPEN;
      HtkChr(c->x + depth * 2, c->y + i - c->top, mark, fg, bg);
    }
    HtkStr(c->x + depth * 2 + 2, c->y + i - c->top, node->text, fg, bg);
  }
}

U0 HtkTreeSelect(HtkCtl *c, I64 index)
{
  I64 total = HtkTreeCount(c);
  I64 probe = 0;
  HtkCtl *node;

  if (index < 0)
    index = 0;
  if (index >= total)
    index = total - 1;
  node = HtkTreeWalk(c, 0, index, &probe, NULL);
  if (!node || node == c->link)
    return;
  c->link = node;
  HtkFire(c);
}

// Mouse: select the clicked node and, like Enter, toggle its expansion.
U0 HtkTreeClick(HtkCtl *c, I64 index)
{
  I64 probe = 0;
  HtkCtl *node;

  if (index < 0 || index >= HtkTreeCount(c))
    return;
  node = HtkTreeWalk(c, 0, index, &probe, NULL);
  if (!node)
    return;
  HtkTreeSelect(c, index);
  if (node->kids) {
    node->value = !node->value;
    htk_dirty = TRUE;
  }
}

Bool HtkTreeKey(HtkCtl *c, CTermEvent *e)
{
  I64 sel = HtkTreeIndexOf(c, c->link);

  if (e->key == TERM_KEY_UP)
    HtkTreeSelect(c, sel - 1);
  else if (e->key == TERM_KEY_DOWN)
    HtkTreeSelect(c, sel + 1);
  else if (e->key == TERM_KEY_RIGHT && c->link) {
    c->link->value = TRUE;
    htk_dirty = TRUE;
  } else if (e->key == TERM_KEY_LEFT && c->link) {
    c->link->value = FALSE;
    htk_dirty = TRUE;
  } else if (e->key == TERM_KEY_ENTER && c->link) {
    c->link->value = !c->link->value;
    htk_dirty = TRUE;
  } else
    return FALSE;
  return TRUE;
}
