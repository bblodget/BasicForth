/*
 * BasicForth — Unit Test Harness
 *
 * Tests core assembly primitives by calling them directly from C.
 * Links against core.o and a per-architecture test_helper.s that
 * bridges C calling conventions to the engine registers (TOS/DSP).
 *
 * Build: gcc -o test_basicforth test_basicforth.c test_helper_<arch>.s core.o
 * Run:   ./test_basicforth
 */

#include <stdio.h>
#include <stdarg.h>
#include <stdint.h>
#include <string.h>

/* --- Assembly interface --- */

extern void call_primitive(void *fn, int64_t tos_in, int64_t *dsp_in,
                           int64_t *tos_out, int64_t **dsp_out);

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

/* Engine init (defined in test_helper) */
extern void init_engine(int64_t here_val, int64_t latest_val);

/* Data stack and dictionary (defined in core.s) */
extern char data_stack_top;
extern char dict_space;
extern int64_t base;

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
 * Stack convention:
 *   TOS = top value (in register)
 *   DSP = pointer to second item (grows downward from data_stack_top)
 *
 * setup_N() prepares the stack with N items.
 * Items are listed bottom-to-top: setup_2(a, b) → [DSP]=a, TOS=b.
 */

static int64_t *stack_top(void)
{
    return (int64_t *)&data_stack_top;
}

/* 1 item: TOS = a, DSP = empty */
static void setup_1(int64_t a, int64_t *tos, int64_t **dsp)
{
    *tos = a;
    *dsp = stack_top();
}

/* 2 items: [DSP] = a, TOS = b */
static void setup_2(int64_t a, int64_t b, int64_t *tos, int64_t **dsp)
{
    int64_t *sp = stack_top();
    *(--sp) = a;
    *dsp = sp;
    *tos = b;
}

/* 3 items: [DSP+8] = a, [DSP] = b, TOS = c */
static void setup_3(int64_t a, int64_t b, int64_t c,
                    int64_t *tos, int64_t **dsp)
{
    int64_t *sp = stack_top();
    *(--sp) = a;
    *(--sp) = b;
    *dsp = sp;
    *tos = c;
}

/* Stack depth: number of items below TOS in memory */
static int stack_depth(int64_t *dsp)
{
    return (int)(stack_top() - dsp);
}

/* --- Primitive tests --- */

static void test_dup(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_1(42, &tos_in, &dsp_in);
    call_primitive(forth_dup, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 42 && dsp_out[0] == 42 && stack_depth(dsp_out) == 1)
        pass("DUP ( 42 -- 42 42 )");
    else
        fail("DUP ( 42 -- 42 42 )",
             "tos=%ld [dsp]=%ld depth=%d",
             tos_out, dsp_out[0], stack_depth(dsp_out));
}

static void test_drop(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2(10, 20, &tos_in, &dsp_in);
    call_primitive(forth_drop, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 10 && stack_depth(dsp_out) == 0)
        pass("DROP ( 10 20 -- 10 )");
    else
        fail("DROP ( 10 20 -- 10 )",
             "tos=%ld depth=%d", tos_out, stack_depth(dsp_out));
}

static void test_swap(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2(1, 2, &tos_in, &dsp_in);
    call_primitive(forth_swap, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 1 && dsp_out[0] == 2 && stack_depth(dsp_out) == 1)
        pass("SWAP ( 1 2 -- 2 1 )");
    else
        fail("SWAP ( 1 2 -- 2 1 )",
             "tos=%ld [dsp]=%ld", tos_out, dsp_out[0]);
}

static void test_over(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2(1, 2, &tos_in, &dsp_in);
    call_primitive(forth_over, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 1 && dsp_out[0] == 2 && dsp_out[1] == 1
        && stack_depth(dsp_out) == 2)
        pass("OVER ( 1 2 -- 1 2 1 )");
    else
        fail("OVER ( 1 2 -- 1 2 1 )",
             "tos=%ld [dsp]=%ld [dsp+1]=%ld depth=%d",
             tos_out, dsp_out[0], dsp_out[1], stack_depth(dsp_out));
}

static void test_add(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2(3, 4, &tos_in, &dsp_in);
    call_primitive(forth_add, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 7 && stack_depth(dsp_out) == 0)
        pass("+ ( 3 4 -- 7 )");
    else
        fail("+ ( 3 4 -- 7 )", "tos=%ld", tos_out);
}

static void test_add_negative(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2(-10, 3, &tos_in, &dsp_in);
    call_primitive(forth_add, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == -7 && stack_depth(dsp_out) == 0)
        pass("+ ( -10 3 -- -7 )");
    else
        fail("+ ( -10 3 -- -7 )", "tos=%ld", tos_out);
}

static void test_sub(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2(10, 3, &tos_in, &dsp_in);
    call_primitive(forth_sub, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 7 && stack_depth(dsp_out) == 0)
        pass("- ( 10 3 -- 7 )");
    else
        fail("- ( 10 3 -- 7 )", "tos=%ld", tos_out);
}

static void test_negate(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_1(5, &tos_in, &dsp_in);
    call_primitive(forth_negate, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == -5)
        pass("NEGATE ( 5 -- -5 )");
    else
        fail("NEGATE ( 5 -- -5 )", "tos=%ld", tos_out);
}

static void test_negate_negative(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_1(-42, &tos_in, &dsp_in);
    call_primitive(forth_negate, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 42)
        pass("NEGATE ( -42 -- 42 )");
    else
        fail("NEGATE ( -42 -- 42 )", "tos=%ld", tos_out);
}

/* --- NUMBER tests --- */

/*
 * test_number_ok: parse string, expect success with given value.
 * test_number_fail: parse string, expect failure.
 *
 * NUMBER stack effect: ( c-addr u -- n true | c-addr u false )
 */

static void test_number_ok(const char *name, const char *input,
                           int64_t expected)
{
    char buf[80];
    int64_t len = (int64_t)strlen(input);
    memcpy(buf, input, len);

    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    /* Stack: ( c-addr u ) → [DSP] = c-addr, TOS = u */
    setup_2((int64_t)buf, len, &tos_in, &dsp_in);
    call_primitive(forth_number, tos_in, dsp_in, &tos_out, &dsp_out);

    /* Success: TOS = true (-1), [DSP] = n */
    if (tos_out == -1 && dsp_out[0] == expected)
        pass(name);
    else
        fail(name, "tos=%ld [dsp]=%ld (expected tos=-1 [dsp]=%ld)",
             tos_out, dsp_out[0], expected);
}

static void test_number_fail_case(const char *name, const char *input)
{
    char buf[80];
    int64_t len = (int64_t)strlen(input);
    memcpy(buf, input, len);

    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2((int64_t)buf, len, &tos_in, &dsp_in);
    call_primitive(forth_number, tos_in, dsp_in, &tos_out, &dsp_out);

    /* Failure: TOS = false (0) */
    if (tos_out == 0)
        pass(name);
    else
        fail(name, "tos=%ld (expected 0)", tos_out);
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
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_1((int64_t)&cell, &tos_in, &dsp_in);
    call_primitive(forth_fetch, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 0xDEADBEEF12345678LL && stack_depth(dsp_out) == 0)
        pass("@ ( addr -- x )");
    else
        fail("@ ( addr -- x )", "tos=0x%lx", tos_out);
}

static void test_store(void)
{
    int64_t cell = 0;
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    /* Need 3 items: sentinel below x and addr (! consumes 2, pops new TOS) */
    setup_3(99, 0x1234567890ABCDEFLL, (int64_t)&cell, &tos_in, &dsp_in);
    call_primitive(forth_store, tos_in, dsp_in, &tos_out, &dsp_out);

    if (cell == 0x1234567890ABCDEFLL && tos_out == 99 && stack_depth(dsp_out) == 0)
        pass("! ( x addr -- )");
    else
        fail("! ( x addr -- )", "cell=0x%lx tos=%ld depth=%d",
             cell, tos_out, stack_depth(dsp_out));
}

static void test_cfetch(void)
{
    unsigned char byte = 0xA5;
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_1((int64_t)&byte, &tos_in, &dsp_in);
    call_primitive(forth_cfetch, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 0xA5 && stack_depth(dsp_out) == 0)
        pass("C@ ( addr -- byte )");
    else
        fail("C@ ( addr -- byte )", "tos=0x%lx", tos_out);
}

static void test_cstore(void)
{
    unsigned char byte = 0;
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_3(99, 0x42, (int64_t)&byte, &tos_in, &dsp_in);
    call_primitive(forth_cstore, tos_in, dsp_in, &tos_out, &dsp_out);

    if (byte == 0x42 && tos_out == 99 && stack_depth(dsp_out) == 0)
        pass("C! ( byte addr -- )");
    else
        fail("C! ( byte addr -- )", "byte=0x%x tos=%ld depth=%d",
             byte, tos_out, stack_depth(dsp_out));
}

/* --- Main --- */

int main(void)
{
    printf("BasicForth Unit Tests\n");
    printf("=====================\n");

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

    section("Number Parsing");
    base = 10;
    test_number();

    section("Memory Access");
    test_fetch();
    test_store();
    test_cfetch();
    test_cstore();

    printf("\n=====================\n");
    printf("%d passed, %d failed, %d total\n", passed, failed, passed + failed);

    return failed ? 1 : 0;
}
