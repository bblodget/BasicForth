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
extern void forth_emit(void);
extern void forth_key(void);
extern void forth_accept(void);
extern void forth_find(void);
extern void forth_parse_word(void);
extern void forth_execute(void);

/* Engine init (defined in test_helper) */
extern void init_engine(int64_t here_val, int64_t latest_val);

/* Data stack and dictionary (defined in core.s) */
extern char data_stack_top;
extern char dict_space;
extern char dict_bye;
extern int64_t base;
extern int64_t source_addr;
extern int64_t source_len;
extern int64_t to_in;

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

/* --- FIND tests --- */

/*
 * FIND stack effect: ( c-addr u -- xt 1 | xt -1 | c-addr u 0 )
 *   Match, immediate: xt 1
 *   Match, normal:    xt -1
 *   Not found:        c-addr u 0
 */

static void test_find_ok(const char *test_name, const char *word,
                         void *expected_xt, int64_t expected_flag)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    setup_2((int64_t)word, (int64_t)strlen(word), &tos_in, &dsp_in);
    call_primitive(forth_find, tos_in, dsp_in, &tos_out, &dsp_out);

    /* TOS = flag, [DSP] = xt */
    if (tos_out == expected_flag && stack_depth(dsp_out) == 1
        && dsp_out[0] == (int64_t)expected_xt)
        pass(test_name);
    else
        fail(test_name, "flag=%ld xt=%p expected_flag=%ld expected_xt=%p depth=%d",
             tos_out, (void *)dsp_out[0], expected_flag,
             expected_xt, stack_depth(dsp_out));
}

static void test_find_not_found(const char *test_name, const char *word)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;
    int64_t len = (int64_t)strlen(word);

    setup_2((int64_t)word, len, &tos_in, &dsp_in);
    call_primitive(forth_find, tos_in, dsp_in, &tos_out, &dsp_out);

    /* TOS = 0, [DSP] = u, [DSP+1] = c-addr */
    if (tos_out == 0 && stack_depth(dsp_out) == 2
        && dsp_out[0] == len && dsp_out[1] == (int64_t)word)
        pass(test_name);
    else
        fail(test_name, "flag=%ld depth=%d", tos_out, stack_depth(dsp_out));
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
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    /* Start with one item on stack (sentinel), PARSE-WORD pushes c-addr and u */
    setup_1(99, &tos_in, &dsp_in);
    call_primitive(forth_parse_word, tos_in, dsp_in, &tos_out, &dsp_out);

    /* Stack: ( 99 c-addr u ) — TOS=u, [DSP]=c-addr, [DSP+8]=99 */
    if (tos_out == 5 && stack_depth(dsp_out) == 2
        && memcmp((void *)dsp_out[0], "hello", 5) == 0)
        pass("PARSE-WORD: hello");
    else
        fail("PARSE-WORD: hello", "u=%ld depth=%d", tos_out, stack_depth(dsp_out));
}

static void test_parse_word_spaces(void)
{
    setup_source("  foo  bar  ");
    int64_t tos_in = 0, tos_out;
    int64_t *dsp_in = stack_top(), *dsp_out;

    /* First word: "foo" */
    call_primitive(forth_parse_word, tos_in, dsp_in, &tos_out, &dsp_out);
    if (tos_out == 3 && memcmp((void *)dsp_out[0], "foo", 3) == 0)
        pass("PARSE-WORD: leading spaces -> foo");
    else
        fail("PARSE-WORD: leading spaces -> foo", "u=%ld", tos_out);

    /* Second word: "bar" — call again with fresh stack but same globals */
    dsp_in = stack_top();
    call_primitive(forth_parse_word, tos_in, dsp_in, &tos_out, &dsp_out);
    if (tos_out == 3 && memcmp((void *)dsp_out[0], "bar", 3) == 0)
        pass("PARSE-WORD: second word -> bar");
    else
        fail("PARSE-WORD: second word -> bar", "u=%ld", tos_out);

    /* Third call: no more tokens */
    dsp_in = stack_top();
    call_primitive(forth_parse_word, tos_in, dsp_in, &tos_out, &dsp_out);
    if (tos_out == 0 && dsp_out[0] == 0)
        pass("PARSE-WORD: end of input -> 0 0");
    else
        fail("PARSE-WORD: end of input -> 0 0", "u=%ld", tos_out);
}

static void test_parse_word_empty(void)
{
    setup_source("");
    int64_t tos_in = 0, tos_out;
    int64_t *dsp_in = stack_top(), *dsp_out;

    call_primitive(forth_parse_word, tos_in, dsp_in, &tos_out, &dsp_out);
    if (tos_out == 0 && dsp_out[0] == 0)
        pass("PARSE-WORD: empty input");
    else
        fail("PARSE-WORD: empty input", "u=%ld", tos_out);
}

/* --- EXECUTE tests --- */

static void test_execute(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    /* Push 42, then push xt of forth_dup as TOS. EXECUTE should DUP 42. */
    /* Stack before EXECUTE: ( 42 xt ) where xt = forth_dup */
    setup_2(42, (int64_t)forth_dup, &tos_in, &dsp_in);
    call_primitive(forth_execute, tos_in, dsp_in, &tos_out, &dsp_out);

    /* After EXECUTE: xt is consumed, forth_dup ran, stack is ( 42 42 ) */
    if (tos_out == 42 && stack_depth(dsp_out) == 1 && dsp_out[0] == 42)
        pass("EXECUTE: dup via xt");
    else
        fail("EXECUTE: dup via xt", "tos=%ld depth=%d [dsp]=%ld",
             tos_out, stack_depth(dsp_out),
             stack_depth(dsp_out) >= 1 ? dsp_out[0] : -1);
}

static void test_execute_add(void)
{
    int64_t tos_in, tos_out;
    int64_t *dsp_in, *dsp_out;

    /* Stack: ( 3 4 xt_add ). EXECUTE should run +, leaving ( 7 ). */
    setup_3(3, 4, (int64_t)forth_add, &tos_in, &dsp_in);
    call_primitive(forth_execute, tos_in, dsp_in, &tos_out, &dsp_out);

    if (tos_out == 7 && stack_depth(dsp_out) == 0)
        pass("EXECUTE: + via xt");
    else
        fail("EXECUTE: + via xt", "tos=%ld depth=%d", tos_out, stack_depth(dsp_out));
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

    section("Dictionary Lookup");
    init_engine((int64_t)&dict_space, (int64_t)&dict_bye);
    test_find();

    section("Parse Word");
    test_parse_word_single();
    test_parse_word_spaces();
    test_parse_word_empty();

    section("Execute");
    test_execute();
    test_execute_add();

    printf("\n=====================\n");
    printf("%d passed, %d failed, %d total\n", passed, failed, passed + failed);

    return failed ? 1 : 0;
}
