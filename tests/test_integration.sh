#!/bin/bash
# BasicForth — Integration Tests
# Copyright (C) 2026 Brandon Blodget
# SPDX-License-Identifier: GPL-2.0-only
#
# Usage: ./test_integration.sh <path-to-basicforth>

if [ $# -eq 0 ]; then
    echo "Usage: $0 <path-to-basicforth> [args...]"
    exit 1
fi
FORTH="$*"

# Resolve the repo root from this script's own location (it lives in tests/),
# so file-path tests work no matter what the caller's working directory is —
# i.e. the documented "./test_integration.sh <path-to-basicforth>" invocation
# from any directory, not only from the build dir the Makefile cd's into.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FORTH_LIB="$REPO_ROOT/src/forth"   # holds core.fs, found via BASICFORTH_PATH

# Colors
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
NC="\033[0m"

# Counters
passed=0
failed=0
slowest_name=""
slowest_ms=0

# Threshold in ms — tests slower than this show timing inline
SLOW_THRESHOLD_MS=100

run_forth() {
    printf '%s\n' "$1" | timeout 2 $FORTH 2>&1
}

# elapsed_ms: compute milliseconds between two %s.%N timestamps
elapsed_ms() {
    local start="$1" end="$2"
    awk "BEGIN { printf \"%d\", ($end - $start) * 1000 }"
}

# update_slowest: track the slowest test (call directly, not in subshell)
update_slowest() {
    local ms="$1" name="$2"
    if [ "$ms" -gt "$slowest_ms" ]; then
        slowest_ms="$ms"
        slowest_name="$name"
    fi
}

# assert_output: check that output contains a fixed substring
assert_output() {
    local name="$1"
    local input="$2"
    local expected="$3"

    local t0 t1 ms
    t0=$(date +%s.%N)
    local output
    output=$(run_forth "$input")
    t1=$(date +%s.%N)
    ms=$(elapsed_ms "$t0" "$t1")
    update_slowest "$ms" "$name"

    if [[ "$output" == *"$expected"* ]]; then
        if [ "$ms" -ge "$SLOW_THRESHOLD_MS" ]; then
            printf "  ${GREEN}PASS${NC}  %s ${YELLOW}(%d ms)${NC}\n" "$name" "$ms"
        else
            printf "  ${GREEN}PASS${NC}  %s\n" "$name"
        fi
        ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s\n" "$name"
        printf "    Input:    %s\n" "$input"
        printf "    Expected: %s\n" "$expected"
        printf "    Got:      %s\n" "$(echo "$output" | head -5)"
        ((failed++))
    fi
}

# assert_error: check that output contains a fixed substring (case-insensitive)
assert_error() {
    local name="$1"
    local input="$2"
    local expected="$3"

    local t0 t1 ms
    t0=$(date +%s.%N)
    local output
    output=$(run_forth "$input")
    t1=$(date +%s.%N)
    ms=$(elapsed_ms "$t0" "$t1")
    update_slowest "$ms" "$name"

    local lower_output lower_expected
    lower_output=$(echo "$output" | tr '[:upper:]' '[:lower:]')
    lower_expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')

    if [[ "$lower_output" == *"$lower_expected"* ]]; then
        if [ "$ms" -ge "$SLOW_THRESHOLD_MS" ]; then
            printf "  ${GREEN}PASS${NC}  %s ${YELLOW}(%d ms)${NC}\n" "$name" "$ms"
        else
            printf "  ${GREEN}PASS${NC}  %s\n" "$name"
        fi
        ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s\n" "$name"
        printf "    Input:    %s\n" "$input"
        printf "    Expected: %s\n" "$expected"
        printf "    Got:      %s\n" "$(echo "$output" | head -5)"
        ((failed++))
    fi
}

section() {
    printf "\n${YELLOW}--- %s ---${NC}\n" "$1"
}

echo "BasicForth Integration Tests"
echo "============================="
echo "Binary: $FORTH"

# =========================================================================
section "Basic Arithmetic"
# =========================================================================

# Output format: "N  ok" where N is the printed number
assert_output "addition"           "3 4 + ."             "7  ok"
assert_output "subtraction"        "10 3 - ."            "7  ok"
assert_output "multiplication"     "6 7 * ."             "42  ok"
assert_output "compound expr"      "2 3 + 4 * ."         "20  ok"
assert_output "multiple ops"       "1 2 3 4 + + + ."     "10  ok"
assert_output "/mod quotient"      "17 5 /mod . ."       "3 2  ok"
assert_output "/mod exact"         "20 4 /mod . ."       "5 0  ok"
assert_output "negate positive"    "42 negate ."         "-42  ok"
assert_output "negate negative"    "-7 negate ."         "7  ok"
assert_output "abs positive"       "42 abs ."            "42  ok"
assert_output "abs negative"       "-42 abs ."           "42  ok"
assert_output "min"                "3 7 min ."           "3  ok"
assert_output "max"                "3 7 max ."           "7  ok"
assert_output "1+"                 "41 1+ ."             "42  ok"
assert_output "1-"                 "43 1- ."             "42  ok"

# =========================================================================
section "Stack Operations"
# =========================================================================

assert_output "dup"                "5 dup + ."           "10  ok"
assert_output "drop"               "1 2 3 drop . ."      "2 1  ok"
assert_output "swap"               "1 2 swap . ."        "1 2  ok"
assert_output "over"               "1 2 over . . ."      "1 2 1  ok"
assert_output "rot"                "1 2 3 rot . . ."     "1 3 2  ok"
assert_output "nip"                "1 2 3 nip . ."       "3 1  ok"
assert_output "tuck"               "1 2 tuck . . ."      "2 1 2  ok"
assert_output "2dup"               "1 2 2dup . . . ."    "2 1 2 1  ok"
assert_output "2drop"              "1 2 3 4 2drop . ."   "2 1  ok"
assert_output "depth empty"        "depth ."             "0  ok"
assert_output "depth with items"   "1 2 3 depth ."       "3  ok"
assert_output "?dup non-zero"      "5 ?dup . ."          "5 5  ok"
assert_output "?dup zero"          "0 ?dup ."            "0  ok"

# =========================================================================
section "Stack Display"
# =========================================================================

assert_output ".s empty"           ".s"                  "<0>"
assert_output ".s with items"      "1 2 3 .s"            "1 2 3"

# =========================================================================
section "Comparison Words"
# =========================================================================

assert_output "= equal"            "42 42 = ."           "-1  ok"
assert_output "= unequal"          "42 7 = ."            "0  ok"
assert_output "< true"             "3 10 < ."            "-1  ok"
assert_output "< false"            "10 3 < ."            "0  ok"
assert_output "< equal"            "5 5 < ."             "0  ok"
assert_output "> true"             "10 3 > ."            "-1  ok"
assert_output "> false"            "3 10 > ."            "0  ok"
assert_output "0= zero"            "0 0= ."              "-1  ok"
assert_output "0= non-zero"        "42 0= ."             "0  ok"
assert_output "0< negative"        "-7 0< ."             "-1  ok"
assert_output "0< positive"        "7 0< ."              "0  ok"
assert_output "0< zero"            "0 0< ."              "0  ok"

# =========================================================================
section "Boolean Logic"
# =========================================================================

assert_output "and"         ': test $FF00 $0FF0 and . ; test'   "3840  ok"
assert_output "or"          ': test $FF00 $0FF0 or . ; test'    "65520  ok"
assert_output "xor"         ': test $FF00 $0FF0 xor . ; test'   "61680  ok"
assert_output "invert 0"           "0 invert ."          "-1  ok"
assert_output "invert -1"          "-1 invert ."         "0  ok"

# =========================================================================
section "Memory Access"
# =========================================================================

# Note: HERE is not yet exposed as a Forth word

# 16/32-bit memory access (w@/w! l@/l!) — used by graphics pixels and DRM structs
assert_output "l! / l@"            'pad $11223344 over l! l@ .'         "287454020"
assert_output "w! / w@"            'pad $ABCD over w! w@ .'             "43981"
assert_output "l! writes 4 bytes"  'pad -1 over ! 0 over l! @ u.'      "18446744069414584320"
assert_output "w! writes 2 bytes"  'pad -1 over ! 0 over w! @ u.'      "18446744073709486080"

# =========================================================================
section "User-defined Words"
# =========================================================================

assert_output "define and use"     ": double dup + ; 5 double ."       "10  ok"
assert_output "word calling word"  ": double dup + ; : quad double double ; 3 quad ." "12  ok"
assert_output "empty definition"   ": noop ; 1 noop ."                 "1  ok"
assert_output "redefine word"      ": foo 1 ; : foo 2 ; foo ."        "2  ok"
assert_output "square"             ": square dup * ; 7 square ."       "49  ok"
assert_output "cube"               ": cube dup dup * * ; 3 cube ."    "27  ok"
assert_output "multi-line def" "$(printf ': double dup + ;\n5 double .')" "10  ok"

# =========================================================================
section "Return Stack"
# =========================================================================

assert_output ">r r> round-trip"   ": test 5 >r r> ; test ."          "5  ok"
assert_output "r@ copies"          ": test 7 >r r@ r> + ; test ."     "14  ok"
assert_output "nested calls" "$(printf ': my-inc 1+ ;\n: stash >r my-inc r> ;\n10 20 stash . .')" "20 11  ok"

# =========================================================================
section "Case Insensitivity"
# =========================================================================

assert_output "uppercase DUP"      "5 DUP + ."           "10  ok"
assert_output "mixed case Dup"     "5 Dup + ."           "10  ok"
assert_output "define upper use lower" ": DOUBLE dup + ; 5 double ." "10  ok"

# =========================================================================
section "Number Parsing"
# =========================================================================

assert_output "decimal"            "42 ."                "42  ok"
assert_output "negative"           "-7 ."                "-7  ok"
assert_output "hex"                ': test $FF . ; test' "255  ok"
assert_output "hex lowercase"      ': test $ff . ; test' "255  ok"
assert_output "binary"             "%1010 ."             "10  ok"
assert_output "forced decimal"     "#99 ."               "99  ok"
assert_output "negative hex"       ': test -$10 . ; test'  "-16  ok"
assert_output "negative binary"    "-%1010 ."            "-10  ok"
assert_output "zero"               "0 ."                 "0  ok"

# =========================================================================
section "Compile Mode Error Recovery"
# =========================================================================

assert_error  "unknown in def"     ": test badword ;"    "? badword"
assert_output "recover after error" "$(printf ': test badword ;\n1 2 + .')" "3  ok"
assert_output "redefine after fail" "$(printf ': foo badword ;\n: foo 42 . ;\nfoo')" "42"

# =========================================================================
section "Error Handling"
# =========================================================================

assert_error  "unknown word"       "foobar"              "? foobar"
assert_error  "compile-only >r"    ">r"                  "compile only"

# =========================================================================
section "Comments"
# =========================================================================

assert_output "paren comment"        "1 ( this is a comment ) 2 + ."  "3"
assert_output "paren in definition"  ': double ( n -- n*2 ) dup + ; 5 double .'  "10"
assert_output "paren no close"       "1 2 + ( no closing paren"       "ok"
assert_output "backslash comment"    '1 2 + . \ this is ignored'      "3"
assert_output "backslash in def"     ': inc 1+ ; \ simple increment
5 inc .'                                                               "6"

# =========================================================================
section "IF / ELSE / THEN"
# =========================================================================

assert_output "if true exec"       ": test 1 if 42 . then ; test"             "42"
assert_output "if false skip"      ": test 0 if 42 . then ; test"             "ok"
assert_output "if else true"       ": test 1 if 42 else 99 then ; test ."     "42"
assert_output "if else false"      ": test 0 if 42 else 99 then ; test ."     "99"
assert_output "nested if"          ": test 1 if 1 if 42 . then then ; test"   "42"
assert_output "if with compare"    ": test 5 3 > if 42 else 0 then ; test ."  "42"
assert_output "if 0= true"        ": test 0 0= if 42 then ; test ."          "42"
assert_error  "if without then"  ": test if ;"                               "unresolved control flow"
assert_error  "begin without until" ": test begin ;"                         "unresolved control flow"
assert_error  "begin then mismatch" ": test begin then ;"                   "? mismatched-control-flow"
assert_error  "if until mismatch"  ": test if until ;"                      "? mismatched-control-flow"
assert_error  "if outside def"   "if"                                       "compile only"
assert_error  "then outside def" "then"                                     "compile only"
assert_error  "begin outside def" "begin"                                   "compile only"

# =========================================================================
section "BEGIN / UNTIL / AGAIN / WHILE / REPEAT"
# =========================================================================

assert_output "begin until"   ": test 5 begin 1- dup 0= until ; test ."      "0"
assert_output "begin while repeat" \
    ": test 3 begin dup while 1- repeat ; test ."                             "0"
assert_output "countdown" \
    ': countdown 3 begin dup 0 > while dup . 1- repeat drop ; countdown'      "3 2 1"
assert_output "begin again (via while)" \
    ": test 5 begin dup while dup . 1- repeat drop ; test"                    "5 4 3 2 1"

# =========================================================================
section "RECURSE"
# =========================================================================

assert_output "factorial"    ": fact dup 1 > if dup 1- recurse * then ; 5 fact ."  "120"
assert_output "factorial 6"  ": fact dup 1 > if dup 1- recurse * then ; 6 fact ."  "720"

# =========================================================================
section "DO / LOOP"
# =========================================================================

assert_output "do loop i"         ": test 5 0 do i . loop ; test"                "0 1 2 3 4"
assert_output "+loop"             ": test 10 0 do i . 2 +loop ; test"            "0 2 4 6 8"
assert_output "+loop non-exact"  ": test 10 0 do i . 3 +loop ; test"            "0 3 6 9"
assert_output "do skip equal"     ": test 0 0 do 42 . loop ; test"               "ok"
assert_output "nested do j"       ": test 2 0 do 2 0 do j . i . 32 emit loop loop ; test"  "0 0"
assert_output "do loop sum"       ": sum 0 5 0 do i + loop ; sum ."              "10"

# =========================================================================
section "LEAVE"
# =========================================================================

assert_output "leave basic"        ": test 10 0 do i 5 = if leave then i . loop ; test"   "0 1 2 3 4"
assert_output "leave first iter"   ": test 10 0 do leave loop 99 . ; test"                "99"
assert_output "leave nested inner" \
    ": test 3 0 do 5 0 do i 2 = if leave then i . loop 32 emit loop ; test"  "0 1  0 1  0 1"
assert_output "leave nested outer" \
    ": test 3 0 do i 1 = if leave then 3 0 do i . loop 32 emit loop ; test"  "0 1 2"
assert_output "leave +loop"        ": test 20 0 do i 10 > if leave then i . 3 +loop ; test"  "0 3 6 9"
assert_error  "leave outside do"  ": test leave ;"                                         "? mismatched-control-flow"

# =========================================================================
section "Defining Words"
# =========================================================================

assert_output "constant"           "42 constant answer answer ."              "42"
assert_output "constant arith"     "42 constant x x x + ."                   "84"
assert_output "create allot"       "create buf 100 allot 42 buf ! buf @ ."   "42"
assert_output "here"               "here 0 <> ."                             "-1"
assert_output "comma"              "here 42 , here swap - ."                 "8"
assert_output "variable"           "variable x 99 x ! x @ ."                "99"
assert_output "two variables"      "variable a variable b 10 a ! 20 b ! a @ b @ + ."  "30"

# =========================================================================
section "DOES>"
# =========================================================================

assert_output "does> constant"    ": myconst create , does> @ ; 42 myconst answer answer ."  "42"
assert_output "does> two uses"    ": myconst create , does> @ ; 10 myconst x 20 myconst y x y + ."  "30"
assert_output "does> array"       ": arr create cells allot does> swap cells + ; 3 arr a 99 0 a ! 0 a @ ."  "99"

# =========================================================================
section "MARKER"
# =========================================================================
# Define a marker, define words after it, use them, then run the marker.
assert_output "MARKER define+use+forget" \
    "marker -w  : mfoo 111 ;  : mbar 222 ;  mfoo . mbar .  -w"  "111 222"
# Running the marker rewinds HERE to exactly its pre-marker value (space reclaimed).
assert_output "MARKER reclaims HERE" \
    "here marker -w  : mfoo 1 ;  : mbar 2 ;  -w  here = ."  "-1"
# After the marker runs, the words it covered are gone (referencing one errors).
assert_error "MARKER forgets its words" \
    "marker -w  : mzap 7 ;  -w  mzap"  "mzap"
# The reclaimed space is reusable: a fresh definition after the marker works.
assert_output "MARKER space is reusable" \
    "marker -w  : mfoo 1 ;  -w  : mfoo 999 ;  mfoo ."  "999"
# Nested markers: the outer marker forgets the inner one too.
assert_error "MARKER nested (outer forgets inner)" \
    "marker -a  : x1 1 ;  marker -b  : x2 2 ;  -a  -b"  "-b"

# =========================================================================
section "CHAR robustness"
# =========================================================================
# char is a parse-time word; misusing it inside a definition (should be [char])
# left it parsing nothing at run time and dereferencing parse-word's NULL c-addr
# → segfault. It must no longer crash; the REPL must survive the next line.
char_safe=$(printf ': star char * emit ;\nstar\n4242 . bye\n' | timeout 5 $FORTH 2>&1)
if [[ "$char_safe" == *"4242"* ]]; then
    printf "  ${GREEN}PASS${NC}  char with no word does not segfault (REPL survives)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  char with no word crashed the REPL\n    Expected 4242\n    Got: %q\n" "$char_safe"; ((failed++))
fi
assert_output "[char] still compiles a char literal" ': star [char] * emit ; star'  "*"
assert_output "char still works at interpret level"  'char * .'                      "42"
# [char] with no word at the very end of a page-sized included file: the byte
# after the mmap is an unmapped page, so dereferencing parse-word's (now NULL)
# c-addr would fault. [char] must check the length and not dereference.
pb_dir="$(mktemp -d)"
{ printf ': foo '; printf '%4084s' ''; printf '[char]'; } > "$pb_dir/page.fs"  # exactly 4096 bytes
pb_forth="${FORTH/.\//$PWD/}"
pb_out=$( cd "$pb_dir" && printf 'include page.fs\n4242 . bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $pb_forth 2>&1 )
rm -rf "$pb_dir"
if [[ "$pb_out" == *"4242"* ]]; then
    printf "  ${GREEN}PASS${NC}  [char] at end of a page-sized file does not fault\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  [char] at a page boundary faulted\n    Expected 4242\n    Got: %q\n" "$pb_out"; ((failed++))
fi

# =========================================================================
section "String Words"
# =========================================================================

assert_output "type"              ': test s" Hello" type ; test'                "Hello"
assert_output "s-quote"           ': test s" AB" s" CD" type type ; test'       "CDAB"
assert_output "dot-quote"         ': test ." Hello World!" ; test'              "Hello World!"
assert_output "dot-quote multi"   ': test ." A" ." B" ; test'                   "AB"
assert_output "dot-paren"         '.( Hello World!)'                           "Hello World!"
# .( must not leak the parsed text onto the stack (regression: it used to push
# one cell per character). depth 0 = . prints -1 only when the stack is clean.
assert_output "dot-paren clean stack" '.( hi) depth 0 = .'                     "-1"
assert_error  "s-quote no close" ': test s" no closing quote ;'                "unterminated string"
assert_error  "dot-quote no close" ': test ." no closing quote ;'              "unterminated string"

# =========================================================================
section "PICK"
# =========================================================================

assert_output "0 pick"            "1 2 3 0 pick ."                              "3"
assert_output "2 pick"            "1 2 3 2 pick ."                              "1"

# =========================================================================
section "core.fs Words"
# =========================================================================

assert_output "CR defined"           "1 2 + ."                        "3"
assert_output "SPACE defined"        ": test space 42 . ; test"       "42"
assert_output "BL defined"           "bl ."                           "32"
assert_output "TRUE"                 "true ."                         "-1"
assert_output "FALSE"                "false ."                        "0"
assert_output "MOD"                  "17 5 mod ."                     "2"
assert_output "/"                    "20 4 / ."                       "5"
assert_output "CELL+"               "0 cell+ ."                      "8"
assert_output "CELLS"               "3 cells ."                      "24"
assert_output "<>"                   "3 4 <> ."                       "-1"
assert_output "<> false"             "5 5 <> ."                       "0"
assert_output "0<>"                  "42 0<> ."                       "-1"
assert_output "0<> false"            "0 0<> ."                        "0"
assert_output "2OVER"                "1 2 3 4 2over . . . . . ."     "2 1 4 3 2 1"
assert_output "2SWAP"                "1 2 3 4 2swap . . . ."         "2 1 4 3"
assert_output "*/"                   "3 7 2 */ ."                     "10"
assert_output "SPACES"               ": test 3 spaces 42 . ; test"   "   42"
assert_output "COUNT"                "create s 5 c, 72 c, 101 c, 108 c, 108 c, 111 c, s count type"  "Hello"

# =========================================================================
section "Graphics (software 2D surface)"
# =========================================================================
# graphics.fs is loaded on demand (not auto-loaded), so include it by absolute
# path. Drawing is verified by reading the pixel buffer back — no display needed.
# A 4x3 surface, stride 16 bytes; pixel (1,2) is at offset 2*16+1*4 = 36.
GR="$FORTH_LIB/graphics.fs"
assert_output "gr pixel plots 32bpp"  "include $GR  48 allocate drop value gb  : g gb 4 3 16 set-surface 0 clear red 1 2 pixel gb 36 + l@ . ; g"  "16711680"
assert_output "gr fill-rect"          "include $GR  48 allocate drop value gb  : g gb 4 3 16 set-surface 0 clear green 0 0 2 1 fill-rect gb 4 + l@ . ; g"  "65280"
assert_output "gr clear fills"        "include $GR  48 allocate drop value gb  : g gb 4 3 16 set-surface blue clear gb 20 + l@ . ; g"  "255"
assert_output "gr out-of-bounds noop" "include $GR  48 allocate drop value gb  : g gb 4 3 16 set-surface white 99 99 pixel depth . ; g"  "0"

# =========================================================================
section "Dynamic Memory (heap)"
# =========================================================================
# ALLOCATE/FREE round-trip: store and read a cell, ior 0 throughout.
assert_output "ALLOCATE/FREE round-trip" \
    ": t 64 allocate .\" ior=\" . dup 4242 swap ! dup @ .\" val=\" . free .\" f=\" . ; t" \
    "ior=0 val=4242 f=0"
# Zero-size request is rejected with a non-zero ior (no allocation).
assert_output "ALLOCATE 0 → non-zero ior" \
    ": t 0 allocate .\" z=\" . drop ; t" \
    "z=22"
# RESIZE grows the block and preserves existing contents.
assert_output "RESIZE preserves contents" \
    ": t 16 allocate drop dup 7 swap ! 256 resize .\" r=\" . dup @ .\" p=\" . free drop ; t" \
    "r=0 p=7"
# An impossibly large request fails cleanly: a-addr 0 and a non-zero ior.
assert_output "ALLOCATE failure → a-addr 0" \
    ": t 1000000000000000 allocate swap .\" a=\" . 0<> .\" bad=\" . ; t" \
    "a=0 bad=-1"
# FREE / RESIZE of a null pointer (e.g. a failed ALLOCATE's result) must not
# dereference it — return a non-zero ior instead of faulting.
assert_output "FREE null → non-zero ior" \
    ": t 0 free .\" fz=\" . ; t" \
    "fz=22"
assert_output "RESIZE null → a-addr 0, non-zero ior" \
    ": t 0 64 resize .\" rz=\" . .\" ra=\" . ; t" \
    "rz=22 ra=0"

# =========================================================================
section "Double-Cell Arithmetic"
# =========================================================================

assert_output "s>d positive"       "10 s>d . ."                       "0 10"
assert_output "s>d negative"       ": test -1 s>d . . ; test"         "-1 -1"
assert_output "um*"                "3 4 um* . ."                      "0 12"
assert_output "m*"                 ": test -3 4 m* . . ; test"        "-1 -12"
assert_output "um/mod"             "42 0 10 um/mod . ."               "4 2"
assert_output "fm/mod positive"    "7 s>d 2 fm/mod . ."               "3 1"
assert_output "fm/mod negative"    ": test 7 s>d -2 fm/mod . . ; test"  "-4 -1"
assert_output "sm/rem"             ": test 7 s>d -2 sm/rem . . ; test"  "-3 1"

# =========================================================================
section "Pictured Numeric Output"
# =========================================================================

assert_output "u. zero"            "0 u."                             "0"
assert_output "u. simple"          "42 u."                            "42"
assert_output "u. large"           "999999 u."                        "999999"
assert_output ".r right-just"      "42 5 .r"                          "   42"
assert_output ".r narrow"          "100 2 .r"                         "100"
assert_output ".r negative"       ': test -42 6 .r ; test'           "   -42"
assert_output ". INT64_MIN"       ': test -9223372036854775808 . ; test'  "-9223372036854775808  ok"
assert_output "*/mod"              "3 7 2 */mod . ."                  "10 1"
assert_output "decimal"            ": test decimal 42 . ; test"       "42"

# =========================================================================
section "BASE and Number Formatting"
# =========================================================================

assert_output "hex output"         'hex #255 . decimal'       "FF"
assert_output "hex u. output"      'hex #255 u. decimal'      "FF"
assert_output "hex input"          ': hex 16 base ! ; FF . decimal'              "FF"
assert_output "hex $ prefix"       ': hex 16 base ! ; $FF . decimal'             "FF"
assert_output "dec # in hex"       'hex #100 . decimal'                         "64"
assert_output "bin output"         ': bin 2 base ! ; bin #10 . decimal'           "1010"
assert_output "bin % prefix"       '%1010 .'                                      "10"
assert_output "oct output"         ': oct 8 base ! ; oct #255 . decimal'          "377"
assert_output "$ prefix decimal"   '$FF .'                                        "255"
assert_output "# prefix hex"       'hex #255 . decimal'         "FF"
assert_output "base restore"       'hex #42 . decimal 42 .'    "2A 42"

# =========================================================================
section "Batch 1: Simple Core Words"
# =========================================================================

# LSHIFT / RSHIFT
assert_output "lshift"            '1 4 lshift .'                        "16"
assert_output "lshift zero"       '42 0 lshift .'                       "42"
assert_output "rshift"            '256 4 rshift .'                      "16"
assert_output "rshift zero"       '42 0 rshift .'                       "42"

# 2* / 2/
assert_output "2*"                '21 2* .'                             "42"
assert_output "2/ positive"       '42 2/ .'                             "21"
assert_output "2/ negative"       '-7 2/ .'                             "-4"
assert_output "2/ -1"             '-1 2/ .'                             "-1"

# U<
assert_output "u< true"           '3 10 u< .'                          "-1"
assert_output "u< false"          '10 3 u< .'                          "0"
assert_output "u< equal"          '5 5 u< .'                           "0"
assert_output "u< unsigned"       '-1 1 u< .'                          "0"

# +!
assert_output "+!"                'variable x 10 x ! 5 x +! x @ .'    "15"

# 2! / 2@
assert_output "2! 2@"             'variable p 8 allot 10 20 p 2! p 2@ . .' "20 10"

# CHAR+ / CHARS
assert_output "char+"             '100 char+ .'                         "101"
assert_output "chars"             '10 chars .'                          "10"

# FILL
assert_output "fill"              'create buf 5 allot buf 5 65 fill buf 5 type' "AAAAA"
assert_output "fill zero len"     'create b2 3 allot b2 0 65 fill 42 .'  "42"

# MOVE
assert_output "move non-overlap"  'create s 3 allot create d 3 allot s 3 65 fill s d 3 move d 3 type' "AAA"
assert_output "move zero len"     '1 2 0 move 42 .' "42"
# Overlapping MOVE must be memmove-safe (regression: the overlap copy direction
# was inverted, smearing bytes — see TODO Known Bugs). Buffer holds "ABCDE".
assert_output "move overlap right" 'create mr 6 allot 65 mr c! 66 mr 1+ c! 67 mr 2 + c! 68 mr 3 + c! 69 mr 4 + c! mr mr 1+ 4 move mr 5 type' "AABCD"
assert_output "move overlap left"  'create ml 6 allot 65 ml c! 66 ml 1+ c! 67 ml 2 + c! 68 ml 3 + c! 69 ml 4 + c! ml 1+ ml 4 move ml 5 type' "BCDEE"
assert_output "move zero balance"  'create mz 2 allot mz mz 1+ 0 move depth 0 = .' "-1"

# ALIGN / ALIGNED
assert_output "aligned"           '1 aligned .'                        "8"
assert_output "aligned 8"         '8 aligned .'                        "8"
assert_output "aligned 9"         '9 aligned .'                        "16"

# CHAR
assert_output "char"              'char A .'                           "65"
assert_output "char space"        'char X .'                           "88"

# =========================================================================
section "Compiler Words"
# =========================================================================

# STATE
assert_output "state interpret"   'state @ .'                          "0"
assert_output "state addr"        ': test state @ ; test .'            "0"

# [ and ]
assert_output "[ ] inline"        ': test [ 42 ] literal ; test .'    "42"

# LITERAL
assert_output "literal"           ': five [ 5 ] literal ; five .'     "5"

# [']
assert_output "['] execute"       ": test ['] dup execute ; 7 test . ." "7 7"

# [CHAR]
assert_output "[char]"            ': test [char] A ; test .'          "65"

# EXIT
assert_output "exit early"        ': test 1 . exit 2 . ; test'        "1"

# POSTPONE immediate word
assert_output "postpone if"       ': my-if postpone if ; immediate : test 1 my-if 42 . then ; test' "42"

# POSTPONE non-immediate word
assert_output "postpone dup"      ': my-dup postpone dup ; immediate : test my-dup ; 7 test . .' "7 7"

# =========================================================================
section "System Words"
# =========================================================================

# >BODY
assert_output ">body"              "create myvar 8 allot ' myvar >body myvar = ." "-1"

# >IN — reflects the parse offset into the current line. For the fixed input
# ">in @ .", >in has advanced past ">in @" (to column 5) when @ runs.
assert_output ">in"                '>in @ .'                          "5"

# SOURCE
assert_output "source"             ': test source nip ; test .'      ""

# ABORT
assert_output "abort recovers"     '1 2 abort 3 .'                   "> "

# ABORT"
assert_output 'abort" true'        ': test true abort" oops" ; test' "oops"
assert_output 'abort" false'       ': test false abort" oops" 42 ; test .' "42"

# >NUMBER
assert_output ">number simple"     ': test 0 0 s" 123" >number 2drop . . ; test'  "0 123"
assert_output ">number hex"        ': test hex 0 0 s" FF" >number 2drop . . decimal ; test' "0 FF"
assert_output ">number partial"    ': test 0 0 s" 12xy" >number nip . 2drop ; test'   "2"

# ENVIRONMENT?
assert_output "environment?"       ': et s" test" environment? . ; et'  "0"

# =========================================================================
section "Core Extension Words"
# =========================================================================

# 0>
assert_output "0> positive"       '5 0> .'                            "-1"
assert_output "0> zero"           '0 0> .'                            "0"
assert_output "0> negative"       '-3 0> .'                           "0"

# U>
assert_output "u> true"           '10 3 u> .'                         "-1"
assert_output "u> false"          '3 10 u> .'                         "0"

# WITHIN
assert_output "within true"       '5 3 10 within .'                   "-1"
assert_output "within false"      '2 3 10 within .'                   "0"
assert_output "within edge lo"    '3 3 10 within .'                   "-1"
assert_output "within edge hi"    '10 3 10 within .'                  "0"

# ERASE
assert_output "erase"             'create buf 3 allot buf 3 65 fill buf 2 erase buf c@ .' "0"

# U.R
assert_output "u.r"               '42 5 u.r'                          "   42"

# UNUSED
assert_output "unused"            'unused 0 > .'                      "-1"

# CASE/OF/ENDOF/ENDCASE
assert_output "case 1"            ': test case 1 of 10 endof 2 of 20 endof 0 swap endcase ; 1 test .' "10"
assert_output "case 2"            ': test case 1 of 10 endof 2 of 20 endof 0 swap endcase ; 2 test .' "20"
assert_output "case default"      ': test case 1 of 10 endof 2 of 20 endof 0 swap endcase ; 3 test .' "0"

# .(
assert_output "dot-paren"         '.( hello)'                         "hello"

# =========================================================================
section "Batch 1: Core Extension Words"
# =========================================================================

# PARSE-NAME
assert_output "parse-name"           'parse-name hello type'              "hello"

# PARSE
assert_output "parse delim"          '41 parse hello) type'               "hello"
assert_output "parse space"          '32 parse hello type'                "hello"
assert_output "parse no delim"       '41 parse hello type'                "hello"

# SOURCE-ID
assert_output "source-id keyboard"   'source-id .'                        "0"
assert_output "source-id evaluate"   ': t s" source-id ." evaluate ; t'  "-1"

# VALUE / TO
assert_output "value"                '10 value x x .'                     "10"
assert_output "to interpret"         '10 value x 20 to x x .'            "20"
assert_output "to compile"           '10 value x : t 20 to x ; t x .'   "20"
assert_output "value unchanged"      '10 value x x . x .'                "10 10"

# :NONAME
assert_output "noname"               ':noname dup * ; 7 swap execute .'   "49"
assert_output "noname in var"        'variable sq :noname dup * ; sq ! 6 sq @ execute .' "36"

# DEFER / IS (vectored execution / late binding). Note: ' and ['] contain an
# apostrophe, escaped as '\'' to survive the single-quoted shell argument.
assert_output "defer/is interpret"   'defer p : c p ; :noname 42 ; is p c .'                 "42"
assert_output "is by tick"           'defer p : one 1 ; '\'' one is p p .'                   "1"
assert_output "is re-vector"         'defer p : c p . ; :noname 1 ; is p c :noname 2 ; is p c'  "1 2"
assert_output "is compile-mode"      'defer p : c p . ; : two 2 ; : sw '\'' two is p ; sw c'  "2"
assert_error  "defer uninitialized"  'defer p p'                                             "uninitialized deferred word"

# ?DO
assert_output "?do normal"           ': t 5 0 ?do i . loop ; t'          "0 1 2 3 4"
assert_output "?do skip"             ': t 5 5 ?do i . loop 99 . ; t'     "99"
assert_output "?do skip empty"       ': t 0 0 ?do i . loop ; t'          " ok"

# WORDS
assert_output "words"                'words'                              "words"

# =========================================================================
section "Batch 2: Programming-Tools + String Words"
# =========================================================================

# ?
assert_output "question fetch"       'variable v 42 v ! v ?'              "42"

# DUMP
assert_output "dump"                 'here 16 dump'                       "|................|"

# /STRING
assert_output "/string"              ': t s" hello world" 6 /string type ; t'  "world"
assert_output "/string zero"         ': t s" hello" 0 /string type ; t'        "hello"

# COMPARE
assert_output "compare equal"        ': t s" hello" s" hello" compare . ; t'   "0"
assert_output "compare less"         ': t s" abc" s" abd" compare . ; t'       "-1"
assert_output "compare greater"      ': t s" abd" s" abc" compare . ; t'       "1"
assert_output "compare shorter"      ': t s" abc" s" abcd" compare . ; t'      "-1"
assert_output "compare longer"       ': t s" abcd" s" abc" compare . ; t'      "1"

# CMOVE / CMOVE>
assert_output "cmove"                'create s 65 c, 66 c, 67 c, create d 3 allot s d 3 cmove d c@ . d 1+ c@ . d 2 + c@ .'  "65 66 67"
assert_output "cmove>"               'create cs 65 c, 66 c, 67 c, create cd 3 allot cs cd 3 cmove> cd c@ . cd 1+ c@ . cd 2 + c@ .'  "65 66 67"
# Zero-count copies must leave a clean stack (regression: CMOVE> dropped only 2
# of its 3 cells when u=0 — see TODO Known Bugs). depth 0 = . prints -1 only if
# the stack is empty afterwards.
assert_output "cmove> zero balance"  'create cz 2 allot cz cz 1+ 0 cmove> depth 0 = .' "-1"
assert_output "cmove zero balance"   'create kz 2 allot kz kz 1+ 0 cmove depth 0 = .' "-1"

# -TRAILING
assert_output "-trailing"            ': t s" hello   " -trailing type ; t'     "hello"
assert_output "-trailing none"       ': t s" hello" -trailing type ; t'        "hello"

# BLANK
assert_output "blank"                'create b 5 allot b 5 blank b c@ . b 4 + c@ .'  "32 32"

# =========================================================================
section "Batch 3: Facility + Double-Number Words"
# =========================================================================

# KEY?
assert_output "key? no input"        'key? .'                              "0"

# MS (just check it doesn't crash — timing is non-deterministic)
assert_output "ms"                   '1 ms 42 .'                           "42"

# SCREEN-WIDTH / SCREEN-HEIGHT (values depend on terminal)
assert_output "screen-width"         'screen-width 0 > .'                  "-1"
assert_output "screen-height"        'screen-height 0 > .'                 "-1"

# D+
assert_output "d+ simple"           ': t 1 0 3 0 d+ . . ; t'              "0 4"
assert_output "d+ carry"            ': t -1 0 1 0 d+ . . ; t'             "1 0"

# D-
assert_output "d- simple"           ': t 5 0 3 0 d- . . ; t'              "0 2"

# D0=
assert_output "d0= true"            ': t 0 0 d0= . ; t'                   "-1"
assert_output "d0= false"           ': t 1 0 d0= . ; t'                   "0"

# D0<
assert_output "d0< true"            ': t 0 -1 d0< . ; t'                  "-1"
assert_output "d0< false"           ': t 0 1 d0< . ; t'                   "0"

# D=
assert_output "d= true"             ': t 5 0 5 0 d= . ; t'               "-1"
assert_output "d= false"            ': t 5 0 6 0 d= . ; t'               "0"

# D.
assert_output "d. positive"         ': t 42 0 d. ; t'                     "42"
assert_output "d. negative"         ': t -42 -1 d. ; t'                   "-42"

# =========================================================================
section "Snake Game Prerequisites"
# =========================================================================

# MS@ (millisecond timestamp)
assert_output "ms@ nonzero"          'ms@ 0 > .'                          "-1"
assert_output "ms@ increases"        'ms@ 1 ms ms@ swap - 0 > .'         "-1"

# CURSOR-OFF / CURSOR-ON (just check they don't crash)
assert_output "cursor-off"           'cursor-off 42 .'                    "42"
assert_output "cursor-on"            'cursor-on 42 .'                     "42"

# Key constants
assert_output "key_up"               'key_up .'                           "129"
assert_output "key_down"             'key_down .'                         "130"
assert_output "key_right"            'key_right .'                        "131"
assert_output "key_left"             'key_left .'                         "132"
assert_output "key_escape"           'key_escape .'                       "27"

# Random number generator
assert_output "rnd range"            '100 rnd dup 0 < invert swap 100 < and .'  "-1"
assert_output "rnd zero base"       '1 rnd .'                             "0"

# INCLUDE (parse-word + included)
assert_output "include word"         'include core.fs 42 .'                      "42"

# Command-line file argument (argv[1])
# Load core.fs via argv[1] (it's idempotent — reloading defines the same words)
t0=$(date +%s.%N)
argv_output=$(printf 'true .\n' | timeout 2 $FORTH core.fs 2>&1)
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "argv file load"
if [[ "$argv_output" == *"-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  argv file load\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  argv file load\n"
    printf "    Expected: -1\n"
    printf "    Got:      %s\n" "$(echo "$argv_output" | head -5)"
    ((failed++))
fi

# BASICFORTH_PATH fallback (load core.fs from a non-CWD path)
# Temporarily rename core.fs so CWD lookup fails, then use env var
t0=$(date +%s.%N)
mv core.fs core.fs.bak 2>/dev/null
bp_output=$(printf 'true .\n' | BASICFORTH_PATH=../../../src/forth timeout 2 $FORTH 2>&1)
mv core.fs.bak core.fs 2>/dev/null
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "BASICFORTH_PATH"
if [[ "$bp_output" == *"-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  BASICFORTH_PATH\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  BASICFORTH_PATH\n"
    printf "    Expected: -1\n"
    printf "    Got:      %s\n" "$(echo "$bp_output" | head -5)"
    ((failed++))
fi

# BASICFORTH_PATH multi-directory: two files resolved from two segments in one
# run. core.fs lives in src/forth, snake.fs in examples; with core.fs moved out
# of CWD, both are found via the colon-separated path (snake.fs in the 1st
# segment, core.fs in the 2nd). MAX_LEN (100) is a snake.fs constant.
t0=$(date +%s.%N)
mv core.fs core.fs.bak 2>/dev/null
bp_output=$(printf 'MAX_LEN .\n' | BASICFORTH_PATH=../../../examples:../../../src/forth timeout 2 $FORTH snake.fs 2>&1)
mv core.fs.bak core.fs 2>/dev/null
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "BASICFORTH_PATH multidir"
if [[ "$bp_output" == *"100"* ]]; then
    printf "  ${GREEN}PASS${NC}  BASICFORTH_PATH multidir\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  BASICFORTH_PATH multidir\n"
    printf "    Expected: 100\n"
    printf "    Got:      %s\n" "$(echo "$bp_output" | head -5)"
    ((failed++))
fi

# examples/snake-mini.fs (the Snake tutorial's finished program) must load and
# its logic must work headlessly: start the snake, drop food one cell ahead of
# the head, advance one frame, and confirm the snake ate and grew (len 3 -> 4).
t0=$(date +%s.%N)
sm_out=$(printf 'include %s/examples/snake-mini.fs\ninit-snake\n12 fx ! 8 fy !\ntick\n.( SNAKELEN=) len @ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0')
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "examples/snake-mini.fs"
if [[ "$sm_out" == *"SNAKELEN=4"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/snake-mini.fs loads and grows on food\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/snake-mini.fs loads and grows on food\n"
    printf "    Expected: SNAKELEN=4\n"
    printf "    Got:      %s\n" "$(echo "$sm_out" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# Snake collision rules (regression guard). Build a length-4 snake coiled in a
# 2x2 block: tail at (5,5), head at (5,6) pointing up toward the tail.
#  - moving up onto the vacating tail cell is LEGAL (no game over)
#  - but EATING onto that tail cell (food there) is a real overlap -> game over
#  - running into a non-tail body segment is game over
sm_setup="include $REPO_ROOT/examples/snake-mini.fs\ninit-snake\n4 len ! 3 hd !\n5 0 bx! 5 0 by!\n6 1 bx! 5 1 by!\n6 2 bx! 6 2 by!\n5 3 bx! 6 3 by!\n5 hx ! 6 hy !\n"
sm_collide() {  # desc  extra-input  expected-OVER
    local out
    out=$(printf "${sm_setup}$2.( OVER=) gameover @ . cr\nbye\n" \
        | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
    if [[ "$out" == *"OVER=$3"* ]]; then
        printf "  ${GREEN}PASS${NC}  snake collision: %s\n" "$1"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  snake collision: %s\n" "$1"
        printf "    Expected: OVER=%s\n    Got:      %s\n" "$3" "$(echo "$out" | tr -dc '[:print:]' | tail -c 50)"
        ((failed++))
    fi
}
sm_collide "follow the vacating tail is legal"  '0 dx ! -1 dy !\n1 fx ! 1 fy !\ntick\n'  "0"
sm_collide "eating onto the tail ends the game" '0 dx ! -1 dy !\n5 fx ! 5 fy !\ntick\n'  "-1"
sm_collide "running into the body ends the game" '1 dx ! 0 dy !\n1 fx ! 1 fy !\ntick\n' "-1"

# examples/snake.fs (the fuller version) must never spawn food on the snake or
# border: its collision is screen-based, so food on the just-vacated tail could
# be eaten without being noticed. Occupy the top half, place food 300 times, and
# confirm every placement lands on an empty cell.
t0=$(date +%s.%N)
sf_food=$(printf 'include %s/examples/snake.fs\nreset-screen draw-border\nvariable bad 0 bad !\n: occupy HEIGHT 2 / 1 do WIDTH 2 - 2 do [char] o i j screen! 2 +loop loop ;\noccupy\n: chk 300 0 do update-food fx @ fy @ screen@ bl <> if 1 bad +! then fx @ 2 mod if 1 bad +! then loop ;\nchk\n.( FOODBAD=) bad @ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/snake.fs food placement"
if [[ "$sf_food" == *"FOODBAD=0"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/snake.fs food spawns only on empty, even (reachable) cells\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/snake.fs food spawns only on empty, even (reachable) cells\n"
    printf "    Expected: FOODBAD=0\n    Got:      %s\n" "$(echo "$sf_food" | tr -dc '[:print:]' | tail -c 50)"; ((failed++))
fi

# ...and the fallback scan must not drop food on an unreachable (odd) column:
# the snake only ever lands on even columns. Occupy every reachable even cell so
# only odd columns remain free; update-food must end the game (no reachable cell)
# rather than place food where the snake can never go.
t0=$(date +%s.%N)
sf_odd=$(printf 'include %s/examples/snake.fs\nreset-screen draw-border\n: occE HEIGHT 1- 1 do WIDTH 1- 2 do [char] o i j screen! 2 +loop loop ;\noccE\nfalse done !\nupdate-food\n.( ODDDONE=) done @ . .( FXPAR=) fx @ 2 mod . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/snake.fs unreachable food"
if [[ "$sf_odd" == *"ODDDONE=-1"* ]] && [[ "$sf_odd" == *"FXPAR=0"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/snake.fs never places food on unreachable columns\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/snake.fs never places food on unreachable columns\n"
    printf "    Expected: ODDDONE=-1 and FXPAR=0\n    Got:      %s\n" "$(echo "$sf_odd" | tr -dc '[:print:]' | tail -c 60)"; ((failed++))
fi

# ...and conversely the last reachable column (even WIDTH-2, just inside the
# right border) must still receive food. Occupy every reachable even column
# except WIDTH-2; food must land there rather than the game giving up.
t0=$(date +%s.%N)
sf_edge=$(printf 'include %s/examples/snake.fs\nreset-screen draw-border\n: occ HEIGHT 1- 1 do WIDTH 2 - 2 do [char] o i j screen! 2 +loop loop ;\nocc\nfalse done ! update-food\n.( EDGEOK=) fx @ WIDTH 2 - = . .( EDGEDONE=) done @ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/snake.fs edge column"
if [[ "$sf_edge" == *"EDGEOK=-1"* ]] && [[ "$sf_edge" == *"EDGEDONE=0"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/snake.fs uses the last reachable column (WIDTH-2)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/snake.fs uses the last reachable column (WIDTH-2)\n"
    printf "    Expected: EDGEOK=-1 and EDGEDONE=0\n    Got:      %s\n" "$(echo "$sf_edge" | tr -dc '[:print:]' | tail -c 60)"; ((failed++))
fi

# ...and a completely full board must not hang update-food: it gives up the
# random search, scans, finds nothing, and ends the game (you filled the board).
# If it looped forever the timeout would kill it and FULLDONE would be missing.
t0=$(date +%s.%N)
sf_full=$(printf 'include %s/examples/snake.fs\nreset-screen\n: fill HEIGHT 0 do WIDTH 0 do [char] o i j screen! loop loop ;\nfill\nfalse done !\nupdate-food\n.( FULLDONE=) done @ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/snake.fs full board"
if [[ "$sf_full" == *"FULLDONE=-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/snake.fs full board ends instead of hanging\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/snake.fs full board ends instead of hanging\n"
    printf "    Expected: FULLDONE=-1\n    Got:      %s\n" "$(echo "$sf_full" | tr -dc '[:print:]' | tail -c 50)"; ((failed++))
fi

# BASICFORTH_PATH multi-directory: match in a later segment (first miss skipped)
t0=$(date +%s.%N)
mv core.fs core.fs.bak 2>/dev/null
bp_output=$(printf 'true .\n' | BASICFORTH_PATH=/nonexistent-bf:../../../src/forth timeout 2 $FORTH 2>&1)
mv core.fs.bak core.fs 2>/dev/null
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "BASICFORTH_PATH later-segment"
if [[ "$bp_output" == *"-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  BASICFORTH_PATH later-segment\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  BASICFORTH_PATH later-segment\n"
    printf "    Expected: -1\n"
    printf "    Got:      %s\n" "$(echo "$bp_output" | head -5)"
    ((failed++))
fi

# BASICFORTH_PATH multi-directory: empty segments are tolerated and skipped
t0=$(date +%s.%N)
mv core.fs core.fs.bak 2>/dev/null
bp_output=$(printf 'true .\n' | BASICFORTH_PATH=:::../../../src/forth timeout 2 $FORTH 2>&1)
mv core.fs.bak core.fs 2>/dev/null
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "BASICFORTH_PATH empty-segments"
if [[ "$bp_output" == *"-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  BASICFORTH_PATH empty-segments\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  BASICFORTH_PATH empty-segments\n"
    printf "    Expected: -1\n"
    printf "    Got:      %s\n" "$(echo "$bp_output" | head -5)"
    ((failed++))
fi

# Nested INCLUDED error context: a path-resolved file that includes another
# path-resolved file must still report ITS OWN name and line for a later error.
# The nested call must not clobber file_name/line globals or the path scratch.
nested_dir="bf_nested_test"
rm -rf "$nested_dir"; mkdir -p "$nested_dir"
printf ': p1 ;\ninclude nchild.fs\nnopetok\n' > "$nested_dir/nparent.fs"
printf ': c1 ;\n: c2 ;\n: c3 ;\n' > "$nested_dir/nchild.fs"
t0=$(date +%s.%N)
bp_output=$(printf 'include nparent.fs\n' | BASICFORTH_PATH="$nested_dir" timeout 2 $FORTH 2>&1)
rm -rf "$nested_dir"
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "nested INCLUDED error context"
if [[ "$bp_output" == *"nparent.fs:3: ? nopetok"* ]]; then
    printf "  ${GREEN}PASS${NC}  nested INCLUDED error context\n"
    ((passed++))
else
    printf "  ${RED}FAIL${NC}  nested INCLUDED error context\n"
    printf "    Expected: nparent.fs:3: ? nopetok\n"
    printf "    Got:      %s\n" "$(echo "$bp_output" | head -5)"
    ((failed++))
fi

# Shebang (#!) script support: a leading "#!" line is skipped so a Forth file
# can be a Unix executable script. core.fs loads from CWD as usual.
sb_dir="bf_shebang_test"
rm -rf "$sb_dir"; mkdir -p "$sb_dir"
# 1) shebang line skipped, rest of the script runs
printf '#!/usr/bin/env basicforth\n7 6 * .\nbye\n' > "$sb_dir/run.fs"
# 2) line numbers stay accurate: error sits on physical line 3
printf '#!/usr/bin/env basicforth\n: good ;\nshebangbad\nbye\n' > "$sb_dir/lines.fs"
# 3) a leading single '#' (decimal literal) must NOT be treated as a shebang
printf '#10 .\nbye\n' > "$sb_dir/hashlit.fs"

t0=$(date +%s.%N)
sb_run=$(printf '' | timeout 2 $FORTH "$sb_dir/run.fs" 2>&1)
sb_lines=$(printf '' | timeout 2 $FORTH "$sb_dir/lines.fs" 2>&1)
sb_hash=$(printf '' | timeout 2 $FORTH "$sb_dir/hashlit.fs" 2>&1)
rm -rf "$sb_dir"
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "shebang scripts"
if [[ "$sb_run" == *"42"* ]]; then
    printf "  ${GREEN}PASS${NC}  shebang skip + run\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  shebang skip + run\n"
    printf "    Expected: 42\n    Got:      %s\n" "$(echo "$sb_run" | head -5)"; ((failed++))
fi
if [[ "$sb_lines" == *"lines.fs:3: ? shebangbad"* ]]; then
    printf "  ${GREEN}PASS${NC}  shebang line numbers\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  shebang line numbers\n"
    printf "    Expected: lines.fs:3: ? shebangbad\n    Got:      %s\n" "$(echo "$sb_lines" | head -5)"; ((failed++))
fi
if [[ "$sb_hash" == *"10"* ]]; then
    printf "  ${GREEN}PASS${NC}  leading # literal not a shebang\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  leading # literal not a shebang\n"
    printf "    Expected: 10\n    Got:      %s\n" "$(echo "$sb_hash" | head -5)"; ((failed++))
fi

# The bundled hello.fs shebang example must keep working (loads cleanly, runs).
t0=$(date +%s.%N)
hello_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/hello.fs" 2>&1)
t1=$(date +%s.%N)
ms=$(elapsed_ms "$t0" "$t1")
update_slowest "$ms" "examples/hello.fs"
if [[ "$hello_out" == *"*****"* && "$hello_out" == *"42"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/hello.fs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/hello.fs\n"
    printf "    Expected: ***** and 42\n    Got:      %s\n" "$(echo "$hello_out" | head -8)"; ((failed++))
fi

# Tier 3: command-line arguments (argc/argv/arg/next-arg) and exit status.
# Under a script, argv[1] (the script) is shifted out, so the user's args are
# arg[1..] and argc counts the interpreter + remaining user args.
args_dir="$(mktemp -d)"
# walk all args with next-arg, and report argc
printf 'argc @ . cr\n: w begin next-arg dup while type space repeat 2drop ; w cr\nbye\n' > "$args_dir/walk.fs"
# index a specific arg and an out-of-range one
printf '1 arg type cr\n5 arg . . cr\nbye\n' > "$args_dir/idx.fs"
# exit status
printf '7 bye-code\n' > "$args_dir/code.fs"

t0=$(date +%s.%N)
walk_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$args_dir/walk.fs" alpha beta gamma 2>&1)
idx_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$args_dir/idx.fs" alpha beta 2>&1)
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$args_dir/code.fs" >/dev/null 2>&1; code_status=$?
echo_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/echo.fs" one two three 2>/dev/null)
rm -rf "$args_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "script args"

# argc = interpreter + 3 user args = 4, and next-arg yields all three
if [[ "$walk_out" == *"4"* && "$walk_out" == *"alpha beta gamma"* ]]; then
    printf "  ${GREEN}PASS${NC}  script args (argc + next-arg)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  script args (argc + next-arg)\n"
    printf "    Expected: 4 and 'alpha beta gamma'\n    Got:      %s\n" "$(echo "$walk_out" | head -5)"; ((failed++))
fi
# 1 arg -> first user arg; 5 arg -> out of range (0 0)
if [[ "$idx_out" == *"alpha"* && "$idx_out" == *"0 0"* ]]; then
    printf "  ${GREEN}PASS${NC}  arg indexing + out-of-range\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  arg indexing + out-of-range\n"
    printf "    Expected: alpha and '0 0'\n    Got:      %s\n" "$(echo "$idx_out" | head -5)"; ((failed++))
fi
# bye-code sets the process exit status
if [[ "$code_status" == "7" ]]; then
    printf "  ${GREEN}PASS${NC}  bye-code exit status\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  bye-code exit status\n"
    printf "    Expected: 7\n    Got:      %s\n" "$code_status"; ((failed++))
fi
# the bundled echo.fs utility prints its args, with clean (banner-free) stdout
if [[ "$echo_out" == "one two three" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/echo.fs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/echo.fs\n"
    printf "    Expected: 'one two three' (exact)\n    Got:      %s\n" "$(echo "$echo_out" | head -5)"; ((failed++))
fi

# Exit-on-error: a startup script that errors must exit non-zero instead of
# dropping into the REPL, so a Forth utility fails like a Unix program.
err_dir="$(mktemp -d)"
printf '.( start) cr nosuchword 42 .\n'  > "$err_dir/bad.fs"     # undefined word
printf 'drop\n'                          > "$err_dir/under.fs"   # stack underflow
printf '.( done) cr bye\n'               > "$err_dir/ok.fs"      # clean + bye
printf ': greet .( loaded) cr ;\n'       > "$err_dir/nobye.fs"   # clean, no bye

t0=$(date +%s.%N)
bad_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$err_dir/bad.fs" 2>&1); bad_status=$?
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$err_dir/under.fs" >/dev/null 2>&1; under_status=$?
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$err_dir/ok.fs" >/dev/null 2>&1; ok_status=$?
# A clean script with no bye still falls into the REPL: the piped line runs.
nobye_out=$(printf '999 . bye\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$err_dir/nobye.fs" 2>&1); nobye_status=$?
rm -rf "$err_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "script exit status"

# bad: reports the offending token, exits 1, and never reached the REPL prompt
if [[ "$bad_status" == "1" && "$bad_out" == *"nosuchword"* && "$bad_out" != *"> "* ]]; then
    printf "  ${GREEN}PASS${NC}  script error → exit 1, no REPL\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  script error → exit 1, no REPL\n"
    printf "    Expected: status 1, 'nosuchword', no prompt\n    Got:      status %s / %s\n" "$bad_status" "$(echo "$bad_out" | head -3)"; ((failed++))
fi
# stack underflow (guard-page fault) during a script also exits non-zero
if [[ "$under_status" != "0" ]]; then
    printf "  ${GREEN}PASS${NC}  script fault → non-zero exit\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  script fault → non-zero exit\n"
    printf "    Expected: non-zero\n    Got:      %s\n" "$under_status"; ((failed++))
fi
# regression: a clean script ending in bye exits 0
if [[ "$ok_status" == "0" ]]; then
    printf "  ${GREEN}PASS${NC}  clean script + bye → exit 0\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  clean script + bye → exit 0\n"
    printf "    Expected: 0\n    Got:      %s\n" "$ok_status"; ((failed++))
fi
# regression: a clean script WITHOUT bye still drops into the REPL (runs 999 .)
if [[ "$nobye_status" == "0" && "$nobye_out" == *"loaded"* && "$nobye_out" == *"999"* ]]; then
    printf "  ${GREEN}PASS${NC}  clean no-bye script → REPL still runs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  clean no-bye script → REPL still runs\n"
    printf "    Expected: status 0, 'loaded' and '999'\n    Got:      status %s / %s\n" "$nobye_status" "$(echo "$nobye_out" | head -3)"; ((failed++))
fi

# File-output words: stdin/stdout/stderr handles + WRITE-FILE / WRITE-LINE.
# Run from script files (not piped REPL input), so the source is not echoed to
# stdout — essential for the stderr-separation check below.
out_dir="$(mktemp -d)"
printf 'stdin . stdout . stderr . cr bye\n'                 > "$out_dir/fds.fs"
printf ': t s" abc" stdout write-file . ; t cr bye\n'       > "$out_dir/wf.fs"
printf ': t s" L1" stdout write-line . ; t cr bye\n'        > "$out_dir/wl.fs"
printf ': t s" XYZZY" 99 write-file . ; t cr bye\n'         > "$out_dir/badfd.fs"
printf ': t s" STDERRMARK" stderr write-line drop ; t bye\n' > "$out_dir/err.fs"

t0=$(date +%s.%N)
fds_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$out_dir/fds.fs" 2>/dev/null)
wf_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$out_dir/wf.fs" 2>/dev/null)
wl_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$out_dir/wl.fs" 2>/dev/null)
badfd_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$out_dir/badfd.fs" 2>/dev/null)
err_drop=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$out_dir/err.fs" 2>/dev/null)
err_both=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$out_dir/err.fs" 2>&1)
rm -rf "$out_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "file-output words"

# stdin/stdout/stderr push 0/1/2
if [[ "$fds_out" == *"0 1 2"* ]]; then
    printf "  ${GREEN}PASS${NC}  stdin/stdout/stderr constants\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  stdin/stdout/stderr constants\n"
    printf "    Expected: 0 1 2\n    Got:      %s\n" "$(echo "$fds_out" | head -3)"; ((failed++))
fi
# WRITE-FILE writes the bytes to stdout and returns ior 0
if [[ "$wf_out" == *"abc0"* ]]; then
    printf "  ${GREEN}PASS${NC}  write-file → stdout, ior 0\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  write-file → stdout, ior 0\n"
    printf "    Expected: abc0\n    Got:      %s\n" "$(echo "$wf_out" | head -3)"; ((failed++))
fi
# WRITE-LINE appends a newline; the line and the ior end up on separate lines
if [[ "$wl_out" == *"L1"* && "$(printf '%s' "$wl_out" | sed -n '2p')" == "0 " ]]; then
    printf "  ${GREEN}PASS${NC}  write-line → stdout + newline\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  write-line → stdout + newline\n"
    printf "    Expected: 'L1' then '0 ' on next line\n    Got:      %s\n" "$(echo "$wl_out" | head -3)"; ((failed++))
fi
# Bad fd: nothing written, ior is EBADF (9), not 0
if [[ "$badfd_out" == *"9"* && "$badfd_out" != *"XYZZY"* ]]; then
    printf "  ${GREEN}PASS${NC}  write-file bad fd → ior 9, no output\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  write-file bad fd → ior 9, no output\n"
    printf "    Expected: '9', no 'XYZZY'\n    Got:      %s\n" "$(echo "$badfd_out" | head -3)"; ((failed++))
fi
# stderr is a distinct stream: dropped by 2>/dev/null, present under 2>&1
if [[ "$err_drop" != *"STDERRMARK"* && "$err_both" == *"STDERRMARK"* ]]; then
    printf "  ${GREEN}PASS${NC}  write-line → stderr (separate from stdout)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  write-line → stderr (separate from stdout)\n"
    printf "    Expected: absent under 2>/dev/null, present under 2>&1\n    Got:      drop=%s both=%s\n" "$err_drop" "$err_both"; ((failed++))
fi

# The bundled lines.fs utility: data lines → stdout, count → stderr (a clean
# split), and a usage error + non-zero exit when no arguments are given.
t0=$(date +%s.%N)
lines_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/lines.fs" alpha beta 2>/dev/null)
lines_both=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/lines.fs" alpha beta 2>&1)
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/lines.fs" >/dev/null 2>&1; lines_noarg=$?
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/lines.fs"

# stdout carries only the data lines; the count goes to stderr
if [[ "$lines_out" == $'alpha\nbeta' && "$lines_both" == *"lines: 2"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/lines.fs (stdout/stderr split)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/lines.fs (stdout/stderr split)\n"
    printf "    Expected: stdout 'alpha<nl>beta', stderr 'lines: 2'\n    Got:      out=%s both=%s\n" "$lines_out" "$lines_both"; ((failed++))
fi
# no arguments → usage message + exit code 2
if [[ "$lines_noarg" == "2" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/lines.fs no-args → exit 2\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/lines.fs no-args → exit 2\n"
    printf "    Expected: 2\n    Got:      %s\n" "$lines_noarg"; ((failed++))
fi

# File-access words: open-file / read-file / close-file, file-size, and a
# create-file + write-file + reopen roundtrip. Run from a script (s" is
# compile-only) reading a fixture file. ." prints at runtime (unlike .().
fa_dir="$(mktemp -d)"
printf 'hello' > "$fa_dir/data.txt"        # 5 bytes, no trailing newline
cat > "$fa_dir/fa.fs" <<FAEOF
create fabuf 128 allot
: t
   s" $fa_dir/data.txt" r/o open-file drop          ( fileid )
   dup file-size drop drop ." SZ=" . cr             ( fileid )
   >r fabuf 128 r@ read-file drop ." RD=" fabuf swap type cr
   r> close-file drop
   s" $fa_dir/out.txt" w/o create-file drop >r
   s" WROTE" r@ write-file drop r> close-file drop
   s" $fa_dir/missing" r/o open-file ." MISS=" . drop cr ;
t bye
FAEOF
t0=$(date +%s.%N)
fa_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$fa_dir/fa.fs" 2>/dev/null)
fa_disk=$(cat "$fa_dir/out.txt" 2>/dev/null)
rm -rf "$fa_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "file-access words"

if [[ "$fa_out" == *"SZ=5"* ]]; then
    printf "  ${GREEN}PASS${NC}  file-size\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  file-size\n    Expected: SZ=5\n    Got:      %s\n" "$fa_out"; ((failed++))
fi
if [[ "$fa_out" == *"RD=hello"* ]]; then
    printf "  ${GREEN}PASS${NC}  open-file + read-file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  open-file + read-file\n    Expected: RD=hello\n    Got:      %s\n" "$fa_out"; ((failed++))
fi
if [[ "$fa_out" == *"MISS=2"* ]]; then
    printf "  ${GREEN}PASS${NC}  open-file missing → ior 2\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  open-file missing → ior 2\n    Expected: MISS=2\n    Got:      %s\n" "$fa_out"; ((failed++))
fi
if [[ "$fa_disk" == "WROTE" ]]; then
    printf "  ${GREEN}PASS${NC}  create-file + write-file roundtrip\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  create-file + write-file roundtrip\n    Expected: WROTE\n    Got:      %s\n" "$fa_disk"; ((failed++))
fi

# INCLUDE error recovery: a compile-time error in an included file (an undefined
# word inside a :) must recover cleanly — the REPL keeps going (regression: it
# left source_addr pointing at the freed mmap → wedge/segfault). Also, tokens
# after `include <file>` on the same line must run (source pointers restored).
inc_dir="$(mktemp -d)"
inc_forth="${FORTH/.\//$PWD/}"          # absolute path (these subshells cd away)
printf ': c1 nosuchword ;\n' > "$inc_dir/bad.fs"
printf ': g1 7 ;\n' > "$inc_dir/good.fs"
inc_recover=$( cd "$inc_dir" && printf 'include bad.fs\n5 6 + . bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $inc_forth 2>&1 )
inc_rest=$( cd "$inc_dir" && printf 'include good.fs g1 . bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $inc_forth 2>&1 )
rm -rf "$inc_dir"
if [[ "$inc_recover" == *"11"* ]]; then
    printf "  ${GREEN}PASS${NC}  INCLUDE recovers from a compile error (REPL keeps going)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  INCLUDE compile-error recovery\n    Expected 11\n    Got: %q\n" "$inc_recover"; ((failed++))
fi
if [[ "$inc_rest" == *"7"* ]]; then
    printf "  ${GREEN}PASS${NC}  tokens after 'include <file>' on the same line run\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tokens after include\n    Expected 7\n    Got: %q\n" "$inc_rest"; ((failed++))
fi

# READ-LINE: one line at a time, terminator (and a CR before it) stripped, a
# blank line returns u2=0/flag=true, the last line without a trailing newline
# is still read, then EOF returns flag=false. Each line is bracketed [..] so
# empty lines and trailing whitespace are visible.
rl_dir="$(mktemp -d)"
printf 'alpha\nbeta\r\ngamma\n\ndelta' > "$rl_dir/in.txt"   # CRLF line 2, blank line 4, no final NL
cat > "$rl_dir/rl.fs" <<RLEOF
create lbuf 64 allot
: t
   s" $rl_dir/in.txt" r/o open-file drop >r
   begin lbuf 64 r@ read-line drop while
      ." [" lbuf swap stdout write-file drop ." ]" cr
   repeat drop
   r> close-file drop ." DONE" cr ;
t 0 bye-code
RLEOF
# One line per call with an undersized (4-char) buffer: a line that exactly
# fills the buffer ("abcd") consumes its terminator (NO phantom empty line), and
# a line longer than the buffer ("abcdefghij") fills the buffer and the rest is
# discarded so the next call starts at the following line. Expected:
#   abcd | 12 | abcd (efghij dropped) | Z
printf 'abcd\n12\nabcdefghij\nZ\n' > "$rl_dir/edge.txt"
cat > "$rl_dir/rledge.fs" <<RLEOF
create lbuf 4 allot
: t
   s" $rl_dir/edge.txt" r/o open-file drop >r
   begin lbuf 4 r@ read-line drop while
      ." [" lbuf swap stdout write-file drop ." ]" cr
   repeat drop
   r> close-file drop ." DONE" cr ;
t 0 bye-code
RLEOF
t0=$(date +%s.%N)
rl_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$rl_dir/rl.fs" 2>/dev/null)
rledge_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$rl_dir/rledge.fs" 2>/dev/null)
rm -rf "$rl_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "read-line"

rl_want=$'[alpha]\n[beta]\n[gamma]\n[]\n[delta]\nDONE'
if [[ "$rl_out" == "$rl_want" ]]; then
    printf "  ${GREEN}PASS${NC}  read-line (CRLF strip, blank line, no final newline, EOF)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  read-line (CRLF strip, blank line, no final newline, EOF)\n    Expected: %q\n    Got:      %q\n" "$rl_want" "$rl_out"; ((failed++))
fi
# exact-fill consumes terminator (no phantom blank); over-long truncates to u1
rledge_want=$'[abcd]\n[12]\n[abcd]\n[Z]\nDONE'
if [[ "$rledge_out" == "$rledge_want" ]]; then
    printf "  ${GREEN}PASS${NC}  read-line exact-fill terminator + over-long truncation\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  read-line exact-fill terminator + over-long truncation\n    Expected: %q\n    Got:      %q\n" "$rledge_want" "$rledge_out"; ((failed++))
fi

# The bundled cat.fs utility: concatenate files to stdout; missing file →
# stderr + exit 1; no args → usage + exit 2.
ca_dir="$(mktemp -d)"
printf 'AAA\n' > "$ca_dir/x"; printf 'BBB\n' > "$ca_dir/y"
t0=$(date +%s.%N)
cat_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat.fs" "$ca_dir/x" "$ca_dir/y" 2>/dev/null)
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat.fs" "$ca_dir/nope" >/dev/null 2>&1; cat_miss=$?
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat.fs" >/dev/null 2>&1; cat_noarg=$?
rm -rf "$ca_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/cat.fs"

if [[ "$cat_out" == $'AAA\nBBB' ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat.fs concatenates files\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat.fs concatenates files\n    Expected: AAA<nl>BBB\n    Got:      %s\n" "$cat_out"; ((failed++))
fi
if [[ "$cat_miss" == "1" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat.fs missing file → exit 1\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat.fs missing file → exit 1\n    Expected: 1\n    Got:      %s\n" "$cat_miss"; ((failed++))
fi
if [[ "$cat_noarg" == "2" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat.fs no-args → exit 2\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat.fs no-args → exit 2\n    Expected: 2\n    Got:      %s\n" "$cat_noarg"; ((failed++))
fi
# A read error must not be silently swallowed: a directory opens but read-file
# returns EISDIR, so cat must exit non-zero.
cd_dir="$(mktemp -d)"; mkdir -p "$cd_dir/sub"
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat.fs" "$cd_dir/sub" >/dev/null 2>&1; cat_rderr=$?
rm -rf "$cd_dir"
if [[ "$cat_rderr" != "0" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat.fs read error → non-zero\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat.fs read error → non-zero\n    Expected: non-zero\n    Got:      %s\n" "$cat_rderr"; ((failed++))
fi

# The companion cat-lines.fs reads with READ-LINE instead of READ-FILE. It
# concatenates the same way, but being line-oriented it normalizes CRLF to LF.
cl_dir="$(mktemp -d)"
printf 'AAA\nBBB\n' > "$cl_dir/x"; printf 'one\r\ntwo\r\n' > "$cl_dir/crlf"
t0=$(date +%s.%N)
cl_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat-lines.fs" "$cl_dir/x" "$cl_dir/x" 2>/dev/null)
cl_crlf=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat-lines.fs" "$cl_dir/crlf" 2>/dev/null)
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat-lines.fs" "$cl_dir/nope" >/dev/null 2>&1; cl_miss=$?
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/cat-lines.fs" >/dev/null 2>&1; cl_noarg=$?
rm -rf "$cl_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/cat-lines.fs"

if [[ "$cl_out" == $'AAA\nBBB\nAAA\nBBB' ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat-lines.fs concatenates files\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat-lines.fs concatenates files\n    Expected: AAA<nl>BBB<nl>AAA<nl>BBB\n    Got:      %q\n" "$cl_out"; ((failed++))
fi
if [[ "$cl_crlf" == $'one\ntwo' ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat-lines.fs normalizes CRLF to LF\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat-lines.fs normalizes CRLF to LF\n    Expected: one<nl>two (no CR)\n    Got:      %q\n" "$cl_crlf"; ((failed++))
fi
if [[ "$cl_miss" == "1" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat-lines.fs missing file → exit 1\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat-lines.fs missing file → exit 1\n    Expected: 1\n    Got:      %s\n" "$cl_miss"; ((failed++))
fi
if [[ "$cl_noarg" == "2" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/cat-lines.fs no-args → exit 2\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/cat-lines.fs no-args → exit 2\n    Expected: 2\n    Got:      %s\n" "$cl_noarg"; ((failed++))
fi

# The bundled sort.fs utility: sort a file's lines into <name>_sorted.<ext>.
so_dir="$(mktemp -d)"
printf 'cherry\napple\nbanana\napple\n' > "$so_dir/u.txt"
t0=$(date +%s.%N)
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/sort.fs" "$so_dir/u.txt" >/dev/null 2>&1; sort_exit=$?
sort_out=$(cat "$so_dir/u_sorted.txt" 2>/dev/null)
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/sort.fs" >/dev/null 2>&1; sort_noarg=$?
rm -rf "$so_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/sort.fs"

# byte-order ascending, output written to the _sorted file, exit 0
if [[ "$sort_out" == $'apple\napple\nbanana\ncherry' && "$sort_exit" == "0" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/sort.fs sorts lines\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/sort.fs sorts lines\n    Expected: apple/apple/banana/cherry, exit 0\n    Got:      exit %s / %s\n" "$sort_exit" "$sort_out"; ((failed++))
fi
if [[ "$sort_noarg" == "2" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/sort.fs no-args → exit 2\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/sort.fs no-args → exit 2\n    Expected: 2\n    Got:      %s\n" "$sort_noarg"; ((failed++))
fi

# Read error must fail loudly, not produce empty output with exit 0: a directory
# opens fine but read-file returns EISDIR.
re_dir="$(mktemp -d)"; mkdir -p "$re_dir/sub.txt"
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH "$REPO_ROOT/examples/sort.fs" "$re_dir/sub.txt" >/dev/null 2>&1; sort_rderr=$?
[ -e "$re_dir/sub_sorted.txt" ] && re_made=yes || re_made=no
rm -rf "$re_dir"
if [[ "$sort_rderr" != "0" && "$re_made" == "no" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/sort.fs read error → non-zero, no output\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/sort.fs read error → non-zero, no output\n    Got:      exit %s, output-made=%s\n" "$sort_rderr" "$re_made"; ((failed++))
fi

# examples/tac.fs — the heap showcase. Reverses stdin's lines into a buffer
# that grows via RESIZE (a pipe's size is unknown). Large input forces several
# doublings from the 256-byte start, exercising ALLOCATE / RESIZE / FREE.
tac_small=$(printf 'one\ntwo\nthree\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH "$REPO_ROOT/examples/tac.fs" 2>/dev/null)
tac_nonl=$(printf 'a\nb\nc' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH "$REPO_ROOT/examples/tac.fs" 2>/dev/null)
tac_dir="$(mktemp -d)"
seq 1 2000 > "$tac_dir/big.txt"
awk '{ a[NR]=$0 } END { for (i=NR; i>=1; i--) print a[i] }' "$tac_dir/big.txt" > "$tac_dir/ref.txt"
t0=$(date +%s.%N)
BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH "$REPO_ROOT/examples/tac.fs" < "$tac_dir/big.txt" > "$tac_dir/got.txt" 2>/dev/null
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/tac.fs"
diff -q "$tac_dir/got.txt" "$tac_dir/ref.txt" >/dev/null && tac_big=ok || tac_big=bad
tac_empty=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH "$REPO_ROOT/examples/tac.fs" 2>/dev/null; printf 'X%s' "$?")
rm -rf "$tac_dir"

if [[ "$tac_small" == $'three\ntwo\none' ]]; then
    printf "  ${GREEN}PASS${NC}  examples/tac.fs reverses lines\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/tac.fs reverses lines\n    Expected: three/two/one\n    Got:      %q\n" "$tac_small"; ((failed++))
fi
if [[ "$tac_nonl" == $'cb\na' ]]; then
    printf "  ${GREEN}PASS${NC}  examples/tac.fs no final newline (GNU semantics)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/tac.fs no final newline\n    Expected: cb<nl>a\n    Got:      %q\n" "$tac_nonl"; ((failed++))
fi
if [[ "$tac_big" == "ok" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/tac.fs large input (RESIZE growth)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/tac.fs large input (RESIZE growth)\n"; ((failed++))
fi
if [[ "$tac_empty" == "X0" ]]; then
    printf "  ${GREEN}PASS${NC}  examples/tac.fs empty input → empty, exit 0\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/tac.fs empty input → empty, exit 0\n    Got:      %q\n" "$tac_empty"; ((failed++))
fi
# A stdout write failure must fail loudly, not exit 0 with truncated output.
# /dev/full always returns ENOSPC on write (Linux); skip where it is absent.
if [ -w /dev/full ]; then
    printf 'a\nb\nc\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH "$REPO_ROOT/examples/tac.fs" >/dev/full 2>/dev/null; tac_werr=$?
    if [[ "$tac_werr" != "0" ]]; then
        printf "  ${GREEN}PASS${NC}  examples/tac.fs write error → non-zero exit\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  examples/tac.fs write error → non-zero exit\n    Expected: non-zero\n    Got:      %s\n" "$tac_werr"; ((failed++))
    fi
fi

# Session persistence (SAVE). Capture only runs in an interactive session, so
# the tests force it on through a pipe with BASICFORTH_SESSION=1. session.fs is
# written to the STARTUP directory (the launch CWD), so each run is wrapped in a
# subshell that cd's to a tmpdir before launching the binary.
sv_dir="$(mktemp -d)"
# The harness is invoked with a relative binary path (./basicforth) from the
# build dir; these subshells cd elsewhere, so resolve it to an absolute command.
sv_forth="${FORTH/.\//$PWD/}"
t0=$(date +%s.%N)
# Session 1: a multi-line def, a one-liner, a transient action, and a bare ALLOT
# (moves HERE but defines no word — must NOT be captured); then save.
( cd "$sv_dir" && printf ': dbl dup + ;\n: tri\n  dup dup * *\n;\n42 .\n100 allot\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
sv_file=$(cat "$sv_dir/session.fs" 2>/dev/null)
# Fresh process in the same dir: startup must auto-load the saved definitions.
sv_reload=$( cd "$sv_dir" && printf '7 dbl . 3 tri . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
# Idempotent: reload, define nothing, save again → file unchanged.
cp "$sv_dir/session.fs" "$sv_dir/before"
( cd "$sv_dir" && printf 'save\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
diff -q "$sv_dir/before" "$sv_dir/session.fs" >/dev/null && sv_idem=ok || sv_idem=bad
# Cumulative: a later session adds a word; the file keeps the old ones too.
( cd "$sv_dir" && printf ': sq dup * ;\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
sv_cumul=$(cat "$sv_dir/session.fs")
# Session OFF (no env, piped stdin is not a tty): save is a no-op, no file made.
off_dir="$(mktemp -d)"
( cd "$off_dir" && printf ': zzz 9 ;\nsave\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
[ -e "$off_dir/session.fs" ] && sv_off=made || sv_off=none
# A failed save must not destroy an existing session.fs. Block the temp file by
# pre-creating session.fs.new as a directory, so create-file on it fails.
fail_dir="$(mktemp -d)"
printf 'PRECIOUS\n' > "$fail_dir/session.fs"
mkdir "$fail_dir/session.fs.new"
( cd "$fail_dir" && printf ': c 3 ;\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
sv_safe=$(cat "$fail_dir/session.fs" 2>/dev/null)
rm -rf "$fail_dir"
# An empty (0-byte) session.fs must auto-load cleanly, not wedge the REPL.
# (Regression: forth_included mishandled empty/tiny files, closing a std fd.)
empty_dir="$(mktemp -d)"
: > "$empty_dir/session.fs"
sv_empty=$( cd "$empty_dir" && printf '3 4 + . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
rm -rf "$empty_dir"
# -session / reload loop. Even when a session uses -session and reload, the saved
# file must stay PURE definitions (those lines are never captured).
rl_dir="$(mktemp -d)"
( cd "$rl_dir" && printf ': widget 100 ;\nsave\n-session\nreload\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
rl_pure=$(cat "$rl_dir/session.fs" 2>/dev/null)
# In one session: word works, -session forgets it, reload brings it back.
rl_loop=$( cd "$rl_dir" && printf 'widget .\n-session\nwidget\nreload\nwidget .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
# reload picks up an external edit to session.fs.
printf ': widget 999 ;\n' > "$rl_dir/session.fs"
rl_edit=$( cd "$rl_dir" && printf 'reload\nwidget . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
rm -rf "$rl_dir"
# reload of a session.fs with a compile error must NOT wedge/crash the REPL
# (regression: forth_included left the freed mmap as the source → segfault).
bad_dir="$(mktemp -d)"
printf ': good 1 ;\n: bad nosuchword ;\n' > "$bad_dir/session.fs"
rl_bad=$( cd "$bad_dir" && printf 'reload\n5 6 + . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
rm -rf "$bad_dir"
# reload with NO session.fs must not destroy the live session or wipe the log:
# define a word interactively, reload (file absent), the word must survive.
miss_dir="$(mktemp -d)"
rl_miss=$( cd "$miss_dir" && printf ': keepme 42 ;\nreload\nkeepme . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
rm -rf "$miss_dir"
# Persistence is interactive-only: reload from a NON-interactive run (no
# BASICFORTH_SESSION, piped stdin) must NOT auto-load session.fs.
scope_dir="$(mktemp -d)"
printf ': secret 123 ;\n' > "$scope_dir/session.fs"
rl_scope=$( cd "$scope_dir" && printf 'reload\nsecret . bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
rm -rf "$scope_dir"
# A reload that faults mid-load (stack underflow in session.fs) must not leave
# the one-shot (skip-capture) flag stuck — the next definition must still be
# captured and saved.
stuck_dir="$(mktemp -d)"
printf ': keep 1 ;\ndrop\n' > "$stuck_dir/session.fs"   # 'drop' underflows on load
( cd "$stuck_dir" && printf 'reload\n: persisted 42 ;\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
rl_stuck=$(cat "$stuck_dir/session.fs" 2>/dev/null)
rm -rf "$stuck_dir"
# session.fs is pinned to the STARTUP directory: after a `cd` away, save must
# still write to the launch dir, not the new cwd.
pin_dir="$(mktemp -d)"
pin_away="$(mktemp -d)"
( cd "$pin_dir" && printf ': pinned 7 ;\ncd %s\nsave\nbye\n' "$pin_away" \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
pin_home=$(cat "$pin_dir/session.fs" 2>/dev/null)
[ -e "$pin_away/session.fs" ] && pin_away_made=yes || pin_away_made=no
rm -rf "$pin_dir" "$pin_away"
# Graceful degradation when boot-time getcwd fails (startup dir removed out from
# under the process): (startup-dir) is empty, so the session paths fall back to
# the bare relative name instead of an absolute "/session.fs" that could pollute
# the filesystem root. The REPL must keep working — confirm it still evaluates.
gone_dir="$(mktemp -d)"
gone_out=$( cd "$gone_dir" && rmdir "$gone_dir" && printf '3 4 + .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "session persistence"
rm -rf "$sv_dir" "$off_dir"

if [[ "$sv_file" == *": dbl dup + ;"* && "$sv_file" == *"dup dup * *"* \
      && "$sv_file" != *"42 ."* && "$sv_file" != *"100 allot"* ]]; then
    printf "  ${GREEN}PASS${NC}  SAVE captures definitions (multi-line), not transient actions or bare ALLOT\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SAVE captures definitions, not transient actions/ALLOT\n    Got: %q\n" "$sv_file"; ((failed++))
fi
if [[ "$sv_reload" == *"14"* && "$sv_reload" == *"27"* ]]; then
    printf "  ${GREEN}PASS${NC}  startup reloads saved definitions\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  startup reloads saved definitions\n    Expected 14 and 27\n    Got: %q\n" "$sv_reload"; ((failed++))
fi
if [[ "$sv_idem" == "ok" ]]; then
    printf "  ${GREEN}PASS${NC}  SAVE is idempotent (re-save unchanged)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SAVE is idempotent\n"; ((failed++))
fi
if [[ "$sv_cumul" == *": dbl dup + ;"* && "$sv_cumul" == *": sq dup * ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  SAVE is cumulative across sessions\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SAVE is cumulative across sessions\n    Got: %q\n" "$sv_cumul"; ((failed++))
fi
if [[ "$sv_off" == "none" ]]; then
    printf "  ${GREEN}PASS${NC}  no capture / no session.fs when not interactive\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  unexpected session.fs created when session inactive\n"; ((failed++))
fi
if [[ "$sv_safe" == "PRECIOUS" ]]; then
    printf "  ${GREEN}PASS${NC}  a failed save preserves the existing session.fs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  a failed save destroyed session.fs\n    Got: %q\n" "$sv_safe"; ((failed++))
fi
if [[ "$sv_empty" == *"7"* ]]; then
    printf "  ${GREEN}PASS${NC}  empty session.fs auto-loads without wedging the REPL\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  empty session.fs wedged the REPL\n    Expected 7\n    Got: %q\n" "$sv_empty"; ((failed++))
fi
if [[ "$rl_pure" == *": widget 100 ;"* && "$rl_pure" != *"-session"* && "$rl_pure" != *"reload"* ]]; then
    printf "  ${GREEN}PASS${NC}  session.fs stays pure definitions (no -session/reload lines)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  session.fs polluted with -session/reload\n    Got: %q\n" "$rl_pure"; ((failed++))
fi
if [[ "$rl_loop" == *"100"*"100"* && "$rl_loop" == *"? widget"* ]]; then
    printf "  ${GREEN}PASS${NC}  -session forgets, reload restores (edit/compile/run loop)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  -session/reload loop\n    Expected 100 ... ? widget ... 100\n    Got: %q\n" "$rl_loop"; ((failed++))
fi
if [[ "$rl_edit" == *"999"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload picks up an external edit to session.fs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload did not pick up the edit\n    Expected 999\n    Got: %q\n" "$rl_edit"; ((failed++))
fi
if [[ "$rl_bad" == *"reload:"* && "$rl_bad" == *"11"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload of a bad session.fs warns and the REPL keeps going\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload of a bad session.fs\n    Expected a 'reload:' warning and 11\n    Got: %q\n" "$rl_bad"; ((failed++))
fi
if [[ "$rl_miss" == *"cannot read"* && "$rl_miss" == *"42"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload with no session.fs reports it and keeps the live session\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload with missing session.fs lost the session\n    Expected 'cannot read' and 42\n    Got: %q\n" "$rl_miss"; ((failed++))
fi
if [[ "$rl_scope" == *"no active session"* && "$rl_scope" == *"? secret"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload is a no-op outside an interactive session (scope)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload auto-loaded session.fs outside an interactive session\n    Got: %q\n" "$rl_scope"; ((failed++))
fi
if [[ "$rl_stuck" == *"persisted"* ]]; then
    printf "  ${GREEN}PASS${NC}  a faulting reload does not leave skip-capture stuck\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  definition after a faulting reload was not captured\n    Got: %q\n" "$rl_stuck"; ((failed++))
fi
if [[ "$pin_home" == *": pinned 7 ;"* && "$pin_away_made" == "no" ]]; then
    printf "  ${GREEN}PASS${NC}  save pins session.fs to the startup dir across a cd\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  session.fs not pinned to startup dir after cd\n    home: %q / away-made: %s\n" "$pin_home" "$pin_away_made"; ((failed++))
fi
if [[ "$gone_out" == *"7"* ]]; then
    printf "  ${GREEN}PASS${NC}  REPL survives a failed boot-time getcwd (relative session.fs fallback)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  REPL broke when boot-time getcwd failed\n    Got: %q\n" "$gone_out"; ((failed++))
fi

# SEE — a source lister over the session capture log (interactive scope). The
# REPL echoes input as '> ...', so the SEE-printed source is isolated with
# grep '^...': echoed lines carry the '> ' prefix, SEE's output does not.
see_dir="$(mktemp -d)"
t0=$(date +%s.%N)
# Basic: SEE prints a word's source.
see_basic=$( cd "$see_dir" && printf ': dbl dup + ;\nsee dbl\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: dbl' )
# Redefinition: SEE shows the MOST RECENT definition.
see_redef=$( cd "$see_dir" && printf ': w 1 ;\n: w 2 ;\nsee w\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: w ' )
# Non-colon defining word: the name comes from the header, so the whole line shows.
see_const=$( cd "$see_dir" && printf '42 constant answer\nsee answer\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^42 constant' )
# Unknown word and missing argument are reported, not crashed.
see_unknown=$( cd "$see_dir" && printf 'see nope\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
see_noarg=$( cd "$see_dir" && printf 'see\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
# A word forgotten by -session must NOT show stale source (SEE matches the live
# xt via FIND, so a rewound word is gone). grep '^: gone' isolates any printed
# source; it must be empty, and the message must say not found.
see_forgot=$( cd "$see_dir" && printf ': gone 7 ;\n-session\nsee gone\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
see_forgot_src=$(printf '%s\n' "$see_forgot" | grep '^: gone' || true)
# Redefine inside a marker scope, then forget the latest: SEE must show the LIVE
# (older, still-defined) version, not the forgotten redefinition.
see_live=$( cd "$see_dir" && printf ': v 1 ;\nmarker -m\n: v 2 ;\n-m\nsee v\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: v ' )
# Multiple definitions on one input line: SEE must find EACH word, not only the
# last (regression — the capture index used to record only the final LATEST, so
# SEE of the earlier word reported "not found"). m1 is the non-last definition.
see_multi=$( cd "$see_dir" && printf ': m1 1 ;  : m2 2 ;\nsee m1\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: m1' )
# An assembly primitive (no source span in its metadata) is labelled as such,
# distinct from "not found".
see_prim=$( cd "$see_dir" && printf 'see dup\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
# A core.fs word is now shown straight from its source file (source metadata).
see_core=$( cd "$see_dir" && printf 'see spaces\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: SPACES' )
# Using SEE must not capture itself into the saved file.
( cd "$see_dir" && printf ': keep 5 ;\nsee keep\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
see_pure=$(cat "$see_dir/session.fs" 2>/dev/null)
# Seeded definitions: SEE must also cover words loaded from session.fs at startup
# (indexed by (index-seeded), not interactive capture). Separate dir with a
# pre-existing session.fs; grep '^...' isolates SEE's printed source from echoes.
seed_dir="$(mktemp -d)"
printf ': sgreet ." hi" cr ;\nvariable sv\n7 constant sc\n' > "$seed_dir/session.fs"
see_sc=$( cd "$seed_dir" && printf 'see sgreet\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: sgreet' )
see_sv=$( cd "$seed_dir" && printf 'see sv\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^variable sv' )
see_sk=$( cd "$seed_dir" && printf 'see sc\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^7 constant sc' )
# ';' inside a string must not truncate the seeded definition's span.
printf ': sstr ." a; b" cr ;\n' > "$seed_dir/session.fs"
see_sstr=$( cd "$seed_dir" && printf 'see sstr\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: sstr' )
# reload re-indexes: seeded words stay see-able after a reload.
printf ': sre 1 ;\n' > "$seed_dir/session.fs"
see_sre=$( cd "$seed_dir" && printf 'reload\nsee sre\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: sre' )
# Case-insensitive defining words: an uppercase VARIABLE (valid Forth) must index.
printf 'VARIABLE su\n' > "$seed_dir/session.fs"
see_su=$( cd "$seed_dir" && printf 'see su\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^VARIABLE su' )
# Custom defining words: a word made by a *user-defined* defining word, loaded
# from session.fs, is now see-able via source metadata — the case the text-parse
# seeded-SEE MVP could not handle.
printf ': mk create , does> @ ;\n5 mk five\n' > "$seed_dir/session.fs"
see_cdw=$( cd "$seed_dir" && printf 'see five\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^5 mk five' )
rm -rf "$seed_dir"
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "SEE"
rm -rf "$see_dir"

if [[ "$see_basic" == ": dbl dup + ;" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE prints a word's source\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE prints a word's source\n    Expected ': dbl dup + ;'\n    Got: %q\n" "$see_basic"; ((failed++))
fi
if [[ "$see_redef" == ": w 2 ;" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows the most recent definition\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE shows the most recent definition\n    Expected ': w 2 ;'\n    Got: %q\n" "$see_redef"; ((failed++))
fi
if [[ "$see_multi" == ": m1 1 ;  : m2 2 ;" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE finds a non-last definition on a shared line\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE finds a non-last definition on a shared line\n    Expected ': m1 1 ;  : m2 2 ;'\n    Got: %q\n" "$see_multi"; ((failed++))
fi
if [[ "$see_prim" == *"is a primitive (assembly)"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE labels an assembly primitive\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE primitive label\n    Expected 'is a primitive (assembly)'\n    Got: %q\n" "$see_prim"; ((failed++))
fi
if [[ "$see_core" == ": SPACES"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows a core.fs word from its source file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE core.fs word\n    Expected a line starting ': SPACES'\n    Got: %q\n" "$see_core"; ((failed++))
fi
if [[ "$see_const" == "42 constant answer" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE handles a non-colon defining word\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE handles a non-colon defining word\n    Expected '42 constant answer'\n    Got: %q\n" "$see_const"; ((failed++))
fi
if [[ "$see_unknown" == *"not found"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE of an unknown word reports not found\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE of an unknown word\n    Expected 'not found'\n    Got: %q\n" "$see_unknown"; ((failed++))
fi
if [[ "$see_noarg" == *"needs a word name"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE with no argument reports it\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE with no argument\n    Expected 'needs a word name'\n    Got: %q\n" "$see_noarg"; ((failed++))
fi
if [[ "$see_pure" == *": keep 5 ;"* && "$see_pure" != *"see"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE does not capture itself into session.fs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE leaked into session.fs\n    Got: %q\n" "$see_pure"; ((failed++))
fi
if [[ -z "$see_forgot_src" && "$see_forgot" == *"not found"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows no stale source for a forgotten word\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE showed stale source after the word was forgotten\n    Got: %q\n" "$see_forgot"; ((failed++))
fi
if [[ "$see_live" == ": v 1 ;" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows the live definition, not a forgotten redefinition\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE showed a forgotten redefinition instead of the live word\n    Expected ': v 1 ;'\n    Got: %q\n" "$see_live"; ((failed++))
fi
if [[ "$see_sc" == ': sgreet ." hi" cr ;' ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows a seeded colon definition (loaded from session.fs)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE of a seeded colon definition\n    Got: %q\n" "$see_sc"; ((failed++))
fi
if [[ "$see_sv" == "variable sv" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows a seeded variable\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE of a seeded variable\n    Expected 'variable sv'\n    Got: %q\n" "$see_sv"; ((failed++))
fi
if [[ "$see_sk" == "7 constant sc" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows a seeded constant (with its value)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE of a seeded constant\n    Expected '7 constant sc'\n    Got: %q\n" "$see_sk"; ((failed++))
fi
if [[ "$see_sstr" == ': sstr ." a; b" cr ;' ]]; then
    printf "  ${GREEN}PASS${NC}  SEE seeded span is not truncated by a ';' inside a string\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE seeded span truncated at a ';' inside a string\n    Got: %q\n" "$see_sstr"; ((failed++))
fi
if [[ "$see_sre" == ": sre 1 ;" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE re-indexes seeded definitions after reload\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE lost seeded definitions after reload\n    Expected ': sre 1 ;'\n    Got: %q\n" "$see_sre"; ((failed++))
fi
if [[ "$see_su" == "VARIABLE su" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE indexes an uppercase defining word (case-insensitive)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE missed an uppercase defining word\n    Expected 'VARIABLE su'\n    Got: %q\n" "$see_su"; ((failed++))
fi
if [[ "$see_cdw" == "5 mk five" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows a custom-defining-word word from session.fs\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE custom-defining-word word\n    Expected '5 mk five'\n    Got: %q\n" "$see_cdw"; ((failed++))
fi

# =========================================================================
section "REDO (recompile a captured word from its source)"
# =========================================================================
# Capture is interactive-only, so force it on via BASICFORTH_SESSION=1 (as the
# SEE/SAVE tests do). REDO re-evaluates a word's saved source so a caller picks
# up a redefined leaf — subroutine threading bakes call targets, so the caller
# would otherwise keep calling the old leaf.
redo_dir="$(mktemp -d)"
# A caller recompiled by REDO calls the NEW leaf (prints 9). Result lines have no
# '> ' echo prefix, so '^9' isolates the printed value.
redo_recompile=$( cd "$redo_dir" && printf ': lf 1 ;\n: cl lf ;\n: lf 9 ;\nredo cl\ncl .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^9' )
# Baseline: without REDO the caller still calls the old leaf (prints 1).
redo_stale=$( cd "$redo_dir" && printf ': lf 1 ;\n: cl lf ;\n: lf 9 ;\ncl .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^1' )
# SEE still shows the source after REDO (log record repointed; the 'redo' line
# itself is not captured as the new source).
redo_see=$( cd "$redo_dir" && printf ': lf 1 ;\n: cl lf ;\nredo cl\nsee cl\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^: cl' )
# Decline paths: primitive, file-loaded word, unknown word.
redo_prim=$( cd "$redo_dir" && printf 'redo dup\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
redo_file=$( cd "$redo_dir" && printf 'redo cr\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
redo_unknown=$( cd "$redo_dir" && printf 'redo nope\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )
rm -rf "$redo_dir"

if [[ "$redo_recompile" == 9* ]]; then
    printf "  ${GREEN}PASS${NC}  REDO recompiles a caller against a redefined leaf\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  REDO did not recompile the caller\n    Expected '9...'\n    Got: %q\n" "$redo_recompile"; ((failed++))
fi
if [[ "$redo_stale" == 1* ]]; then
    printf "  ${GREEN}PASS${NC}  baseline: without REDO the caller keeps the old leaf\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  stale-caller baseline\n    Got: %q\n" "$redo_stale"; ((failed++))
fi
if [[ "$redo_see" == ": cl lf ;" ]]; then
    printf "  ${GREEN}PASS${NC}  SEE shows the source after REDO\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE source lost/corrupted after REDO\n    Expected ': cl lf ;'\n    Got: %q\n" "$redo_see"; ((failed++))
fi
if [[ "$redo_prim" == *"is a primitive"* ]]; then
    printf "  ${GREEN}PASS${NC}  REDO declines a primitive\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  REDO primitive decline\n    Got: %q\n" "$redo_prim"; ((failed++))
fi
if [[ "$redo_file" == *"loaded from a file"* ]]; then
    printf "  ${GREEN}PASS${NC}  REDO declines a file-loaded word\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  REDO file-word decline\n    Got: %q\n" "$redo_file"; ((failed++))
fi
if [[ "$redo_unknown" == *"not found"* ]]; then
    printf "  ${GREEN}PASS${NC}  REDO of an unknown word reports not found\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  REDO unknown word\n    Got: %q\n" "$redo_unknown"; ((failed++))
fi

# =========================================================================
section "Persistence of state-setting words (to / is)"
# =========================================================================
# save now records direct TO/IS assignments (not just definitions), so a value's
# contents and a deferred word's action survive save+reload. Forced on with
# BASICFORTH_SESSION=1 like the other persistence tests; each runs a session that
# saves, then a fresh session that auto-loads the written session.fs.
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf '0 value pv\n7 to pv\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_to=$( cd "$ps_dir" && printf 'pv .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^7' )
rm -rf "$ps_dir"
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf 'defer pg\n: ph pg ;\n:noname 42 ; is pg\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_is=$( cd "$ps_dir" && printf 'ph .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^42' )
rm -rf "$ps_dir"
# Over-capture guard: a TO *inside* a called word compiles a store (not forth_to),
# so calling it neither logs a 'setpc' command line nor persists the runtime value.
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf '0 value pc\n: setpc 9 to pc ;\nsetpc\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_call_line=$(grep -c '^setpc$' "$ps_dir/session.fs")
ps_reload=$( cd "$ps_dir" && printf 'pc .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep '^0' )
rm -rf "$ps_dir"
# Errored assignment must not leak: the following transient line is not captured.
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf '0 value pe\n5 to pe zzz\n1 2 + .\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_leak=$(grep -cE '1 2 \+|5 to pe' "$ps_dir/session.fs")
rm -rf "$ps_dir"

if [[ "$ps_to" == 7* ]]; then
    printf "  ${GREEN}PASS${NC}  TO assignment persists across save/reload\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  TO did not persist\n    Expected '7...'\n    Got: %q\n" "$ps_to"; ((failed++))
fi
if [[ "$ps_is" == 42* ]]; then
    printf "  ${GREEN}PASS${NC}  IS assignment (defer action) persists across save/reload\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  IS did not persist\n    Expected '42...'\n    Got: %q\n" "$ps_is"; ((failed++))
fi
if [[ "$ps_call_line" == "0" && "$ps_reload" == 0* ]]; then
    printf "  ${GREEN}PASS${NC}  a TO inside a called word is not over-captured\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  over-capture guard\n    call-line count: %q  reload: %q\n" "$ps_call_line" "$ps_reload"; ((failed++))
fi
if [[ "$ps_leak" == "0" ]]; then
    printf "  ${GREEN}PASS${NC}  an errored assignment line does not leak into capture\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  errored-assignment leak\n    matched lines: %q\n" "$ps_leak"; ((failed++))
fi

# =========================================================================
section "Snake Game Prerequisites (cont.)"
# =========================================================================
# Snake game words (test game helpers without loading the full file)
assert_output "snake screen-pos"     ': screen-pos 80 * + ; 5 3 screen-pos .'   "245"


# =========================================================================
section "Startup: core.fs-not-found warning"
# =========================================================================
# The binary holds only the asm primitives; everything else is in core.fs, found
# via CWD then BASICFORTH_PATH. If it's reachable nowhere, the load is silently
# skipped — so warn on stderr instead of leaving a mysteriously crippled REPL.
# Resolve the binary to an absolute command (FORTH is "./basicforth" or
# "qemu-... ./basicforth"); these subshells cd into a tmpdir with no core.fs.
warn_forth="${FORTH/.\//$PWD/}"
warn_dir="$(mktemp -d)"
# No core.fs reachable (empty CWD, BASICFORTH_PATH unset) → warning on stderr.
# `2>&1 1>/dev/null` keeps stderr only, so the banner/ok (stdout) can't match.
warn_missing=$( cd "$warn_dir" && printf 'bye\n' \
    | env -u BASICFORTH_PATH timeout 5 $warn_forth 2>&1 1>/dev/null )
# core.fs found via BASICFORTH_PATH → no warning on stderr.
warn_found=$( cd "$warn_dir" && printf 'bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $warn_forth 2>&1 1>/dev/null )
# An empty core.fs in CWD opens but defines nothing — it was FOUND, so no warning
# (detection keys off the file being opened, not off any word being defined).
warn_empty_dir="$(mktemp -d)"
: > "$warn_empty_dir/core.fs"
warn_empty=$( cd "$warn_empty_dir" && printf 'bye\n' \
    | env -u BASICFORTH_PATH timeout 5 $warn_forth 2>&1 1>/dev/null )
rm -rf "$warn_dir" "$warn_empty_dir"

if [[ "$warn_missing" == *"core.fs not found"* && "$warn_missing" == *"BASICFORTH_PATH"* ]]; then
    printf "  ${GREEN}PASS${NC}  warns on stderr when core.fs is not found\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  expected a core.fs-not-found warning on stderr\n    Got: %q\n" "$warn_missing"; ((failed++))
fi
if [[ -z "$warn_found" ]]; then
    printf "  ${GREEN}PASS${NC}  no warning when core.fs is found\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  spurious stderr when core.fs present\n    Got: %q\n" "$warn_found"; ((failed++))
fi
if [[ -z "$warn_empty" ]]; then
    printf "  ${GREEN}PASS${NC}  no warning when core.fs is empty (found, defines nothing)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  spurious warning for an empty but present core.fs\n    Got: %q\n" "$warn_empty"; ((failed++))
fi


# =========================================================================
section "Help system (man / topics / apropos)"
# =========================================================================

# Build a throwaway docs directory with two .md topics plus a non-.md file
# that must be ignored.
docs_dir="$(mktemp -d)"
printf '# Widgets\nThe widget subsystem and its gears.\n' > "$docs_dir/Widgets.md"
printf '# Sound\nNothing relevant in this one.\n'         > "$docs_dir/Sound.md"
printf 'ignore me\n'                                      > "$docs_dir/notes.txt"

# docs_check NAME INPUT EXPECTED — run with BASICFORTH_DOCS pointed at docs_dir
docs_check() {
    local name="$1" input="$2" expected="$3"
    local t0 t1 ms output
    t0=$(date +%s.%N)
    output=$(printf '%s\n' "$input" | BASICFORTH_PATH="$FORTH_LIB" \
        BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
    t1=$(date +%s.%N)
    ms=$(elapsed_ms "$t0" "$t1")
    update_slowest "$ms" "$name"
    if [[ "$output" == *"$expected"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s\n" "$name"
        printf "    Input:    %s\n" "$input"
        printf "    Expected: %s\n" "$expected"
        printf "    Got:      %s\n" "$(echo "$output" | head -5)"
        ((failed++))
    fi
}

docs_check "topics lists .md topics"       "topics" "Widgets"
docs_check "topics ignores non-.md"        "topics" "Sound"
docs_check "man pages a topic"             "man Widgets" "widget subsystem and its gears"
docs_check "man is case-insensitive"       "man widgets" "widget subsystem and its gears"
docs_check "man on missing topic"          "man nope" "no help for nope"
docs_check "apropos finds a match"         "apropos gears" "Widgets"
docs_check "apropos is case-insensitive"   "apropos GEARS" "Widgets"

# notes.txt is not a topic
notes_out=$(printf 'topics\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$notes_out" != *"notes"* ]]; then
    printf "  ${GREEN}PASS${NC}  topics excludes notes.txt\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  topics excludes notes.txt\n"; ((failed++))
fi

# apropos must not list a file that lacks the keyword
ap_out=$(printf 'apropos gears\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$ap_out" != *"Sound"* ]]; then
    printf "  ${GREEN}PASS${NC}  apropos omits non-matching topic\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  apropos omits non-matching topic\n"; ((failed++))
fi

# Unset BASICFORTH_DOCS — every command reports it gracefully
unset_out=$(printf 'topics\n' | BASICFORTH_PATH="$FORTH_LIB" \
    env -u BASICFORTH_DOCS timeout 2 $FORTH 2>&1)
if [[ "$unset_out" == *"BASICFORTH_DOCS not set"* ]]; then
    printf "  ${GREEN}PASS${NC}  topics with no BASICFORTH_DOCS\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  topics with no BASICFORTH_DOCS\n"
    printf "    Got:      %s\n" "$(echo "$unset_out" | head -3)"; ((failed++))
fi

# Long docs path must not overflow the internal path buffer. Pad the directory
# with resolvable "/." segments so the directory still opens (the kernel/open
# clamp keeps it valid) while the segment length exceeds the path-build buffer.
# Before the bounds check this corrupted the dictionary; now man/apropos just
# find nothing and the REPL stays alive.
long_docs="$docs_dir"
while [ "${#long_docs}" -lt 600 ]; do long_docs="$long_docs/."; done
long_out=$(printf 'man Widgets\napropos gears\n42 .\nbye\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$long_docs" timeout 2 $FORTH 2>&1)
long_status=$?
if [ "$long_status" -eq 0 ] && [[ "$long_out" == *"42"* ]] && [[ "$long_out" == *"Goodbye!"* ]]; then
    printf "  ${GREEN}PASS${NC}  long docs path does not corrupt memory\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  long docs path does not corrupt memory\n"
    printf "    exit %s, output: %s\n" "$long_status" "$(echo "$long_out" | head -3)"; ((failed++))
fi

# Section grouping: topics groups topics under their directory (section) name,
# and apropos labels each hit with its section. Use two named subdirectories
# plus an empty one (no .md → no header).
sec_base="$(mktemp -d)"
mkdir -p "$sec_base/RefSec" "$sec_base/TutSec" "$sec_base/EmptySec"
printf '# Alpha\nwidget gear\n' > "$sec_base/RefSec/Alpha.md"
printf '# Beta\nmore widget\n'  > "$sec_base/RefSec/Beta.md"
printf '# Lesson\nnothing\n'    > "$sec_base/TutSec/Lesson.md"
printf 'not a topic\n'          > "$sec_base/EmptySec/readme.txt"
sec_docs="$sec_base/RefSec:$sec_base/TutSec:$sec_base/EmptySec"

sec_out=$(printf 'topics\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sec_docs" timeout 2 $FORTH 2>&1)
if [[ "$sec_out" == *"RefSec"* ]] && [[ "$sec_out" == *"TutSec"* ]] \
   && [[ "$sec_out" == *"Alpha"* ]] && [[ "$sec_out" == *"Lesson"* ]]; then
    printf "  ${GREEN}PASS${NC}  topics groups under section headers\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  topics groups under section headers\n"
    printf "    Got:      %s\n" "$(echo "$sec_out" | head -6)"; ((failed++))
fi

# An empty section (no .md) must not print a header
if [[ "$sec_out" != *"EmptySec"* ]]; then
    printf "  ${GREEN}PASS${NC}  topics omits empty section header\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  topics omits empty section header\n"; ((failed++))
fi

# apropos labels each hit with its section
aps_out=$(printf 'apropos widget\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sec_docs" timeout 2 $FORTH 2>&1)
if [[ "$aps_out" == *"Alpha (RefSec)"* ]] && [[ "$aps_out" == *"Beta (RefSec)"* ]]; then
    printf "  ${GREEN}PASS${NC}  apropos labels hits with section\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  apropos labels hits with section\n"
    printf "    Got:      %s\n" "$(echo "$aps_out" | head -4)"; ((failed++))
fi

# topics sorts names alphabetically within a section, regardless of the order
# the filesystem returns them. Create them out of order and expect them sorted.
sort_base="$(mktemp -d)"
for n in Zebra Apple Mango; do printf '# %s\n' "$n" > "$sort_base/$n.md"; done
sort_out=$(printf 'topics\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sort_base" timeout 2 $FORTH 2>&1)
if [[ "$sort_out" == *"Apple Mango Zebra"* ]]; then
    printf "  ${GREEN}PASS${NC}  topics sorts names within a section\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  topics sorts names within a section\n"
    printf "    Got:      %s\n" "$(echo "$sort_out" | head -4)"; ((failed++))
fi
rm -rf "$sort_base"

rm -rf "$sec_base"

# A "topic" that is actually a directory: open() succeeds but read() returns
# EISDIR. man must report it via page-file's "(read error)" and the REPL must
# keep running afterward — a regression guard for page-file no longer aborting
# through (man-in) (which would skip its directory-fd cleanup and leak it).
mkdir "$docs_dir/Brokendir.md"
brk_out=$(printf 'man Brokendir\n9 9 + .\nbye\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$brk_out" == *"(read error)"* && "$brk_out" == *"18"* ]]; then
    printf "  ${GREEN}PASS${NC}  man on a directory-topic reports read error, REPL survives\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  man on a directory-topic (page-file cleanup)\n    Got: %s\n" "$(echo "$brk_out" | head -5)"; ((failed++))
fi

rm -rf "$docs_dir"

# =========================================================================
section "Interactive tutorial (tutorial / next / back)"
# =========================================================================

# A tutorial file is just a docs .md walked one "## " step at a time. Step 1 is
# the title + intro before the first heading; each "## " starts a new step.
tut_dir="$(mktemp -d)"
printf '# Lesson One\nintro line about FOO\n## Step Two\ncontent TWO here\n## Step Three\ncontent THREE here\n' \
    > "$tut_dir/Lesson.md"

# tut_check NAME INPUT EXPECTED — run with BASICFORTH_DOCS pointed at tut_dir
tut_check() {
    local name="$1" input="$2" expected="$3"
    local output
    output=$(printf '%s\n' "$input" | BASICFORTH_PATH="$FORTH_LIB" \
        BASICFORTH_DOCS="$tut_dir" timeout 2 $FORTH 2>&1)
    if [[ "$output" == *"$expected"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s\n" "$name"
        printf "    Input:    %s\n" "$input"
        printf "    Expected: %s\n" "$expected"
        printf "    Got:      %s\n" "$(echo "$output" | head -6)"; ((failed++))
    fi
}

tut_check "tutorial shows step 1"          "tutorial Lesson"                 "intro line about FOO"
tut_check "tutorial step 1 footer"         "tutorial Lesson"                 "step 1"
tut_check "tutorial name is case-insens."  "tutorial lesson"                 "intro line about FOO"
tut_check "next advances to step 2"        $'tutorial Lesson\nnext'          "content TWO here"
tut_check "next twice reaches step 3"      $'tutorial Lesson\nnext\nnext'    "content THREE here"
tut_check "next past end reports end"      $'tutorial Lesson\nnext\nnext\nnext' "end of 'Lesson'"
tut_check "back returns to previous step"  $'tutorial Lesson\nnext\nback'    "intro line about FOO"
# A heading line marks a boundary but is itself shown as that step's title
tut_check "step heading is shown"          $'tutorial Lesson\nnext'          "## Step Two"
# After a step the REPL is live again — a following command runs normally
tut_check "REPL live between steps"        $'tutorial Lesson\n7 8 + .'       "15"
tut_check "next before start hints"        "next"                            "start a tutorial first"
tut_check "back before start hints"        "back"                            "start a tutorial first"
tut_check "unknown tutorial name"          "tutorial nope"                   "no tutorial named nope"

# back at step 1 stays at step 1 (does not underflow)
tut_b1=$(printf 'tutorial Lesson\nback\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$tut_dir" timeout 2 $FORTH 2>&1)
if [[ "$tut_b1" == *"step 1"* ]] && [[ "$tut_b1" != *"step 0"* ]]; then
    printf "  ${GREEN}PASS${NC}  back at step 1 stays at step 1\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  back at step 1 stays at step 1\n"
    printf "    Got:      %s\n" "$(echo "$tut_b1" | head -4)"; ((failed++))
fi

# Unset BASICFORTH_DOCS — tutorial reports it gracefully
tut_unset=$(printf 'tutorial Lesson\n' | BASICFORTH_PATH="$FORTH_LIB" \
    env -u BASICFORTH_DOCS timeout 2 $FORTH 2>&1)
if [[ "$tut_unset" == *"BASICFORTH_DOCS not set"* ]]; then
    printf "  ${GREEN}PASS${NC}  tutorial with no BASICFORTH_DOCS\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tutorial with no BASICFORTH_DOCS\n"
    printf "    Got:      %s\n" "$(echo "$tut_unset" | head -3)"; ((failed++))
fi

rm -rf "$tut_dir"

# =========================================================================
section "Shell Words"
# =========================================================================
# pwd / cd navigate the real process directory. `cd` with no argument returns to
# the startup directory (where BasicForth was launched), not $HOME. The startup
# dir here is the directory the test runs in (its physical, symlink-resolved
# path, to match what getcwd reports).
shell_start=$(pwd -P)

# pwd prints the current (startup) directory
assert_output "pwd shows cwd"          "pwd"                              "$shell_start"
# cd changes directory; pwd reflects it
assert_output "cd changes dir"         $'cd /tmp\npwd'                    "/tmp"
# a failed cd reports the offending path
assert_output "cd bad path errors"     "cd /no/such/dir"                 "cd: cannot access /no/such/dir"
# bare cd returns to the startup directory (proves cd state really changes:
# shell_start is not present in the input, so this can't pass on echo alone)
assert_output "bare cd goes home"      $'cd /tmp\ncd\npwd'               "$shell_start"

# cd ~ expands to $HOME. Match $HOME + newline so it isn't satisfied by
# shell_start (which lives *under* $HOME, i.e. contains it as a prefix). Use the
# physical path to match what getcwd reports even if $HOME is a symlink.
th_home=$(cd "$HOME" 2>/dev/null && pwd -P)
th_tilde=$(run_forth $'cd ~\npwd')
if [[ -n "$th_home" && "$th_tilde" == *"$th_home"$'\n'* ]]; then
    printf "  ${GREEN}PASS${NC}  cd ~ expands to \$HOME\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cd ~ did not go to \$HOME (%s)\n    Got: %q\n" "$th_home" "$th_tilde"; ((failed++))
fi
# cd ~ with HOME unset: ~ is left as-is, chdir fails, and it aborts (no " ok").
th_unset=$(printf 'cd ~\n' | env -u HOME BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH 2>&1)
if [[ "$th_unset" == *"cd: cannot access ~"* && "$th_unset" != *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  cd ~ with HOME unset errors gracefully\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cd ~ with HOME unset\n    Got: %q\n" "$th_unset"; ((failed++))
fi
# Only "~" / "~/..." expand. "~user" is a different, unsupported form: it must be
# left UNCHANGED (not concatenated onto $HOME), so cd errors on the literal token.
th_user=$(printf 'cd ~nobody\n' | HOME=/home/x BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH 2>&1)
if [[ "$th_user" == *"cd: cannot access ~nobody"* ]]; then
    printf "  ${GREEN}PASS${NC}  cd ~user is left unchanged (no \$HOME concatenation)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cd ~user mis-expanded\n    Got: %q\n" "$th_user"; ((failed++))
fi
# A pathologically long $HOME must not overflow the expansion buffer: the
# expansion is skipped and cd errors, and the REPL stays alive (prints 4 after).
th_big_home=$(printf '/%.0s' {1..1500})
th_big=$(printf 'cd ~\n2 2 + .\n' | HOME="$th_big_home" BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH 2>&1)
if [[ "$th_big" == *"cannot access"* && "$th_big" == *"4"* ]]; then
    printf "  ${GREEN}PASS${NC}  long \$HOME does not overflow ~ expansion\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  long \$HOME overflowed or crashed\n    Got: %q\n" "$th_big"; ((failed++))
fi
# Off-by-one boundary: the expanded path must fit chdir's buffer *with its NUL*,
# so the usable max is one less than the buffer (1024). A $HOME of exactly 1024
# must be rejected (~ left as-is -> "cannot access ~"), not expanded to a
# 1024-char path. (1023 would expand; this guards the >= vs > boundary.)
th_bound_home=$(printf 'Z%.0s' $(seq 1 1024))
th_bound=$(printf 'cd ~\n' | HOME="$th_bound_home" BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH 2>&1)
if [[ "$th_bound" == *"cannot access ~"* && "$th_bound" != *"ZZZ"* ]]; then
    printf "  ${GREEN}PASS${NC}  cd ~ rejects \$HOME at the length boundary (no off-by-one)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cd ~ boundary off-by-one\n    Got: %q\n" "$th_bound"; ((failed++))
fi
# ~ expansion is uniform across the path-taking words, not just cd (regression:
# only cd expanded ~, so `pushd ~`/`ls ~`/`cat ~` failed). pushd ~ -> $HOME; and
# cat ~ expands to $HOME (a directory) so it reaches the read-error path -- an
# UNexpanded "~" would instead be "cannot open file", so this proves expansion.
ps_tilde=$(run_forth $'pushd ~\npwd')
if [[ -n "$th_home" && "$ps_tilde" == *"$th_home"$'\n'* ]]; then
    printf "  ${GREEN}PASS${NC}  pushd ~ expands to \$HOME\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  pushd ~ did not expand\n    Got: %q\n" "$ps_tilde"; ((failed++))
fi
cat_tilde=$(run_forth "cat ~")
if [[ "$cat_tilde" == *"cat: read error"* ]]; then
    printf "  ${GREEN}PASS${NC}  cat ~ expands (~ -> \$HOME dir, hits read error)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cat ~ did not expand\n    Got: %q\n" "$cat_tilde"; ((failed++))
fi

# ls / cat / more over a temp dir with known contents (absolute paths, so the
# binary's own CWD doesn't matter). The expected strings are file *contents* or
# entry names, none of which appear in the echoed input line.
fw_dir="$(mktemp -d)"
printf 'hello\nworld\n' > "$fw_dir/greet.txt"
mkdir "$fw_dir/sub"
assert_output "ls lists a directory"     "ls $fw_dir"               "greet.txt"
assert_output "ls shows subdirectories"  "ls $fw_dir"               "sub"
assert_output "cat dumps a file"         "cat $fw_dir/greet.txt"    "world"
assert_output "more pages a file"        "more $fw_dir/greet.txt"   "hello"
assert_output "cat missing file errors"  "cat $fw_dir/nope.txt"     "cat: cannot open file"
assert_output "ls missing dir errors"    "ls $fw_dir/nope"          "ls: cannot open directory"
# cat on a directory: open() succeeds but read() fails (EISDIR). Must surface the
# error, not silently stop and report success (a read error swallowed by the loop).
assert_output "cat surfaces read error"  "cat $fw_dir/sub"          "cat: read error"

# Error paths must ABORT (signal failure to the REPL), not print " ok" as if the
# command succeeded. Check the message IS shown and " ok" is NOT, while a
# successful command still prints " ok" (control).
ab_cat=$(run_forth "cat $fw_dir/sub")        # cat a directory -> read error + abort
ab_cd=$(run_forth "cd /no/such/dir")         # cd failure -> abort
ab_more=$(run_forth "more $fw_dir/sub")      # more a directory -> page-file read error + abort
ab_ok=$(run_forth "ls $fw_dir")              # success still prints " ok"
rm -rf "$fw_dir"
if [[ "$ab_cat" == *"cat: read error"* && "$ab_cat" != *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  cat error aborts (no \" ok\")\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cat error returned success to the REPL\n    Got: %q\n" "$ab_cat"; ((failed++))
fi
if [[ "$ab_more" == *"(read error)"* && "$ab_more" != *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  more error aborts (no \" ok\")\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  more error returned success to the REPL\n    Got: %q\n" "$ab_more"; ((failed++))
fi
if [[ "$ab_cd" == *"cd: cannot access"* && "$ab_cd" != *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  cd error aborts (no \" ok\")\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cd error returned success to the REPL\n    Got: %q\n" "$ab_cd"; ((failed++))
fi
if [[ "$ab_ok" == *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  successful shell word still prints \" ok\"\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  success path lost its \" ok\"\n    Got: %q\n" "$ab_ok"; ((failed++))
fi

# Directory stack: pushd <dir> records the current dir (absolute) and cd's there;
# popd returns to it; dirs lists current + saved. shell_start is the startup dir
# and never appears in the echoed input, so checking it proves the stack really
# recorded/restored the old dir (not an echo artifact).
ps_dir="$(mktemp -d)"
ps_dirs=$(run_forth $'pushd '"$ps_dir"$'\ndirs')        # dirs must list the saved startup dir
ps_pop=$(run_forth $'pushd '"$ps_dir"$'\npopd\npwd')    # popd returns to the startup dir
ps_empty=$(run_forth "popd")                            # popd on empty stack -> abort
ps_bad=$(run_forth "pushd /no/such/dir")                # pushd missing dir -> abort
rm -rf "$ps_dir"
if [[ "$ps_dirs" == *"$shell_start"* ]]; then
    printf "  ${GREEN}PASS${NC}  pushd records dir, dirs lists it\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  dirs did not list the pushed dir\n    Got: %q\n" "$ps_dirs"; ((failed++))
fi
if [[ "$ps_pop" == *"$shell_start"* ]]; then
    printf "  ${GREEN}PASS${NC}  popd returns to the pushed-from dir\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  popd did not return home\n    Got: %q\n" "$ps_pop"; ((failed++))
fi
if [[ "$ps_empty" == *"directory stack empty"* && "$ps_empty" != *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  popd on empty stack aborts (no \" ok\")\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  popd on empty stack\n    Got: %q\n" "$ps_empty"; ((failed++))
fi
if [[ "$ps_bad" == *"pushd: cannot access"* && "$ps_bad" != *" ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  pushd to a missing dir aborts (no \" ok\")\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  pushd to a missing dir\n    Got: %q\n" "$ps_bad"; ((failed++))
fi

# popd must NOT lose the saved dir if the restore chdir fails. Deterministic via
# a coproc: pushd, wait for its " ok", remove the saved dir, then popd — the
# entry must survive (still listed by dirs after the failed restore). timeout
# guards against a hang if " ok" never arrives.
pp_from="$(mktemp -d)"; pp_to="$(mktemp -d)"
# $sv_forth is the absolute binary command (the coproc cd's away, so ./basicforth
# would not resolve); set earlier in the session-persistence section.
coproc PP { cd "$pp_from" && BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1; }
printf 'pushd %s\n' "$pp_to" >&"${PP[1]}"
while IFS= read -r -u "${PP[0]}" pp_ln; do [[ "$pp_ln" == *" ok"* ]] && break; done
rmdir "$pp_from"                                   # saved dir vanishes before popd
printf 'dirs\npopd\ndirs\nbye\n' >&"${PP[1]}"
pp_out=""; while IFS= read -r -u "${PP[0]}" pp_ln; do pp_out+="$pp_ln"$'\n'; done
wait "$PP_PID" 2>/dev/null
rm -rf "$pp_to"
pp_after=${pp_out#*cannot restore directory}       # text printed after the failed popd
if [[ "$pp_out" == *"cannot restore directory"* && "$pp_after" == *"$pp_from"* ]]; then
    printf "  ${GREEN}PASS${NC}  popd keeps the saved dir when restore fails\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  popd lost the saved dir on restore failure\n    Got: %q\n" "$pp_out"; ((failed++))
fi

# =========================================================================
section "Version"
# =========================================================================
# -v / --version print the banner string to stdout and exit 0, before any
# startup work — and unlike the interactive banner, they are NOT gated on a tty
# (so the output is captured here through a pipe). The `version` word prints the
# same string at the REPL.

t0=$(date +%s.%N)
v_out=$(printf '' | timeout 2 $FORTH -v 2>&1);        v_status=$?
ver_out=$(printf '' | timeout 2 $FORTH --version 2>&1); ver_status=$?
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "version flags"

# -v: prints the banner, exits 0, never shows a REPL prompt
if [[ "$v_status" == "0" && "$v_out" == *"*** BasicForth"* && "$v_out" == *"***"* && "$v_out" != *"> "* ]]; then
    printf "  ${GREEN}PASS${NC}  -v prints version, exit 0\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  -v prints version, exit 0\n"
    printf "    Expected: '*** BasicForth ... ***', status 0, no prompt\n    Got:      status %s / %s\n" "$v_status" "$(echo "$v_out" | head -3)"; ((failed++))
fi
# --version: same behavior as -v
if [[ "$ver_status" == "0" && "$ver_out" == *"*** BasicForth"* && "$ver_out" != *"> "* ]]; then
    printf "  ${GREEN}PASS${NC}  --version prints version, exit 0\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  --version prints version, exit 0\n"
    printf "    Expected: '*** BasicForth ...', status 0, no prompt\n    Got:      status %s / %s\n" "$ver_status" "$(echo "$ver_out" | head -3)"; ((failed++))
fi

# the `version` word prints the banner string at the REPL
assert_output "version word"       "version"             "*** BasicForth"

# =========================================================================
section "Line Editor (BASICFORTH_EDITOR)"
# =========================================================================
# The interactive line editor only engages when stdin is a tty, so force it on
# with BASICFORTH_EDITOR=1 and feed raw key bytes via printf escapes:
#   \033[A up   \033[B down   \033[C right   \033[D left   \001 Ctrl-A (home)
#   \005 Ctrl-E (end)   \177 backspace (DEL).

# assert_editor: editor forced on; output must contain a fixed substring.
assert_editor() {
    local name="$1" input_fmt="$2" expected="$3"
    local t0 t1 ms output
    t0=$(date +%s.%N)
    output=$(printf "$input_fmt" | BASICFORTH_EDITOR=1 timeout 2 $FORTH 2>&1)
    t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "$name"
    if [[ "$output" == *"$expected"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s\n" "$name"
        printf "    Expected: %s\n" "$expected"
        printf "    Got:      %s\n" "$(echo "$output" | head -5)"
        ((failed++))
    fi
}

# assert_editor_count: editor forced on; require exactly N occurrences of a
# needle. Used for history recall, where re-executing the recalled line emits
# its marker an extra time (the echoed command text never contains the marker).
assert_editor_count() {
    local name="$1" input_fmt="$2" needle="$3" want="$4"
    local output n
    output=$(printf "$input_fmt" | BASICFORTH_EDITOR=1 timeout 2 $FORTH 2>&1)
    n=$(printf '%s' "$output" | grep -o -- "$needle" | wc -l | tr -d ' ')
    if [ "$n" = "$want" ]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s (got %s, want %s)\n" "$name" "$n" "$want"
        ((failed++))
    fi
}

# Cursor editing: each line below must still parse to "1 2 + ." → 3.
assert_editor "left-arrow + mid-line insert" '1 2 .\033[D+ \nbye\n'           "3  ok"
assert_editor "backspace deletes at cursor"  '999\177\177\1771 2 + .\nbye\n'   "3  ok"
assert_editor "Ctrl-A home then insert"      '2 + .\0011 \nbye\n'              "3  ok"
assert_editor "Ctrl-E end after Ctrl-A"      '1 2 +\001\005 .\nbye\n'          "3  ok"
# History: 88 emit prints 'X', 89 emit prints 'Y'; recall re-emits the marker.
assert_editor_count "history up recalls prev"      '88 emit\n\033[A\nbye\n'                      'X' 2
assert_editor_count "history up/up/down -> 89"     '88 emit\n89 emit\n\033[A\033[A\033[B\nbye\n' 'Y' 2

# =========================================================================
section "BYE"
# =========================================================================

assert_output "bye prints goodbye" "bye"                 "Goodbye!"

# =========================================================================
# Summary
# =========================================================================

total=$((passed + failed))
echo ""
echo "======================="
printf "%d passed, %d failed, %d total\n" "$passed" "$failed" "$total"
if [ -n "$slowest_name" ]; then
    printf "Slowest: %s (%d ms)\n" "$slowest_name" "$slowest_ms"
fi

if [ "$failed" -gt 0 ]; then
    exit 1
fi
