static const AsmTarget target_s390 = {
	.local_label_prefix = ".Lahc_asm",
	.c_clobbers = "\"memory\", \"cc\", \"r0\", \"r1\", \"r2\", "
		"\"r3\", \"r4\", \"r5\", \"r14\"",
	.llvm_constraints = "~{memory},~{cc},~{r0},~{r1},~{r2},~{r3},~{r4},"
		"~{r5},~{r14}",
};
