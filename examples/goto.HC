// HolyC has no 'continue': Terry says use goto. Both directions work.
I64 i = 0;
loop:
i++;
if (i > 8)
  goto done;
if (i % 2)
  goto loop;      // backward jump, skip odd numbers
"%d ", i;
goto loop;
done:
"\n";

// #define and #ifdef work at token level
#define ANSWER 42
#ifdef ANSWER
"answer is %d\n", ANSWER;
#else
"no answer\n";
#endif
