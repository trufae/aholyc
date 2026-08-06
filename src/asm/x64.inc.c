/* Data-only x86-64 adapter for TempleOS's Intel-order assembler dialect. */
#define RENAME(from_, to_) { from_, to_, NULL, -1 }
#define MEM_RENAME(from_, to_, size_, operand_) \
	{ from_, to_, size_, operand_ }

static const AsmRename x64_renames[] = {
	RENAME ("CQTO", "cqo"), RENAME ("CLTD", "cdq"),
	RENAME ("CBTW", "cbw"), RENAME ("CWTL", "cwde"),
	RENAME ("CLTQ", "cdqe"), RENAME ("RET1", "ret"),
	RENAME ("IMUL2", "imul"), RENAME ("REPZ", "repe"),
	RENAME ("REPNZ", "repne"),
	RENAME ("USE16", ".code16"), RENAME ("USE32", ".code32"),
	RENAME ("USE64", ".code64"),
	MEM_RENAME ("MOVZBW", "movzx", "byte ptr", 2),
	MEM_RENAME ("MOVZBL", "movzx", "byte ptr", 2),
	MEM_RENAME ("MOVZBQ", "movzx", "byte ptr", 2),
	MEM_RENAME ("MOVZWL", "movzx", "word ptr", 2),
	MEM_RENAME ("MOVZWQ", "movzx", "word ptr", 2),
	MEM_RENAME ("MOVSBW", "movsx", "byte ptr", 2),
	MEM_RENAME ("MOVSBL", "movsx", "byte ptr", 2),
	MEM_RENAME ("MOVSBQ", "movsx", "byte ptr", 2),
	MEM_RENAME ("MOVSWL", "movsx", "word ptr", 2),
	MEM_RENAME ("MOVSWQ", "movsx", "word ptr", 2),
	MEM_RENAME ("MOVSLQ", "movsxd", "dword ptr", 2),
	{ NULL, NULL, NULL, -1 },
};

static const AsmWidth x64_widths[] = {
	{ 'b', "byte ptr" }, { 'w', "word ptr" },
	{ 'l', "dword ptr" }, { 'q', "qword ptr" }, { 0, NULL },
};

static const AsmSize x64_operand_sizes[] = {
	{ "I8", "byte ptr" }, { "U8", "byte ptr" },
	{ "I16", "word ptr" }, { "U16", "word ptr" },
	{ "I32", "dword ptr" }, { "U32", "dword ptr" },
	{ "I64", "qword ptr" }, { "U64", "qword ptr" },
	{ NULL, NULL },
};

static const char *const x64_sized_mnemonics[] = {
	"adc", "add", "and", "bsf", "bsr", "bt", "btc", "btr", "bts",
	"cmp", "dec", "div", "idiv", "imul", "inc", "lea", "mov", "neg",
	"not", "or", "pop", "push", "rcl", "rcr", "rol", "ror", "sal",
	"sar", "sbb", "shl", "shr", "sub", "test", "xadd", "xchg", "xor",
	NULL,
};

static const char *const x64_prefixes[] = {
	"lock", "rep", "repe", "repz", "repne", "repnz", NULL,
};

static const AsmTarget target_x64 = {
	.intel_dialect = true,
#ifdef __APPLE__
	.local_label_prefix = "Lahc_asm",
#else
	.local_label_prefix = ".Lahc_asm",
#endif
	.align_nop_fill = "0x90",
	.frame_pointer = "RBP",
	.c_operand_modifier = "V",
	.c_clobbers = "\"memory\", \"cc\", \"rax\", \"rcx\", \"rdx\", "
		"\"rsi\", \"rdi\", \"r8\", \"r9\", \"r10\", \"r11\", "
		"\"xmm0\", \"xmm1\", \"xmm2\", \"xmm3\", \"xmm4\", \"xmm5\", "
		"\"xmm6\", \"xmm7\", \"xmm8\", \"xmm9\", \"xmm10\", \"xmm11\", "
		"\"xmm12\", \"xmm13\", \"xmm14\", \"xmm15\"",
	.llvm_constraints = "~{memory},~{dirflag},~{fpsr},~{flags},~{rax},~{rcx},"
		"~{rdx},~{rsi},~{rdi},~{r8},~{r9},~{r10},~{r11},~{xmm0},~{xmm1},"
		"~{xmm2},~{xmm3},~{xmm4},~{xmm5},~{xmm6},~{xmm7},~{xmm8},~{xmm9},"
		"~{xmm10},~{xmm11},~{xmm12},~{xmm13},~{xmm14},~{xmm15}",
	.renames = x64_renames,
	.widths = x64_widths,
	.operand_sizes = x64_operand_sizes,
	.sized_mnemonics = x64_sized_mnemonics,
	.prefixes = x64_prefixes,
};

#undef MEM_RENAME
#undef RENAME
