# BasicForth — Forth Core Words

The Forth words layer is the top layer of BasicForth's three-layer
architecture. Everything here is pure Forth — portable across all
architectures, built entirely from the ASM primitives in core.s.

```
┌─────────────────────────────────────────────┐
│  core.fs          (pure Forth words)   ◄──  │  THIS LAYER
├─────────────────────────────────────────────┤
│  core.s           (asm primitives)          │  Per-arch, platform-independent
├─────────────────────────────────────────────┤
│  platform_linux.s (Linux syscalls)          │  Per-arch, platform-specific
└─────────────────────────────────────────────┘
```

## Design Philosophy

- **Forth 2012 Standard.** We implement the Core word set (section 6.1) from
  the [Forth 2012 Standard](https://forth-standard.org/standard/core). This
  means existing standard Forth code should run on BasicForth.
- **Write in Forth, not assembly.** If a word can be defined in terms of
  existing primitives, it belongs here. Only move it down to core.s if
  performance demands it.
- **Portable.** core.fs is shared across ARM64 and x86-64. It lives in
  `src/forth/` and is loaded identically on both architectures.
- **Layered.** Words build on each other — derived stack operations first,
  then arithmetic, then control flow, then formatting.
- **Extensible.** Additional standard word sets (see Future Extensions)
  and BasicForth-specific words can be added as optional libraries.

## Standard Core Words (6.1)

The Forth 2012 standard defines 133 required core words. Some are
implemented as ASM primitives in core.s (see
[Core_Primitives.md](Core_Primitives.md)); the rest are defined in Forth
in core.fs.

The **Layer** column indicates where each word is implemented:
- **asm** — in core.s (assembly primitive)
- **forth** — in core.fs (Forth definition)
- **both** — thin Forth wrapper around an asm primitive

Status: ( ) = not yet implemented, (x) = implemented

### Stack Operations

| Word  | Stack effect                                   | Layer | Status | Notes                   |
|-------|------------------------------------------------|-------|--------|-------------------------|
| DUP   | ( x -- x x )                                  | asm   | (x)    |                         |
| DROP  | ( x -- )                                      | asm   | (x)    |                         |
| SWAP  | ( x1 x2 -- x2 x1 )                           | asm   | (x)    |                         |
| OVER  | ( x1 x2 -- x1 x2 x1 )                        | asm   | (x)    |                         |
| ROT   | ( x1 x2 x3 -- x2 x3 x1 )                     | asm   | (x)    |                         |
| ?DUP  | ( x -- 0 \| x x )                             | asm   | (x)    |                         |
| 2DUP  | ( x1 x2 -- x1 x2 x1 x2 )                     | asm   | (x)    |                         |
| 2DROP | ( x1 x2 -- )                                  | asm   | (x)    |                         |
| 2SWAP | ( x1 x2 x3 x4 -- x3 x4 x1 x2 )              | forth | ( )    |                         |
| 2OVER | ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )        | forth | ( )    |                         |
| >R    | ( x -- ) (R: -- x )                            | asm   | (x)    | compile-only            |
| R>    | ( -- x ) (R: x -- )                            | asm   | (x)    | compile-only            |
| R@    | ( -- x ) (R: x -- x )                          | asm   | (x)    | compile-only            |
| DEPTH | ( -- +n )                                      | asm   | (x)    |                         |

### Arithmetic

| Word   | Stack effect                                  | Layer | Status | Notes                   |
|--------|-----------------------------------------------|-------|--------|-------------------------|
| +      | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |
| -      | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |
| NEGATE | ( n -- -n )                                   | asm   | (x)    |                         |
| *      | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |
| /      | ( n1 n2 -- n3 )                               | forth | (x)    | /MOD NIP (in core.fs)   |
| MOD    | ( n1 n2 -- rem )                              | forth | (x)    | /MOD DROP (in core.fs)  |
| /MOD   | ( n1 n2 -- rem quot )                         | asm   | (x)    | div-by-zero safe        |
| */     | ( n1 n2 n3 -- n4 )                            | forth | ( )    | >R M* R> FM/MOD NIP     |
| */MOD  | ( n1 n2 n3 -- n4 n5 )                         | forth | ( )    | >R M* R> FM/MOD         |
| 1+     | ( n -- n+1 )                                  | asm   | (x)    |                         |
| 1-     | ( n -- n-1 )                                  | asm   | (x)    |                         |
| ABS    | ( n -- u )                                    | asm   | (x)    |                         |
| 2*     | ( x -- x*2 )                                  | forth | ( )    | 1 LSHIFT                |
| 2/     | ( x -- x/2 )                                  | forth | ( )    | 1 RSHIFT                |
| +!     | ( n a-addr -- )                               | forth | ( )    | DUP @ ROT + SWAP !      |
| CELL+  | ( a-addr -- a-addr+8 )                        | forth | (x)    | 8 + (in core.fs)        |
| CELLS  | ( n -- n*8 )                                  | forth | (x)    | 8 * (in core.fs)        |
| CHAR+  | ( c-addr -- c-addr+1 )                        | forth | ( )    | 1 +                     |
| CHARS  | ( n -- n )                                    | forth | ( )    | no-op on byte-addressed |

### Double-Width Arithmetic

| Word   | Stack effect                                  | Layer | Status | Notes                   |
|--------|-----------------------------------------------|-------|--------|-------------------------|
| M*     | ( n1 n2 -- d )                                | asm   | ( )    | Signed multiply -> double |
| UM*    | ( u1 u2 -- ud )                               | asm   | ( )    | Unsigned multiply -> double |
| FM/MOD | ( d n -- rem quot )                           | asm   | ( )    | Floored divide          |
| SM/REM | ( d n -- rem quot )                           | asm   | ( )    | Symmetric divide        |
| UM/MOD | ( ud u -- rem quot )                          | asm   | ( )    | Unsigned double divide  |
| S>D    | ( n -- d )                                    | forth | ( )    | DUP 0< IF -1 ELSE 0 THEN |

### Logic and Comparison

| Word   | Stack effect                                  | Layer | Status | Notes                   |
|--------|-----------------------------------------------|-------|--------|-------------------------|
| AND    | ( x1 x2 -- x3 )                              | asm   | (x)    |                         |
| OR     | ( x1 x2 -- x3 )                              | asm   | (x)    |                         |
| XOR    | ( x1 x2 -- x3 )                              | asm   | (x)    |                         |
| INVERT | ( x -- ~x )                                   | asm   | (x)    |                         |
| LSHIFT | ( x u -- x<<u )                               | asm   | ( )    |                         |
| RSHIFT | ( x u -- x>>u )                               | asm   | ( )    |                         |
| 0=     | ( x -- flag )                                 | asm   | (x)    |                         |
| 0<     | ( n -- flag )                                 | asm   | (x)    |                         |
| =      | ( x1 x2 -- flag )                             | asm   | (x)    |                         |
| <      | ( n1 n2 -- flag )                             | asm   | (x)    |                         |
| >      | ( n1 n2 -- flag )                             | asm   | (x)    |                         |
| U<     | ( u1 u2 -- flag )                             | asm   | ( )    |                         |
| MIN    | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |
| MAX    | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |

### Memory

| Word    | Stack effect                                  | Layer | Status | Notes                   |
|---------|-----------------------------------------------|-------|--------|-------------------------|
| @       | ( a-addr -- x )                               | asm   | (x)    | Fetch cell              |
| !       | ( x a-addr -- )                               | asm   | (x)    | Store cell              |
| C@      | ( c-addr -- char )                            | asm   | (x)    | Fetch byte              |
| C!      | ( char c-addr -- )                            | asm   | (x)    | Store byte              |
| 2@      | ( a-addr -- x1 x2 )                          | forth | ( )    |                         |
| 2!      | ( x1 x2 a-addr -- )                          | forth | ( )    |                         |
| FILL    | ( c-addr u char -- )                          | forth | ( )    |                         |
| MOVE    | ( addr1 addr2 u -- )                          | forth | ( )    |                         |
| ALIGN   | ( -- )                                        | forth | ( )    | Align HERE              |
| ALIGNED | ( addr -- a-addr )                            | forth | ( )    |                         |
| ALLOT   | ( n -- )                                      | asm   | (x)    | Bounds-checked both directions |
| HERE    | ( -- addr )                                   | asm   | (x)    | Push HERE register      |
| ,       | ( x -- )                                      | asm   | (x)    | Store x at HERE, advance |
| C,      | ( char -- )                                   | asm   | (x)    | Store byte at HERE      |

### I/O

| Word    | Stack effect                                  | Layer | Status | Notes                   |
|---------|-----------------------------------------------|-------|--------|-------------------------|
| EMIT    | ( char -- )                                   | both  | (x)    | asm pops stack, calls platform |
| KEY     | ( -- char )                                   | both  | (x)    | asm calls platform, pushes stack |
| TYPE    | ( c-addr u -- )                               | forth | ( )    | Loop: C@ EMIT           |
| ACCEPT  | ( c-addr +n1 -- +n2 )                        | asm   | (x)    | Line input with editing  |
| CR      | ( -- )                                        | forth | (x)    | 10 EMIT (in core.fs)    |
| SPACE   | ( -- )                                        | forth | (x)    | 32 EMIT (in core.fs)    |
| SPACES  | ( n -- )                                      | forth | ( )    | Loop: SPACE              |
| .       | ( n -- )                                      | asm   | (x)    | Print signed number      |
| U.      | ( u -- )                                      | forth | ( )    | Print unsigned number    |
| ."      | ( "ccc" -- )                                  | forth | ( )    | Compile string + TYPE    |
| BL      | ( -- char )                                   | forth | (x)    | 32 (in core.fs)         |
| CHAR    | ( "name" -- char )                            | forth | ( )    | First char of next word  |

### Number Formatting

| Word | Stack effect                                    | Layer | Status | Notes                   |
|------|-------------------------------------------------|-------|--------|-------------------------|
| <#   | ( -- )                                          | forth | ( )    | Begin number conversion  |
| #    | ( ud1 -- ud2 )                                  | forth | ( )    | Convert one digit        |
| #S   | ( ud1 -- ud2 )                                  | forth | ( )    | Convert remaining digits |
| #>   | ( xd -- c-addr u )                              | forth | ( )    | End number conversion    |
| HOLD | ( char -- )                                     | forth | ( )    | Insert char in output    |
| SIGN | ( n -- )                                        | forth | ( )    | Insert minus if negative |
| BASE | ( -- a-addr )                                   | forth | ( )    | Number base variable     |

### Dictionary and Compiler

| Word      | Stack effect                                  | Layer | Status | Notes                   |
|-----------|-----------------------------------------------|-------|--------|-------------------------|
| :         | ( "name" -- )                                 | asm   | (x)    | Begin compilation        |
| ;         | ( -- )                                        | asm   | (x)    | End compilation (IMMEDIATE) |
| CREATE    | ( "name" -- )                                 | asm   | (x)    | Compiles push-data-addr  |
| DOES>     | ( -- a-addr )                                 | asm   | ( )    | Define runtime behavior  |
| VARIABLE  | ( "name" -- )                                 | forth | (x)    | CREATE 1 CELLS ALLOT (core.fs) |
| CONSTANT  | ( x "name" -- )                               | asm   | (x)    | Compiles push-value code |
| IMMEDIATE | ( -- )                                        | asm   | (x)    | Mark word as immediate   |
| '         | ( "name" -- xt )                              | asm   | (x)    | Find xt (IMMEDIATE)      |
| EXECUTE   | ( xt -- )                                     | asm   | (x)    | Call execution token     |
| LITERAL   | ( x -- )                                      | forth | ( )    | Compile inline literal   |
| POSTPONE  | ( "name" -- )                                 | forth | ( )    | Compile compilation      |
| RECURSE   | ( -- )                                        | asm   | (x)    | Compile call to self (IMMEDIATE) |
| STATE     | ( -- a-addr )                                 | forth | ( )    | Compile/interpret flag   |
| [         | ( -- )                                        | forth | ( )    | Switch to interpret      |
| ]         | ( -- )                                        | forth | ( )    | Switch to compile        |
| [CHAR]    | ( "name" -- )                                 | forth | ( )    | Compile char literal     |
| FIND      | ( c-addr u -- xt 1 \| xt -1 \| c-addr u 0 )  | asm   | (x)    | Dictionary lookup        |
| >BODY     | ( xt -- a-addr )                              | forth | ( )    | xt to data field         |
| DECIMAL   | ( -- )                                        | forth | ( )    | Set BASE to 10           |
| WORD      | ( char -- c-addr )                            | forth | ( )    | Parse delimited word     |
| >NUMBER   | ( ud c-addr u -- ud c-addr u )                | forth | ( )    | Convert string to number |
| >IN       | ( -- a-addr )                                 | forth | ( )    | Input parse position     |
| SOURCE    | ( -- c-addr u )                               | forth | ( )    | Current input buffer     |
| EVALUATE  | ( c-addr u -- )                               | asm   | (x)    | Interpret string         |

### Control Flow

| Word   | Stack effect                                   | Layer | Status | Notes                   |
|--------|------------------------------------------------|-------|--------|-------------------------|
| IF     | ( flag -- )                                    | asm   | (x)    | Inline conditional branch |
| ELSE   | ( -- )                                         | asm   | (x)    | Inline branch, patch IF |
| THEN   | ( -- )                                         | asm   | (x)    | Patch forward reference  |
| BEGIN  | ( -- )                                         | asm   | (x)    | Mark loop start          |
| UNTIL  | ( flag -- )                                    | asm   | (x)    | Inline conditional back  |
| WHILE  | ( flag -- )                                    | asm   | (x)    | Inline conditional fwd   |
| REPEAT | ( -- )                                         | asm   | (x)    | Inline branch, patch     |
| DO     | ( limit index -- ) (R: -- limit index )        | asm   | (x)    | Inline loop setup        |
| LOOP   | ( -- ) (R: limit index -- )                    | asm   | (x)    | Increment and test       |
| +LOOP  | ( n -- ) (R: limit index -- )                  | asm   | (x)    | Boundary-crossing test   |
| I      | ( -- n ) (R: limit index -- limit index )       | asm   | (x)    | Current loop index       |
| J      | ( -- n )                                       | asm   | (x)    | Outer loop index         |
| LEAVE  | ( -- ) (R: loop-sys -- )                       | forth | ( )    | Exit loop (deferred)     |
| UNLOOP | ( -- ) (R: limit index -- )                    | asm   | (x)    | Discard loop params      |
| RECURSE| ( -- )                                         | asm   | (x)    | Compile call to self     |
| EXIT   | ( -- )                                         | asm   | ( )    | Return from word (RET)   |

### Comments

| Word | Stack effect                                    | Layer | Status | Notes                   |
|------|-------------------------------------------------|-------|--------|-------------------------|
| (    | ( "ccc)" -- )                                   | asm   | (x)    | IMMEDIATE, skip to )    |
| \    | ( "ccc" -- )                                    | asm   | (x)    | IMMEDIATE, skip to EOL  |

### System

| Word          | Stack effect                                  | Layer | Status | Notes                   |
|---------------|-----------------------------------------------|-------|--------|-------------------------|
| ABORT         | ( -- )                                        | forth | ( )    | Clear stacks, QUIT      |
| ABORT"        | ( flag "ccc" -- )                             | forth | ( )    | Conditional abort + msg |
| QUIT          | ( -- )                                        | forth | ( )    | Main interpreter loop   |
| ENVIRONMENT?  | ( c-addr u -- false \| i*x true )             | forth | ( )    | Query environment       |
| S"            | ( "ccc" -- c-addr u )                         | forth | ( )    | String literal          |

## Core Extension Words (6.2)

The standard also defines 49 optional extension words. We plan to implement
commonly useful ones:

| Word       | Stack effect                                  | Notes                        |
|------------|-----------------------------------------------|------------------------------|
| NIP        | ( x1 x2 -- x2 )                              | asm (x)                      |
| TUCK       | ( x1 x2 -- x2 x1 x2 )                       | asm (x)                      |
| <>         | ( x1 x2 -- flag )                            | forth (x) = INVERT (core.fs) |
| 0<>        | ( x -- flag )                                 | forth (x) 0= INVERT (core.fs) |
| 0>         | ( n -- flag )                                 | 0 >                         |
| AGAIN      | ( -- )                                        | Unconditional loop back      |
| HEX        | ( -- )                                        | Set BASE to 16               |
| TRUE       | ( -- true )                                   | -1                           |
| FALSE      | ( -- false )                                  | 0                            |
| WITHIN     | ( n lo hi -- flag )                           | OVER - >R - R> U<            |
| CASE       | ( -- )                                        | Begin CASE statement         |
| OF         | ( x1 x2 -- \| x1 )                           | Test case value              |
| ENDOF      | ( -- )                                        | End of case branch           |
| ENDCASE    | ( x -- )                                      | End CASE statement           |
| ?DO        | ( limit index -- )                            | Skip-if-equal DO             |
| VALUE      | ( x "name" -- )                               | Named value                  |
| TO         | ( x "name" -- )                               | Assign to VALUE              |
| PARSE      | ( char -- c-addr u )                          | Parse with delimiter         |
| PARSE-NAME | ( -- c-addr u )                               | Parse whitespace-delimited   |
| PICK       | ( xu...x0 u -- xu...x0 xu )                  | Copy nth item                |
| PAD        | ( -- c-addr )                                 | Scratch buffer               |
| ERASE      | ( addr u -- )                                 | Fill with zeros              |
| REFILL     | ( -- flag )                                   | Refill input buffer          |
| SOURCE-ID  | ( -- 0 \| -1 )                               | Input source identifier      |
| .(         | ( "ccc)" -- )                                 | Print immediately            |
| .R         | ( n1 n2 -- )                                  | Right-justified print        |
| U.R        | ( u n -- )                                    | Right-justified unsigned     |
| U>         | ( u1 u2 -- flag )                             | Unsigned greater-than        |
| \          | ( -- )                                        | Line comment                 |

## Future Standard Word Sets

The Forth 2012 standard defines additional optional word sets that we may
implement as separate libraries:

| Word Set          | Section | Words | Notes                              |
|-------------------|---------|-------|------------------------------------|
| Block             | 7       | 12    | Block file I/O                     |
| Double-Number     | 8       | 20    | Double-cell arithmetic             |
| Exception         | 9       | 5     | CATCH and THROW                    |
| Facility          | 10      | 10    | KEY?, EKEY, AT-XY, PAGE            |
| File-Access       | 11      | 27    | File I/O                           |
| Floating-Point    | 12      | 51    | Floating-point math                |
| Locals            | 13      | 2     | Local variables                    |
| Memory-Allocation | 14      | 3     | ALLOCATE, FREE, RESIZE             |
| Programming-Tools | 15      | 13    | SEE, WORDS, .S                     |
| Search-Order      | 16      | 10    | Vocabulary / wordlist management   |
| String            | 17      | 8     | String operations                  |

## BasicForth-Specific Words

Words not in the standard, specific to BasicForth's goals:

| Word     | Stack effect      | Layer | Status | Notes                                  |
|----------|-------------------|-------|--------|----------------------------------------|
| BYE      | ( -- )            | asm   | (x)    | Print "Goodbye!", restore terminal, exit |
| .S       | ( -- )            | asm   | (x)    | Print stack non-destructively          |
| INCLUDED | ( c-addr u -- )   | asm   | (x)    | Load and interpret a Forth source file |
| TRUE     | ( -- -1 )         | forth | (x)    | -1 (in core.fs)                        |
| FALSE    | ( -- 0 )          | forth | (x)    | 0 (in core.fs)                         |

*This section will grow as we add game, graphics, and robotics words.*

## Implementation Notes

*This section will be filled in as words are implemented. Each entry
will document the actual Forth definition and any design decisions.*
