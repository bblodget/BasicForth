/*
 * config.inc -- tunable sizes, shared by both architectures.
 *
 * Included by core.s and main.s on both architectures. C-style comments
 * because this file is read by two assemblers whose line-comment characters
 * differ (`#` on x86, `//` on ARM64); a slash-star comment is accepted by both.
 *
 * PAGE_SIZE is deliberately NOT here: it belongs to each platform_linux.s,
 * which is where a port to a system with different pages would change it.
 *
 * Change a value here and both architectures pick it up. The Makefiles list
 * this file as a dependency of core.o and main.o, so editing it forces a
 * rebuild -- a size that changed without one would be far worse than no
 * sharing at all, because the guard pages and the stack they fence would
 * disagree.
 *
 * Sizes are BYTES. A cell is 8 bytes, so divide by 8 for the cell count.
 *
 * These bound different things and are not interchangeable:
 *
 *   DATA_STACK_SIZE    how much a single expression can hold, and how deep
 *                      recursion can go when each level leaves items behind.
 *   LOCALS_STACK_SIZE  recursion depth times locals per frame. A word with
 *                      eight locals uses eight cells per level; nothing else
 *                      touches this stack.
 *
 * Both are fenced by PROT_NONE guard pages, so overflowing either is a clean
 * reported error rather than corruption -- but it IS an error, and the size is
 * what decides when a legitimate program hits it.
 *
 * In .bss these cost address space, not memory: the kernel commits pages on
 * first touch, so a stack that is never deep is never resident.
 */

.equ CELL,              8       /* 64-bit cells, both architectures */

/* --- per thread, REPL and worker alike ----------------------------------- */
/*
 * ONE constant each, not one per thread kind. What a computation can hold, and
 * how deep it can recurse, must not depend on which thread happens to run it --
 * so there is deliberately no way to express a REPL/worker difference here.
 *
 * That is not tidiness. Until 2026-08-11 the two data stacks WERE separate
 * numbers in separate files (4096 in the assembler, 8192 in threads.fs) and had
 * silently drifted to different values, with nothing explaining why the thread
 * you actually type at got the smaller one. Two constants that are supposed to
 * stay equal is the arrangement that produced that; one makes it unrepresentable.
 */
.equ DATA_STACK_SIZE,   8192    /* 1024 cells. Raised from 4096 when the two
                                   were unified -- raising is the safe
                                   direction, since no working program breaks
                                   by being given more room, whereas halving
                                   the workers' could break one that works. */
.equ LOCALS_STACK_SIZE, 16384   /* 2048 cells */

/* --- workers only -------------------------------------------------------- */

.equ THREAD_RSTACK_SIZE, 65536  /* The one size with no counterpart: the REPL's
                                   return stack is the process stack (~8 MB),
                                   handed to it by the kernel, so there is
                                   nothing here to unify it with. */

/* The REPL's stacks are reserved in .bss by core.s; a worker's are carved from
 * the single allocate block in threads.fs. Different mechanisms, same numbers:
 * threads.fs repeats none of them, reading each back through the
 * (dstack-size) / (thread-rsize) / (lstack-size) primitives, so the Forth side
 * and the assembler side cannot disagree about how big a stack is or where to
 * fence it. */
