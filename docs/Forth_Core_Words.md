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
| 2SWAP | ( x1 x2 x3 x4 -- x3 x4 x1 x2 )              | forth | (x)    | core.fs                 |
| 2OVER | ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )        | forth | (x)    | core.fs                 |
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
| */     | ( n1 n2 n3 -- n4 )                            | forth | (x)    | core.fs: >R * R> /      |
| */MOD  | ( n1 n2 n3 -- n4 n5 )                         | forth | (x)    | core.fs: >R M* R> FM/MOD |
| 1+     | ( n -- n+1 )                                  | asm   | (x)    |                         |
| 1-     | ( n -- n-1 )                                  | asm   | (x)    |                         |
| ABS    | ( n -- u )                                    | asm   | (x)    |                         |
| 2*     | ( x -- x*2 )                                  | forth | (x)    | 1 LSHIFT (core.fs)      |
| 2/     | ( x -- x/2 )                                  | asm   | (x)    | Arithmetic shift right   |
| +!     | ( n a-addr -- )                               | forth | (x)    | core.fs                  |
| CELL+  | ( a-addr -- a-addr+8 )                        | forth | (x)    | 8 + (in core.fs)        |
| CELLS  | ( n -- n*8 )                                  | forth | (x)    | 8 * (in core.fs)        |
| CHAR+  | ( c-addr -- c-addr+1 )                        | forth | (x)    | 1+ (in core.fs)         |
| CHARS  | ( n -- n )                                    | forth | (x)    | no-op (byte-addressed)  |

### Double-Width Arithmetic

| Word   | Stack effect                                  | Layer | Status | Notes                   |
|--------|-----------------------------------------------|-------|--------|-------------------------|
| M*     | ( n1 n2 -- d )                                | asm   | (x)    | Signed multiply -> double |
| UM*    | ( u1 u2 -- ud )                               | asm   | (x)    | Unsigned multiply -> double |
| FM/MOD | ( d n -- rem quot )                           | asm   | (x)    | Floored divide          |
| SM/REM | ( d n -- rem quot )                           | asm   | (x)    | Symmetric divide        |
| UM/MOD | ( ud u -- rem quot )                          | asm   | (x)    | Unsigned double divide  |
| S>D    | ( n -- d )                                    | asm   | (x)    | Sign-extend to double   |

### Logic and Comparison

| Word   | Stack effect                                  | Layer | Status | Notes                   |
|--------|-----------------------------------------------|-------|--------|-------------------------|
| AND    | ( x1 x2 -- x3 )                              | asm   | (x)    |                         |
| OR     | ( x1 x2 -- x3 )                              | asm   | (x)    |                         |
| XOR    | ( x1 x2 -- x3 )                              | asm   | (x)    |                         |
| INVERT | ( x -- ~x )                                   | asm   | (x)    |                         |
| LSHIFT | ( x u -- x<<u )                               | asm   | (x)    |                         |
| RSHIFT | ( x u -- x>>u )                               | asm   | (x)    | Logical shift           |
| 0=     | ( x -- flag )                                 | asm   | (x)    |                         |
| 0<     | ( n -- flag )                                 | asm   | (x)    |                         |
| =      | ( x1 x2 -- flag )                             | asm   | (x)    |                         |
| <      | ( n1 n2 -- flag )                             | asm   | (x)    |                         |
| >      | ( n1 n2 -- flag )                             | asm   | (x)    |                         |
| U<     | ( u1 u2 -- flag )                             | asm   | (x)    |                         |
| MIN    | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |
| MAX    | ( n1 n2 -- n3 )                               | asm   | (x)    |                         |

### Memory

| Word    | Stack effect                                  | Layer | Status | Notes                   |
|---------|-----------------------------------------------|-------|--------|-------------------------|
| @       | ( a-addr -- x )                               | asm   | (x)    | Fetch cell              |
| !       | ( x a-addr -- )                               | asm   | (x)    | Store cell              |
| C@      | ( c-addr -- char )                            | asm   | (x)    | Fetch byte              |
| C!      | ( char c-addr -- )                            | asm   | (x)    | Store byte              |
| 2@      | ( a-addr -- x1 x2 )                          | forth | (x)    | core.fs                 |
| 2!      | ( x1 x2 a-addr -- )                          | forth | (x)    | core.fs                 |
| FILL    | ( c-addr u char -- )                          | forth | (x)    | core.fs                 |
| MOVE    | ( addr1 addr2 u -- )                          | forth | (x)    | core.fs, overlap-safe   |
| ALIGN   | ( -- )                                        | forth | (x)    | core.fs                 |
| ALIGNED | ( addr -- a-addr )                            | forth | (x)    | core.fs                 |
| ALLOT   | ( n -- )                                      | asm   | (x)    | Bounds-checked both directions |
| HERE    | ( -- addr )                                   | asm   | (x)    | Push HERE register      |
| ,       | ( x -- )                                      | asm   | (x)    | Store x at HERE, advance |
| C,      | ( char -- )                                   | asm   | (x)    | Store byte at HERE      |

### I/O

| Word    | Stack effect                                  | Layer | Status | Notes                   |
|---------|-----------------------------------------------|-------|--------|-------------------------|
| EMIT    | ( char -- )                                   | both  | (x)    | asm pops stack, calls platform |
| KEY     | ( -- char )                                   | both  | (x)    | asm calls platform, pushes stack |
| TYPE    | ( c-addr u -- )                               | asm   | (x)    | Write string to stdout   |
| ACCEPT  | ( c-addr +n1 -- +n2 )                        | asm   | (x)    | Line input with editing  |
| CR      | ( -- )                                        | forth | (x)    | 10 EMIT (in core.fs)    |
| SPACE   | ( -- )                                        | forth | (x)    | 32 EMIT (in core.fs)    |
| SPACES  | ( n -- )                                      | forth | (x)    | core.fs                  |
| .       | ( n -- )                                      | asm   | (x)    | Print signed number      |
| U.      | ( u -- )                                      | forth | (x)    | core.fs: 0 <# #S #> TYPE |
| ."      | ( "ccc" -- )                                  | asm   | (x)    | Compile string + TYPE    |
| BL      | ( -- char )                                   | forth | (x)    | 32 (in core.fs)         |
| CHAR    | ( "name" -- char )                            | forth | (x)    | core.fs                  |

### Number Formatting

| Word | Stack effect                                    | Layer | Status | Notes                   |
|------|-------------------------------------------------|-------|--------|-------------------------|
| <#   | ( -- )                                          | forth | (x)    | Begin number conversion  |
| #    | ( ud1 -- ud2 )                                  | forth | (x)    | Convert one digit        |
| #S   | ( ud1 -- ud2 )                                  | forth | (x)    | Convert remaining digits |
| #>   | ( xd -- c-addr u )                              | forth | (x)    | End number conversion    |
| HOLD | ( char -- )                                     | forth | (x)    | Insert char in output    |
| SIGN | ( n -- )                                        | forth | (x)    | Insert minus if negative |
| BASE | ( -- a-addr )                                   | asm   | (x)    | Number base variable     |

### Dictionary and Compiler

| Word      | Stack effect                                  | Layer | Status | Notes                   |
|-----------|-----------------------------------------------|-------|--------|-------------------------|
| :         | ( "name" -- )                                 | asm   | (x)    | Begin compilation        |
| ;         | ( -- )                                        | asm   | (x)    | End compilation (IMMEDIATE) |
| CREATE    | ( "name" -- )                                 | asm   | (x)    | Compiles push-data-addr  |
| DOES>     | ( -- a-addr )                                 | asm   | (x)    | Attach runtime to CREATE'd word |
| VARIABLE  | ( "name" -- )                                 | forth | (x)    | CREATE 1 CELLS ALLOT (core.fs) |
| CONSTANT  | ( x "name" -- )                               | asm   | (x)    | Compiles push-value code |
| IMMEDIATE | ( -- )                                        | asm   | (x)    | Mark word as immediate   |
| '         | ( "name" -- xt )                              | asm   | (x)    | Find xt (IMMEDIATE)      |
| EXECUTE   | ( xt -- )                                     | asm   | (x)    | Call execution token     |
| LITERAL   | ( x -- )                                      | asm   | (x)    | IMMEDIATE+COMPILE_ONLY   |
| POSTPONE  | ( "name" -- )                                 | asm   | (x)    | IMMEDIATE+COMPILE_ONLY   |
| RECURSE   | ( -- )                                        | asm   | (x)    | Compile call to self (IMMEDIATE) |
| STATE     | ( -- a-addr )                                 | asm   | (x)    | Push state variable addr |
| [         | ( -- )                                        | asm   | (x)    | Switch to interpret (IMM)|
| ]         | ( -- )                                        | asm   | (x)    | Switch to compile        |
| [CHAR]    | ( "name" -- )                                 | asm   | (x)    | IMMEDIATE+COMPILE_ONLY   |
| FIND      | ( c-addr u -- xt 1 \| xt -1 \| c-addr u 0 )  | asm   | (x)    | Dictionary lookup        |
| >BODY     | ( xt -- a-addr )                              | asm   | (x)    | xt to data field         |
| DECIMAL   | ( -- )                                        | forth | (x)    | core.fs: #10 BASE !     |
| WORD      | ( char -- c-addr )                            | forth | (x)    | core.fs                  |
| >NUMBER   | ( ud c-addr u -- ud c-addr u )                | forth | (x)    | core.fs                  |
| >IN       | ( -- a-addr )                                 | asm   | (x)    | Push to_in variable addr |
| SOURCE    | ( -- c-addr u )                               | asm   | (x)    | Current input buffer     |
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
| LEAVE  | ( -- ) (R: loop-sys -- )                       | asm   | (x)    | Exit DO loop early       |
| UNLOOP | ( -- ) (R: limit index -- )                    | asm   | (x)    | Discard loop params      |
| RECURSE| ( -- )                                         | asm   | (x)    | Compile call to self     |
| EXIT   | ( -- )                                         | asm   | (x)    | IMMEDIATE+COMPILE_ONLY   |

### Comments

| Word | Stack effect                                    | Layer | Status | Notes                   |
|------|-------------------------------------------------|-------|--------|-------------------------|
| (    | ( "ccc)" -- )                                   | asm   | (x)    | IMMEDIATE, skip to )    |
| \    | ( "ccc" -- )                                    | asm   | (x)    | IMMEDIATE, skip to EOL  |

### System

| Word          | Stack effect                                  | Layer | Status | Notes                   |
|---------------|-----------------------------------------------|-------|--------|-------------------------|
| ABORT         | ( -- )                                        | asm   | (x)    | Clear stacks, reset REPL |
| ABORT"        | ( flag "ccc" -- )                             | forth | (x)    | core.fs (IMMEDIATE)      |
| QUIT          | ( -- )                                        | asm   | (x)    | Reset RSP, enter REPL    |
| ENVIRONMENT?  | ( c-addr u -- false \| i*x true )             | forth | (x)    | core.fs (always false)   |
| S"            | ( "ccc" -- c-addr u )                         | asm   | (x)    | Inline string literal   |

## Core Extension Words (6.2)

The standard also defines 49 optional extension words. We plan to implement
commonly useful ones:

| Word       | Stack effect                                  | Status | Notes                   |
|------------|-----------------------------------------------|--------|-------------------------|
| NIP        | ( x1 x2 -- x2 )                              | (x)    | asm                     |
| TUCK       | ( x1 x2 -- x2 x1 x2 )                       | (x)    | asm                     |
| <>         | ( x1 x2 -- flag )                             | (x)    | core.fs                 |
| 0<>        | ( x -- flag )                                 | (x)    | core.fs                 |
| 0>         | ( n -- flag )                                 | (x)    | core.fs                 |
| AGAIN      | ( -- )                                        | (x)    | asm (IMMEDIATE)         |
| HEX        | ( -- )                                        | (x)    | core.fs                 |
| TRUE       | ( -- true )                                   | (x)    | core.fs                 |
| FALSE      | ( -- false )                                  | (x)    | core.fs                 |
| WITHIN     | ( n lo hi -- flag )                           | (x)    | core.fs                 |
| CASE       | ( -- )                                        | (x)    | asm (IMMEDIATE)         |
| OF         | ( x1 x2 -- \| x1 )                           | (x)    | asm (IMMEDIATE)         |
| ENDOF      | ( -- )                                        | (x)    | asm (IMMEDIATE)         |
| ENDCASE    | ( x -- )                                      | (x)    | asm (IMMEDIATE)         |
| COMPILE,   | ( xt -- )                                     | (x)    | asm                     |
| ?DO        | ( limit index -- )                            | (x)    | asm (IMMEDIATE)         |
| VALUE      | ( x "name" -- )                               | (x)    | asm                     |
| TO         | ( x "name" -- )                               | (x)    | asm (IMMEDIATE)         |
| :NONAME    | ( -- xt )                                     | (x)    | asm                     |
| PARSE      | ( char -- c-addr u )                          | (x)    | asm                     |
| PARSE-NAME | ( -- c-addr u )                               | (x)    | core.fs                 |
| PICK       | ( xu...x0 u -- xu...x0 xu )                   | (x)    | asm                     |
| PAD        | ( -- c-addr )                                 | (x)    | asm                     |
| ERASE      | ( addr u -- )                                 | (x)    | core.fs                 |
| UNUSED     | ( -- u )                                      | (x)    | asm                     |
| SOURCE-ID  | ( -- 0 \| -1 )                                | (x)    | asm                     |
| .(         | ( "ccc)" -- )                                 | (x)    | core.fs (IMMEDIATE)     |
| .R         | ( n1 n2 -- )                                  | (x)    | core.fs                 |
| U.R        | ( u n -- )                                    | (x)    | core.fs                 |
| U>         | ( u1 u2 -- flag )                              | (x)    | core.fs                 |
| HOLDS      | ( c-addr u -- )                               | (x)    | core.fs                 |
| \\         | ( -- )                                        | (x)    | asm (IMMEDIATE)         |

## Programming-Tools Word Set (15)

| Word  | Stack effect      | Status | Notes                   |
|-------|-------------------|--------|-------------------------|
| .S    | ( -- )            | (x)    | asm                     |
| ?     | ( a-addr -- )     | (x)    | core.fs                 |
| DUMP  | ( addr u -- )     | (x)    | core.fs                 |
| SEE   | ( "name" -- )     | ( )    | future                  |
| WORDS | ( -- )            | (x)    | asm                     |

## String Word Set (17)

| Word      | Stack effect                   | Status | Notes                   |
|-----------|--------------------------------|--------|-------------------------|
| -TRAILING | ( c-addr u1 -- c-addr u2 )    | (x)    | core.fs                 |
| /STRING   | ( c-addr u n -- c-addr+n u-n ) | (x)    | core.fs                 |
| BLANK     | ( c-addr u -- )                | (x)    | core.fs                 |
| CMOVE     | ( c-addr1 c-addr2 u -- )       | (x)    | core.fs                 |
| CMOVE>    | ( c-addr1 c-addr2 u -- )       | (x)    | core.fs                 |
| COMPARE   | ( c-addr1 u1 c-addr2 u2 -- n ) | (x)    | core.fs                 |
| SEARCH    | ( c-addr1 u1 c-addr2 u2 -- )  | ( )    | future                  |
| SLITERAL  | ( c-addr u -- )                | ( )    | asm (IMMEDIATE)         |

## Facility Word Set (10)

| Word          | Stack effect      | Status | Notes                   |
|---------------|-------------------|--------|-------------------------|
| AT-XY         | ( u1 u2 -- )      | (x)    | asm (platform)          |
| KEY?          | ( -- flag )        | (x)    | asm (platform)          |
| PAGE          | ( -- )             | (x)    | asm (platform)          |
| MS            | ( u -- )           | (x)    | asm (platform)          |
| SCREEN-WIDTH  | ( -- u )           | (x)    | asm (platform)          |
| SCREEN-HEIGHT | ( -- u )           | (x)    | asm (platform)          |

## Double-Number Word Set (8)

| Word    | Stack effect                    | Status | Notes                   |
|---------|---------------------------------|--------|-------------------------|
| D+      | ( d1 d2 -- d3 )                | (x)    | core.fs                 |
| D-      | ( d1 d2 -- d3 )                | (x)    | core.fs                 |
| D.      | ( d -- )                        | (x)    | core.fs                 |
| D0=     | ( d -- flag )                   | (x)    | core.fs                 |
| D0<     | ( d -- flag )                   | (x)    | core.fs                 |
| D=      | ( d1 d2 -- flag )               | (x)    | core.fs                 |
| D<      | ( d1 d2 -- flag )               | (x)    | core.fs                 |
| DNEGATE | ( d -- d )                      | (x)    | core.fs                 |
| DABS    | ( d -- d )                      | (x)    | core.fs                 |

## Future Standard Word Sets

The Forth 2012 standard defines additional optional word sets that we may
implement as separate libraries:

| Word Set          | Section | Words | Notes                              |
|-------------------|---------|-------|------------------------------------|
| Block             | 7       | 12    | Block file I/O                     |
| Exception         | 9       | 5     | CATCH and THROW                    |
| File-Access       | 11      | 27    | File I/O                           |
| Floating-Point    | 12      | 51    | Floating-point math                |
| Locals            | 13      | 2     | Local variables                    |
| Memory-Allocation | 14      | 3     | ALLOCATE, FREE, RESIZE             |
| Search-Order      | 16      | 10    | Vocabulary / wordlist management   |

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
