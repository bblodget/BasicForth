/*
 * BasicForth — Unit Test Harness
 *
 * Tests core assembly primitives by calling them directly from C.
 * Links against core.o and a per-architecture test_helper.s that
 * bridges C calling conventions to the engine register (DSP).
 *
 * Pure memory data stack model: everything lives on the memory stack
 * addressed by DSP. No separate TOS register.
 *
 * Build: gcc -o test_basicforth test_basicforth.c test_helper_<arch>.s core.o
 * Run:   ./test_basicforth
 */

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>
#include <sys/mman.h>

/* --- Assembly interface --- */

extern void call_primitive(void *fn, int64_t *dsp_in, int64_t **dsp_out);

/* Core primitives */
extern void forth_dup(void);
extern void forth_drop(void);
extern void forth_swap(void);
extern void forth_over(void);
extern void forth_add(void);
extern void forth_sub(void);
extern void forth_negate(void);
extern void forth_number(void);
extern void forth_fetch(void);
extern void forth_store(void);
extern void forth_cfetch(void);
extern void forth_cstore(void);
extern void forth_emit(void);
extern void forth_key(void);
extern void forth_accept(void);
extern void forth_find(void);
extern void forth_parse_word(void);
extern void forth_execute(void);
extern void forth_mul(void);
extern void forth_divmod(void);
extern void forth_one_plus(void);
extern void forth_one_minus(void);
extern void forth_abs(void);
extern void forth_min(void);
extern void forth_max(void);
extern void forth_equal(void);
extern void forth_less(void);
extern void forth_greater(void);
extern void forth_zero_equal(void);
extern void forth_zero_less(void);
extern void forth_and(void);
extern void forth_or(void);
extern void forth_xor(void);
extern void forth_invert(void);

/* Engine init (defined in test_helper) */
extern void init_engine(int64_t here_val, int64_t latest_val);

/* Data stack and dictionary (defined in core.s) */
extern char data_stack_top;
extern char dict_space;
extern char dict_tick;
extern int64_t base;
extern int64_t source_addr;
extern int64_t source_len;
extern int64_t to_in;
extern int64_t sp0;
extern int64_t error_flag;

/* --- Test framework --- */

static int passed = 0;
static int failed = 0;

static void pass(const char *name)
{
    printf("  \033[32mPASS\033[0m  %s\n", name);
    passed++;
}

static void fail(const char *name, const char *fmt, ...)
{
    printf("  \033[31mFAIL\033[0m  %s — ", name);
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    failed++;
}

static void section(const char *name)
{
    printf("\n--- %s ---\n", name);
}

/* --- Stack helpers --- */

/*
 * Pure memory data stack model:
 *   DSP points to the top item on stack (grows downward from data_stack_top).
 *   Stack depth = (stack_top() - dsp).
 *   An empty stack has DSP = stack_top() (depth 0).
 *
 * Items are listed bottom-to-top: setup_2(a, b) places a below b.
 *   [DSP+8] = a (bottom), [DSP] = b (top)
 */

static int64_t *stack_top(void)
{
    return (int64_t *)&data_stack_top;
}

static int stack_depth(int64_t *dsp)
{
    return (int)(stack_top() - dsp);
}

/* Empty stack (depth 0): DSP = stack_top */
static int64_t *setup_0(void)
{
    return stack_top();
}

/* 1 item: [DSP] = a */
static int64_t *setup_1(int64_t a)
{
    int64_t *sp = stack_top();
    *(--sp) = a;
    return sp;
}

/* 2 items: [DSP+8] = a (bottom), [DSP] = b (top) */
static int64_t *setup_2(int64_t a, int64_t b)
{
    int64_t *sp = stack_top();
    *(--sp) = a;
    *(--sp) = b;
    return sp;
}

/* 3 items: a (bottom), b (middle), c (top) */
static int64_t *setup_3(int64_t a, int64_t b, int64_t c)
{
    int64_t *sp = stack_top();
    *(--sp) = a;
    *(--sp) = b;
    *(--sp) = c;
    return sp;
}

/* --- Primitive tests --- */

static void test_dup(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(42);
    call_primitive(forth_dup, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 42 && dsp_out[1] == 42)
        pass("DUP ( 42 -- 42 42 )");
    else
        fail("DUP ( 42 -- 42 42 )",
             "[0]=%ld [1]=%ld depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out));
}

static void test_drop(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 20);
    call_primitive(forth_drop, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 10)
        pass("DROP ( 10 20 -- 10 )");
    else
        fail("DROP ( 10 20 -- 10 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_swap(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 20);
    call_primitive(forth_swap, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 10 && dsp_out[1] == 20)
        pass("SWAP ( 10 20 -- 20 10 )");
    else
        fail("SWAP ( 10 20 -- 20 10 )",
             "[0]=%ld [1]=%ld depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out));
}

static void test_over(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 20);
    call_primitive(forth_over, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 3 && dsp_out[0] == 10
        && dsp_out[1] == 20 && dsp_out[2] == 10)
        pass("OVER ( 10 20 -- 10 20 10 )");
    else
        fail("OVER ( 10 20 -- 10 20 10 )",
             "[0]=%ld [1]=%ld [2]=%ld depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out) >= 3 ? dsp_out[2] : -1,
             stack_depth(dsp_out));
}

static void test_add(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 20);
    call_primitive(forth_add, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 30)
        pass("+ ( 10 20 -- 30 )");
    else
        fail("+ ( 10 20 -- 30 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_add_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, -3);
    call_primitive(forth_add, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 7)
        pass("+ ( 10 -3 -- 7 )");
    else
        fail("+ ( 10 -3 -- 7 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_sub(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 3);
    call_primitive(forth_sub, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 7)
        pass("- ( 10 3 -- 7 )");
    else
        fail("- ( 10 3 -- 7 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_negate(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(42);
    call_primitive(forth_negate, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -42)
        pass("NEGATE ( 42 -- -42 )");
    else
        fail("NEGATE ( 42 -- -42 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_negate_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(-7);
    call_primitive(forth_negate, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 7)
        pass("NEGATE ( -7 -- 7 )");
    else
        fail("NEGATE ( -7 -- 7 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_mul(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(6, 7);
    call_primitive(forth_mul, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 42)
        pass("* ( 6 7 -- 42 )");
    else
        fail("* ( 6 7 -- 42 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_mul_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(-3, 4);
    call_primitive(forth_mul, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -12)
        pass("* ( -3 4 -- -12 )");
    else
        fail("* ( -3 4 -- -12 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_divmod(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(17, 5);
    call_primitive(forth_divmod, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 2 && dsp_out[1] == 2 && dsp_out[0] == 3)
        pass("/MOD ( 17 5 -- 2 3 )");
    else
        fail("/MOD ( 17 5 -- 2 3 )",
             "rem=%ld quot=%ld depth=%d",
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             dsp_out[0], stack_depth(dsp_out));
}

static void test_divmod_exact(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(20, 4);
    call_primitive(forth_divmod, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 2 && dsp_out[1] == 0 && dsp_out[0] == 5)
        pass("/MOD ( 20 4 -- 0 5 )");
    else
        fail("/MOD ( 20 4 -- 0 5 )",
             "rem=%ld quot=%ld depth=%d",
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             dsp_out[0], stack_depth(dsp_out));
}

static void test_divmod_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(-7, 2);
    call_primitive(forth_divmod, dsp_in, &dsp_out);

    /* C/asm truncated division: -7/2 = -3 rem -1 */
    if (stack_depth(dsp_out) == 2 && dsp_out[1] == -1 && dsp_out[0] == -3)
        pass("/MOD ( -7 2 -- -1 -3 )");
    else
        fail("/MOD ( -7 2 -- -1 -3 )",
             "rem=%ld quot=%ld depth=%d",
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             dsp_out[0], stack_depth(dsp_out));
}

static void test_divmod_overflow(void)
{
    int64_t *dsp_in, *dsp_out;
    int64_t int64_min = (int64_t)0x8000000000000000LL;

    dsp_in = setup_2(int64_min, -1);
    call_primitive(forth_divmod, dsp_in, &dsp_out);

    /* INT64_MIN / -1 overflows; we return 0 INT64_MIN (matches ARM64 SDIV) */
    if (stack_depth(dsp_out) == 2 && dsp_out[1] == 0 && dsp_out[0] == int64_min)
        pass("/MOD ( INT64_MIN -1 -- 0 INT64_MIN )");
    else
        fail("/MOD ( INT64_MIN -1 -- 0 INT64_MIN )",
             "rem=%ld quot=%ld depth=%d",
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             dsp_out[0], stack_depth(dsp_out));
}

static void test_divmod_by_zero(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 0);
    call_primitive(forth_divmod, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 2 && dsp_out[1] == 0 && dsp_out[0] == 0)
        pass("/MOD ( 10 0 -- 0 0 )");
    else
        fail("/MOD ( 10 0 -- 0 0 )",
             "rem=%ld quot=%ld depth=%d",
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             dsp_out[0], stack_depth(dsp_out));
}

static void test_one_plus(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(41);
    call_primitive(forth_one_plus, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 42)
        pass("1+ ( 41 -- 42 )");
    else
        fail("1+ ( 41 -- 42 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_one_minus(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(42);
    call_primitive(forth_one_minus, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 41)
        pass("1- ( 42 -- 41 )");
    else
        fail("1- ( 42 -- 41 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_abs(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(-42);
    call_primitive(forth_abs, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 42)
        pass("ABS ( -42 -- 42 )");
    else
        fail("ABS ( -42 -- 42 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_abs_positive(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(7);
    call_primitive(forth_abs, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 7)
        pass("ABS ( 7 -- 7 )");
    else
        fail("ABS ( 7 -- 7 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_min(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 3);
    call_primitive(forth_min, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 3)
        pass("MIN ( 10 3 -- 3 )");
    else
        fail("MIN ( 10 3 -- 3 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_min_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(-5, 3);
    call_primitive(forth_min, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -5)
        pass("MIN ( -5 3 -- -5 )");
    else
        fail("MIN ( -5 3 -- -5 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_max(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 3);
    call_primitive(forth_max, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 10)
        pass("MAX ( 10 3 -- 10 )");
    else
        fail("MAX ( 10 3 -- 10 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_max_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(-5, 3);
    call_primitive(forth_max, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 3)
        pass("MAX ( -5 3 -- 3 )");
    else
        fail("MAX ( -5 3 -- 3 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

/* --- Comparison tests --- */

static void test_equal_true(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(42, 42);
    call_primitive(forth_equal, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("= ( 42 42 -- -1 )");
    else
        fail("= ( 42 42 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_equal_false(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(42, 7);
    call_primitive(forth_equal, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("= ( 42 7 -- 0 )");
    else
        fail("= ( 42 7 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_less_true(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(3, 10);
    call_primitive(forth_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("< ( 3 10 -- -1 )");
    else
        fail("< ( 3 10 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_less_false(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 3);
    call_primitive(forth_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("< ( 10 3 -- 0 )");
    else
        fail("< ( 10 3 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_less_equal(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(5, 5);
    call_primitive(forth_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("< ( 5 5 -- 0 )");
    else
        fail("< ( 5 5 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_less_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(-5, 3);
    call_primitive(forth_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("< ( -5 3 -- -1 )");
    else
        fail("< ( -5 3 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_greater_true(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(10, 3);
    call_primitive(forth_greater, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("> ( 10 3 -- -1 )");
    else
        fail("> ( 10 3 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_greater_false(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(3, 10);
    call_primitive(forth_greater, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("> ( 3 10 -- 0 )");
    else
        fail("> ( 3 10 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_zero_equal_true(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(0);
    call_primitive(forth_zero_equal, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("0= ( 0 -- -1 )");
    else
        fail("0= ( 0 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_zero_equal_false(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(42);
    call_primitive(forth_zero_equal, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("0= ( 42 -- 0 )");
    else
        fail("0= ( 42 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_zero_less_true(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(-7);
    call_primitive(forth_zero_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("0< ( -7 -- -1 )");
    else
        fail("0< ( -7 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_zero_less_false(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(7);
    call_primitive(forth_zero_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("0< ( 7 -- 0 )");
    else
        fail("0< ( 7 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_zero_less_zero(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(0);
    call_primitive(forth_zero_less, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("0< ( 0 -- 0 )");
    else
        fail("0< ( 0 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

/* --- Logic tests --- */

static void test_and(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(0xFF00, 0x0FF0);
    call_primitive(forth_and, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0x0F00)
        pass("AND ( $FF00 $0FF0 -- $0F00 )");
    else
        fail("AND ( $FF00 $0FF0 -- $0F00 )",
             "[0]=$%lx depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_or(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(0xFF00, 0x0FF0);
    call_primitive(forth_or, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0xFFF0)
        pass("OR ( $FF00 $0FF0 -- $FFF0 )");
    else
        fail("OR ( $FF00 $0FF0 -- $FFF0 )",
             "[0]=$%lx depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_xor(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2(0xFF00, 0x0FF0);
    call_primitive(forth_xor, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0xF0F0)
        pass("XOR ( $FF00 $0FF0 -- $F0F0 )");
    else
        fail("XOR ( $FF00 $0FF0 -- $F0F0 )",
             "[0]=$%lx depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_invert(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(0);
    call_primitive(forth_invert, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -1)
        pass("INVERT ( 0 -- -1 )");
    else
        fail("INVERT ( 0 -- -1 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_invert_true(void)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1(-1);
    call_primitive(forth_invert, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0)
        pass("INVERT ( -1 -- 0 )");
    else
        fail("INVERT ( -1 -- 0 )",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

/* --- NUMBER tests --- */

/*
 * test_number_ok: parse string, expect success with given value.
 * test_number_fail: parse string, expect failure.
 *
 * NUMBER stack effect: ( c-addr u -- n true | c-addr u false )
 *   Success: depth 2, [1] = n (bottom), [0] = -1 (true, top)
 *   Failure: depth 3, [2] = c-addr, [1] = u, [0] = 0 (false)
 */

static void test_number_ok(const char *name, const char *input,
                           int64_t expected)
{
    char buf[80];
    int64_t len = (int64_t)strlen(input);
    memcpy(buf, input, len);

    int64_t *dsp_in, *dsp_out;

    /* Stack: ( c-addr u ) → [DSP+8] = c-addr, [DSP] = u */
    dsp_in = setup_2((int64_t)buf, len);
    call_primitive(forth_number, dsp_in, &dsp_out);

    /* Success: [0] = true (-1), [1] = n */
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == -1
        && dsp_out[1] == expected)
        pass(name);
    else
        fail(name, "[0]=%ld [1]=%ld depth=%d (expected [0]=-1 [1]=%ld)",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out), expected);
}

static void test_number_fail_case(const char *name, const char *input)
{
    char buf[80];
    int64_t len = (int64_t)strlen(input);
    memcpy(buf, input, len);

    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2((int64_t)buf, len);
    call_primitive(forth_number, dsp_in, &dsp_out);

    /* Failure: [0] = false (0) */
    if (dsp_out[0] == 0)
        pass(name);
    else
        fail(name, "[0]=%ld (expected 0)", dsp_out[0]);
}

static void test_number(void)
{
    /* Decimal */
    test_number_ok("NUMBER: 0",          "0",       0);
    test_number_ok("NUMBER: 42",         "42",      42);
    test_number_ok("NUMBER: 1000",       "1000",    1000);
    test_number_ok("NUMBER: -7",         "-7",      -7);
    test_number_ok("NUMBER: -1",         "-1",      -1);
    test_number_ok("NUMBER: #99",        "#99",     99);

    /* Hex */
    test_number_ok("NUMBER: $FF",        "$FF",     255);
    test_number_ok("NUMBER: $ff",        "$ff",     255);
    test_number_ok("NUMBER: $1A3",       "$1A3",    419);
    test_number_ok("NUMBER: $0",         "$0",      0);

    /* Binary */
    test_number_ok("NUMBER: %1010",      "%1010",   10);
    test_number_ok("NUMBER: %11111111",  "%11111111", 255);
    test_number_ok("NUMBER: %0",         "%0",      0);

    /* Negative with prefix */
    test_number_ok("NUMBER: -$10",       "-$10",    -16);
    test_number_ok("NUMBER: $-10",       "$-10",    -16);
    test_number_ok("NUMBER: -%1010",     "-%1010",  -10);
    test_number_ok("NUMBER: %-1010",     "%-1010",  -10);

    /* Failure cases */
    test_number_fail_case("NUMBER: empty",       "");
    test_number_fail_case("NUMBER: hello",       "hello");
    test_number_fail_case("NUMBER: $GG",         "$GG");
    test_number_fail_case("NUMBER: %2",          "%2");
    test_number_fail_case("NUMBER: -",           "-");
    test_number_fail_case("NUMBER: $",           "$");
    test_number_fail_case("NUMBER: $-",          "$-");
    test_number_fail_case("NUMBER: 12abc",       "12abc");
}

/* --- Memory tests --- */

static void test_fetch(void)
{
    int64_t cell = 0xDEADBEEF12345678LL;
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1((int64_t)&cell);
    call_primitive(forth_fetch, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0xDEADBEEF12345678LL)
        pass("@ ( addr -- x )");
    else
        fail("@ ( addr -- x )",
             "[0]=0x%lx depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_store(void)
{
    int64_t cell = 0;
    int64_t *dsp_in, *dsp_out;

    /* ! ( x addr -- ) : consumes both, depth 0 after */
    dsp_in = setup_2(0x1234567890ABCDEFLL, (int64_t)&cell);
    call_primitive(forth_store, dsp_in, &dsp_out);

    if (cell == 0x1234567890ABCDEFLL && stack_depth(dsp_out) == 0)
        pass("! ( x addr -- )");
    else
        fail("! ( x addr -- )",
             "cell=0x%lx depth=%d", cell, stack_depth(dsp_out));
}

static void test_cfetch(void)
{
    unsigned char byte = 0xA5;
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_1((int64_t)&byte);
    call_primitive(forth_cfetch, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 0xA5)
        pass("C@ ( addr -- byte )");
    else
        fail("C@ ( addr -- byte )",
             "[0]=0x%lx depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_cstore(void)
{
    unsigned char byte = 0;
    int64_t *dsp_in, *dsp_out;

    /* C! ( byte addr -- ) : consumes both, depth 0 after */
    dsp_in = setup_2(0x42, (int64_t)&byte);
    call_primitive(forth_cstore, dsp_in, &dsp_out);

    if (byte == 0x42 && stack_depth(dsp_out) == 0)
        pass("C! ( byte addr -- )");
    else
        fail("C! ( byte addr -- )",
             "byte=0x%x depth=%d", byte, stack_depth(dsp_out));
}

/* --- FIND tests --- */

/*
 * FIND stack effect: ( c-addr u -- xt 1 | xt -1 | c-addr u 0 )
 *   Match, immediate: depth 2, [1]=xt, [0]=1
 *   Match, normal:    depth 2, [1]=xt, [0]=-1
 *   Not found:        depth 3, [2]=c-addr, [1]=u, [0]=0
 */

static void test_find_ok(const char *test_name, const char *word,
                         void *expected_xt, int64_t expected_flag)
{
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_2((int64_t)word, (int64_t)strlen(word));
    call_primitive(forth_find, dsp_in, &dsp_out);

    /* [0] = flag, [1] = xt */
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == expected_flag
        && dsp_out[1] == (int64_t)expected_xt)
        pass(test_name);
    else
        fail(test_name, "flag=%ld xt=%p expected_flag=%ld expected_xt=%p depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? (void *)dsp_out[1] : NULL,
             expected_flag, expected_xt, stack_depth(dsp_out));
}

static void test_find_not_found(const char *test_name, const char *word)
{
    int64_t *dsp_in, *dsp_out;
    int64_t len = (int64_t)strlen(word);

    dsp_in = setup_2((int64_t)word, len);
    call_primitive(forth_find, dsp_in, &dsp_out);

    /* [0] = 0, [1] = u, [2] = c-addr */
    if (stack_depth(dsp_out) == 3 && dsp_out[0] == 0
        && dsp_out[1] == len && dsp_out[2] == (int64_t)word)
        pass(test_name);
    else
        fail(test_name, "flag=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_find(void)
{
    /* Basic lookups (all normal, flag = -1) */
    test_find_ok("FIND: dup",     "dup",     forth_dup,     -1);
    test_find_ok("FIND: drop",    "drop",    forth_drop,    -1);
    test_find_ok("FIND: swap",    "swap",    forth_swap,    -1);
    test_find_ok("FIND: over",    "over",    forth_over,    -1);
    test_find_ok("FIND: negate",  "negate",  forth_negate,  -1);
    test_find_ok("FIND: accept",  "accept",  forth_accept,  -1);
    test_find_ok("FIND: find",    "find",    forth_find,    -1);

    /* Single-char and symbol names */
    test_find_ok("FIND: +",       "+",       forth_add,     -1);
    test_find_ok("FIND: -",       "-",       forth_sub,     -1);
    test_find_ok("FIND: @",       "@",       forth_fetch,   -1);
    test_find_ok("FIND: !",       "!",       forth_store,   -1);
    test_find_ok("FIND: c@",      "c@",      forth_cfetch,  -1);
    test_find_ok("FIND: c!",      "c!",      forth_cstore,  -1);

    /* Case insensitive */
    test_find_ok("FIND: DUP",     "DUP",     forth_dup,     -1);
    test_find_ok("FIND: Swap",    "Swap",    forth_swap,    -1);
    test_find_ok("FIND: NEGATE",  "NEGATE",  forth_negate,  -1);
    test_find_ok("FIND: C@",      "C@",      forth_cfetch,  -1);

    /* Not found — original c-addr u preserved */
    test_find_not_found("FIND: xyzzy",    "xyzzy");
    test_find_not_found("FIND: du",       "du");
    test_find_not_found("FIND: drops",    "drops");
    test_find_not_found("FIND: empty",    "");
}

/* --- PARSE-WORD tests --- */

static void setup_source(const char *input)
{
    source_addr = (int64_t)input;
    source_len = (int64_t)strlen(input);
    to_in = 0;
}

static void test_parse_word_single(void)
{
    setup_source("hello");
    int64_t *dsp_in, *dsp_out;

    /* Empty stack — PARSE-WORD pushes ( c-addr u ) */
    dsp_in = setup_0();
    call_primitive(forth_parse_word, dsp_in, &dsp_out);

    /* Stack: ( c-addr u ) — [0]=u (top), [1]=c-addr (bottom) */
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 5
        && memcmp((void *)dsp_out[1], "hello", 5) == 0)
        pass("PARSE-WORD: hello");
    else
        fail("PARSE-WORD: hello",
             "u=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_parse_word_spaces(void)
{
    setup_source("  foo  bar  ");
    int64_t *dsp_in, *dsp_out;

    /* First word: "foo" */
    dsp_in = setup_0();
    call_primitive(forth_parse_word, dsp_in, &dsp_out);
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 3
        && memcmp((void *)dsp_out[1], "foo", 3) == 0)
        pass("PARSE-WORD: leading spaces -> foo");
    else
        fail("PARSE-WORD: leading spaces -> foo",
             "u=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));

    /* Second word: "bar" — call again with fresh stack but same globals */
    dsp_in = setup_0();
    call_primitive(forth_parse_word, dsp_in, &dsp_out);
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 3
        && memcmp((void *)dsp_out[1], "bar", 3) == 0)
        pass("PARSE-WORD: second word -> bar");
    else
        fail("PARSE-WORD: second word -> bar",
             "u=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));

    /* Third call: no more tokens */
    dsp_in = setup_0();
    call_primitive(forth_parse_word, dsp_in, &dsp_out);
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 0 && dsp_out[1] == 0)
        pass("PARSE-WORD: end of input -> 0 0");
    else
        fail("PARSE-WORD: end of input -> 0 0",
             "u=%ld c-addr=%ld depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out));
}

static void test_parse_word_empty(void)
{
    setup_source("");
    int64_t *dsp_in, *dsp_out;

    dsp_in = setup_0();
    call_primitive(forth_parse_word, dsp_in, &dsp_out);
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 0 && dsp_out[1] == 0)
        pass("PARSE-WORD: empty input");
    else
        fail("PARSE-WORD: empty input",
             "u=%ld c-addr=%ld depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out));
}

/* --- EXECUTE tests --- */

static void test_execute(void)
{
    int64_t *dsp_in, *dsp_out;

    /* Stack: ( 42 xt_dup ). EXECUTE consumes xt, runs DUP on 42. */
    dsp_in = setup_2(42, (int64_t)forth_dup);
    call_primitive(forth_execute, dsp_in, &dsp_out);

    /* After EXECUTE: DUP ran on 42 → ( 42 42 ) */
    if (stack_depth(dsp_out) == 2 && dsp_out[0] == 42 && dsp_out[1] == 42)
        pass("EXECUTE: dup via xt");
    else
        fail("EXECUTE: dup via xt",
             "[0]=%ld [1]=%ld depth=%d",
             dsp_out[0],
             stack_depth(dsp_out) >= 2 ? dsp_out[1] : -1,
             stack_depth(dsp_out));
}

static void test_execute_add(void)
{
    int64_t *dsp_in, *dsp_out;

    /* Stack: ( 10 20 xt_add ). EXECUTE consumes xt, runs + on 10 20. */
    dsp_in = setup_3(10, 20, (int64_t)forth_add);
    call_primitive(forth_execute, dsp_in, &dsp_out);

    /* After EXECUTE: + ran → ( 30 ) */
    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 30)
        pass("EXECUTE: + via xt");
    else
        fail("EXECUTE: + via xt",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

/* --- Compiler tests --- */

extern void forth_lit(void);
extern void compile_call(void);
extern void compile_ret(void);
extern void compile_literal(void);
extern int64_t state;
extern void forth_colon(void);
extern void forth_semicolon(void);

/*
 * Test forth_lit: compile a tiny code sequence in dict_space that
 * calls forth_lit with inline value 42, then returns.
 * Execute it via call_primitive to verify the literal lands on stack.
 *
 * For x86-64 the compiled code is:
 *   CALL forth_lit   (5 bytes)
 *   .quad 42         (8 bytes)
 *   RET              (1 byte)
 *
 * For ARM64 the compiled code is:
 *   STP X29, X30, [SP, #-16]!  (4 bytes, prolog)
 *   BL forth_lit                (4 bytes)
 *   .quad 42                    (8 bytes)
 *   LDP X29, X30, [SP], #16    (4 bytes, epilog)
 *   RET                         (4 bytes)
 */
static void test_lit(void)
{
    int64_t *dsp_in, *dsp_out;

    /* Build a tiny function in dict_space that pushes literal 42 */
    init_engine((int64_t)&dict_space, (int64_t)&dict_tick);

    uint8_t *code = (uint8_t *)&dict_space;

#if defined(__x86_64__)
    /* CALL forth_lit (E8 + rel32) */
    code[0] = 0xE8;
    int32_t offset = (int32_t)((uint8_t *)forth_lit - (code + 5));
    *(int32_t *)(code + 1) = offset;
    /* inline value */
    *(int64_t *)(code + 5) = 42;
    /* RET */
    code[13] = 0xC3;
#elif defined(__aarch64__)
    /* STP X29, X30, [SP, #-16]! = 0xA9BF7BFD */
    *(uint32_t *)(code + 0) = 0xA9BF7BFD;
    /* BL forth_lit */
    int32_t bl_offset = (int32_t)((uint8_t *)forth_lit - (code + 4)) >> 2;
    *(uint32_t *)(code + 4) = 0x94000000 | (bl_offset & 0x03FFFFFF);
    /* inline value */
    *(int64_t *)(code + 8) = 42;
    /* LDP X29, X30, [SP], #16 = 0xA8C17BFD */
    *(uint32_t *)(code + 16) = 0xA8C17BFD;
    /* RET = 0xD65F03C0 */
    *(uint32_t *)(code + 20) = 0xD65F03C0;
#endif

    dsp_in = setup_0();
    call_primitive((void *)code, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == 42)
        pass("LIT: pushes inline 42");
    else
        fail("LIT: pushes inline 42",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

static void test_lit_negative(void)
{
    int64_t *dsp_in, *dsp_out;

    init_engine((int64_t)&dict_space, (int64_t)&dict_tick);

    uint8_t *code = (uint8_t *)&dict_space;

#if defined(__x86_64__)
    code[0] = 0xE8;
    int32_t offset = (int32_t)((uint8_t *)forth_lit - (code + 5));
    *(int32_t *)(code + 1) = offset;
    *(int64_t *)(code + 5) = -7;
    code[13] = 0xC3;
#elif defined(__aarch64__)
    *(uint32_t *)(code + 0) = 0xA9BF7BFD;
    int32_t bl_offset = (int32_t)((uint8_t *)forth_lit - (code + 4)) >> 2;
    *(uint32_t *)(code + 4) = 0x94000000 | (bl_offset & 0x03FFFFFF);
    *(int64_t *)(code + 8) = -7;
    *(uint32_t *)(code + 16) = 0xA8C17BFD;
    *(uint32_t *)(code + 20) = 0xD65F03C0;
#endif

    dsp_in = setup_0();
    call_primitive((void *)code, dsp_in, &dsp_out);

    if (stack_depth(dsp_out) == 1 && dsp_out[0] == -7)
        pass("LIT: pushes inline -7");
    else
        fail("LIT: pushes inline -7",
             "[0]=%ld depth=%d", dsp_out[0], stack_depth(dsp_out));
}

/* --- Stack guard tests --- */

/* Helper: call primitive with given stack setup and return the error_flag */
static int64_t call_check_error(void *fn, int64_t *dsp_in)
{
    int64_t *dsp_out;
    error_flag = 0;
    call_primitive(fn, dsp_in, &dsp_out);
    return error_flag;
}

/* + on empty stack should trigger underflow */
static void test_underflow_add(void)
{
    int64_t err = call_check_error(forth_add, setup_0());
    if (err == 1)
        pass("guard: + on empty stack triggers underflow");
    else
        fail("guard: + on empty stack triggers underflow",
             "error_flag=%ld (expected 1)", err);
}

/* SWAP on 1 item should trigger underflow */
static void test_underflow_swap(void)
{
    int64_t err = call_check_error(forth_swap, setup_1(42));
    if (err == 1)
        pass("guard: SWAP on 1 item triggers underflow");
    else
        fail("guard: SWAP on 1 item triggers underflow",
             "error_flag=%ld (expected 1)", err);
}

/* ! on 1 item should trigger underflow (needs 2) */
static void test_underflow_store(void)
{
    int64_t dummy = 0;
    int64_t err = call_check_error(forth_store, setup_1((int64_t)&dummy));
    if (err == 1)
        pass("guard: ! on 1 item triggers underflow");
    else
        fail("guard: ! on 1 item triggers underflow",
             "error_flag=%ld (expected 1)", err);
}

/* DUP in a loop should eventually trigger overflow */
static void test_overflow_dup(void)
{
    int64_t *dsp_out;
    int64_t *dsp = setup_1(1);

    error_flag = 0;
    /* DUP 600 times — stack is 512 cells, should overflow */
    for (int i = 0; i < 600 && error_flag == 0; i++) {
        call_primitive(forth_dup, dsp, &dsp_out);
        dsp = dsp_out;
    }
    if (error_flag == 2)
        pass("guard: DUP loop triggers overflow");
    else
        fail("guard: DUP loop triggers overflow",
             "error_flag=%ld (expected 2)", error_flag);
}

/* + with valid 2 items should NOT trigger error */
static void test_no_underflow_add(void)
{
    int64_t *dsp_in, *dsp_out;
    dsp_in = setup_2(10, 20);
    error_flag = 0;
    call_primitive(forth_add, dsp_in, &dsp_out);
    if (error_flag == 0 && stack_depth(dsp_out) == 1 && dsp_out[0] == 30)
        pass("guard: + with 2 items succeeds (no false alarm)");
    else
        fail("guard: + with 2 items succeeds (no false alarm)",
             "error_flag=%ld [0]=%ld depth=%d",
             error_flag, dsp_out[0], stack_depth(dsp_out));
}

/* --- Main --- */

int main(void)
{
    printf("BasicForth Unit Tests\n");
    printf("=====================\n");

    /* Initialize sp0 so stack guards work correctly */
    sp0 = (int64_t)&data_stack_top;

    section("Stack Primitives");
    test_dup();
    test_drop();
    test_swap();
    test_over();

    section("Arithmetic");
    test_add();
    test_add_negative();
    test_sub();
    test_negate();
    test_negate_negative();
    test_mul();
    test_mul_negative();
    test_divmod();
    test_divmod_exact();
    test_divmod_negative();
    test_divmod_overflow();
    test_divmod_by_zero();
    test_one_plus();
    test_one_minus();
    test_abs();
    test_abs_positive();
    test_min();
    test_min_negative();
    test_max();
    test_max_negative();

    section("Comparisons");
    test_equal_true();
    test_equal_false();
    test_less_true();
    test_less_false();
    test_less_equal();
    test_less_negative();
    test_greater_true();
    test_greater_false();
    test_zero_equal_true();
    test_zero_equal_false();
    test_zero_less_true();
    test_zero_less_false();
    test_zero_less_zero();

    section("Logic");
    test_and();
    test_or();
    test_xor();
    test_invert();
    test_invert_true();

    section("Number Parsing");
    base = 10;
    test_number();

    section("Memory Access");
    test_fetch();
    test_store();
    test_cfetch();
    test_cstore();

    section("Dictionary Lookup");
    init_engine((int64_t)&dict_space, (int64_t)&dict_tick);
    test_find();

    section("Parse Word");
    test_parse_word_single();
    test_parse_word_spaces();
    test_parse_word_empty();

    section("Execute");
    test_execute();
    test_execute_add();

    section("Compiler");
    /* Make dict_space executable for compiler tests */
    {
        uintptr_t page = (uintptr_t)&dict_space & ~0xFFF;
        mprotect((void *)page, 65536 + 4096, PROT_READ | PROT_WRITE | PROT_EXEC);
    }
    test_lit();
    test_lit_negative();

    /* Stack underflow/overflow is caught by guard pages (SIGSEGV handler)
     * in the real binary. Guard pages don't exist in the test binary, so
     * we only test that valid operations don't produce false alarms. */
    section("Stack Guards");
    test_no_underflow_add();

    printf("\n=====================\n");
    printf("%d passed, %d failed, %d total\n", passed, failed, passed + failed);

    return failed ? 1 : 0;
}
