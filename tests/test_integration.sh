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

# CMOVE
assert_output "cmove"                'create s 65 c, 66 c, 67 c, create d 3 allot s d 3 cmove d c@ . d 1+ c@ . d 2 + c@ .'  "65 66 67"

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

# Snake game words (test game helpers without loading the full file)
assert_output "snake screen-pos"     ': screen-pos 80 * + ; 5 3 screen-pos .'   "245"


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
