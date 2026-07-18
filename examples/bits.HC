// Bit manipulation: Bsf/Bsr/BCnt scan values; Bt/Btc/Btr/Bts/BEqu (and
// the atomic L* forms) operate on a bit field through a byte pointer.
"%d %d %d\n", Bsf(0x1000), Bsr(0x1000), Bsf(0);
"%d %d %d\n", Bsr(0), BCnt(0xFF), BCnt(0);
"%d %d\n", Bsf(I64_MIN), Bsr(I64_MIN);
"%d\n", BCnt(-1);

U8 field[16];
MemSet(field, 0, 16);
"%d %d %d\n", Bts(field, 3), Bt(field, 3), Bts(field, 3);
"%d %d\n", Btr(field, 3), Bt(field, 3);
"%d %d %d\n", Btc(field, 100), Bt(field, 100), Btc(field, 100);
BEqu(field, 42, TRUE);
"%d %d\n", Bt(field, 42), field[5];
BEqu(field, 42, FALSE);
"%d\n", Bt(field, 42);

// locked forms are the same, atomic across threads
"%d %d %d\n", LBts(field, 7), Bt(field, 7), LBtr(field, 7);
"%d %d\n", LBtc(field, 8), LBtc(field, 8);
LBEqu(field, 9, TRUE);
"%d\n", Bt(field, 9);

// find the set bits (span kept under 53 bits: exact on the JS backend)
I64 word = 0x201008040201, i, n = 0;
for (i = Bsf(word); i >= 0; i = Bsf(word)) {
  Btr(&word, i);
  n++;
}
"%d bits\n", n;
