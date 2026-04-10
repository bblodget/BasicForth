# BasicForth — Control Flow

BasicForth compiles control flow as inline native branch instructions,
following the Subroutine Threaded Code (STC) approach. There are no
BRANCH or 0BRANCH runtime primitives — the compiler emits real machine
code directly.

## How It Works

All control flow words are **IMMEDIATE** and **COMPILE_ONLY**. They run
at compile time (inside `: ... ;`) and emit branch instructions into the
definition being compiled. At runtime, the CPU executes those branches
natively.

### Forward References (IF, ELSE, WHILE)

When IF compiles a conditional branch, it doesn't yet know where THEN
will be. So it:

1. Emits the branch instruction with a **placeholder offset** (0)
2. Pushes the **patch address** onto the data stack (compile-time stack)

When THEN runs later, it:

1. Pops the patch address
2. Calculates the offset from the branch to the current HERE
3. **Patches** the placeholder with the real offset

### Backward References (BEGIN, UNTIL, AGAIN)

BEGIN just pushes the current HERE — the loop start address. When UNTIL
or AGAIN runs, the target is already known, so it emits the branch with
the correct offset immediately. No patching needed.

## Branch Encoding

### x86-64

**Conditional (0branch)** — 16 bytes of inline code:
```
mov (%r15), %rax       # load flag from data stack     [49 8B 07]
add $8, %r15           # pop                           [49 83 C7 08]
test %rax, %rax        # set zero flag                 [48 85 C0]
jz rel32               # jump if false                 [0F 84 xx xx xx xx]
```

**Unconditional (branch)** — 5 bytes:
```
jmp rel32              # always jump                   [E9 xx xx xx xx]
```

Both use the same offset formula: `target - (offset_field_addr + 4)`.

### ARM64

**Conditional (0branch)** — 8 bytes (2 instructions):
```
LDR X9, [X19], #8     # pop flag from data stack      [F8408669]
CBZ X9, offset         # branch if zero                [B4000009 + offset]
```

**Unconditional (branch)** — 4 bytes:
```
B offset               # always branch                 [14000000 + offset]
```

ARM64 offsets are encoded as bitfields within the instruction word:
- **B**: 26-bit signed word offset in bits [25:0] (range: +/-128 MB)
- **CBZ**: 19-bit signed word offset in bits [23:5] (range: +/-1 MB)

Patching reads the instruction, detects B vs CBZ by checking bit 31,
calculates the word offset, and encodes it into the appropriate bitfield.

## Compile-Time Stack Tags

To detect mis-paired control structures (e.g., `BEGIN ... THEN`), each
control flow word pushes a **tag** alongside its address:

| Tag      | Value | Pushed by              | Expected by                    |
|----------|-------|------------------------|--------------------------------|
| CF_ORIG  | 1     | IF, ELSE, WHILE, DO    | THEN, ELSE, REPEAT, LOOP       |
| CF_DEST  | 2     | BEGIN, DO              | UNTIL, AGAIN, WHILE, REPEAT, LOOP |
| CF_LEAVE | 3     | DO (saved leave count) | LOOP, +LOOP                    |

The compile-time stack for `: test IF 42 THEN ;` looks like:

```
After IF:    ( patch-addr CF_ORIG )
After THEN:  ( )  — consumed and patched
```

For `: test BEGIN ... WHILE ... REPEAT ;`:

```
After BEGIN:   ( begin-addr CF_DEST )
After WHILE:   ( begin-addr CF_DEST while-patch CF_ORIG )
After REPEAT:  ( )  — both consumed
```

If a tag doesn't match, the compiler prints `"? mismatched-control-flow"`
and rolls back the definition.

## Error Detection

Three levels of protection:

1. **Compile-only enforcement**: Using IF, THEN, BEGIN, etc. outside a
   definition prints `"compile only"`.

2. **Tag mismatch**: `BEGIN ... THEN` or `IF ... UNTIL` prints
   `"? mismatched-control-flow"` and rolls back the definition.

3. **Balance check**: `;` verifies the data stack depth matches what `:`
   saved. Unresolved forward references (e.g., `IF` without `THEN`)
   print `"unresolved control flow"` and roll back.

All three recover cleanly — subsequent definitions work normally.

## Mismatch Recovery

On a tag mismatch, the compiler needs to abort cleanly even when called
from nested contexts (EVALUATE inside INCLUDED). The mechanism:

1. `forth_interpret_line` saves RSP/SP and all callee-saved registers
   at entry into `il_rsp`/`il_sp` (with nesting support — the previous
   value is saved on the stack).

2. On mismatch, `cf_check_tag` restores DSP, LATEST, HERE, and STATE,
   then "longjmps" back to `forth_interpret_line` by restoring RSP/SP
   and all callee-saved registers from the saved frame.

3. `forth_interpret_line` returns error (1) to its caller, which handles
   it through the normal error path — whether that's the REPL printing
   `"? token"`, or INCLUDED printing `"file:line: ? token"`.

## Word Reference

### IF ( flag -- )
Compile: emit conditional forward branch, push patch address.
Runtime: pop flag; if false, skip to matching THEN or ELSE.

### THEN ( -- )
Compile: patch the forward branch from IF or ELSE to land here.
Runtime: no code emitted — just a compile-time patch point.

### ELSE ( -- )
Compile: emit unconditional forward branch (skip ELSE body), patch IF's
branch to land here (start of ELSE body).
Runtime: if IF's condition was true, skip over ELSE body.

### BEGIN ( -- )
Compile: push current HERE as loop start address.
Runtime: no code emitted — just a compile-time marker.

### UNTIL ( flag -- )
Compile: emit conditional backward branch to BEGIN.
Runtime: pop flag; if false, loop back to BEGIN.

### AGAIN ( -- )
Compile: emit unconditional backward branch to BEGIN.
Runtime: always loop back to BEGIN (infinite loop).

### WHILE ( flag -- )
Compile: emit conditional forward branch (exit test), push patch address.
Runtime: pop flag; if false, exit loop (jump past REPEAT).

### REPEAT ( -- )
Compile: emit unconditional backward branch to BEGIN, patch WHILE's
forward branch to land here.
Runtime: always loop back to BEGIN.

### RECURSE ( -- )
Compile: emit a CALL/BL to the current definition's code entry point.
Runtime: call self recursively.

### DO ( limit index -- ) (R: -- limit index)
Compile: emit inline code to pop limit and index from data stack,
compare, skip loop body if equal, push to return stack.
Pushes three pairs to the compile-time stack: (skip-patch, CF_ORIG),
(saved-leave-count, CF_LEAVE), (body-addr, CF_DEST).
Runtime: set up counted loop. If limit == index, skip the body entirely.

### LOOP ( -- ) (R: limit index -- | limit index' )
Compile: emit inline code to pop loop params from return stack,
increment index by 1, compare with limit. If equal, loop is done
(params stay popped). If not, push back and branch to loop body.
Patches DO's skip-if-equal forward branch and all LEAVE forward
branches to land after LOOP. Restores the leave count for nesting.
Runtime: increment and test counted loop.

### +LOOP ( n -- ) (R: limit index -- | limit index' )
Compile: like LOOP but pops increment from data stack instead of
using 1. Uses boundary-crossing detection: the loop terminates when
the index crosses the limit boundary, computed as
`(old_index - limit) XOR (new_index - limit)` having the sign bit set.
This correctly handles non-unit increments that don't land exactly on
the limit (e.g., `10 0 DO ... 3 +LOOP` exits after 0, 3, 6, 9).

### I ( -- index )
Compile: emit inline code to read the loop index from the return stack
and push it to the data stack.
Runtime: push current loop index. On x86-64 reads from `[RSP]`. On
ARM64 reads from `[SP]` (loop params are above the prolog frame).

### J ( -- index )
Compile: emit inline code to read the outer loop's index from the
return stack (past the inner loop's params).
Runtime: push outer loop index. Reads from `[RSP+16]` (x86-64) or
`[SP+16]` (ARM64).

### LEAVE ( -- ) (R: limit index -- )
Compile: emit UNLOOP (drop loop params from return stack) followed by an
unconditional forward branch. The branch is patched by LOOP or +LOOP to
land after the loop. Multiple LEAVEs per loop are supported; all are
patched when LOOP/+LOOP compiles.
Runtime: exit the innermost DO loop immediately, continuing after LOOP/+LOOP.

### UNLOOP ( -- ) (R: limit index -- )
Compile: emit inline code to drop loop parameters from the return stack.
Runtime: remove loop params without testing. Required before returning
early from a word containing a DO loop, to clean up the return stack.

## Return Stack Layout (DO/LOOP)

DO pushes limit and index onto the return stack as a pair:

```
x86-64:                  ARM64:
[RSP+0]  = index        [SP+0]  = index    ← I reads here
[RSP+8]  = limit        [SP+8]  = limit
[RSP+16] = ...           [SP+16] = ...      ← J reads here (outer loop)
```

On ARM64, DO uses `STP` to push both values as a 16-byte aligned pair.
The colon definition's prolog frame (X29/X30) sits below the loop params
since DO pushes above it.

## Examples

```forth
\ Absolute value
: abs   dup 0< if negate then ;

\ Sign function (-1, 0, or 1)
: sign  dup 0< if drop -1 else
        dup 0= if drop 0 else drop 1 then then ;

\ Countdown using BEGIN/UNTIL
: countdown  5 begin dup . 1- dup 0= until drop ;

\ Countdown using BEGIN/WHILE/REPEAT
: countdown2  5 begin dup 0 > while dup . 1- repeat drop ;

\ Factorial using RECURSE
: fact  dup 1 > if dup 1- recurse * then ;

\ DO/LOOP basics
: stars  0 do 42 emit loop ;
5 stars    \ prints *****

\ I and J in nested loops
: table  3 0 do  3 0 do  j . i . 32 emit  loop cr loop ;

\ +LOOP with non-unit increment
: evens  10 0 do i . 2 +loop ;   \ prints 0 2 4 6 8

\ Factorial with DO/LOOP
: fact  1 swap 1+ 1 do i * loop ;
6 fact .   \ prints 720

\ Sum of 0..N-1
: sum  0 swap 0 do i + loop ;
10 sum .   \ prints 45

\ LEAVE — exit loop early
: find-first  10 0 do i 5 = if leave then i . loop ;
find-first   \ prints 0 1 2 3 4 (exits before printing 5)
```
