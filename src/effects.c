/* Native exception-effect analysis and try lowering selection. */
#include "aholyc.h"

enum {
	E_LOCAL = 1, /* direct throw/rethrow in the current function */
	E_CALL = 2,  /* exception may cross a function-call boundary */
};

bool is_throw_call(Node *n) {
	return n && n->kind == ND_CALL && n->func && !strcmp (n->func->name, "throw");
}

/* Keep in step with runtime/rt.c; arbitrary externs may be aholyc modules. */
static bool extern_can_throw(Obj *fn) {
	static const char *const names[] = {
		"throw", "MAlloc", "CAlloc", "StrNew", "MStrPrint",
		"StrPrintJoin", "GetStr", NULL
	};
	if (!fn->from_prelude) {
		return true;
	}
	for (int i = 0; names[i]; i++) {
		if (!strcmp (fn->name, names[i])) {
			return true;
		}
	}
	return false;
}

static unsigned effect(Node *n);

static unsigned list_effect(Node *n) {
	unsigned e = 0;
	for (; n; n = n->next) {
		e |= effect (n);
	}
	return e;
}

static unsigned effect(Node *n) {
	if (!n) {
		return 0;
	}
	if (n->kind == ND_EXPR_STMT && is_throw_call (n->lhs)) {
		return list_effect (n->lhs->args) | E_LOCAL;
	}
	if (n->kind == ND_TRY) {
		unsigned body = effect (n->then);
		n->try_mode = !body? TRY_NONE: body & E_CALL? TRY_DYNAMIC: TRY_LOCAL;
		return body? effect (n->els) | E_LOCAL: 0;
	}
	unsigned e = effect (n->lhs) | effect (n->rhs) | effect (n->cond) |
		effect (n->then) | effect (n->els) | effect (n->init) |
		effect (n->inc) | list_effect (n->body) | list_effect (n->args);
	if (n->kind == ND_CALL && (is_throw_call (n) || !n->func || n->func->can_throw)) {
		e |= E_CALL;
	}
	return e;
}

void analyze_exceptions(Program *prog) {
	for (Obj *fn = prog->funcs; fn; fn = fn->next) {
		fn->can_throw = fn->body? false: extern_can_throw (fn);
	}
	bool changed;
	do {
		changed = false;
		for (Obj *fn = prog->funcs; fn; fn = fn->next) {
			if (fn->body && !fn->can_throw && effect (fn->body)) {
				fn->can_throw = changed = true;
			}
		}
	} while (changed);
	for (Obj *fn = prog->funcs; fn; fn = fn->next) {
		if (fn->body) {
			effect (fn->body);
		}
	}
	prog->startup->can_throw = effect (prog->startup->body) != 0;
}
