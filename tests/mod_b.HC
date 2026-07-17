// module B: consumes module A through extern declarations
extern I64 counter;
extern I64 Twice(I64 x);

"twice(%d)=%d\n", counter, Twice(counter);
