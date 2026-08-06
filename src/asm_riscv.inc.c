static const AsmTarget target_riscv = {
	.local_label_prefix = ".Lahc_asm",
	.c_clobbers = "\"memory\", \"ra\", \"t0\", \"t1\", \"t2\", \"a0\", "
		"\"a1\", \"a2\", \"a3\", \"a4\", \"a5\", \"a6\", \"a7\", "
		"\"t3\", \"t4\", \"t5\", \"t6\"",
	.llvm_constraints = "~{memory},~{x1},~{x5},~{x6},~{x7},~{x10},~{x11},"
		"~{x12},~{x13},~{x14},~{x15},~{x16},~{x17},~{x28},~{x29},~{x30},~{x31}",
};
