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

# Every test runs with BASICFORTH_PATH pointing at this checkout's library, so
# a `require` inside a test resolves from the tree under test and never from
# the caller's environment. Without it the suite silently borrowed whatever a
# sourced setup.sh had exported — green here, ten font failures in a
# bare shell or on a CI runner. Tests that need a different path (or none)
# still set their own on the command line, which wins over this default.
run_forth() {
    printf '%s\n' "$1" | BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH 2>&1
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

# assert_result: like assert_output, but matches only what the interpreter
# PRINTED.  run_forth captures the echoed input too ("> 5 5 <= ."), and
# assert_output matches by substring, so an expectation that also occurs in the
# input passes no matter what the word does -- '-1 1 <= .' expecting "-1" is
# green even for a completely broken <=.  Dropping the echo first closes that
# hole.  Both forms of echo have to go: the "> " line and the "... " lines a
# multi-line input produces -- missing the latter is how the differential test
# below first passed against a deliberately broken <= (its echo contains "0=",
# which matched an expected "0").  Use this whenever the expected text could
# appear in the input.
assert_result() {
    local name="$1"
    local input="$2"
    local expected="$3"

    local t0 t1 ms
    t0=$(date +%s.%N)
    local output
    output=$(run_forth "$input" | sed '/^> /d; /^>$/d; /^\.\.\. /d')
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
assert_output "clearstack"         "1 2 3 clearstack depth ."  "0  ok"
assert_output "clearstack empty"   "clearstack depth ."  "0  ok"

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

assert_output "popcount 0"         "0 popcount ."        "0  ok"
assert_output "popcount 7"         "7 popcount ."        "3  ok"
assert_output "popcount 255"       "255 popcount ."      "8  ok"
assert_output "popcount -1"        "-1 popcount ."       "64  ok"
assert_output "popcount top bit"   "1 63 lshift popcount ."   "1  ok"
assert_output "popcount alternating" ': test $5555555555555555 popcount . ; test' "32  ok"
# the mask idiom documented on this word must not disturb the caller's BASE:
# `[ hex ] .. [ decimal ]` would leave BASE decimal for whoever loaded it
assert_output "\$-prefix literal leaves BASE alone" \
    'hex : m $5555555555555555 ; base @ decimal .'  "16  ok"

# ...and run the `zero-fields` definition EXACTLY as the reference page writes
# it, so the page is what is under test rather than a copy of it that can
# drift. A bracket-form mask computes the same answer and still fails here.
doc_zf=$(sed -n '/^## popcount/,/^## There is no/p' \
             "$REPO_ROOT/docs/Language-Reference/Comparison.md" \
         | sed -n '/: zero-fields/,/;$/p' | sed 's/^    //' | tr '\n' ' ')
if [[ -z "$doc_zf" ]]; then
    printf "  ${RED}FAIL${NC}  documented zero-fields: snippet not found in Comparison.md\n"; ((failed++))
else
    assert_output "documented zero-fields works and leaves BASE alone" \
        "hex $doc_zf base @ decimal . -1 zero-fields . 0 zero-fields ." "16 0 32  ok"
fi
# every bit position, checked against a counting loop — catches a shift or
# mask that is right for small values and wrong at the top of the cell
assert_output "popcount vs loop, all 64 bit positions" \
    ': ref ( x -- n ) 0 swap 64 0 do dup 1 and rot + swap 1 rshift loop drop ;
     : chk 0 64 0 do 1 i lshift dup popcount swap ref <> if 1+ then loop . ;
     chk' "0  ok"

# =========================================================================
section "Memory Access"
# =========================================================================

# Note: HERE is not yet exposed as a Forth word

# 16/32-bit memory access (w@/w! l@/l!) — used by graphics pixels and C structs
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
section "Redefinition warning"
# =========================================================================
# Interactive redefinitions print gforth's "redefined foo" (build_header
# checks find before building, gated on cur_source_id == 0 so file loads —
# startup core.fs, include/require, module reloads — stay silent and free).

assert_output "colon redefine warns"    ": rw1 1 ; : rw1 2 ;"          "redefined rw1"
assert_output "variable redefine warns" "variable rw2 variable rw2"    "redefined rw2"
assert_output "create redefine warns"   "create rw3 create rw3"        "redefined rw3"
assert_output "constant redefine warns" "1 constant rw4 2 constant rw4" "redefined rw4"
assert_output "defer redefine warns"    "defer rw5 defer rw5"          "redefined rw5"
assert_output "cross-definer warns"     "variable rw6 : rw6 1 ;"       "redefined rw6"
assert_output "warns with name as typed" ": rw7 1 ; : RW7 2 ;"         "redefined RW7"
assert_output "evaluate redefine warns" $': rw8 1 ;\ns" : rw8 2 ;" evaluate' "redefined rw8"

# First definitions must stay silent (and so must startup: any "redefined"
# during core.fs would show up in every test above this line)
fresh_out=$(run_forth ": rw9 1 ; variable rw10 rw9 .")
if [[ "$fresh_out" == *"1  ok"* && "$fresh_out" != *"redefined"* ]]; then
    printf "  ${GREEN}PASS${NC}  first definitions are silent\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  first definitions are silent\n"
    printf "    Got:      %s\n" "$(echo "$fresh_out" | head -4)"; ((failed++))
fi

# :e never warns — it REQUIRES the word to exist, so "redefined" is its
# whole job description ((ce-go) arms the one-shot (redef-quiet) skip).
# The next plain redefinition must still warn (the skip is consumed).
rde_dir="$(mktemp -d)"
rde_forth="${FORTH/.\//$PWD/}"   # absolutize ./basicforth in place — $FORTH may be
                                 # a multi-word qemu command, and the test cds away
rde_out=$( cd "$rde_dir" && printf 'save t\n: f 1 ;\n:e f 2 ;\nf .\n: f 3 ;\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $rde_forth 2>&1 )
if [[ $(echo "$rde_out" | grep -c "redefined f") -eq 1 && "$rde_out" == *"2  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  :e redefines silently; next plain redefine still warns\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  :e redefines silently; next plain redefine still warns\n"
    printf "    Got:      %s\n" "$(echo "$rde_out" | head -8)"; ((failed++))
fi
rm -rf "$rde_dir"

# Redefinitions INSIDE an included file are silent — libraries and module
# reloads redefine on purpose
rdw_dir="$(mktemp -d)"
printf ': rwf 1 ;\n: rwf 2 ;\nvariable rwf\n' > "$rdw_dir/redefs.fs"
rdw_out=$(run_forth "include $rdw_dir/redefs.fs  : rwf 9 ;")
# exactly ONE warning: the interactive : rwf 9 ; — none from inside the file
if [[ $(echo "$rdw_out" | grep -o "redefined rwf" | wc -l) -eq 1 ]]; then
    printf "  ${GREEN}PASS${NC}  include: file redefinitions silent, next interactive warns\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  include: file redefinitions silent, next interactive warns\n"
    printf "    Got:      %s\n" "$(echo "$rdw_out" | head -4)"; ((failed++))
fi
rm -rf "$rdw_dir"

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

# tick of an undefined word errors instead of silently pushing 0 (which
# EXECUTE/CATCH would then jump through: segfault, found 2026-07-21 in the
# Exceptions lesson). Interpret mode keeps the stack; compile mode abandons
# the definition cleanly (no bogus "unresolved control flow" at ;).
assert_error  "tick of undefined word"  "' nosuchword execute"  "? nosuchword"
assert_output "tick error keeps the stack" \
    "$(printf "1 2 3 ' nosuchword catch\ndepth . . . .")"  "3 3 2 1"
assert_output "tick error aborts definition cleanly" \
    "$(printf ": t ' missingword ;\n: t2 42 . ;\nt2")"  "42"

# =========================================================================
section "CATCH / THROW"
# =========================================================================

assert_output "catch clean xt returns 0"  ": good 1 2 + ; ' good catch . ."  "0 3"
assert_output "catch returns thrown code" \
    ": boom 111 222 5 throw 333 ; ' boom catch . depth ."  "5 0"
assert_output "0 throw is a no-op"        "1 2 0 throw + ."  "3"
assert_error  "uncaught throw reports"    "77 throw"  "uncaught exception: 77"
assert_output "session survives uncaught throw" \
    "$(printf '77 throw\n1 2 + .')"  "3  ok"
assert_output "uncaught abort stays silent" \
    "$(printf '1 2 3 abort\n5 5 + . depth .')"  "10 0"
assert_output "catch intercepts abort\" as -2" \
    ": risky true abort\" boom\" ; ' risky catch ."  "boom-2"
assert_output "nested catch rethrows outward" \
    ": inner 7 throw ; : outer ['] inner catch 100 + throw ; ' outer catch ."  "107"
assert_output "throw across evaluate restores source" \
    ": t s\" 5 throw\" evaluate 999 ; ' t catch . 123 ."  "5 123"
assert_output "outer catch survives error inside evaluate" \
    ": bad s\" nosuchword\" evaluate ; : run ['] bad catch drop 42 throw ; ' run catch ."  "42"

# throw out of an INCLUDED file: the load stops, the code reaches the catch,
# and the interpreter's file context is restored (the rest of the line runs).
# Depth ends at 2: the c-addr u the xt consumed are unspecified cells but
# still counted — CATCH restores the stack POINTER, not the contents.
ct_dir="$(mktemp -d)"
printf '111 9 throw 222\n' > "$ct_dir/thrower.fs"
assert_output "throw across included restores context" \
    "s\" $ct_dir/thrower.fs\" ' included catch . 5 . depth ."  "9 5 2"
rm -rf "$ct_dir"

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
# CASE arm bookkeeping. Before 2026-07-29 the CASE family pushed UNTAGGED
# values, so ENDOF could not tell its own pending OF-branch from a previous
# arm's exit branch: an extra ENDOF silently emitted WRONG CODE (arms ran each
# other's bodies), and closing a non-CASE construct with a CASE word handed
# patch_forward a tag value as an address and SEGFAULTED the process — fatal
# during a file load. Found in the Dark Star port.
assert_error  "extra endof"      ": bad case 0 of 11 endof 1 of 22 endof endof endcase ;" "? mismatched-control-flow"
assert_error  "of without endof" ": bad case 0 of 11 endof of endcase ;"    "? mismatched-control-flow"
assert_error  "case missing endof" ": bad case 0 of 11 endcase ;"          "? mismatched-control-flow"
assert_error  "if closed by endcase" ": bad if 1 endcase ;"                "? mismatched-control-flow"
assert_error  "if closed by endof"   ": bad if 1 endof ;"                  "? mismatched-control-flow"
assert_error  "do closed by endcase" ": bad do 1 endcase ;"                "? mismatched-control-flow"
assert_error  "begin closed by endcase" ": bad begin 1 endcase ;"          "? mismatched-control-flow"
# an IF opened inside an arm and closed out of order — the likeliest typo
assert_error  "endof over an open if" ": bad case 1 of if 2 endof then endcase ;" "? mismatched-control-flow"
assert_error  "endcase without case"  ": bad endcase ;"                    "? mismatched-control-flow"
assert_error  "extra endcase"    ": bad case 0 of 11 endof endcase endcase ;" "? mismatched-control-flow"
# and the well-formed cases still compile and run, including nested both ways
assert_output "case nested in if" ": t if case 1 of 11 endof 99 endcase else 0 then ; 1 1 t ." "11"
assert_output "if nested in arm"  ": t case 1 of 5 3 > if 42 else 0 then endof 99 endcase ; 1 t ." "42"

assert_error  "if outside def"   "if"                                       "compile only"
assert_error  "then outside def" "then"                                     "compile only"
assert_error  "begin outside def" "begin"                                   "compile only"
# `;` is compile-only like its siblings above -- a stray one used to be
# accepted in silence, which swallowed a typo at the end of a REPL line.
assert_error  "semicolon outside def" ";"                                   "compile only"
# it names the offending word and ABORTS the line, like every other error.
# It used to report and keep parsing, so the rest of the line ran anyway --
# `['] dup 999 .` then executed `dup` on an empty stack and the underflow, not
# the real mistake, was what you saw. The stack is left as it was.
assert_output "stray ; names the word"       "1 2 ; + ."         "compile only: ;"
assert_output "stray ; aborts the line, stack untouched" "1 2 ; + .
.s"                                                         "<2> 1 2"
# and it is still perfectly good at the end of a definition
assert_output "; still ends a definition"    ": sq dup * ; 5 sq ."          "25"
assert_output "; still ends a :noname"       ":noname 9 ; execute ."        "9"
# The same rejection inside EVALUATE, which runs the same outer interpreter.
# EVALUATE swallows the report (it returns the status to its caller and nothing
# prints it -- true of an undefined word there too, not special to this), so
# what is observable is that the line inside EVALUATE stopped: the definition
# resumes afterwards and the stray `;` did not end it.
assert_output "stray ; inside evaluate stops that line" \
              ": t s\" ; 999 .\" evaluate 42 . ; t"                        "42"
# The wording is per-token state, and a nested EVALUATE runs a whole interpret
# loop inside ONE outer token -- so EVALUATE brackets it, like the source
# context. Without that, an error raised later in the SAME outer token inherits
# the inner string's wording. Reaching a wording-less error site at run time
# takes `execute` on a compile-only word, which skips the compile-only check and
# lands in cf_check_tag with a bogus tag. Verified: with the bracketing removed
# the second line below reports "compile only: mismatched-control-flow".
assert_output "a nested evaluate does not leak its error wording" \
              ": leaky s\" ;\" evaluate  0 99 ' then execute ;
leaky"                                                      "? mismatched-control-flow"
# the same error with no evaluate in front, as the control
assert_output "control-flow mismatch reports plainly" \
              ": plain 0 99 ' then execute ;
plain"                                                      "? mismatched-control-flow"
# and nesting still returns values correctly through two levels
assert_output "evaluate nests two deep" \
              ": inner s\" 2 3 +\" evaluate ;
: outer s\" inner\" evaluate ;
outer ."                                                    "5"


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
assert_output "variable starts 0"  "variable z0 z0 @ ."                      "0"
# A fresh dictionary is zeros anyway, so the case that bites is a rollback:
# marker/reload replay the definition over space something else has since
# used. `create 1 cells allot` handed back those stale bytes.
assert_output "variable 0 after rollback" \
    "marker -m variable zr 7 zr ! : pad7 here 64 allot 64 7 fill ; pad7 -m variable zr zr @ ." "0"

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
section ".module (list your module's words)"
# =========================================================================
# A fresh module has defined nothing on top of core.fs.
assert_output ".module reports an empty module" \
    ".module"  "empty module"
# Defining one word: the count is 1 (proves the ~330 core words are excluded —
# if they leaked in the count would be hundreds), and the name is listed.
assert_output ".module counts only your words" \
    ": zonk ;  .module"  "1 word in this module"
assert_output ".module lists your word's name" \
    ": zonk ;  .module"  "zonk"
# Words of every kind count, newest-first (matching WORDS' chain order).
assert_output ".module lists newest-first" \
    ": a1 ;  : b2 ;  : c3 ;  .module"  "c3 b2 a1"
assert_output ".module counts a mix of word kinds" \
    "7 constant k  variable v  defer d  : w ;  .module"  "4 words in this module"
# NEW clears the module back to a clean slate.
assert_output "new clears the module" \
    ": gone 1 ;  new  .module"  "empty module"

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

# Interpreted (STATE-smart) S" and ." — outside a definition S" returns the
# string in one of two alternating transient buffers; ." types immediately.
# Expected strings are chosen so they can't match the echoed input line.
assert_output "s-quote interpreted"     's" hel" s" lo" type type'              "lohel"
assert_output "s-quote buffer cycle"    's" one" s" two" s" three" type type'   "threetwo"
assert_output "dot-quote interpreted"   '." AB" ." CD"'                         "ABCD"
assert_output "s-quote interp leading space" 's"  pad" type ." |"'              " pad|"
assert_output "s-quote empty interp"    's" " swap drop . ." <>"'               "0 <>"
assert_error  "s-quote interp too long" 'create ebuf 320 allot ebuf 320 char x fill char s ebuf c! char " ebuf 1+ c! 32 ebuf 2 + c! char " ebuf 310 + c! ebuf 311 evaluate' "interpreted string too long"

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

# Shapes and sprites on an 8x6 surface (stride 32). Helper p prints the pixel
# at (x,y). Sprite sp is a 2x2 packed 32bpp block holding 1 2 / 3 4. The setup
# is multi-line: the input line buffer is 256 bytes and $GR is a long path.
GRP="include $GR
192 allocate drop value gb
: p 32 * swap 4 * + gb + l@ . ;
: s gb 8 6 32 set-surface 0 clear ;"
SPR="16 allocate drop value sp  1 sp l!  2 sp 4 + l!  3 sp 8 + l!  4 sp 12 + l!"
GRP="$GRP
$SPR"
assert_output "gr line horizontal"     "$GRP
: g s red 1 1 5 1 line 3 1 p 6 1 p ; g"            "16711680 0"
assert_output "gr line vertical"       "$GRP
: g s red 2 0 2 4 line 2 3 p 2 5 p ; g"            "16711680 0"
assert_output "gr line diagonal"       "$GRP
: g s red 0 0 5 5 line 3 3 p 3 2 p ; g"            "16711680 0"
assert_output "gr line clips quietly"  "$GRP
: g s red -5 -5 20 20 line 2 2 p depth . ; g"      "16711680 0"
assert_output "gr rect outline hollow" "$GRP
: g s green 1 1 4 3 rect 1 1 p 4 3 p 2 2 p ; g"    "65280 65280 0"
assert_output "gr circle rim, hollow"  "$GRP
: g s blue 4 3 2 circle 6 3 p 4 1 p 4 3 p ; g"     "255 255 0"
assert_output "gr fill-circle"         "$GRP
: g s blue 4 3 2 fill-circle 4 3 p 0 0 p ; g"      "255 0"
assert_output "gr blit"                "$GRP
: g s sp 1 1 2 2 blit 1 1 p 2 2 p 0 0 p ; g"       "1 4 0"
assert_output "gr blit clip: src shifts" "$GRP
: g s sp -1 0 2 2 blit 0 0 p 0 1 p 1 0 p ; g"      "2 4 0"
assert_output "gr blit-key transparent" "$GRP
: g 7 sp l! 9 sp 4 + l! gb 8 6 32 set-surface 5 clear 7 sp 0 0 2 2 blit-key 0 0 p 1 0 p ; g" "5 9"
assert_output "gr grab/blit round-trip" "$GRP
: g s red 2 2 pixel sp 2 2 2 2 grab 0 clear sp 2 2 2 2 blit 2 2 p 3 3 p depth . ; g" "16711680 0 0"

# l, — packs 32-bit pixels, unlike , which would leave a 4-byte gap between
# them. A create-table built with l, must blit as a sprite (the Sprites
# lesson types art in this way), and the dictionary must survive being left
# 4-byte rather than cell aligned: the colon definition after it has to run.
assert_output "gr l, packs 32-bit pixels" "$GRP
create art 11 l, 22 l, 33 l, 44 l,
: g art l@ . art 4 + l@ . art 12 + l@ . ; g"        "11 22 44"
assert_output "gr l, table blits as a sprite" "$GRP
create art2 11 l, 22 l, 33 l, 44 l,
: g s art2 1 1 2 2 blit 1 1 p 2 1 p 2 2 p ; g"      "11 22 44"
assert_output "gr l, blit-key on a typed table" "$GRP
create art3 11 l, 22 l, 33 l, 44 l,
: g s 22 art3 0 0 2 2 blit-key 0 0 p 1 0 p 1 1 p ; g"  "11 0 44"
# stamp — 1-bit sprites drawn in a colour supplied at draw time. The bit
# order is the thing most likely to be wrong, so the asymmetric pattern
# %10000000 pins that column 0 is the HIGH bit (a mirrored implementation
# would light column 7 instead). 0-bits must leave the background alone.
assert_output "gr stamp bit order is MSB-first" "$GRP
create bs %10000000 c, %00000001 c,
: g s red bs 0 0 8 2 stamp  0 0 p 7 0 p 7 1 p 0 1 p ; g"   "16711680 0 16711680 0"
assert_output "gr stamp 0-bits are transparent" "$GRP
create bs2 %10100000 c,
: g s blue 0 0 8 1 fill-rect  red bs2 0 0 8 1 stamp
  0 0 p 1 0 p 2 0 p ; g"                                   "16711680 255 16711680"
assert_output "gr stamp colour is per-call" "$GRP
create bs3 %11000000 c,
: g s red bs3 0 0 2 1 stamp  green bs3 0 1 2 1 stamp  0 0 p 0 1 p ; g" \
    "16711680 65280"
# Width not a multiple of 8: stride is ceil(w/8), and the spare bits in the
# last byte (columns 12..15 here) must NOT be drawn. The surface is only 8
# wide, so shift the sprite left by 8 to bring its SECOND byte on-screen:
# sprite columns 8..11 land at x=0..3, and if the loop overran w they would
# also paint x=4..7.
assert_output "gr stamp stride ceil(w/8), spare bits ignored" "$GRP
create bs4 %00000000 c, %11111111 c,
: g s red bs4 -8 0 12 1 stamp  0 0 p 3 0 p 4 0 p ; g"      "16711680 16711680 0"
assert_output "gr stamp clips off every edge" "$GRP
create bs5 %11111111 c,
: g s red bs5 -4 0 8 1 stamp  0 0 p
  red bs5 99 99 8 1 stamp  red bs5 0 0 0 1 stamp  depth . ; g"  "16711680 0"
# row, — bitmap art from strings. The point is that it is not a second
# format: it must compile byte-for-byte what the % binary rows would.
assert_output "gr row, matches the binary form byte for byte" "$GRP
: b-art %00111100 c, %01111110 c, ;
create bart b-art
: s-art s\" ..####..\" row,  s\" .######.\" row, ;
create sart s-art
: g bart c@ sart c@ =  bart 1+ c@ sart 1+ c@ =  and . ; g"      "-1"
# '.', space and '0' are clear; '#', '*', '1', 'X' all draw.
assert_output "gr row, off chars are . space 0" "$GRP
: m-art s\" .#  0*1X\" row, ;
create mart m-art
: g mart c@ . ; g"                                              "71"
# A row of u chars compiles ceil(u/8) bytes, partial byte left-aligned.
assert_output "gr row, pads a partial byte left" "$GRP
: p-art s\" ###\" row, ;
create part p-art
: g part c@ . ; g"                                              "224"
assert_output "gr row, 12 wide is two bytes" "$GRP
: t-art s\" ############\" row, ;
create tart t-art
: g tart c@ . tart 1+ c@ . ; g"                                 "255 240"
# row,-built art must stamp identically to the same art in binary.
assert_output "gr row, art stamps correctly" "$GRP
: a-art s\" #.#\" row, ;
create aart a-art
: g s red aart 0 0 3 1 stamp  0 0 p 1 0 p 2 0 p ; g"   "16711680 0 16711680"
assert_output "gr odd l, count leaves dict usable" "$GRP
create odd 1 l, 2 l, 3 l,
: after 4242 ;
: g odd 8 + l@ . after . ; g"                       "3 4242"
# stamp-scale — each set bit becomes a scale x scale block. The diagonal
# sprite (col0,row0 and col1,row1 set) at 2x lights the two 2x2 blocks on the
# main diagonal (0,0)/(3,3) and leaves the off-diagonal cells transparent.
assert_output "gr stamp-scale magnifies each set bit" "$GRP
create ds %10000000 c, %01000000 c,
: g s red ds 0 0 2 2 2 stamp-scale
  0 0 p 1 1 p 2 2 p 3 3 p  2 0 p 0 2 p ; g" \
    "16711680 16711680 16711680 16711680 0 0"
# scale 1 is exactly stamp (the fast pixel path): a 1-wide sprite lights only
# column 0, never a magnified column 1.
assert_output "gr stamp-scale at 1x does not magnify" "$GRP
create d1 %10000000 c,
: g s red d1 0 0 1 1 1 stamp-scale  0 0 p 1 0 p ; g"   "16711680 0"
# a big magnification hanging off any edge clips like stamp -- no crash, clean
assert_output "gr stamp-scale clips off-screen" "$GRP
create d2 %10000000 c,
: g s red d2 99 99 1 1 3 stamp-scale
  red d2 -2 -2 1 1 3 stamp-scale  depth . ; g"         "0"

# =========================================================================
section "Fonts (text on a surface)"
# =========================================================================
# font-terminus-8x16.fs is loaded on demand; it `require`s fontcore.fs (the
# engine), which `require`s graphics.fs, all resolved through BASICFORTH_PATH,
# and the data file selects itself. Rendering is verified by reading pixels
# back -- no display.
# Probe glyph is $DB (full block, all 128 bits set), so it fills its whole 8x16
# cell in the draw colour -- lets us assert exact pixels without depending on
# any letter's shape. Space (32) is all-zero, so it draws nothing.
# Surface: 32x32, stride 128; helper p prints the pixel at (x,y).
FNT="include $FORTH_LIB/font-terminus-8x16.fs
32 32 * 4 * allocate drop value fb
: p pixel-addr l@ . ;
: s fb 32 32  32 4 *  set-surface  0 clear ;"

# geometry constants
assert_output "font cell is 8x16"     "$FNT
: g font-w . font-h . ; g"                             "8 16"
# glyph draws in the given colour: the full block fills its cell top-left..bottom-right
assert_output "font glyph fills cell in colour" "$FNT
: g s red \$DB 0 0 glyph  0 0 p  7 15 p ; g"           "16711680 16711680"
# 0-bits are transparent: a space leaves the background untouched
assert_output "font space is transparent" "$FNT
: g s blue clear  red 32 0 0 glyph  0 0 p ; g"         "255"
# text advances font-w per glyph: a two-block string lights x=0 and x=8, not x=16
assert_output "font text advances font-w" "$FNT
create two \$DB c, \$DB c,
: g s red two 2 0 0 text  0 0 p  8 0 p  16 0 p ; g"    "16711680 16711680 0"
# newline (10) returns to the start column and drops font-h
assert_output "font text newline wraps down" "$FNT
create nl \$DB c, 10 c, \$DB c,
: g s red nl 3 0 0 text  0 0 p  0 16 p  8 0 p ; g"     "16711680 16711680 0"
# carriage return (13) is ignored -- second block still lands at x=8
assert_output "font text ignores CR" "$FNT
create cr1 \$DB c, 13 c, \$DB c,
: g s red cr1 3 0 0 text  8 0 p ; g"                   "16711680"
# glyphs clip off every edge, like stamp -- no crash, stack clean
assert_output "font glyph clips off-screen" "$FNT
: g s red \$DB -4 0 glyph  red \$DB 99 99 glyph  0 0 p depth . ; g"  "16711680 0"
# >glyph: consecutive characters are font-h bytes apart in the table
assert_output "font >glyph stride is font-h" "$FNT
: g [char] B >glyph  [char] A >glyph  - . ; g"         "16"
# text with colour chosen per call: same bytes, two colours
assert_output "font colour is per call" "$FNT
create one \$DB c,
: g s red one 1 0 0 text  green one 1 0 16 text  0 0 p  0 16 p ; g"  "16711680 65280"
# font-scale (sticky, default 1): at 2x a full-block glyph fills a 16x32 cell,
# so (8,0) -- background at 1x -- is now lit, and (16,0) past the cell is not.
assert_output "font-scale magnifies a glyph" "$FNT
: g s 2 to font-scale  red \$DB 0 0 glyph
  0 0 p  15 31 p  8 0 p  16 0 p ; g"                   "16711680 16711680 16711680 0"
# the pen advance scales too: two 2x blocks span x=0..31, so the second glyph's
# far edge (31,0) is lit only if text advanced by font-w*2, not font-w.
assert_output "font-scale scales the pen advance" "$FNT
create two2 \$DB c, \$DB c,
: g s 2 to font-scale  red two2 2 0 0 text
  0 0 p  16 0 p  31 0 p ; g"                           "16711680 16711680 16711680"
# sticky but resettable: back to 1 and the glyph is native 8x16 again
assert_output "font-scale resets to native" "$FNT
: g s 2 to font-scale  1 to font-scale  red \$DB 0 0 glyph
  7 0 p  8 0 p ; g"                                    "16711680 0"
# The engine (fontcore.fs) loads on its own -- text/glyph/font-scale live there,
# not in the font data file. With no font selected yet, the metrics are 0 and
# font-scale defaults to 1.
assert_output "fontcore loads standalone" "include $FORTH_LIB/fontcore.fs
: g font-w . font-h . font-scale . ; g"                "0 0 1"
# font! registers a font's table + cell size and derives the row stride
# (ceil(w/8)); a data file's selector word calls it. A 12-wide font strides 2
# bytes/row; re-calling terminus-8x16 switches the current font back to 8x16.
assert_output "font! sets metrics, selector switches" "$FNT
create wide 64 allot
: g wide 12 16 font!  font-w . font-h . font-stride .
  terminus-8x16  font-w . font-h . font-stride . ; g"  "12 16 2 8 16 1"

# >xy converts a character cell to its pixel corner, using the same advance
# `text` does -- so it tracks font-scale, not just the cell size.
assert_output "font >xy is col*font-w, row*font-h" "$FNT
: g 3 2 >xy . . ; g"                                   "32 24"
assert_output "font >xy follows font-scale" "$FNT
: g 2 to font-scale  3 2 >xy . . ; g"                  "64 48"
# and it agrees with where text actually lands: a block at row 1 column 1 is
# lit at its own corner and dark one pixel above-left of it
assert_output "font >xy matches where text draws" "$FNT
create one1 \$DB c,
: g s red one1 1  1 1 >xy  text  1 1 >xy p  8 15 p ; g"  "16711680 0"

# A second data file, font-vga-8x8.fs (the IBM 8x8 VGA face), on the same
# engine: every word below is the one used above, only the cell is 8 tall.
VGA="include $FORTH_LIB/font-vga-8x8.fs
32 32 * 4 * allocate drop value fb
: p pixel-addr l@ . ;
: s fb 32 32  32 4 *  set-surface  0 clear ;"

assert_output "vga font cell is 8x8"  "$VGA
: g font-w . font-h . font-stride . ; g"               "8 8 1"
# the full block fills all 8 rows and stops -- row 8 belongs to the next line
assert_output "vga glyph fills an 8x8 cell" "$VGA
: g s red \$DB 0 0 glyph  0 0 p  7 7 p  0 8 p ; g"     "16711680 16711680 0"
# glyphs are font-h bytes apart, so 8 here where terminus is 16
assert_output "vga >glyph stride is 8" "$VGA
: g [char] B >glyph  [char] A >glyph  - . ; g"         "8"
# newline drops font-h, which is now 8
assert_output "vga text newline drops 8" "$VGA
create nl8 \$DB c, 10 c, \$DB c,
: g s red nl8 3 0 0 text  0 8 p  0 16 p ; g"           "16711680 0"
# Both fonts loaded at once: a selector switches the metrics AND the glyph
# data. The probe is row 8 of a full block -- inside terminus's 16-row cell,
# past the end of vga's 8-row one. The file selects itself, so vga is current
# straight after the include.
assert_output "two fonts coexist, selectors switch" "$FNT
include $FORTH_LIB/font-vga-8x8.fs
: g s font-h .  terminus-8x16 font-h .
  red \$DB 0 0 glyph  0 8 p
  vga-8x8 font-h .  s red \$DB 0 0 glyph  0 8 p ; g"   "8 16 16711680 8 0"

# =========================================================================
section "FFI (dlopen / dlsym / ccall)"
# =========================================================================
# Calls into libc through the same path SDL bindings use. Works under QEMU
# too (the emulated ld.so resolves libc.so.6 inside the -L sysroot).
FFI="$FORTH_LIB/ffi.fs"
assert_output "ccall 0 args (getpid>0)"  "include $FFI  : t s\" libc.so.6\" dlopen s\" getpid\" dlsym >r 0 r> (ccall) 0> . ; t"  "-1"
assert_output "ccall 1 arg (labs -42)"   "include $FFI  : t s\" libc.so.6\" dlopen s\" labs\" dlsym >r -42 1 r> (ccall) . ; t"  "42"
assert_output "ccall 4 args (snprintf)"  "include $FFI  create fmt 37 c, 108 c, 100 c, 0 c,  : t s\" libc.so.6\" dlopen s\" snprintf\" dlsym >r pad 68 fmt 9876 4 r> (ccall) . pad 4 type ; t"  "4 9876"
assert_output "(dlopen) bad lib -> 0"    "include $FFI  : t s\" libnosuch.so.99\" >z (dlopen) 0= . ; t"  "-1"
assert_output "dlopen bad lib aborts"    "include $FFI  : t s\" libnosuch.so.99\" dlopen ; t"  "dlopen: cannot load library"

# --- float arguments ---
# libm is the oracle: exact, well-defined functions, so a wrong register or a
# wrong ORDER gives a wrong number rather than a crash.
# >f32 first -- the bit patterns are checkable by hand:
#   0.5 = 0x3F000000 = 1056964608     1.0  = 0x3F800000 = 1065353216
#   0.25 = 0x3E800000 = 1048576000   -0.5  = 0xBF000000 = 3204448256
assert_result ">f32 bit patterns" \
    "include $FFI  1 2 >f32 . 1 1 >f32 . 1 4 >f32 . -1 2 >f32 . 0 1 >f32 ." \
    "1056964608 1065353216 1048576000 3204448256 0"
# A zero denominator gives 0, not an infinity: a bad ratio should be silence
# rather than a value that poisons whatever consumes it.
assert_result ">f32 divide by zero -> 0" "include $FFI  1 0 >f32 . 0 0 >f32 ." "0 0"

# The float-call tests need several lines: one REPL line has a length limit,
# and these bind three symbols before calling. `f>i` rounds an f32 bit pattern
# back to an integer so the result is printable (not `rnd`, which core.fs
# already uses for random numbers).
fpre="include $FFI
s\" libm.so.6\" dlopen value LM
LM s\" lroundf\" dlsym value LR
: f>i ( fbits -- n ) 0 1 LR (ccallf) ;"

# One float in, integer out: the value reaches the float register at all.
# lroundf rounds half AWAY from zero, so 2.5 -> 3 and -3.5 -> -4.
assert_result "ccallf 1 float arg (lroundf)" \
    "$fpre
: t 7 2 >f32 f>i . 5 2 >f32 f>i . -7 2 >f32 f>i . ;
t" \
    "4 3 -4"
# Two floats with a float result. fdimf(a,b) = max(a-b,0) is ASYMMETRIC, so
# swapping the float registers changes the answer -- this checks their ORDER,
# not merely that both arrived.
assert_result "ccallf 2 float args, order (fdimf)" \
    "$fpre
LM s\" fdimf\" dlsym value FD
: t 9 1 >f32 3 1 >f32 0 2 FD (ccallf>f) f>i .  3 1 >f32 9 1 >f32 0 2 FD (ccallf>f) f>i . ;
t" \
    "6 0"
# Three floats: fmaf(a,b,c) = a*b+c, a different answer if any pair swapped.
assert_result "ccallf 3 float args (fmaf)" \
    "$fpre
LM s\" fmaf\" dlsym value FM
: t 3 1 >f32 4 1 >f32 5 1 >f32 0 3 FM (ccallf>f) f>i .  10 1 >f32 10 1 >f32 1 1 >f32 0 3 FM (ccallf>f) f>i . ;
t" \
    "17 101"
# Mixed: ldexpf(float x, int exp) = x * 2^exp. C interleaves them; we group
# integers first and floats second, and the ABI still lines up because each
# register file is assigned independently of the other.
assert_result "ccallf mixed int and float (ldexpf)" \
    "$fpre
LM s\" ldexpf\" dlsym value LX
: t 2 3 1 >f32 1 1 LX (ccallf>f) f>i .  10 1 1 >f32 1 1 LX (ccallf>f) f>i .  -1 7 1 >f32 1 1 LX (ccallf>f) f>i . ;
t" \
    "12 1024 4"
# With no float args at all, (ccallf) must behave exactly like (ccall).
assert_result "ccallf with no floats == ccall" \
    "include $FFI  : t s\" libc.so.6\" dlopen s\" labs\" dlsym >r -42 1 0 r> (ccallf) . ; t" \
    "42"

# SDL3 backend — needs libSDL3 on the host. Uses SDL's dummy video driver so
# no display is required: open window + renderer + streaming texture, lock,
# draw through the graphics.fs surface, read the pixel back, close. Skipped
# under QEMU (no aarch64 libSDL3 in the -L sysroot).
if [[ "$FORTH" == *qemu* ]]; then
    printf "  ${YELLOW}SKIP${NC}  SDL3 open+draw+readback (no libSDL3 in the qemu sysroot)\n"
elif ! ldconfig -p 2>/dev/null | grep -q libSDL3; then
    printf "  ${YELLOW}SKIP${NC}  SDL3 open+draw+readback (libSDL3 not installed)\n"
else
    sdl_px=$(printf 'include %s/graphics.fs\ninclude %s/ffi.fs\ninclude %s/sdl3.fs\n: t 64 32 sdl-open sdl-frame red clear gr-base @ l@ u. sdl-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_VIDEODRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$sdl_px" | grep -q '16711680'; then
        printf "  ${GREEN}PASS${NC}  SDL3 open+draw+readback (red pixel via dummy video driver)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  SDL3 open+draw+readback\n    Got: %q\n" "$sdl_px"; ((failed++))
    fi

    # sdl-scale: the window is scaled but the drawing surface stays logical
    sdl_sc=$(printf 'include %s/graphics.fs\ninclude %s/ffi.fs\ninclude %s/sdl3.fs\n: t 4 to sdl-scale 48 20 sdl-open sdl-frame gr-width @ u. gr-height @ u. sdl-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_VIDEODRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$sdl_sc" | grep -q '48 20'; then
        printf "  ${GREEN}PASS${NC}  sdl-scale keeps the surface logical (48x20 at scale 4)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  sdl-scale keeps the surface logical\n    Got: %q\n" "$sdl_sc"; ((failed++))
    fi

    # require sdl3.fs pulls its own deps (ffi, graphics), and a second require
    # under a live window is a no-op: sdl-win must be preserved, not zeroed.
    sdl_rq=$(printf 'require sdl3.fs\n32 16 sdl-open\nsdl-win\nrequire sdl3.fs\nsdl-win swap over = . 0= 0= .\nsdl-close\nbye\n' \
        | SDL_VIDEODRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$sdl_rq" | grep -q -- '-1 -1'; then
        printf "  ${GREEN}PASS${NC}  require sdl3.fs: deps auto-load; re-require keeps a live window\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  require sdl3.fs deps/idempotence\n    Got: %q\n" "$sdl_rq"; ((failed++))
    fi

    # sdl-title: settable before AND after sdl-open (SDL_SetWindowTitle works on
    # a live window), sticky across sdl-close, over-long names truncated to fit
    # the 128-byte buffer, and every path leaves the stack balanced. The title
    # buffer is checked directly — the dummy driver has no title bar to read.
    sdl_ti=$(printf ': zlen ( a -- n ) dup begin dup c@ while 1+ repeat swap - ;\nrequire sdl3.fs\n(z-title) ztype cr\ns" Invaders" sdl-title\n32 16 sdl-open\n(z-title) ztype cr\ns" Live" sdl-title\n(z-title) ztype cr\nsdl-close\n(z-title) ztype cr\n: mk here 300 0 do [char] X c, loop 300 ;\nmk sdl-title\n.( LEN=) (z-title) zlen . .( D=) depth . cr\nbye\n' \
        | SDL_VIDEODRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$sdl_ti" | grep -q 'BasicForth' \
       && printf '%s' "$sdl_ti" | grep -q 'Invaders' \
       && printf '%s' "$sdl_ti" | grep -q 'Live' \
       && printf '%s' "$sdl_ti" | grep -qE 'LEN=127 +D=0'; then
        printf "  ${GREEN}PASS${NC}  sdl-title: default, pre/post-open, sticky, truncated at 127\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  sdl-title\n    Got: %q\n" "$sdl_ti"; ((failed++))
    fi

    # Keycode constants must equal the SDLK_* values in SDL_keycode.h -- a
    # wrong one fails silently at run time (a key that simply never matches).
    # The named ones are the keys with no character; a printable key is its
    # own ASCII code, which is what the [char] w comparison checks.
    sdl_kc=$(printf 'include sdl3.fs\nkey-backspace . key-tab . key-enter . key-esc . key-space .\nkey-left . key-right . key-up . key-down .\nkey-q char q = .\nbye\n' \
        | SDL_VIDEODRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$sdl_kc" | grep -q '8 9 13 27 32' \
       && printf '%s' "$sdl_kc" | grep -q '1073741904 1073741903 1073741906 1073741905' \
       && printf '%s' "$sdl_kc" | grep -q '^\-1  ok'; then
        printf "  ${GREEN}PASS${NC}  SDL keycode constants match SDLK_* (and ASCII for printables)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  SDL keycode constants\n    Got: %q\n" "$sdl_kc"; ((failed++))
    fi

    # Cold start: one include of bounce.fs loads the whole stack via require.
    sdl_cb=$(printf 'include bounce.fs\n3 bounce-frames depth .\nbye\n' \
        | SDL_VIDEODRIVER=dummy SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB:$REPO_ROOT/examples" timeout 10 $FORTH 2>&1)
    if printf '%s' "$sdl_cb" | grep -q '0  ok'; then
        printf "  ${GREEN}PASS${NC}  cold-start: include bounce.fs pulls sdl3+sound via require\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  cold-start bounce via require\n    Got: %q\n" "$sdl_cb"; ((failed++))
    fi
fi

# SDL3 audio — same skip rules, dummy audio driver so no sound hardware is
# required. tone before snd-open must be a silent no-op (depth unchanged);
# after snd-open the stream is live and tone queues PCM (tone aborts via
# snd-error if SDL_PutAudioStreamData fails).
if [[ "$FORTH" == *qemu* ]]; then
    printf "  ${YELLOW}SKIP${NC}  SDL3 audio open+tone (no libSDL3 in the qemu sysroot)\n"
elif ! ldconfig -p 2>/dev/null | grep -q libSDL3; then
    printf "  ${YELLOW}SKIP${NC}  SDL3 audio open+tone (libSDL3 not installed)\n"
else
    snd_out=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t 123 45 tone depth . snd-open? . 440 100 tone 440 0 tone 440 -9 tone depth . .\" put-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$snd_out" | grep -q '0 -1 0 put-ok'; then
        printf "  ${GREEN}PASS${NC}  SDL3 audio open+tone (queued PCM via dummy audio driver)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  SDL3 audio open+tone\n    Got: %q\n" "$snd_out"; ((failed++))
    fi
    # No working audio (bogus driver): snd-open? must return false without
    # aborting, and tone must stay a no-op — a game degrades to soundless.
    snd_na=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t snd-open? . 300 50 tone depth . .\" na-ok\" ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=nosuchdriver BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$snd_na" | grep -q '0 0 na-ok'; then
        printf "  ${GREEN}PASS${NC}  SDL3 audio unavailable -> soundless no-op\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  SDL3 audio unavailable -> soundless no-op\n    Got: %q\n" "$snd_na"; ((failed++))
    fi
    # bye with the audio device still open must end the whole process. SDL
    # spawns threads, so a plain SYS_exit (only the calling thread) leaves a
    # zombie main thread + live SDL threads and the parent waits forever;
    # platform_exit uses SYS_exit_group. timeout kills a hang -> status 124.
    printf 'include %s/ffi.fs\ninclude %s/sound.fs\nsnd-open beep\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        printf "  ${GREEN}PASS${NC}  bye exits with audio open (exit_group ends SDL threads)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  bye exits with audio open (process lingered or errored)\n"; ((failed++))
    fi
    # Closing the window must not silence the game. sdl-close used to call
    # SDL_Quit(), which ends EVERY subsystem, so tearing down the window also
    # freed the audio device sound.fs was holding. snd-stream stayed non-zero,
    # so tone's own `snd-stream 0=` guard could not see it, and the next note
    # wrote into freed memory — a core dump inside SDL's audio thread, well
    # away from anything Forth could report.
    mix_a=$(printf 'require sound.fs\nrequire sdl3.fs\nsnd-open\n32 16 sdl-open\nsdl-close\n440 40 tone\ndepth . .\" audio-ok\"\nsnd-close\nbye\n' \
        | SDL_VIDEODRIVER=dummy SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$mix_a" | grep -q '0 audio-ok'; then
        printf "  ${GREEN}PASS${NC}  sdl-close leaves audio alive (quits only SDL_INIT_VIDEO)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  sdl-close leaves audio alive\n    Got: %q\n" "$mix_a"; ((failed++))
    fi
    # The mirror, which already held: snd-close quits only SDL_INIT_AUDIO, so
    # the window keeps drawing. Reads the pixel back to prove the surface is
    # still live rather than merely that nothing crashed.
    mix_b=$(printf 'require sound.fs\nrequire sdl3.fs\nsnd-open\n32 16 sdl-open\nsnd-close\nsdl-frame red clear gr-base @ l@ u.\nsdl-close\ndepth . .\" video-ok\"\nbye\n' \
        | SDL_VIDEODRIVER=dummy SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$mix_b" | grep -q '16711680' && printf '%s' "$mix_b" | grep -q '0 video-ok'; then
        printf "  ${GREEN}PASS${NC}  snd-close leaves the window drawable (quits only SDL_INIT_AUDIO)\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  snd-close leaves the window drawable\n    Got: %q\n" "$mix_b"; ((failed++))
    fi

    # --- mixing channels ---
    # The point of channels: sounds on DIFFERENT channels play together.
    # tone-on puts two tones on channels 1 and 2, and both must report queued
    # audio at once, with the tone channel untouched.
    ch_mix=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t snd-open? drop 440 300 1 tone-on 660 300 2 tone-on 1 ch-playing? . 2 ch-playing? . tone-ch ch-playing? . 1 ch-stop 1 ch-playing? . 2 ch-playing? . snd-stop 2 ch-playing? . .\" mix-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_mix" | grep -q -- '-1 -1 0 0 -1 0 mix-ok'; then
        printf "  ${GREEN}PASS${NC}  channels mix; ch-stop stops only its own channel\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  channels mix / ch-stop scope\n    Got: %q\n" "$ch_mix"; ((failed++))
    fi

    # REGRESSION GUARD for the channel rewrite: bare `tone` must still queue on
    # the dedicated tone channel, so a run of tones plays in SEQUENCE exactly
    # as it did before channels existed. Two 100 ms tones at 44100 Hz mono
    # 16-bit = 2*8820 bytes, so the second must ADD to the first rather than
    # land on some other channel. Dark Star's siren sweep depends on this.
    ch_seq=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t snd-open? drop 440 100 tone tone-ch ch-queued 440 100 tone tone-ch ch-queued swap - . tone-ch ch-queued 17000 > . .\" seq-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_seq" | grep -q '8820 -1 seq-ok'; then
        printf "  ${GREEN}PASS${NC}  bare tone still sequences on the tone channel\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  tone sequencing on tone-ch\n    Got: %q\n" "$ch_seq"; ((failed++))
    fi

    # snd-alloc is round-robin, never hands back tone-ch, and steals the OLDEST
    # channel once they are all busy. Filling every channel with a long tone
    # and allocating twice must give 1 then 2 -- the two least recently used.
    ch_alloc=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: fill snd-channels 1 ?do 220 2000 i tone-on loop ;\n: t snd-open? drop snd-alloc . snd-alloc . snd-alloc . fill snd-alloc . snd-alloc . .\" alloc-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_alloc" | grep -q '1 2 3 1 2 alloc-ok'; then
        printf "  ${GREEN}PASS${NC}  snd-alloc round-robins, then steals the oldest\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  snd-alloc round-robin / stealing\n    Got: %q\n" "$ch_alloc"; ((failed++))
    fi

    # snd-channels is read once, at open, and clamped into 2..snd-max-channels.
    ch_cnt=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t 4 to snd-channels snd-open? drop snd-channels . snd-close 999 to snd-channels snd-open? drop snd-channels snd-max-channels = . snd-close 1 to snd-channels snd-open? drop snd-channels . .\" cnt-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_cnt" | grep -q '4 -1 2 cnt-ok'; then
        printf "  ${GREEN}PASS${NC}  snd-channels is settable and clamped at open\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  snd-channels clamping\n    Got: %q\n" "$ch_cnt"; ((failed++))
    fi

    # Volume clamps to 0..snd-unity, and an out-of-range channel is inert
    # rather than a wild dictionary write.
    ch_vol=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t snd-open? drop 3 ch-vol@ . 9999 3 ch-vol! 3 ch-vol@ . -5 3 ch-vol! 3 ch-vol@ . 99 ch-vol@ . 7 99 ch-vol! 99 ch-queued . pad 4 99 ch-put 99 ch-stop .\" vol-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_vol" | grep -q '256 256 0 256 0 vol-ok'; then
        printf "  ${GREEN}PASS${NC}  ch-vol clamps; out-of-range channels are inert\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  ch-vol clamping / channel bounds\n    Got: %q\n" "$ch_vol"; ((failed++))
    fi

    # Volume is SDL's per-stream gain now, applied as it PULLS the audio, so
    # ch-put must hand the bytes over untouched: the same loaded sound can be
    # playing on several channels, and the queued byte count must not depend on
    # the volume either. 1000 and -1000 (65536-1000 = 64536 through w@).
    ch_scale=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\ncreate SB 8 allot\n: t snd-open? drop 1000 SB w! -1000 SB 2 + w! 1000 SB 4 + w! -1000 SB 6 + w! 64 4 ch-vol! SB 8 4 ch-put SB w@ . SB 2 + w@ . 4 ch-queued 8 = . 4 ch-vol@ . .\" scale-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_scale" | grep -q '1000 64536 -1 64 scale-ok'; then
        printf "  ${GREEN}PASS${NC}  ch-put passes samples through; volume is SDL gain\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  ch-put pass-through\n    Got: %q\n" "$ch_scale"; ((failed++))
    fi

    # ch-fade lowers the GAIN over time and stops the channel, leaving the
    # recorded volume alone so it can be restored -- and a hard stop mid-fade
    # must restore it too, or the next sound on that channel plays faint for
    # no visible reason.
    ch_fade=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: a snd-open? drop 200 1 ch-vol! 440 3000 1 tone-on ;\n: b 60 1 ch-fade 1 ch-vol@ . 20 ms snd-pump 1 ch-playing? . ;\n: c 200 ms snd-pump 1 ch-playing? . 1 ch-vol@ . ;\n: d 200 2 ch-vol! 440 3000 2 tone-on 60 2 ch-fade ;\n: e 20 ms snd-pump 2 ch-stop 2 ch-vol@ . .\" fade-ok\" snd-close ;\na b c d e\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_fade" | grep -q -- '200 -1 0 200 200 fade-ok'; then
        printf "  ${GREEN}PASS${NC}  ch-fade stops the channel and restores the volume\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  ch-fade lifecycle\n    Got: %q\n" "$ch_fade"; ((failed++))
    fi

    # A fade must not outlive the sound it was fading. There are three ways it
    # can end early, and each one leaves a deadline that would stop a LATER,
    # unrelated sound on the same channel:
    #   1. ch-stop cancels it explicitly
    #   2. the faded sound simply finishes before the fade does
    #   3. snd-alloc hands the channel out again once it fell silent
    # The observable in every case is whether a NEW sound survives being pumped
    # past the old deadline -- ch-vol@ cannot see any of it, because a fade
    # moves the GAIN and never the recorded volume.
    ch_early=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n0 value AC\n: a snd-open? drop 440 50 1 tone-on 200 1 ch-fade ;\n: b 120 ms snd-pump 1 ch-playing? 0= . ;\n: c 440 3000 1 tone-on ;\n: d 200 ms snd-pump 1 ch-playing? . 1 ch-vol@ . ;\n: e 440 50 2 tone-on 200 2 ch-fade 120 ms snd-pump ;\n: f snd-alloc to AC  440 3000 AC tone-on  200 ms snd-pump ;\n: g AC ch-playing? . AC ch-vol@ . .\" early-ok\" snd-close ;\na b c d e f g\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_early" | grep -q -- '-1 -1 256 -1 256 early-ok'; then
        printf "  ${GREEN}PASS${NC}  a fade dies with its sound, not with its deadline\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  fade outliving its sound\n    Got: %q\n" "$ch_early"; ((failed++))
    fi

    # A fade moves the GAIN and never the recorded volume, so a ch-vol! made
    # while fading must survive the fade ending. (Snapshotting the volume at
    # ch-fade time and writing it back on cancel silently undoes the change --
    # the setting reverts to whatever it was when the fade started.)
    ch_volfade=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: a snd-open? drop 200 1 ch-vol! 440 3000 1 tone-on 400 1 ch-fade ;\n: b 50 ms snd-pump 100 1 ch-vol! 1 ch-vol@ . ;\n: c 440 3000 1 tone-on 1 ch-vol@ . ;\n: d 180 2 ch-vol! 440 3000 2 tone-on 100 2 ch-fade 20 ms snd-pump 90 2 ch-vol! 200 ms snd-pump 2 ch-vol@ . .\" volfade-ok\" snd-close ;\na b c d\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_volfade" | grep -q '100 100 90 volfade-ok'; then
        printf "  ${GREEN}PASS${NC}  a volume set during a fade survives the fade ending\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  volume changed during a fade\n    Got: %q\n" "$ch_volfade"; ((failed++))
    fi

    # While a fade is running the gain belongs to the fade. ch-vol! must record
    # the new volume but NOT apply it directly: doing both jumps the gain to
    # full volume for one frame and then snaps it back at the next pump, which
    # is an audible blip in the middle of a fade. Setting the SAME volume
    # half-way through a fade must leave the gain exactly where it was.
    # (0.5 = 1056964608, 1.0 = 1065353216.)
    ch_jump=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n0 value G\n: a snd-open? drop 256 1 ch-vol! 440 9000 1 tone-on 1000 1 ch-fade ;\n: b 500 ms snd-pump 1 (ch-gain@) to G G 1065353216 < . ;\n: c 256 1 ch-vol! 1 (ch-gain@) G = . 1 ch-vol@ . ;\n: d 120 1 ch-vol! 1 (ch-gain@) G = . 1 ch-vol@ . .\" jump-ok\" snd-close ;\na b c d\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_jump" | grep -q -- '-1 -1 256 -1 120 jump-ok'; then
        printf "  ${GREEN}PASS${NC}  ch-vol! during a fade records without jumping the gain\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  ch-vol! gain jump during a fade\n    Got: %q\n" "$ch_jump"; ((failed++))
    fi

    # The ramp must read the volume EACH pump, not once at ch-fade time: lower
    # the volume mid-fade and the fade continues from the lower level instead
    # of jumping back up. ch-vol@ cannot see this -- it reports the setting,
    # which is correct either way -- so the observable is the gain SDL is
    # actually applying, compared as f32 bit patterns (which for positive
    # values order exactly as the values do).
    # A 10-second fade decays only ~0.2% over the 20 ms here, so a gain that
    # has fallen below 0.5 can only have come from the volume change.
    ch_ramp=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: a snd-open? drop 256 1 ch-vol! 440 9000 1 tone-on 10000 1 ch-fade ;\n: b 20 ms snd-pump 1 (ch-gain@) 1063675494 > . ;\n: c 38 1 ch-vol! 20 ms snd-pump 1 (ch-gain@) 1056964608 < . .\" ramp-ok\" snd-close ;\na b c\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_ramp" | grep -q -- '-1 -1 ramp-ok'; then
        printf "  ${GREEN}PASS${NC}  a fade ramps from the live volume, not a stale one\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  fade ramp reads the volume each pump\n    Got: %q\n" "$ch_ramp"; ((failed++))
    fi

    # Isolating the rule that does the work: queueing on a channel whose fade is
    # STILL RUNNING (its sound has not ended, so snd-pump has no reason to
    # notice) must cancel that fade, or the deadline arrives and takes both
    # sounds with it -- and the gain must go back to full (1.0 = 1065353216),
    # or the surviving sound plays at whatever level the fade had reached.
    ch_overlap=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: a snd-open? drop 440 3000 1 tone-on 200 1 ch-fade ;\n: b 20 ms snd-pump 1 ch-playing? . ;\n: c 660 3000 1 tone-on ;\n: d 300 ms snd-pump 1 ch-playing? . 1 ch-vol@ . 1 (ch-gain@) 1065353216 = . .\" over-ok\" snd-close ;\na b c d\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_overlap" | grep -q -- '-1 -1 256 -1 over-ok'; then
        printf "  ${GREEN}PASS${NC}  queueing during a fade cancels it, keeping both sounds\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  queueing during a running fade\n    Got: %q\n" "$ch_overlap"; ((failed++))
    fi

    # A fade cancelled by ch-stop must not still be pending: if it is, the next
    # sound played on that channel gets stopped by the stale deadline. ch-vol@
    # cannot see this -- a fade moves the GAIN, never the recorded volume -- so
    # the observable is whether a NEW sound survives being pumped past the old
    # fade's deadline.
    ch_stale=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: a snd-open? drop 440 3000 1 tone-on 40 1 ch-fade ;\n: b 10 ms snd-pump 1 ch-stop ;\n: c 440 3000 1 tone-on ;\n: d 100 ms snd-pump 1 ch-playing? . .\" stale-ok\" snd-close ;\na b c d\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_stale" | grep -q -- '-1 stale-ok'; then
        printf "  ${GREEN}PASS${NC}  a stopped fade does not stop the next sound too\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  stale fade after ch-stop\n    Got: %q\n" "$ch_stale"; ((failed++))
    fi

    # A stream that is RESAMPLING (any sample whose rate is not the device's)
    # holds a few input bytes back waiting for more input that never arrives,
    # so ch-queued sits at a small non-zero number forever. ch-playing? asks
    # the OUTPUT side instead, which does reach zero -- otherwise snd-wait
    # spins on that channel and snd-alloc never sees it free again.
    # Flushing the stream would also release those bytes, but it means
    # declaring end-of-input after every sound, and SDL warns of a gap at the
    # join -- which would gap consecutive tones, the sequencing tone has
    # always had. 200 samples at 16 kHz is 12.5 ms, so 300 ms is ample.
    # Both directions, with wide margins so neither depends on when SDL's audio
    # thread happens to run: 8000 bytes at 16 kHz is 250 ms of audio, so it is
    # unambiguously PLAYING 30 ms in and unambiguously finished 600 ms later.
    # The second half is the one that matters -- a resampling stream holds a
    # little input back, so a channel measured by ch-queued would never report
    # empty, snd-wait would spin on it and snd-alloc would never see it free.
    ch_flush=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n0 value BUF\n: a snd-open? drop 8000 allocate drop to BUF AUDIO_S16LE 1 16000 5 ch-format! ;\n: b BUF 8000 5 ch-put 30 ms 5 ch-playing? . ;\n: c 600 ms 5 ch-playing? . snd-alloc 0 > . 5 ch-wait BUF free drop .\" flush-ok\" snd-close ;\na b c\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_flush" | grep -q -- '-1 0 -1 flush-ok'; then
        printf "  ${GREEN}PASS${NC}  a resampled channel finishes instead of hanging forever\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  resampled channel never finishes\n    Got: %q\n" "$ch_flush"; ((failed++))
    fi

    # ch-put must NOT declare end-of-input, or consecutive sounds on a channel
    # are separated by a gap -- which would break the seamless run of tones
    # that channel 0 exists to preserve. There is no direct way to observe a
    # gap from here, so this pins the side effect instead: flushing releases
    # the bytes a resampling stream holds back, driving the residue to 0.
    # Measured both ways -- 14 bytes without a flush, 0 with one -- so a
    # non-zero residue after playout is the tripwire. Note the obvious test
    # (comparing ch-queued after two tones) detects nothing: it reads 17640
    # either way, because flushing converts data without unqueueing it.
    ch_noflush=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: a snd-open? drop AUDIO_S16LE 1 16000 4 ch-format! pad 400 4 ch-put ;\n: b 300 ms 4 ch-queued 0 > . 4 ch-playing? . .\" noflush-ok\" snd-close ;\na b\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_noflush" | grep -q -- '-1 0 noflush-ok'; then
        printf "  ${GREEN}PASS${NC}  ch-put leaves the stream open, so sounds join seamlessly\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  ch-put declared end-of-input\n    Got: %q\n" "$ch_noflush"; ((failed++))
    fi

    # --- playing loaded samples (wav.fs) ---
    # A wav plays on a channel; two plays land on different channels and both
    # sound at once; the queued byte count is the sample's own size, which is
    # what proves nothing was converted or copied on the way in.
    wav_play=$(printf 'include %s/wav.fs\ns" %s" wav-load value S\n0 value C1  0 value C2\n: a snd-open? drop S wav-play to C1  S wav-play to C2 ;\n: b C1 C2 <> . C1 ch-playing? . C2 ch-playing? . ;\n: c C1 ch-queued S wav-bytes = . S wav-ms . .\" play-ok\" snd-close ;\na b c\nbye\n' "$FORTH_LIB" "/usr/share/sounds/sound-icons/pipe.wav" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$wav_play" | grep -q -- '-1 -1 -1 -1 768 play-ok'; then
        printf "  ${GREEN}PASS${NC}  wav-play mixes two sounds, queueing the sample untouched\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  wav-play\n    Got: %q\n" "$wav_play"; ((failed++))
    fi
    # wav-play must tell the channel what is coming: pipe.wav is 16 kHz mono
    # 16-bit (format 32784 = 0x8010), against a device side of 44100. Reading
    # the format back is the direct check -- the queued byte count is identical
    # whether or not the format was set, so it cannot catch this.
    wav_fmt=$(printf 'include %s/wav.fs\ns" %s" wav-load value S\n: a snd-open? drop tone-ch ch-format@ . . . ;\n: b S 5 wav-play-on 5 ch-format@ . . . ;\n: c 440 50 5 tone-on 5 ch-format@ . . . .\" fmt-ok\" snd-close ;\na b c\nbye\n' "$FORTH_LIB" "/usr/share/sounds/sound-icons/pipe.wav" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$wav_fmt" | grep -q '44100 1 32784 16000 1 32784 44100 1 32784 fmt-ok'; then
        printf "  ${GREEN}PASS${NC}  wav-play sets the channel format; tone-on sets it back\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  wav-play channel format\n    Got: %q\n" "$wav_fmt"; ((failed++))
    fi

    # A sample that failed to load must not be playable, and must not be
    # mistaken for channel 0.
    wav_null=$(printf 'include %s/wav.fs\n: t snd-open? drop 0 wav-play . 0 5 wav-play-on 5 ch-queued . .\" null-ok\" snd-close ; t\nbye\n' "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$wav_null" | grep -q -- '-1 0 null-ok'; then
        printf "  ${GREEN}PASS${NC}  playing a failed load is inert, and is not channel 0\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  wav-play on a null sample\n    Got: %q\n" "$wav_null"; ((failed++))
    fi

    # Every channel word must be a silent no-op with no device open, the same
    # contract tone already had, so a soundless system never aborts.
    ch_closed=$(printf 'include %s/ffi.fs\ninclude %s/sound.fs\n: t 440 100 3 tone-on pad 4 3 ch-put 3 ch-stop snd-stop snd-wait 3 ch-queued . snd-alloc . depth . .\" closed-ok\" ; t\nbye\n' "$FORTH_LIB" "$FORTH_LIB" \
        | SDL_AUDIO_DRIVER=dummy BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
    if printf '%s' "$ch_closed" | grep -q '0 0 0 closed-ok'; then
        printf "  ${GREEN}PASS${NC}  channel words are no-ops with no device open\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  channel words with no device\n    Got: %q\n" "$ch_closed"; ((failed++))
    fi
fi

# =========================================================================
section "WAV decoding (wavcore.fs)"
# =========================================================================
# wavcore.fs is deliberately FFI-free -- no SDL, no audio device -- so these
# run on every architecture, including under qemu where `require sound.fs`
# aborts on dlopen. The fixtures are built in Forth rather than committed as
# binaries, so the bytes under test are visible in this file.
wav_dir="$(mktemp -d)"
wav_forth="${FORTH/.\//$PWD/}"   # absolutize: the test cds into $wav_dir
cat > "$wav_dir/mk.fs" <<'WAVEOF'
require wavcore.fs
create WB 2048 allot   variable WP   variable WN
: b, ( c -- )        WB WP @ + c!  1 WP +! ;
: w, ( x -- )        WB WP @ + w!  2 WP +! ;
: l, ( x -- )        WB WP @ + l!  4 WP +! ;
: tag, ( c-addr u -- ) 0 ?do dup i + c@ b, loop drop ;
: fmt, ( chans bits -- )   \ a fmt chunk for `chans` channels at `bits` bits
    s" fmt " tag,  16 l,
    1 w,                          ( chans bits )
    over w,  44100 l,  88200 l,  2 w,  w,  drop ;
: ffmt, ( chans bits -- )  \ same, but format code 3 (IEEE float)
    s" fmt " tag,  16 l,
    3 w,  over w,  44100 l,  88200 l,  2 w,  w,  drop ;
: pcm24, ( frames chans -- )   \ 3 bytes per sample, little-endian
    * 0 ?do  0 b,  i b,  i b,  loop ;
: data24, ( frames chans -- )  2dup * 3 *  s" data" tag, l,  pcm24, ;
: pcm, ( frames chans -- )  * 0 ?do  i 100 * 1000 -  w,  loop ;
: save-as ( c-addr u -- )  w/o bin create-file drop >r
    WB WP @ r@ write-file drop  r> close-file drop ;
\ a well-formed 16-bit mono file, optionally with junk before fmt and a loop
: start, ( -- )  0 WP !  s" RIFF" tag,  0 l,  s" WAVE" tag, ;
: finish, ( -- ) WP @ 8 -  WB 4 + l! ;      \ patch the RIFF size field
: data, ( frames chans -- )  2dup * 2*  s" data" tag, l,  pcm, ;
: smpl, ( start end -- )
    s" smpl" tag,  60 l,
    0 l, 0 l, 0 l, 60 l, 0 l, 0 l, 0 l,  1 l,  0 l,     \ 36-byte header
    0 l, 0 l,                                    \ cuePointId, loop type
    swap l, l,                                   \ start, end
    0 l, 0 l, ;
: junk, ( -- )  s" LIST" tag,  8 l,  s" INFO" tag,  s" hey" tag, 0 b, ;
: mk-ok      start, 1 16 fmt,  8 1 data, finish,  s" ok.wav" save-as ;
: mk-stereo  start, 2 16 fmt,  8 2 data, finish,  s" st.wav" save-as ;
: mk-junk    start, junk, 1 16 fmt, 8 1 data, finish, s" junk.wav" save-as ;
: mk-loop    start, 1 16 fmt, 2 6 smpl, 8 1 data, finish, s" loop.wav" save-as ;
: mk-badloop start, 1 16 fmt, 6 2 smpl, 8 1 data, finish, s" bad.wav" save-as ;
\ The smpl end point is INCLUSIVE, so on 8 frames the largest legal end is 7;
\ end=8 is already one frame past the audio and must be refused.
: mk-edge    start, 1 16 fmt, 2 7 smpl, 8 1 data, finish, s" edge.wav" save-as ;
: mk-past    start, 1 16 fmt, 2 8 smpl, 8 1 data, finish, s" past.wav" save-as ;
: mk-8bit    start, 1 8 fmt,  8 1 data, finish,  s" b8.wav" save-as ;
: mk-24      start, 1 24 fmt, 8 1 data24, finish, s" b24.wav" save-as ;
: mk-f32     start, 1 32 ffmt, 8 1 data, finish,  s" f32.wav" save-as ;
: mk-f16     start, 1 16 ffmt, 8 1 data, finish,  s" f16.wav" save-as ;
: mk-b12     start, 1 12 fmt,  8 1 data, finish,  s" b12.wav" save-as ;
: mk-nofmt   start, 8 1 data, finish,            s" nofmt.wav" save-as ;
: mk-nodata  start, 1 16 fmt, finish,            s" nodat.wav" save-as ;
: mk-short   0 WP ! s" RIFF" tag, 0 l, finish,   s" tiny.wav" save-as ;
: mk-notriff 0 WP ! s" JUNK" tag, 0 l, s" WAVE" tag, finish, s" nr.wav" save-as ;
: mk-runover start, 1 16 fmt,  s" data" tag, 9999 l,  8 1 pcm, finish,
             s" over.wav" save-as ;
: build  mk-ok mk-stereo mk-junk mk-loop mk-badloop mk-edge mk-past mk-8bit
         mk-24 mk-f32 mk-f16 mk-b12
         mk-nofmt mk-nodata mk-short mk-notriff mk-runover ;
: ? ( c-addr u -- ) wav-load dup 0= if drop wav-why type ."  | " exit then
    dup wav-frames . dup wav-rate . dup wav-chans . dup wav-bits .
    dup wav-float? if ." F " else ." I " then
    dup wav-loop? if dup wav-loop-start . dup wav-loop-end . else ." - " then
    ." | " wav-free ;
: run  build
    s" ok.wav" ?  s" st.wav" ?  s" junk.wav" ?  s" loop.wav" ?  s" bad.wav" ?
    s" edge.wav" ?  s" past.wav" ?
    s" b24.wav" ?  s" f32.wav" ?
    s" b8.wav" ?  s" f16.wav" ?  s" b12.wav" ?  s" nofmt.wav" ?  s" nodat.wav" ?  s" tiny.wav" ?
    s" nr.wav" ?  s" over.wav" ?  s" gone.wav" ?
    ." depth=" depth . ;
run
bye
WAVEOF
wav_out=$( cd "$wav_dir" && BASICFORTH_PATH="$FORTH_LIB" timeout 20 $wav_forth mk.fs 2>&1 )
# Expected, in order: mono 8 frames; stereo 8 frames; junk chunk skipped;
# loop kept; reversed loop dropped; then each refusal by name.
# 24-bit arrives as 32-bit (widened, frame count preserved); float reports F.
wav_want='8 44100 1 16 I - | 8 44100 2 16 I - | 8 44100 1 16 I - | 8 44100 1 16 I 2 6 | 8 44100 1 16 I - | 8 44100 1 16 I 2 7 | 8 44100 1 16 I - | 8 44100 1 32 I - | 4 44100 1 32 F - | 16 44100 1 8 I - |'
wav_want2='wav: need 8, 16, 24 or 32-bit samples'
wav_want3='wav: no fmt chunk'
wav_want4='wav: no data chunk'
wav_want5='wav: too short to be a RIFF file'
wav_want6='wav: not a RIFF file'
wav_want7='wav: a chunk runs past the end of the file'
wav_want8='wav: cannot read the file'
wav_want9='wav: float samples must be 32-bit'
if printf '%s' "$wav_out" | grep -qF "$wav_want" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want2" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want3" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want4" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want5" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want6" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want7" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want8" \
   && printf '%s' "$wav_out" | grep -qF "$wav_want9" \
   && printf '%s' "$wav_out" | grep -qF 'depth=0'; then
    printf "  ${GREEN}PASS${NC}  wav-load decodes, skips unknown chunks, refuses the rest by name\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  wav-load decoding\n    Got: %s\n" "$(echo "$wav_out" | tail -3)"; ((failed++))
fi

# 24-bit is the one depth SDL cannot take, so wavcore widens it to 32-bit --
# LOSSLESSLY, by shifting up 8, which also puts the sign bit where a 32-bit
# sample wants it. The fixture writes bytes (0, i, i) per sample, so sample i
# must come back as (i<<24)|(i<<16): 0, 16842752, 33685504, 50528256.
# Checking the frame count alone would not notice a wrong shift.
wav_widen=$( cd "$wav_dir" && printf 'require wavcore.fs\ns\" b24.wav\" wav-load value S\n: w S wav-data swap 4 * + l@ . ;\nS wav-bits . S wav-frames . 0 w 1 w 2 w 3 w S wav-free depth .\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 20 $wav_forth 2>&1 )
if printf '%s' "$wav_widen" | grep -q '32 8 0 16842752 33685504 50528256 0'; then
    printf "  ${GREEN}PASS${NC}  24-bit widens to 32-bit losslessly, sign and all\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  24-bit widening values\n    Got: %s\n" "$(echo "$wav_widen" | tail -2)"; ((failed++))
fi

# wav-from decodes an image already in memory -- the same bytes a file holds.
# It must agree with wav-load exactly, including through the 24-bit widening
# path, which swaps the image for a converted block mid-decode. And it must
# COPY: the sample points into its own block and wav-free releases it, so
# adopting the caller's bytes would free memory the caller still owns. The last
# check reads the source buffer's RIFF tag back after the sample is freed
# (1179011410 = "RIFF" as a little-endian cell). A zero-length image is named
# as such: without that guard it still fails, but through the allocate path,
# reporting "out of memory" for a problem that has nothing to do with memory.
wav_from=$( cd "$wav_dir" && printf 'require wavcore.fs\n0 value RAW  0 value LEN\n: slurp r/o bin open-file drop >r r@ file-size drop drop to LEN LEN allocate drop to RAW RAW LEN r@ read-file drop drop r> close-file drop ;\n: d dup 0= if drop ." X" exit then dup wav-frames . dup wav-bits . dup wav-loop? if dup wav-loop-start . then wav-free ;\ns" b24.wav" slurp\ns" b24.wav" wav-load d  RAW LEN wav-from d\nRAW l@ 1179011410 = . RAW free drop\ns" loop.wav" slurp RAW LEN wav-from d\nRAW 0 wav-from drop wav-why type\nRAW free drop depth .\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 20 $wav_forth 2>&1 )
# Each Forth line prints its own output line, so match them separately.
if printf '%s' "$wav_from" | grep -q '8 32 8 32' \
   && printf '%s' "$wav_from" | grep -q -- '-1' \
   && printf '%s' "$wav_from" | grep -q '8 16 2' \
   && printf '%s' "$wav_from" | grep -q 'wav: empty image'; then
    printf "  ${GREEN}PASS${NC}  wav-from decodes an in-memory image, copying it\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  wav-from\n    Got: %s\n" "$(echo "$wav_from" | tail -3)"; ((failed++))
fi

# Many load/free cycles must stay correct: the file image is a SECOND heap
# block, so wav-free has two things to release and a mistake there shows up as
# a double-free or a corrupted later load. NOTE this does not detect a plain
# leak -- there is no heap-usage introspection to assert against, and 500
# copies of a 60-byte fixture would not exhaust anything. It is a stability
# check, not a memory-accounting one.
wav_leak=$( cd "$wav_dir" && printf 'require wavcore.fs\n: cyc s" ok.wav" wav-load dup 0= if drop false exit then dup wav-frames 8 <> if wav-free false exit then wav-free true ;\n: many true 500 0 ?do cyc 0= if drop false leave then loop ;\nmany . depth .\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 20 $wav_forth 2>&1 )
if printf '%s' "$wav_leak" | grep -q -- '-1 0'; then
    printf "  ${GREEN}PASS${NC}  500 wav load/free cycles stay correct\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  wav load/free cycles\n    Got: %s\n" "$(echo "$wav_leak" | tail -2)"; ((failed++))
fi

# A refused loop must report -1 -1, not the numbers it just refused. Reporting
# the rejected end back would hand a caller the very value that indexes past
# the audio, and "no loop" would answer differently depending on HOW the file
# was wrong (no smpl chunk, reversed range, or out of range).
wav_noloop=$( cd "$wav_dir" && \
    printf 'require wavcore.fs\n: e ( c-addr u -- ) wav-load dup wav-loop-start . dup wav-loop-end . wav-free ;\ns\" ok.wav\" e s\" bad.wav\" e s\" past.wav\" e s\" loop.wav\" e depth .\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 20 $wav_forth 2>&1 )
if printf '%s' "$wav_noloop" | grep -q -- '-1 -1 -1 -1 -1 -1 2 6 0'; then
    printf "  ${GREEN}PASS${NC}  a refused loop reports -1 -1, not the value it refused\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  refused loop endpoints\n    Got: %s\n" "$(echo "$wav_noloop" | tail -2)"; ((failed++))
fi

# Accessors on a failed load (0) must be inert rather than dereference null.
wav_null=$(printf 'require wavcore.fs\n0 wav-frames . 0 wav-rate . 0 wav-chans . 0 wav-bytes . 0 wav-data . 0 wav-loop? . 0 wav-free .\" null-ok\" depth .\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1)
if printf '%s' "$wav_null" | grep -q '0 0 0 0 0 0 null-ok0'; then
    printf "  ${GREEN}PASS${NC}  wav accessors are inert on a failed load\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  wav accessors on null\n    Got: %s\n" "$(echo "$wav_null" | tail -2)"; ((failed++))
fi

rm -rf "$wav_dir"

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
assert_output "binary output"      'binary #10 . decimal'                         "1010"
assert_output "binary input"       'binary 1011 decimal .'                        "11"
assert_output ".s follows BASE"    'binary 110 .s decimal'                        "<1> 110"
assert_output ".s hex"             '30 hex .s decimal'                            "<1> 1E"
assert_output ".s decimal format"  '1 2 3 .s'                                     "<3> 1 2 3"
assert_output ".s empty stack"     '.s'                                           "<0>"
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

# <= / >= / U<= / U>=  (extensions, not Forth 2012 CORE)
# The interesting cases are the ones a naive `a b - 0<` would get wrong:
# equal operands, and the signed pair that overflows on subtraction.
assert_result "<= less"           '4 5 <= .'                           "-1"
assert_result "<= equal"          '5 5 <= .'                           "-1"
assert_result "<= greater"        '5 4 <= .'                           "0"
assert_result ">= less"           '4 5 >= .'                           "0"
assert_result ">= equal"          '5 5 >= .'                           "-1"
assert_result ">= greater"        '5 4 >= .'                           "-1"
assert_result "<= negative"       '-5 -4 <= .'                         "-1"
assert_result ">= negative"       '-4 -5 >= .'                         "-1"
assert_result "<= zero cross"     '-1 0 <= .'                          "-1"
assert_result ">= zero cross"     '0 -1 >= .'                          "-1"
# MAX = -1 1 rshift, MIN = 1 63 lshift.  MAX-MIN overflows a signed cell,
# so these fail for any implementation that subtracts and tests the sign.
assert_result "<= max/min"        '-1 1 rshift 1 63 lshift <= .'       "0"
assert_result "<= min/max"        '1 63 lshift -1 1 rshift <= .'       "-1"
assert_result ">= max/min"        '-1 1 rshift 1 63 lshift >= .'       "-1"
assert_result ">= min/max"        '1 63 lshift -1 1 rshift >= .'       "0"
assert_result "<= min/min"        '1 63 lshift dup <= .'               "-1"
assert_result ">= max/max"        '-1 1 rshift dup >= .'               "-1"
assert_result "u<= less"          '4 5 u<= .'                          "-1"
assert_result "u<= equal"         '5 5 u<= .'                          "-1"
assert_result "u<= greater"       '5 4 u<= .'                          "0"
assert_result "u>= equal"         '5 5 u>= .'                          "-1"
assert_result "u>= greater"       '5 4 u>= .'                          "-1"
# -1 is the largest unsigned value, so u<= and <= must disagree here.
assert_result "<= vs u<= signed"  '-1 1 <= .'                          "-1"
assert_result "u<= unsigned"      '-1 1 u<= .'                         "0"
assert_result "u<= wrap other"    '1 -1 u<= .'                         "-1"
assert_result "u>= unsigned"      '-1 1 u>= .'                         "-1"
assert_result "u<= zero"          '0 -1 u<= .'                         "-1"
assert_result "u>= zero"          '0 0 u>= .'                          "-1"
# Each new primitive must agree with the slow form it replaces, over a value
# set that spans both signed and unsigned boundaries.  0 mismatches expected.
assert_result "cmp differential" \
    'create CV 1 63 lshift , -2 , -1 , 0 , 1 , 2 , -1 1 rshift ,
     variable CBAD  : cv cells CV + @ ;  : ck = 0= if 1 CBAD +! then ;
     : sweep 7 0 do 7 0 do
         j cv i cv <=  j cv i cv > 0=          ck
         j cv i cv >=  j cv i cv < 0=          ck
         j cv i cv u<= j cv i cv swap u< 0=    ck
         j cv i cv u>= j cv i cv u< 0=         ck
       loop loop ;  sweep CBAD @ . ." mismatched"'          "0 mismatched"

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

# U.0R — same field, zeros for padding
assert_output "u.0r pads"         '42 6 u.0r'                         "000042"
assert_output "u.0r zero"         '0 4 u.0r'                          "0000"
assert_output "u.0r exact fit"    '4242 4 u.0r'                       "4242"
assert_output "u.0r overflows"    '255 2 u.0r'                        "255"
assert_output "u.0r width 0"      '7 0 u.0r'                          "7"
assert_output "u.0r unsigned"     '-1 4 u.0r'         "18446744073709551615"
# follows BASE, and leaves it alone (the classic bug in this family)
assert_output "u.0r hex color"    'hex FF00 6 u.0r decimal'           "00FF00"
assert_output "u.0r binary row"   'binary #60 #8 u.0r decimal'        "00111100"
assert_output "u.0r keeps base"   'hex FF 4 u.0r decimal space base @ .' "00FF 10"
assert_output "u.0r stack clean"  '42 6 u.0r space depth .'           "000042 0"

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

# +TO: add to a value. It parses the name only to fetch the current contents,
# rewinds >IN, and lets TO do the store — so it has to work in both states, and
# every failure has to come out of TO looking exactly like a bare TO's.
assert_output "+to interpret"        '10 value x 5 +to x x .'                       "15"
assert_output "+to compile"          '10 value x : t 5 +to x ; t t x .'             "20"
assert_output "+to in a do loop"     '0 value x : t 4 0 do 10 +to x loop ; t x .'   "40"
assert_output "+to twice in one def" '0 value x 0 value y : t 1 +to x 2 +to y ; t x . y .'  "1 2"
assert_output "+to twice on a line"  '0 value x 1 +to x 2 +to x x .'                "3"
assert_output "+to negative"         '10 value x -4 +to x x .'                      "6"
assert_output "+to leaves no cells"  '0 value x 1 +to x depth .'                    "0"
# The error paths are TO's, verbatim — nothing is caught and re-reported here.
assert_error  "+to refuses a variable"     'variable v 1 +to v'   "v: not a value or deferred word"
assert_error  "+to on an unknown name"     '1 +to no-such-value'  "? no-such-value"
assert_error  "+to with no name at all"    '0 value x 1 +to'      "not a value or deferred word"
# The value goes on its own line: a line error rolls the dictionary back to
# where that LINE started, so a same-line `value x` would be forgotten too.
assert_output "session survives a bad +to" '0 value x
1 +to zz
5 +to x x . depth .'  "5 0"

# :NONAME
assert_output "noname"               ':noname dup * ; 7 swap execute .'   "49"
assert_output "noname in var"        'variable sq :noname dup * ; sq ! 6 sq @ execute .' "36"

# DEFER / IS (vectored execution / late binding). Note: ' and ['] contain an
# apostrophe, escaped as '\'' to survive the single-quoted shell argument.
assert_output "defer/is interpret"   'defer p : c p ; :noname 42 ; is p c .'                 "42"
assert_output "is by tick"           'defer p : one 1 ; '\'' one is p p .'                   "1"
assert_output "is re-vector"         'defer p : c p . ; :noname 1 ; is p c :noname 2 ; is p c'  "1 2"
assert_output "is compile-mode"      'defer p : c p . ; : two 2 ; : sw '\'' two is p ; sw c'  "2"
assert_error  "defer uninitialized names the word"       'defer p p'          "p: uninitialized deferred word"
assert_error  "defer uninitialized names the right word" 'defer p defer q q'  "q: uninitialized deferred word"
# Flags2 (header offset 9) carries a word-type code: 1 = defer, 0 = ordinary,
# 2 = value.
assert_output "Flags2 tags a defer as type 1"     'defer p (latest@) 9 + c@ .'  "1"
assert_output "Flags2 leaves a colon word type 0" ': c 1 ; (latest@) 9 + c@ .'  "0"
assert_output "Flags2 tags a value as type 2"     '5 value v (latest@) 9 + c@ .'  "2"
# to/is are type-checked against Flags2: is wants a defer; to takes a value or
# a defer; anything else is refused (the store used to corrupt compiled code).
assert_error  "to refuses an ordinary word"   ': w 7 ; 5 to w'      "w: not a value or deferred word"
assert_error  "to refuses a constant"         '42 constant k 9 to k'  "k: not a value or deferred word"
assert_error  "is refuses an ordinary word"   ': w 7 ; '\'' w is w'  "w: not a deferred word"
assert_error  "is refuses a value"            '5 value v 6 is v'     "v: not a deferred word"
assert_output "to on a defer still allowed"   'defer p : one 1 ; '\'' one to p p .'  "1"
# A refused store must leave the target intact (it used to be corrupted).
ti_out=$(printf ': w 7 ;\n5 to w\nw .\nbye\n' | timeout 2 $FORTH 2>&1)
if [[ "$ti_out" == *"w: not a value or deferred word"* && "$ti_out" == *"7  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  refused to leaves the word intact\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  refused to leaves the word intact\n    Got: %s\n" "$(echo "$ti_out"|head -4)"; ((failed++))
fi
# defer@ / action-of (Forth 2012) and SEE's binding report.
assert_output "defer@ reads the action"      'defer p : one 1 ; '\'' one is p '\'' p defer@ execute .'  "1"
assert_output "action-of reads the action"   'defer p : one 1 ; '\'' one is p action-of p execute .'    "1"
assert_error  "action-of refuses a non-defer" ': w 7 ; action-of w'  "w: not a deferred word"
sb_out=$(printf 'defer d\nsee d\n: one 1 ;\n'\''  one is d\nsee d\n:noname 42 . ; is d\nsee d\nbye\nn\n' \
    | BASICFORTH_SESSION=1 timeout 2 $FORTH 2>&1)
if [[ "$sb_out" == *"currently: uninitialized"* && "$sb_out" == *"currently: ' one is d"* \
      && "$sb_out" == *":noname 42 . ; is d"* ]]; then
    printf "  ${GREEN}PASS${NC}  see reports a defer's binding (uninit/named/:noname)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  see defer-binding report\n    Got: %q\n" "$sb_out"; ((failed++))
fi

# ...and a MULTI-LINE :noname binding: see prints the whole recorded group
# (the old log-line heuristic showed only the final line), via the anonymous
# header's own source metadata.
sbm_out=$(printf 'defer d\n:noname 40\n  2 + . ; is d\nsee d\nbye\nn\n' \
    | BASICFORTH_SESSION=1 timeout 2 $FORTH 2>&1)
if [[ "$sbm_out" == *":noname 40"* && "$sbm_out" == *"2 + . ; is d"* ]]; then
    printf "  ${GREEN}PASS${NC}  see shows a multi-line :noname binding in full\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  see multi-line :noname binding\n    Got: %q\n" "$sbm_out"; ((failed++))
fi

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

# INCLUDE of a directory must error, not segfault (open succeeds on a
# directory; the raw mmap then fails with -ENODEV, which the old check —
# exactly -1 — missed, so -19 was used as the file base address).
assert_error  "include directory errors"    'include /tmp'                       "cannot open /tmp"
assert_output "include directory recovers"  $'include /tmp\n." A." ." B." cr'    "A.B."

# Tabs are whitespace: a source file indented with real tabs (or with tabs
# between tokens) must tokenize — parse-word treats every char <= 0x20 as a
# delimiter, not just space.
tab_file="$(mktemp)"
printf ': tabbed\n\t7 8 + . ;\ntabbed\n: tab2 5\t6 + . ;\ntab2\nbye\n' > "$tab_file"
tab_out=$(BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH "$tab_file" 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
rm -f "$tab_file"
if [[ "$tab_out" == *"15"* && "$tab_out" == *"11"* && "$tab_out" != *"?"* ]]; then
    printf "  ${GREEN}PASS${NC}  tab-indented source file loads\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tab-indented source file loads\n"
    printf "    Expected: 15 and 11, no errors\n    Got:      %s\n" "$(echo "$tab_out" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

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

# examples/chase.fs (the Chase tutorial's finished program) must load and its
# top-down design must work headlessly. step-toward (the smart step every
# brain shares) closes the LONGER axis only — never both (a diagonal pursuer
# would outrun the player) — and x moves in 2-column strides (terminal cells
# are ~2x tall as wide): monster (5,5), aim (10,8) -> (7,5).
t0=$(date +%s.%N)
ch_hunt=$(printf 'include %s/examples/chase.fs\ninit-game\n5 0 mx! 5 0 my!\n10 8 aim!\n0 step-toward\n.( CHX=) 0 mx@ . .( CHY=) 0 my@ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/chase.fs"
if [[ "$ch_hunt" == *"CHX=7"* && "$ch_hunt" == *"CHY=5"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/chase.fs step-toward strides x, one axis per frame\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/chase.fs step-toward strides x, one axis per frame\n"
    printf "    Expected: CHX=7 CHY=5\n    Got:      %s\n" "$(echo "$ch_hunt" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# ...and once x is level with the aim, it switches to the y axis:
# monster (10,5), aim (10,8) -> (10,6).
ch_axis=$(printf 'include %s/examples/chase.fs\ninit-game\n10 0 mx! 5 0 my!\n10 8 aim!\n0 step-toward\n.( AXX=) 0 mx@ . .( AXY=) 0 my@ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
if [[ "$ch_axis" == *"AXX=10"* && "$ch_axis" == *"AXY=6"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/chase.fs step-toward switches to the shorter axis\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/chase.fs step-toward switches to the shorter axis\n"
    printf "    Expected: AXX=10 AXY=6\n    Got:      %s\n" "$(echo "$ch_axis" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# Brains are dice + aim: hunt takes the smart step 50% of frames, drift 15%.
# 200 one-step trials from (5,5) chasing a player at (10,8): the smart step is
# x -> 7, a 2-column stride (p=.5+.5/6~.58 for hunt -> mean 117; p~.29 for drift ->
# mean 58, wobble included). Bounds sit ~4.5 sigma out: stable, not flaky.
ch_dice=$(printf 'include %s/examples/chase.fs\ninit-game\n10 px ! 8 py !\nvariable hh  variable dh\n: htrial 5 0 mx! 5 0 my! 0 hunt  0 mx@ 7 = if 1 hh +! then ;\n: dtrial 5 0 mx! 5 0 my! 0 drift 0 mx@ 7 = if 1 dh +! then ;\n: tally 200 0 do htrial dtrial loop ;\ntally\n.( HUNTOK=) hh @ 85 > . .( DRIFTOK=) dh @ 90 < . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
if [[ "$ch_dice" == *"HUNTOK=-1"* && "$ch_dice" == *"DRIFTOK=-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/chase.fs hunt is sharp, drift is dim (dice)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/chase.fs hunt is sharp, drift is dim (dice)\n"
    printf "    Expected: HUNTOK=-1 DRIFTOK=-1\n    Got:      %s\n" "$(echo "$ch_dice" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# Per-monster brains (the Pac-Man trick): step-monsters runs DIFFERENT minds
# per monster — each slot's token, with that monster's index as argument.
# Install two deterministic test brains (the live ones roll dice) and check
# each slot ran its own.
ch_brains=$(printf 'include %s/examples/chase.fs\ninit-game\n: b0 ( i -- ) drop 100 0 mx! ;\n: b1 ( i -- ) drop 200 1 mx! ;\n%s b0 0 brain!  %s b1 1 brain!\n2 mcount !\nstep-monsters\n.( H0X=) 0 mx@ . .( A1X=) 1 mx@ . cr\nbye\n' "$REPO_ROOT" "'" "'" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
if [[ "$ch_brains" == *"H0X=100"* && "$ch_brains" == *"A1X=200"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/chase.fs runs a different brain per monster\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/chase.fs runs a different brain per monster\n"
    printf "    Expected: H0X=100 A1X=200\n    Got:      %s\n" "$(echo "$ch_brains" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# A monster reaching the player ends the game (collide? sets caught).
ch_caught=$(printf 'include %s/examples/chase.fs\ninit-game\npx @ 0 mx! py @ 0 my!\nfalse caught !\ncollide?\n.( CAUGHT=) caught @ . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
if [[ "$ch_caught" == *"CAUGHT=-1"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/chase.fs ends the game when a monster catches you\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/chase.fs ends the game when a monster catches you\n"
    printf "    Expected: CAUGHT=-1\n    Got:      %s\n" "$(echo "$ch_caught" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# input drains the whole key queue each frame, last key wins: three queued
# DOWN arrows then a LEFT, one input call — the heading must be LEFT, not the
# first stale DOWN. (The sleep lets the drain loop see an empty pipe and stop.)
ch_drain=$({ printf 'include %s/examples/chase.fs\ninit-game\n: t input ." PDX=" pdx @ . ." PDY=" pdy @ . cr ;\n' "$REPO_ROOT"; \
    printf 't\n\033[B\033[B\033[B\033[D'; sleep 1; printf 'bye\n'; } \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
if [[ "$ch_drain" == *"PDX=-1"* && "$ch_drain" == *"PDY=0"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/chase.fs input drains the queue; last key wins\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/chase.fs input drains the queue; last key wins\n"
    printf "    Expected: PDX=-1 PDY=0\n    Got:      %s\n" "$(echo "$ch_drain" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# examples/game-template.fs must load and run out of the box: the stubs make
# `game` a working (blank) frame loop. Make done? end after one frame and
# FRAME instant, then run the whole engine headlessly — finish's stub prints
# "done." and control returns to the interpreter.
t0=$(date +%s.%N)
gt_run=$(printf 'include %s/examples/game-template.fs\n0 to FRAME\n:noname true ; is done?\ngame\n.( TPLOK=1) cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "examples/game-template.fs"
if [[ "$gt_run" == *"done."* && "$gt_run" == *"TPLOK=1"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/game-template.fs runs a full frame out of the box\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/game-template.fs runs a full frame out of the box\n"
    printf "    Expected: done. + TPLOK=1\n    Got:      %s\n" "$(echo "$gt_run" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

# The template's seams accept the intended workflow: FRAME is a value (to
# tunes it) and each seam is a deferred word an is can retarget.
gt_seam=$(printf 'include %s/examples/game-template.fs\n90 to FRAME\n.( FR=) FRAME . cr\n:noname 7 ;\nis update\nupdate\n.( UPD=) . cr\nbye\n' "$REPO_ROOT" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 | tr -d '\0' | tr -dc '[:print:]\n')
if [[ "$gt_seam" == *"FR=90"* && "$gt_seam" == *"UPD=7"* ]]; then
    printf "  ${GREEN}PASS${NC}  examples/game-template.fs seams retarget with to/is\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  examples/game-template.fs seams retarget with to/is\n"
    printf "    Expected: FR=90 UPD=7\n    Got:      %s\n" "$(echo "$gt_seam" | tr -dc '[:print:]' | tail -c 80)"
    ((failed++))
fi

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

# fam is an abstract enum translated by the platform layer; an out-of-range
# fam must fail like a failed open with ior EINVAL, not reach the OS as
# arbitrary flag bits.
assert_output "open-file bad fam -> EINVAL"  's" nofile.xyz" 7 open-file swap drop einval = .'  "-1"
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

# Module persistence: SAVE <name> / LOAD / RELOAD / NEW over named, cwd-relative
# files (no more magic session.fs). Capture only runs in an interactive session,
# so the tests force it on with BASICFORTH_SESSION=1; subshells cd to a tmpdir.
sv_dir="$(mktemp -d)"
# Harness uses a relative binary path (./basicforth); resolve it to absolute since
# these subshells cd elsewhere.
sv_forth="${FORTH/.\//$PWD/}"
t0=$(date +%s.%N)
# Session 1: a multi-line def, a one-liner, a transient action, and a bare ALLOT
# (moves HERE but defines no word — must NOT be captured); save to mod.fs.
( cd "$sv_dir" && printf ': dbl dup + ;\n: tri\n  dup dup * *\n;\n42 .\n100 allot\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
sv_file=$(cat "$sv_dir/mod.fs" 2>/dev/null)
# `basicforth mod.fs` loads the module: its words are defined, capture is on.
sv_reload=$( cd "$sv_dir" && printf '7 dbl . 3 tri . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null )
# Idempotent: load, define nothing, bare save (→ current file) → file unchanged.
cp "$sv_dir/mod.fs" "$sv_dir/before"
( cd "$sv_dir" && printf 'save\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1 )
diff -q "$sv_dir/before" "$sv_dir/mod.fs" >/dev/null && sv_idem=ok || sv_idem=bad
# Cumulative: load, add a word, save → the file keeps the old ones too.
( cd "$sv_dir" && printf ': sq dup * ;\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1 )
sv_cumul=$(cat "$sv_dir/mod.fs")
rm -rf "$sv_dir"
# Session OFF (no env, piped stdin not a tty): no capture; SAVE <name> writes
# nothing (the log is empty), so no file is made.
off_dir="$(mktemp -d)"
( cd "$off_dir" && printf ': zzz 9 ;\nsave mod.fs\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
[ -e "$off_dir/mod.fs" ] && sv_off=made || sv_off=none
rm -rf "$off_dir"
# A failed save never destroys an existing file (atomic .new + rename): block the
# temp by pre-creating mod.fs.new as a directory, so create-file on it fails.
fail_dir="$(mktemp -d)"
printf 'PRECIOUS\n' > "$fail_dir/mod.fs"
mkdir "$fail_dir/mod.fs.new"
( cd "$fail_dir" && printf ': c 3 ;\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
sv_safe=$(cat "$fail_dir/mod.fs" 2>/dev/null)
rm -rf "$fail_dir"
# An empty (0-byte) module file loads cleanly, not wedging the REPL.
empty_dir="$(mktemp -d)"
: > "$empty_dir/mod.fs"
sv_empty=$( cd "$empty_dir" && printf '3 4 + . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null )
rm -rf "$empty_dir"
# -session / reload loop: in one run a word works, -session forgets it, reload
# brings it back from the file.
rl_dir="$(mktemp -d)"
printf ': widget 100 ;\n' > "$rl_dir/mod.fs"
rl_loop=$( cd "$rl_dir" && printf 'widget .\n-session\nwidget\nreload\nwidget .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null )
# The saved file stays PURE definitions (-session / reload / save are never captured).
( cd "$rl_dir" && printf '-session\nreload\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1 )
rl_pure=$(cat "$rl_dir/mod.fs" 2>/dev/null)
# reload picks up an external edit to the module file.
printf ': widget 999 ;\n' > "$rl_dir/mod.fs"
rl_edit=$( cd "$rl_dir" && printf 'reload\nwidget . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null )
rm -rf "$rl_dir"
# A broken module: interactive `basicforth bad.fs` reports the error and DROPS TO
# THE REPL (so you can fix it), the REPL keeps working...
bad_dir="$(mktemp -d)"
printf ': good 1 ;\n: bad nosuchword ;\n' > "$bad_dir/mod.fs"
rl_bad=$( cd "$bad_dir" && printf '5 6 + . bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
# ...but non-interactively the same broken module exits non-zero (Unix utility).
( cd "$bad_dir" && printf '5 6 + . bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1 )
rl_bad_code=$?
rm -rf "$bad_dir"
# LOAD <file> swaps the module mid-session; NEW clears it to a clean slate.
sw_dir="$(mktemp -d)"
printf ': alpha 1 ;\n' > "$sw_dir/a.fs"
printf ': beta 2 ;\n' > "$sw_dir/b.fs"
rl_swap=$( cd "$sw_dir" && printf 'alpha .\nload b.fs\nbeta .\nalpha\nnew\nbeta\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth a.fs 2>&1 )
rm -rf "$sw_dir"
# reload outside an interactive session is a no-op (no active session).
scope_dir="$(mktemp -d)"
printf ': secret 123 ;\n' > "$scope_dir/mod.fs"
rl_scope=$( cd "$scope_dir" && printf 'reload\nsecret . bye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
rm -rf "$scope_dir"
# Graceful degradation when boot-time getcwd fails (startup dir removed out from
# under the process): the REPL must keep working — confirm it still evaluates.
gone_dir="$(mktemp -d)"
gone_out=$( cd "$gone_dir" && rmdir "$gone_dir" && printf '3 4 + .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
t1=$(date +%s.%N); ms=$(elapsed_ms "$t0" "$t1"); update_slowest "$ms" "module persistence"

# `100 allot` IS captured: it moved HERE, so it is dictionary state a replay
# needs (the same rule that keeps a CREATE'd table's data rows). `42 .` moved
# neither pointer, so it stays out.
if [[ "$sv_file" == *": dbl dup + ;"* && "$sv_file" == *"dup dup * *"* \
      && "$sv_file" != *"42 ."* && "$sv_file" == *"100 allot"* ]]; then
    printf "  ${GREEN}PASS${NC}  SAVE <name> captures definitions (multi-line) + dictionary-moving lines, not transient actions\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SAVE captures definitions + dict-moving lines, not transient actions\n    Got: %q\n" "$sv_file"; ((failed++))
fi
if [[ "$sv_reload" == *"14"* && "$sv_reload" == *"27"* ]]; then
    printf "  ${GREEN}PASS${NC}  basicforth <module> loads the saved definitions\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  loading a module\n    Expected 14 and 27\n    Got: %q\n" "$sv_reload"; ((failed++))
fi
if [[ "$sv_idem" == "ok" ]]; then
    printf "  ${GREEN}PASS${NC}  bare SAVE is idempotent (re-save unchanged)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SAVE is idempotent\n"; ((failed++))
fi
if [[ "$sv_cumul" == *": dbl dup + ;"* && "$sv_cumul" == *": sq dup * ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  SAVE is cumulative (adds new defs, keeps old)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SAVE is cumulative\n    Got: %q\n" "$sv_cumul"; ((failed++))
fi
if [[ "$sv_off" == "none" ]]; then
    printf "  ${GREEN}PASS${NC}  no capture / no file written when not interactive\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  unexpected file created when session inactive\n"; ((failed++))
fi
if [[ "$sv_safe" == "PRECIOUS" ]]; then
    printf "  ${GREEN}PASS${NC}  a failed save preserves the existing file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  a failed save destroyed the file\n    Got: %q\n" "$sv_safe"; ((failed++))
fi
if [[ "$sv_empty" == *"7"* ]]; then
    printf "  ${GREEN}PASS${NC}  an empty module file loads without wedging the REPL\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  empty module file wedged the REPL\n    Expected 7\n    Got: %q\n" "$sv_empty"; ((failed++))
fi
if [[ "$rl_loop" == *"100"*"100"* && "$rl_loop" == *"? widget"* ]]; then
    printf "  ${GREEN}PASS${NC}  -session forgets, reload restores (edit/compile/run loop)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  -session/reload loop\n    Expected 100 ... ? widget ... 100\n    Got: %q\n" "$rl_loop"; ((failed++))
fi
if [[ "$rl_pure" == *": widget 100 ;"* && "$rl_pure" != *"-session"* && "$rl_pure" != *"reload"* ]]; then
    printf "  ${GREEN}PASS${NC}  the module file stays pure definitions (no -session/reload lines)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  module file polluted with -session/reload\n    Got: %q\n" "$rl_pure"; ((failed++))
fi
if [[ "$rl_edit" == *"999"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload picks up an external edit to the module file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload did not pick up the edit\n    Expected 999\n    Got: %q\n" "$rl_edit"; ((failed++))
fi
if [[ "$rl_bad" == *"nosuchword"* && "$rl_bad" == *"11"* ]]; then
    printf "  ${GREEN}PASS${NC}  a broken module drops to the REPL (interactive), which keeps going\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  broken module did not drop to the REPL\n    Expected 'nosuchword' and 11\n    Got: %q\n" "$rl_bad"; ((failed++))
fi
if [[ "$rl_bad_code" != "0" ]]; then
    printf "  ${GREEN}PASS${NC}  a broken module exits non-zero when NOT interactive (utility)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  broken module exited 0 non-interactively\n"; ((failed++))
fi
if [[ "$rl_swap" == *"1"* && "$rl_swap" == *"2"* && "$rl_swap" == *"? alpha"* && "$rl_swap" == *"? beta"* ]]; then
    printf "  ${GREEN}PASS${NC}  LOAD swaps the module, NEW clears it\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  LOAD/NEW\n    Expected 1, 2, '? alpha', '? beta'\n    Got: %q\n" "$rl_swap"; ((failed++))
fi
if [[ "$rl_scope" == *"no active session"* && "$rl_scope" == *"? secret"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload is a no-op outside an interactive session (scope)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload acted outside an interactive session\n    Got: %q\n" "$rl_scope"; ((failed++))
fi
if [[ "$gone_out" == *"7"* ]]; then
    printf "  ${GREEN}PASS${NC}  REPL survives a failed boot-time getcwd\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  REPL broke when boot-time getcwd failed\n    Got: %q\n" "$gone_out"; ((failed++))
fi
# EDIT is splice + reload: the edited word's new text replaces its definition
# in the module file and the reload rebuilds every caller by construction —
# leaf=1 → mid=leaf*10 → top prints mid; after editing leaf to 2, `top` must
# print 20 and the FILE must hold the new text with no history and no temp
# droppings. `edit` spawns $EDITOR on "<module>.edit.fs" (the .fs suffix so
# editors filetype-detect Forth) — here a sed.
ep_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: mid leaf 10 * ;\n: top mid . ;\n' > "$ep_dir/mod.fs"
ep_out=$( cd "$ep_dir" && printf 'top\nedit leaf\ntop\nbye\n' \
    | EDITOR='sed -i s/1/2/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 ;
    echo "FILE:"; cat mod.fs; ls mod.fs.edit.fs 2>/dev/null && echo "TEMP-LEFT" )
ep_n=$(grep -c ': leaf' <<<"$ep_out")
rm -rf "$ep_dir"
if [[ "$ep_out" == *"20"* && "$ep_out" == *"FILE:"*": leaf 2 ;"* && "$ep_n" == "1" \
      && "$ep_out" != *"TEMP-LEFT"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit splices the file and reloads — callers live, no droppings\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit splice+reload\n    Expected 20, leaf 2 spliced once, no temp file\n    Got: %q\n" "$ep_out"; ((failed++))
fi
# An untouched temp file is a no-op: vi's :q! exits 0 (only :cq reports
# failure), so edit compares the file image before/after the editor instead
# of trusting the exit status. Nothing is spliced or reloaded.
eu_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: mid leaf 10 * ;\n' > "$eu_dir/mod.fs"
eu_out=$( cd "$eu_dir" && printf 'edit leaf\nmid .\nbye\n' \
    | EDITOR=true BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$eu_dir"
if [[ "$eu_out" == *"edit: unchanged"* && "$eu_out" == *"10"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit with an untouched file is a no-op\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit with an untouched file is a no-op\n    Got: %q\n" "$eu_out"; ((failed++))
fi
# ...which protects deferred words: edit <defer> + quit-without-saving used to
# resubmit the defer line, redefining the defer as fresh (uninitialized) and
# losing its binding. The binding must survive an aborted edit.
ed_dir="$(mktemp -d)"
printf 'defer render\n' > "$ed_dir/mod.fs"
ed_out=$( cd "$ed_dir" && printf ':noname 42 . ; is render\nsave\nedit render\nrender\nbye\n' \
    | EDITOR=true BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$ed_dir"
if [[ "$ed_out" == *"edit: unchanged"* && "$ed_out" == *"42"* && "$ed_out" != *"uninitialized"* ]]; then
    printf "  ${GREEN}PASS${NC}  aborted edit of a defer keeps its binding\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  aborted edit of a defer keeps its binding\n    Got: %q\n" "$ed_out"; ((failed++))
fi
# edit on a DEFERRED word follows the binding. Three flows: an uninitialized
# defer explains itself; a named action redirects to that word; a :noname
# action opens ITS source — saving re-binds the defer live (no propagation:
# callers go through the defer).
ef_dir="$(mktemp -d)"
printf 'defer d\n' > "$ef_dir/mod.fs"
ef_out=$( cd "$ef_dir" && printf 'edit d\n: w1 7 . ;\n'\'' w1 is d\nedit d\n:noname 42 . ; is d\nsave\nedit d\nd\nbye\nn\n' \
    | EDITOR='sed -i s/42/43/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$ef_dir"
if [[ "$ef_out" == *"is uninitialized"* && "$ef_out" == *"edit w1 instead"* && "$ef_out" == *"43"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit on a defer follows the binding (uninit/named/:noname)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit on a defer follows the binding\n    Got: %q\n" "$ef_out"; ((failed++))
fi

# ...and editing a MULTI-LINE :noname binding: the group's xt sits on the data
# stack BETWEEN the replayed lines, so (rd-eval-lines) must keep its loop
# bookkeeping in variables — the xt used to shadow it, corrupt the walk, and
# leak a cell that eventually fed a length to free (segfault). The edited
# group must re-bind, and the stack must come back clean.
em_dir="$(mktemp -d)"
printf 'defer d\n: go2 . . ;\n' > "$em_dir/mod.fs"
printf '#!/bin/sh\nsed -i "s/111/222/" "$1"\n' > "$em_dir/ed.sh" && chmod +x "$em_dir/ed.sh"
em_out=$( cd "$em_dir" && printf ':noname 111\n7 go2 ; is d\nsave\nedit d\nd\n.( DEPTH=) depth . cr\nbye\nn\n' \
    | EDITOR="$em_dir/ed.sh" BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$em_dir"
if [[ "$em_out" == *"7 222"* && "$em_out" == *"DEPTH=0"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit of a multi-line :noname binding re-binds, stack clean\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit of a multi-line :noname binding\n    Expected: 7 222 and DEPTH=0\n    Got: %q\n" "$em_out"; ((failed++))
fi

# DEFINE: `edit` for a word that doesn't exist yet — opens $EDITOR on a
# ": name / ;" template, evaluates + logs the result (multi-line formatting
# survives, `see` shows it, `save` persists it). The scripted editor writes a
# two-line body over the template.
df_dir="$(mktemp -d)"
printf '#!/bin/sh\nprintf ": p100\\n    100 + ;\\n" > "$1"\n' > "$df_dir/ed.sh" && chmod +x "$df_dir/ed.sh"
df_out=$( cd "$df_dir" && printf 'define p100\n5 p100 .\nsee p100\nsave m.fs\nbye\n' \
    | EDITOR="$df_dir/ed.sh" BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 ;
    echo "SAVED:" ; cat m.fs 2>/dev/null )
rm -rf "$df_dir"
if [[ "$df_out" == *"105"* && "$df_out" == *"SAVED:"*": p100"* ]]; then
    printf "  ${GREEN}PASS${NC}  define creates a new word in the editor; see/save cover it\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  define creates a new word in the editor\n    Expected 105 and p100 in the save file\n    Got: %q\n" "$df_out"; ((failed++))
fi
# define refuses an existing word (use edit) — the editor must NOT be spawned
# (EDITOR=false would exit 1 and report "editor exited with status").
dx_out=$( printf ': leaf 1 ;\ndefine leaf\nleaf .\nbye\n' \
    | EDITOR=false BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
if [[ "$dx_out" == *"define: leaf is already defined"* && "$dx_out" == *"use edit"* \
      && "$dx_out" != *"exited with status"* && "$dx_out" == *"1"* ]]; then
    printf "  ${GREEN}PASS${NC}  define refuses an existing word without spawning the editor\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  define refuses an existing word\n    Got: %q\n" "$dx_out"; ((failed++))
fi
# An untouched template is a no-op: nothing is defined, nothing is logged.
du_out=$( printf 'define nope\nnope\nbye\n' \
    | EDITOR=true BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
if [[ "$du_out" == *"define: unchanged"* && "$du_out" == *"? nope"* ]]; then
    printf "  ${GREEN}PASS${NC}  define with an untouched template defines nothing\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  define with an untouched template\n    Got: %q\n" "$du_out"; ((failed++))
fi

# BARE EDIT: `edit` with no name opens the CURRENT MODULE FILE itself and
# reloads on change — the edit-on-disk loop (edit + reload) in one word.
# Unsaved work is AUTO-SAVED first (an edit implies the file is current), so
# the editor sees it and the reload replays it.
be_dir="$(mktemp -d)"
printf ': leaf 41 ;\n' > "$be_dir/mod.fs"
be_out=$( cd "$be_dir" && printf 'leaf .\n: extra 7 ;\nedit\nleaf .\nextra .\nbye\n' \
    | EDITOR='sed -i s/41/52/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$be_dir"
if [[ "$be_out" == *"41"* && "$be_out" == *"52"* && "$be_out" == *"7"* && "$be_out" == *"saved to"* ]]; then
    printf "  ${GREEN}PASS${NC}  bare edit auto-saves, opens the module file, reloads\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  bare edit auto-save + reload\n    Expected 41, 52, extra=7 kept\n    Got: %q\n" "$be_out"; ((failed++))
fi
# An untouched module file skips the reload, so the session (including
# unsaved interactive definitions) is kept as-is.
bu_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$bu_dir/mod.fs"
bu_out=$( cd "$bu_dir" && printf ': extra 7 ;\nedit\nextra .\nbye\n' \
    | EDITOR=true BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$bu_dir"
if [[ "$bu_out" == *"edit: unchanged"* && "$bu_out" == *"7"* ]]; then
    printf "  ${GREEN}PASS${NC}  bare edit with an untouched file keeps the session\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  bare edit with an untouched file\n    Got: %q\n" "$bu_out"; ((failed++))
fi
# Without a current module file there is nothing to open.
bn_out=$( printf 'edit\nbye\n' \
    | EDITOR=true BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
if [[ "$bn_out" == *"edit: no current file"* \
   && "$bn_out" == *"save <name> to start one, or load <name>"* ]]; then
    printf "  ${GREEN}PASS${NC}  bare edit without a module suggests save and load\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  bare edit without a module\n    Got: %q\n" "$bn_out"; ((failed++))
fi

# :e — inline mutation: retype a definition at the prompt; on ; it splices
# the module file over the word's newest definition and reloads. Callers are
# rebuilt by the reload and the session ends clean.
ce_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: mid leaf 10 * ;\n' > "$ce_dir/mod.fs"
ce_out=$( cd "$ce_dir" && printf 'mid .\n:e leaf 3 ;\nmid .\n(dirty) @ .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$ce_dir"
if [[ "$ce_out" == *"30"* && "$ce_out" == *"0  ok"* && "$ce_out" == *"FILE:"*": leaf 3 ;"*": mid leaf 10 * ;"* \
      && "$ce_out" != *": leaf 1"* ]]; then
    printf "  ${GREEN}PASS${NC}  :e splices the file and reloads — callers live, clean\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  :e basic splice\n    Got: %q\n" "$ce_out"; ((failed++))
fi
# Multi-line :e: the whole formatted group (comments, indentation) lands in
# the file, exactly as typed.
cm2_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$cm2_dir/mod.fs"
cm2_out=$( cd "$cm2_dir" && printf ':e leaf\n  \\ doubled now\n  2 * ;\n5 leaf .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$cm2_dir"
if [[ "$cm2_out" == *"10"* && "$cm2_out" == *"FILE:"*"doubled now"*"2 * ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  multi-line :e keeps formatting in the file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  multi-line :e\n    Got: %q\n" "$cm2_out"; ((failed++))
fi
# Refusals flush the rest of the input line (it was the definition body), so
# nothing lands on the stack: unknown word, deferred word. An unsaved session
# is no refusal at all — the mutation auto-saves and proceeds.
cf_dir="$(mktemp -d)"
printf ': leaf 1 ;\ndefer d\n' > "$cf_dir/mod.fs"
cf_out=$( cd "$cf_dir" && printf ':e nosuch 1 ;\ndepth .\n:e d 1 ;\ndepth .\n: w 6 ;\n:e leaf 9 ;\ndepth .\nleaf .\nw .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$cf_dir"
if [[ "$cf_out" == *"not defined"* && "$cf_out" == *"is deferred"* \
      && "$cf_out" == *"saved to"* && "$cf_out" == *"9"* && "$cf_out" == *"6"* \
      && "$cf_out" != *"stack underflow"* ]]; then
    printf "  ${GREEN}PASS${NC}  :e refusals flush; dirty session auto-saves and proceeds\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  :e refusal/auto-save\n    Got: %q\n" "$cf_out"; ((failed++))
fi
# A body that opens its OWN definition is refused before the splice. `: leaf
# 2 ;` is the muscle memory for defining a word, so it is what hands reach
# for after `:e leaf` — but :e already supplied the `:`, and the resulting
# file (": leaf" then ": leaf 2 ;") compiles at the prompt (the old leaf is
# still findable) yet cannot be replayed from a clean file, where the name is
# hidden inside its own unfinished definition. That used to write the broken
# file, lose the word, and leave neither :e nor delete able to reach it.
co_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$co_dir/mod.fs"
co_out=$( cd "$co_dir" && printf ':e leaf\n: leaf 2 ;\nleaf .\n:e leaf 3 ;\nleaf .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$co_dir"
if [[ "$co_out" == *"cannot open a definition"* && "$co_out" == *"1  ok"* \
      && "$co_out" == *"3  ok"* && "$co_out" == *"FILE:"*": leaf 3 ;"* \
      && "$co_out" != *"module may be incomplete"* ]]; then
    printf "  ${GREEN}PASS${NC}  :e body opening a definition is refused, file intact\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  :e body-opens-definition guard\n    Got: %q\n" "$co_out"; ((failed++))
fi
# ...and only the FIRST body token is judged, because a bare ":" token turns
# up inside perfectly ordinary bodies — quoted ([char] :), inside a string
# (s" : "), or in a comment (\ a : b). Scanning the whole body rejected all
# three; a guard that blocks a valid edit is worse than the corruption it
# prevents, so each of these must pass.
cq_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: p 2 ;\n: q 3 ;\n' > "$cq_dir/mod.fs"
cq_out=$( cd "$cq_dir" && printf ':e leaf [char] : emit 7 ;\nleaf .\n:e p s" : " type 9 ;\np .\n:e q\n \\ ratio here : two\n 4 ;\nq .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$cq_dir"
if [[ "$cq_out" == *":7"* && "$cq_out" == *": 9"* && "$cq_out" == *"4  ok"* \
      && "$cq_out" != *"cannot open a definition"* ]]; then
    printf "  ${GREEN}PASS${NC}  :e allows a colon quoted, in a string, or in a comment\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  :e colon false positive\n    Got: %q\n" "$cq_out"; ((failed++))
fi

# Forward-reference warning: a mutation whose new text calls a word defined
# LATER in the file (here: helper, auto-saved to the end moments before) is
# spliced in place anyway, with a warning naming the culprit — the reload's
# line error then points at the fix (bare edit, move helper up).
fw_dir="$(mktemp -d)"
printf ': hunt 1 ;\n: chase hunt 2 * ;\n' > "$fw_dir/mod.fs"
fw_out=$( cd "$fw_dir" && printf ': helper 5 ;\n:e hunt helper 1+ ;\nbye\nn\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$fw_dir"
fw_file="${fw_out#*FILE:}"
if [[ "$fw_out" == *"warning: hunt uses helper, defined later"* \
      && "$fw_file" == *": hunt helper 1+ ;"*": chase hunt 2 * ;"*": helper 5 ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  mutation with a later dependency warns, splices in place\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  forward-reference warning\n    Got: %q\n" "$fw_out"; ((failed++))
fi
# An errored :e definition disarms: the next definition is a plain binding,
# not a splice — leaf and the file stay untouched.
cx_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$cx_dir/mod.fs"
cx_out=$( cd "$cx_dir" && printf ':e leaf\n  nosuchword ;\n: other 42 ;\nother .\nleaf .\nbye\nn\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$cx_dir"
if [[ "$cx_out" == *"? nosuchword"* && "$cx_out" == *"42"* && "$cx_out" == *"1  ok"* \
      && "$cx_out" == *"FILE:"*": leaf 1 ;"* && "$cx_out" != *"other"*"FILE"*"other"* ]]; then
    printf "  ${GREEN}PASS${NC}  an errored :e disarms — next definition binds normally\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  errored :e disarm\n    Got: %q\n" "$cx_out"; ((failed++))
fi

# ` ok` is suppressed while a definition is open: the "... " continuation
# prompt already says "still compiling", so one ok per line doubled the height
# of every multi-line definition. Exactly one ok for the whole definition.
qo_out=$(printf ': my-count\n5 0 do\ni .\nloop ;\nmy-count\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1)
# exactly one ok for the definition, on its CLOSING line (a silent line keeps
# its ok on the command line — see the owed-newline rule in platform_linux.s),
# and none on the continuation lines.
qo_oks=$(grep -c ' ok' <<< "$qo_out")
if [[ "$qo_out" == *"loop ; ok"* && "$qo_out" != *"5 0 do ok"* \
      && "$qo_out" != *"i . ok"* && "$qo_oks" == 2 \
      && "$qo_out" == *"0 1 2 3 4  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  no ok per line while a definition is open\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  ok while compiling (ok lines=%s)\n    Got: %q\n" "$qo_oks" "$qo_out"; ((failed++))
fi

# An aborted definition must not leave its half-built header as LATEST. The
# per-line recovery snapshot points AT that header for a definition spanning
# lines, so restoring it left F_HIDDEN set forever — and everything that asks
# "is a definition open?" (the ok suppression above, the Ctrl-D guard) then
# answered yes for the rest of the session. Both abort routes: a failed word
# and cancel;.
ap_out=$(printf ': bad\nnosuchword\n1 2 + .\n: foo\ncancel;\n3 4 + .\n(latest@) 8 + c@ 64 and .\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1)
if [[ "$ap_out" == *"3  ok"* && "$ap_out" == *"7  ok"* && "$ap_out" == *"0  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  an aborted definition leaves no hidden LATEST\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  aborted definition leaves hidden LATEST\n    Got: %q\n" "$ap_out"; ((failed++))
fi

# cancel; abandons the definition being typed — nothing defined, the rest of
# the line discarded, a pending :e disarmed (nothing spliced, file untouched);
# a later :e still works, and at the prompt cancel; is a friendly no-op.
cq_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$cq_dir/mod.fs"
cq_out=$( cd "$cq_dir" && printf ': foo 1 2 cancel; 3 ;\nfoo\n:e leaf 999 cancel;\nleaf .\ncancel;\n:e leaf 2 ;\nleaf .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$cq_dir"
if [[ "$cq_out" == *"canceled"* && "$cq_out" == *"? foo"* && "$cq_out" == *"1  ok"* \
      && "$cq_out" == *"nothing to cancel"* && "$cq_out" == *"2  ok"* \
      && "$cq_out" == *"FILE:"*": leaf 2 ;"* && "$cq_out" != *"FILE:"*"999"* ]]; then
    printf "  ${GREEN}PASS${NC}  cancel; abandons : and :e definitions cleanly\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cancel;\n    Got: %q\n" "$cq_out"; ((failed++))
fi

# cancel; mid-MULTI-LINE :e: the continuation lines compile as usual until
# cancel; unwinds them — the armed splice never fires.
cq2_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$cq2_dir/mod.fs"
cq2_out=$( cd "$cq2_dir" && printf ':e leaf\n  42\ncancel;\nleaf .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$cq2_dir"
if [[ "$cq2_out" == *"canceled"* && "$cq2_out" == *"1  ok"* \
      && "$cq2_out" == *"FILE:"*": leaf 1 ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  cancel; mid-multi-line :e — nothing spliced\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cancel; multi-line :e\n    Got: %q\n" "$cq2_out"; ((failed++))
fi

# DELETE <name> — :e with nothing as the replacement: the word's newest group
# is spliced OUT of the module file and the module reloads. Survivors replay
# fine; the deleted word is gone from file and dictionary both.
dl_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: mid 2 ;\n' > "$dl_dir/mod.fs"
dl_out=$( cd "$dl_dir" && printf 'delete leaf\nmid .\nleaf\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$dl_dir"
if [[ "$dl_out" == *"deleted leaf"* && "$dl_out" == *"2  ok"* && "$dl_out" == *"? leaf"* \
      && "$dl_out" == *"FILE:"*": mid 2 ;"* && "$dl_out" != *"FILE:"*"leaf"* ]]; then
    printf "  ${GREEN}PASS${NC}  delete splices the group out of the file and reloads\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  delete basic\n    Got: %q\n" "$dl_out"; ((failed++))
fi
# Deleting a redefinition resurrects the prior definition — the "undo my
# redefinition" the warning invites. The dirty session auto-saves first
# (appending the new group), then the newest group is removed.
dr_dir="$(mktemp -d)"
printf ': greet 111 . ;\n' > "$dr_dir/mod.fs"
dr_out=$( cd "$dr_dir" && printf ': greet 222 . ;\ndelete greet\ngreet\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$dr_dir"
if [[ "$dr_out" == *"redefined greet"* && "$dr_out" == *"deleted greet"* \
      && "$dr_out" == *"111"* && "$dr_out" == *"FILE:"*": greet 111 . ;"* \
      && "$dr_out" != *"FILE:"*"222"* ]]; then
    printf "  ${GREEN}PASS${NC}  deleting a redefinition resurrects the prior definition\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  delete resurrection\n    Got: %q\n" "$dr_out"; ((failed++))
fi
# Deleting a depended-on word: the dependent fails its replay line with an
# honest `? name` (dependency surfacing, not dangling pointers) — and the
# delete still lands.
dd_dir="$(mktemp -d)"
printf ': basew 42 . ;\n: caller basew ;\n' > "$dd_dir/mod.fs"
dd_out=$( cd "$dd_dir" && printf 'delete basew\ncaller\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1;
    echo "FILE:"; cat mod.fs )
rm -rf "$dd_dir"
if [[ "$dd_out" == *"? basew"* && "$dd_out" == *"module may be incomplete"* \
      && "$dd_out" == *"deleted basew"* && "$dd_out" == *"? caller"* \
      && "$dd_out" == *"FILE:"*": caller basew ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  deleting a depended-on word surfaces the dependent via replay\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  delete dependent\n    Got: %q\n" "$dd_out"; ((failed++))
fi
# Refusals: unknown word, primitive, a word not in the module file (core.fs
# words), a missing name, and no current file at all.
dg_dir="$(mktemp -d)"
printf ': leaf 1 ;\n' > "$dg_dir/mod.fs"
dg_out=$( cd "$dg_dir" && printf 'delete nosuch\ndelete dup\ndelete erase\ndelete\nleaf .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$dg_dir"
dg_nf=$( printf ': w 1 ;\ndelete w\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
if [[ "$dg_out" == *"delete: nosuch not found"* \
      && "$dg_out" == *"delete: dup is a primitive (assembly); cannot delete"* \
      && "$dg_out" == *"delete: erase is not in"* \
      && "$dg_out" == *"delete: needs a word name"* && "$dg_out" == *"1  ok"* \
      && "$dg_nf" == *"delete: no current file — only saved words can be deleted"* ]]; then
    printf "  ${GREEN}PASS${NC}  delete refusals: unknown, primitive, not-in-module, no name, no file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  delete refusals\n    Got: %q\n    NoFile: %q\n" "$dg_out" "$dg_nf"; ((failed++))
fi

# LIST pages the CAPTURE LOG (BASIC's LIST). The log is the file image — the
# loaded text plus every line captured since — so a word defined seconds ago
# lists like one read from disk, and there is no "unsaved changes" caveat left
# to print. With no file at all a scratch session still lists what you typed
# (BASIC lists before you SAVE); only an empty log has nothing to show.
ls_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: mid leaf 10 * ;\n' > "$ls_dir/mod.fs"
ls_out=$( cd "$ls_dir" && printf 'list\n: extra 5 ;\nlist\nbye\nn\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$ls_dir"
# once as the echoed input line, once in the second listing
ls_extra=$(grep -c ': extra 5 ;' <<< "$ls_out")
ls_nf=$( printf 'list\n: solo 7 ;\nlist\nreload\nbye\nn\n' \
    | BASICFORTH_SESSION=1 timeout 5 $FORTH 2>&1 )
ls_solo=$(grep -c ': solo 7 ;' <<< "$ls_nf")
if [[ "$ls_out" == *": mid leaf 10 * ;"* && "$ls_extra" == 2 \
      && "$ls_out" != *"unsaved changes"* \
      && "$ls_nf" == *"nothing to list — define a word, or load <name>"* \
      && "$ls_solo" == 2 \
      && "$ls_nf" == *"reload: no current file — save <name> to start one, or load <name>"* ]]; then
    printf "  ${GREEN}PASS${NC}  list pages the log (unsaved word included, no caveat; scratch session; empty)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  list\n    Got: %q (extra=%s)\n    No-file: %q (solo=%s)\n" \
        "$ls_out" "$ls_extra" "$ls_nf" "$ls_solo"; ((failed++))
fi

# A module file whose last line has no trailing newline must not be run
# together with the first line captured this session: the log is line-
# structured, so seeding tops it up with the missing newline. Before the fix
# SAVE wrote `: tail 2 ;: extra 5 ;` — one unparseable line, real data loss.
nl_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: tail 2 ;' > "$nl_dir/nonl.fs"        # NO trailing newline
nl_out=$( cd "$nl_dir" && printf ': extra 5 ;\nlist\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth nonl.fs 2>&1 )
nl_file=$(cat "$nl_dir/nonl.fs")
rm -rf "$nl_dir"
if [[ "$nl_out" != *": tail 2 ;: extra"* && "$nl_file" != *": tail 2 ;: extra"* \
      && "$nl_file" == *": tail 2 ;"* && "$nl_file" == *": extra 5 ;"* ]]; then
    printf "  ${GREEN}PASS${NC}  a file with no trailing newline stays line-structured (list + save)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  no-trailing-newline seeding\n    Got: %q\n    File: %q\n" "$nl_out" "$nl_file"; ((failed++))
fi

# FAULT RECOVERY vs the module: a reload that hits a guard fault (here a
# top-level + underflows) must (a) keep every definition COMPLETED before the
# bad line — ; re-anchors the recovery snapshot — and (b) leave the log
# seeded from the file it read, so a later SAVE writes that file back
# byte-identically instead of a stale image of the previous module (this was
# real data loss: save used to silently revert on-disk edits).
fr_dir="$(mktemp -d)"
printf ': a 1 ;\n: b a 10 * ;\n' > "$fr_dir/mod.fs"
printf ': a 1 ;\n: NEW-WORK 42 ;\n+\n: b a 10 * ;\n' > "$fr_dir/bad.fs"
fr_out=$( cd "$fr_dir" && printf 'sh cp bad.fs mod.fs\nreload\na .\nNEW-WORK .\nb .\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
fr_same=$(cmp -s "$fr_dir/mod.fs" "$fr_dir/bad.fs" && echo SAME)
rm -rf "$fr_dir"
if [[ "$fr_out" == *"stack underflow"* && "$fr_out" == *"1  ok"* && "$fr_out" == *"42  ok"* \
      && "$fr_out" == *"? b"* && "$fr_same" == "SAME" ]]; then
    printf "  ${GREEN}PASS${NC}  faulted reload: words before the fault survive, save is file-faithful\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  faulted reload recovery\n    Got: %q  file-same: %q\n" "$fr_out" "$fr_same"; ((failed++))
fi

# The guard-fault messages write with a RAW syscall from the signal handler,
# not through platform_write, so they must pay the owed newline themselves —
# otherwise they land on the command line (`> dropstack underflow`). Reported
# from a live session 2026-07-29, the day after the owed newline shipped: the
# two flush points cover every ordinary write, and these two are the exception.
gm_out=$(printf 'drop\n1 2 + .\nbye\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1)
if [[ "$gm_out" == *$'> drop\nstack underflow'* && "$gm_out" != *"dropstack"* ]]; then
    printf "  ${GREEN}PASS${NC}  guard message starts on its own line (pays the owed newline)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  guard message appended to the command line\n    Got: %q\n" "$gm_out"; ((failed++))
fi

# A guard fault on the SAME LINE as a forget must not resurrect the forgotten
# words: (restore-dict) re-anchors the recovery snapshot.
fm_out=$( printf 'marker m\n: x 1 ;\nm +\nx .\n: y 2 ;\ny .\nbye\n' \
    | BASICFORTH_SESSION=1 timeout 5 $FORTH 2>&1 )
if [[ "$fm_out" == *"stack underflow"* && "$fm_out" == *"? x"* && "$fm_out" == *"2  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  fault after a forget does not resurrect forgotten words\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  fault-after-forget re-anchor\n    Got: %q\n" "$fm_out"; ((failed++))
fi

# SPLICE-SAVE (Module_Architecture stage 1, hyper-static): a plain `:`
# redefinition is a NEW BINDING — earlier words keep the old one — so SAVE
# appends it verbatim (replay-faithful) and keeps the file text untouched
# (comments, layout, every binding in order). A second save is byte-identical.
sp_dir="$(mktemp -d)"
printf '\\ header comment\n: leaf 1 ;\n\n\\ mid doc\n: mid leaf 10 * ;\n' > "$sp_dir/mod.fs"
sp_out=$( cd "$sp_dir" && printf ': leaf 2 ;\n: extra leaf 42 + ;\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1;
    cat mod.fs; cp mod.fs s1
    printf 'save\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1
    cmp -s mod.fs s1 && echo "SAME"; echo "REPLAY:"
    printf 'mid . extra .\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 | sed -n 2p )
sp_n=$(grep -c ': leaf' <<<"$sp_out")
if [[ "$sp_out" == *": leaf 1 ;"* && "$sp_out" == *"header comment"* && "$sp_out" == *"mid doc"* \
      && "$sp_out" == *"SAME"* && "$sp_n" == "2" && "$sp_out" == *"REPLAY:"*"10 44"* ]]; then
    printf "  ${GREEN}PASS${NC}  save appends a : rebinding (hyper-static), file text untouched\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  hyper-static append save\n    Got: %q (leaf defs: %s)\n" "$sp_out" "$sp_n"; ((failed++))
fi
rm -rf "$sp_dir"
# Intermediate bindings are load-bearing: in `: a 1 ; : b a ; : a 2 ;` the
# word b captured the FIRST a — the saved file must keep all three in order
# (a last-wins dedup would write a file that doesn't even load).
hs_dir="$(mktemp -d)"
hs_out=$( cd "$hs_dir" && printf ': a 1 ;\n: b a ;\n: a 2 ;\nsave m.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1;
    cat m.fs; echo "REPLAY:"
    printf 'b . a .\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth m.fs 2>&1 | sed -n 2p )
if [[ "$hs_out" == *": a 1 ;"*": b a ;"*": a 2 ;"* && "$hs_out" == *"REPLAY:"*"1 2"* ]]; then
    printf "  ${GREEN}PASS${NC}  save keeps every binding in order (a/b/a replays 1 2)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  hyper-static binding order\n    Got: %q\n" "$hs_out"; ((failed++))
fi
rm -rf "$hs_dir"
# EDIT is a MUTATION: the edited word's definition is replaced where it
# stands, mutation history never accumulates, and the save is idempotent.
se_dir="$(mktemp -d)"
printf ': leaf 1 ;\n: mid leaf 10 * ;\n' > "$se_dir/mod.fs"
se_out=$( cd "$se_dir" && printf 'edit leaf\nsave\nbye\n' \
    | EDITOR='sed -i s/1/2/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1;
    cat mod.fs; cp mod.fs s1
    printf 'save\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1
    cmp -s mod.fs s1 && echo "SAME" )
se_want=$(printf ': leaf 2 ;\n: mid leaf 10 * ;\nSAME')
if [[ "$se_out" == "$se_want" ]]; then
    printf "  ${GREEN}PASS${NC}  edit mutates in place: zero accumulation, idempotent\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit splice\n    Got: %q\n    Want: %q\n" "$se_out" "$se_want"; ((failed++))
fi
rm -rf "$se_dir"
# A mutation targets the binding it actually edited: after `: thrust 25 ;`
# (a new binding in the tail), `edit thrust` must rewrite THAT binding, not
# the file's original — climb keeps capturing the old thrust on replay.
bm_dir="$(mktemp -d)"
printf ': thrust 10 ;\n: climb thrust 2 * ;\n' > "$bm_dir/mod.fs"
bm_out=$( cd "$bm_dir" && printf ': thrust 25 ;\nsave\nedit thrust\nbye\n' \
    | EDITOR='sed -i s/25/30/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1;
    cat mod.fs; echo "REPLAY:"
    printf ': probe thrust . ; climb . probe\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 | sed -n 2p )
if [[ "$bm_out" == *": thrust 10 ;"*": climb thrust 2 * ;"*": thrust 30 ;"* \
      && "$bm_out" != *"25"* && "$bm_out" == *"REPLAY:"*"20 30"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit after a rebinding mutates the tail binding, not the seed\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit targets the edited binding\n    Got: %q\n" "$bm_out"; ((failed++))
fi
rm -rf "$bm_dir"
# Assignments and :noname groups are order-dependent effects: SAVE keeps the
# file's lines verbatim and appends the session's in the order they happened
# (both groups; the later `is` wins on replay).
sa_dir="$(mktemp -d)"
printf 'defer brain\n10 value speed\n: hunt 1 ;\n' > "$sa_dir/mod.fs"
printf "' hunt is brain\n" >> "$sa_dir/mod.fs"
sa_out=$( cd "$sa_dir" && printf ':noname 2 ; is brain\n:noname 3 ; is brain\n25 to speed\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1;
    cat mod.fs; echo "REPLAY:"
    printf 'brain . speed .\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 | sed -n 2p )
sa_hunt=$(grep -c "' hunt is brain" <<<"$sa_out")
sa_anon=$(grep -c ':noname' <<<"$sa_out")
sa_speed=$(grep -c '25 to speed' <<<"$sa_out")
if [[ "$sa_hunt" == "1" && "$sa_anon" == "2" && "$sa_speed" == "1" \
      && "$sa_out" == *"REPLAY:"*"3 25"* ]]; then
    printf "  ${GREEN}PASS${NC}  save keeps assignments and :noname groups in typed order\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  assignment/anon order\n    Got: %q\n" "$sa_out"; ((failed++))
fi
rm -rf "$sa_dir"

# USES treats :noname actions first-class, and an edit reaches every
# :noname-bound defer through the reload: both groups (saved into the file)
# replay against the edited helper, so BOTH bindings pick up the new code.
ap_dir="$(mktemp -d)"
printf 'defer d1\ndefer d2\n: helper 100 + ;\n' > "$ap_dir/mod.fs"
ap_out=$( cd "$ap_dir" && printf ':noname 5 helper . ; is d1\n:noname 7 helper . ; is d2\nuses helper\nuses d1\nsave\nedit helper\nd1\nd2\nbye\nn\n' \
    | EDITOR='sed -i s/100/200/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$ap_dir"
if [[ "$ap_out" == *"helper is used by: (:noname is d2) (:noname is d1)"* \
      && "$ap_out" == *"d1 is used by: (none)"* ]]; then
    printf "  ${GREEN}PASS${NC}  uses reports live :noname actions (own binding skipped)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  uses on :noname actions\n    Got: %q\n" "$ap_out"; ((failed++))
fi
if [[ "$ap_out" == *"205"* && "$ap_out" == *"207"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit reaches every :noname-bound defer via the reload\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit into :noname actions\n    Expected: 205 and 207\n    Got: %q\n" "$ap_out"; ((failed++))
fi
# Superseded :noname groups stay harmless under reload semantics: both saved
# groups replay in order, the LAST `is` wins, and the transitive chain
# (helper2 calls the edited helper) is rebuilt by construction (7+201 = 208).
ag_dir="$(mktemp -d)"
printf 'defer d\n: helper 100 + ;\n: helper2 helper 1+ ;\n' > "$ag_dir/mod.fs"
ag_out=$( cd "$ag_dir" && printf ':noname 5 helper . ; is d\n:noname 7 helper2 . ; is d\nsave\nedit helper\nd\nbye\nn\n' \
    | EDITOR='sed -i s/100/200/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1 )
rm -rf "$ag_dir"
if [[ "$ag_out" == *"208"* && "$ag_out" != *"205"* ]]; then
    printf "  ${GREEN}PASS${NC}  reload keeps the last :noname binding (transitive ok)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  superseded :noname group under reload\n    Expected 208 (last binding wins)\n    Got: %q\n" "$ag_out"; ((failed++))
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
( cd "$see_dir" && printf ': keep 5 ;\nsee keep\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
see_pure=$(cat "$see_dir/mod.fs" 2>/dev/null)
# SEE must also cover the words of a LOADed module (read from the file via source
# metadata, not interactive capture). Separate dir with a module file we load.
seed_dir="$(mktemp -d)"
printf ': sgreet ." hi" cr ;\nvariable sv\n7 constant sc\n' > "$seed_dir/mod.fs"
see_sc=$( cd "$seed_dir" && printf 'see sgreet\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^: sgreet' )
see_sv=$( cd "$seed_dir" && printf 'see sv\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^variable sv' )
see_sk=$( cd "$seed_dir" && printf 'see sc\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^7 constant sc' )
# ';' inside a string must not truncate the loaded definition's span.
printf ': sstr ." a; b" cr ;\n' > "$seed_dir/mod.fs"
see_sstr=$( cd "$seed_dir" && printf 'see sstr\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^: sstr' )
# reload re-indexes: loaded words stay see-able after a reload.
printf ': sre 1 ;\n' > "$seed_dir/mod.fs"
see_sre=$( cd "$seed_dir" && printf 'reload\nsee sre\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^: sre' )
# Case-insensitive defining words: an uppercase VARIABLE (valid Forth) must index.
printf 'VARIABLE su\n' > "$seed_dir/mod.fs"
see_su=$( cd "$seed_dir" && printf 'see su\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^VARIABLE su' )
# Custom defining words: a word made by a *user-defined* defining word, loaded
# from a module file, is see-able via source metadata — the case the text-parse
# seeded-SEE MVP could not handle.
printf ': mk create , does> @ ;\n5 mk five\n' > "$seed_dir/mod.fs"
see_cdw=$( cd "$seed_dir" && printf 'see five\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^5 mk five' )
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
if [[ "$see_prim" == *"is a primitive (assembly)"* && "$see_prim" == *"try: help dup"* \
      && "$see_prim" == *"dis dup"* ]]; then
    printf "  ${GREEN}PASS${NC}  SEE labels an assembly primitive, points at help and dis\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  SEE primitive label\n    Expected 'is a primitive (assembly)' + 'try: help dup' + 'dis dup'\n    Got: %q\n" "$see_prim"; ((failed++))
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

# uses — list the session words that reference a given word (whole-word,
# case-insensitive, over the interactive capture log like SEE). Forced on
# through a pipe with BASICFORTH_SESSION=1.
uses_dir="$(mktemp -d)"
# Lists referencing words newest-first; excludes the target's own def and
# words that don't reference it (c uses nothing).
uses_basic=$( cd "$uses_dir" && printf 'variable mc\n: a mc @ . ;\n: b mc @ 1+ . ;\n: c 1 . ;\nuses mc\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep 'used by' )
# Whole-word + case-insensitive: MC matches mc, but mcx (used by 'nope') does not.
uses_word=$( cd "$uses_dir" && printf 'variable mc\nvariable mcx\n: nope mcx @ . ;\n: v mc @ . ;\nuses MC\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep 'used by' )
# Nothing references it.
uses_none=$( cd "$uses_dir" && printf ': a 1 . ;\nuses zzz\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null | grep 'used by' )
# Missing argument is reported, not crashed.
uses_noarg=$( cd "$uses_dir" && printf 'uses\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null )

if [[ "$uses_basic" == *"mc is used by: b a"* ]]; then
    printf "  ${GREEN}PASS${NC}  uses lists referencing words newest-first, excluding the target\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  uses basic\n    Expected 'mc is used by: b a'\n    Got: %q\n" "$uses_basic"; ((failed++))
fi
if [[ "$uses_word" == *"used by: v"* && "$uses_word" != *nope* ]]; then
    printf "  ${GREEN}PASS${NC}  uses matches whole words case-insensitively (mc, not mcx)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  uses whole-word/case\n    Expected 'used by: v' and no 'nope'\n    Got: %q\n" "$uses_word"; ((failed++))
fi
if [[ "$uses_none" == *"(none)"* ]]; then
    printf "  ${GREEN}PASS${NC}  uses reports when nothing references the word\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  uses none\n    Expected '(none)'\n    Got: %q\n" "$uses_none"; ((failed++))
fi
if [[ "$uses_noarg" == *"usage: uses"* ]]; then
    printf "  ${GREEN}PASS${NC}  uses with no argument prints usage\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  uses no-arg\n    Expected 'usage: uses'\n    Got: %q\n" "$uses_noarg"; ((failed++))
fi
# FILE-loaded words: uses reads a word's source from its file (like SEE), so it
# works on a program loaded as a startup argument — no capture/session needed.
uses_file=$( printf 'uses mcount\nbye\n' \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth "$REPO_ROOT/examples/chase.fs" 2>/dev/null | grep 'used by' )
if [[ "$uses_file" == *step-monsters* && "$uses_file" == *draw-monsters* && "$uses_file" != *"(none)"* ]]; then
    printf "  ${GREEN}PASS${NC}  uses searches file-loaded words (examples/chase.fs, no session)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  uses on a file-loaded program\n    Expected step-monsters + draw-monsters\n    Got: %q\n" "$uses_file"; ((failed++))
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
# save records direct TO/IS assignments (not just definitions), so a value's
# contents and a deferred word's action survive save + reload. Forced on with
# BASICFORTH_SESSION=1; each runs a session that saves a module, then a fresh
# session that loads it back.
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf '0 value pv\n7 to pv\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_to=$( cd "$ps_dir" && printf 'pv .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^7' )
rm -rf "$ps_dir"
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf 'defer pg\n: ph pg ;\n:noname 42 ; is pg\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_is=$( cd "$ps_dir" && printf 'ph .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^42' )
rm -rf "$ps_dir"
# Over-capture guard: a TO *inside* a called word compiles a store (not forth_to),
# so calling it neither logs a 'setpc' command line nor persists the runtime value.
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf '0 value pc\n: setpc 9 to pc ;\nsetpc\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_call_line=$(grep -c '^setpc$' "$ps_dir/mod.fs")
ps_reload=$( cd "$ps_dir" && printf 'pc .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^0' )
rm -rf "$ps_dir"
# Errored assignment must not leak: the following transient line is not captured.
ps_dir="$(mktemp -d)"
( cd "$ps_dir" && printf '0 value pe\n5 to pe zzz\n1 2 + .\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
ps_leak=$(grep -cE '1 2 \+|5 to pe' "$ps_dir/mod.fs")
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
section "Module lifecycle (keep / on-start / on-stop)"
# =========================================================================
# `keep` marks a line that defined nothing to be logged anyway; on-start /
# on-stop are optional words a module defines to (re)acquire and release the
# resources a reload would otherwise strand. Same harness as the to/is section:
# BASICFORTH_SESSION=1 forces capture on for piped input.

# --- keep: a non-defining line reaches the file, and replays ---
mk_dir="$(mktemp -d)"
( cd "$mk_dir" && printf 'variable v\n7 v !\n42 v !  keep\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
mk_kept=$(grep -c '^42 v !  keep$' "$mk_dir/mod.fs")     # the kept line is written verbatim
mk_dropped=$(grep -c '^7 v !$' "$mk_dir/mod.fs")         # the unkept one still is not
mk_replay=$( cd "$mk_dir" && printf 'v @ .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^42' )
# Re-saving the reloaded module must be byte-identical: the `keep` token replayed
# from the file is inert (source-id is the fileid, not 0), so it must not re-log.
cp "$mk_dir/mod.fs" "$mk_dir/before.fs"
( cd "$mk_dir" && printf 'save\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1 )
if cmp -s "$mk_dir/before.fs" "$mk_dir/mod.fs"; then mk_idem=SAME; else mk_idem=DIFF; fi
rm -rf "$mk_dir"

# --- keep: data rows after a CREATE survive (the documented capture gap) ---
mk_dir="$(mktemp -d)"
( cd "$mk_dir" && printf 'create tbl\n1 , 2 , 3 ,  keep\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
mk_tbl=$( cd "$mk_dir" && printf 'tbl @ . tbl cell+ @ . tbl 2 cells + @ .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^1 2 3')
rm -rf "$mk_dir"

# --- data laid down after a CREATE survives save (HERE moved, LATEST did not) ---
mk_dir="$(mktemp -d)"
( cd "$mk_dir" && printf 'create tbl\n1 , 2 , 3 ,\ncreate art\n%%00111100 c,\n%%11111111 c,\n5 5 + .\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
mk_rows=$( cd "$mk_dir" && printf 'tbl @ . tbl cell+ @ . tbl 2 cells + @ . art c@ . art 1+ c@ .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep '^1 2 3 60 255')
mk_transient=$(grep -c '^5 5 + \.$' "$mk_dir/mod.fs")     # still dropped: moved neither
# re-saving the reloaded module must stay byte-identical
cp "$mk_dir/mod.fs" "$mk_dir/before.fs"
( cd "$mk_dir" && printf 'save\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs >/dev/null 2>&1 )
if cmp -s "$mk_dir/before.fs" "$mk_dir/mod.fs"; then mk_rows_idem=SAME; else mk_rows_idem=DIFF; fi
rm -rf "$mk_dir"

# --- a marker rollback moves the pointers BACKWARD: still not captured ---
mk_dir="$(mktemp -d)"
( cd "$mk_dir" && printf 'marker -try\n: doomed 1 ;\n-try\n: keeper 2 ;\nsave mod.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
mk_marker=$(grep -cE '^-try$' "$mk_dir/mod.fs")
mk_keeper=$(grep -c '^: keeper 2 ;$' "$mk_dir/mod.fs")
rm -rf "$mk_dir"

# --- the module verbs must not capture themselves (they move neither pointer) ---
mk_dir="$(mktemp -d)"
( cd "$mk_dir" && printf ': w1 1 ;\nsave mod.fs\n.module\nlist\n-session\nsave\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth >/dev/null 2>&1 )
mk_verbs=$(grep -cE '^(save|list|\.module|-session|reload)' "$mk_dir/mod.fs")
rm -rf "$mk_dir"

# --- on-start / on-stop fire, in the right order, around each verb ---
mk_dir="$(mktemp -d)"
cat > "$mk_dir/mod.fs" <<'MKEOF'
: on-start  ." [start]" cr ;
: on-stop   ." [stop]" cr ;
: mk-hi  ." hi" cr ;
MKEOF
# startup with a module file runs on-start (parity with reload)
mk_boot=$( cd "$mk_dir" && printf 'bye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep -c '\[start\]')
# load: start only (nothing was open yet); reload: stop then start; new: stop only
mk_seq=$( cd "$mk_dir" && printf 'load mod.fs\nreload\nnew\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>/dev/null \
    | grep -oE '\[(start|stop)\]' | tr '\n' ' ')
# a reload must not leak cells (FIND leaves the name behind when a hook is absent)
mk_depth=$( cd "$mk_dir" && printf 'reload\n.( D=) depth . cr\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>/dev/null | grep -oE 'D=[0-9]+')
rm -rf "$mk_dir"

# --- a module with no hooks is unaffected, and a throwing hook is non-fatal ---
mk_dir="$(mktemp -d)"
cat > "$mk_dir/plain.fs" <<'MKEOF'
: mk-plain  99 ;
MKEOF
mk_plain=$( cd "$mk_dir" && printf 'reload\nmk-plain .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth plain.fs 2>/dev/null | grep '^99')
cat > "$mk_dir/bad.fs" <<'MKEOF'
: on-start  -9 throw ;
: mk-alive  77 ;
MKEOF
mk_bad=$( cd "$mk_dir" && printf 'mk-alive .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth bad.fs 2>/dev/null)
# a hook that reloads must not recurse forever (the timeout is the real assertion)
cat > "$mk_dir/loop.fs" <<'MKEOF'
: on-start  reload ;
: mk-loop  55 ;
MKEOF
mk_loop=$( cd "$mk_dir" && printf 'mk-loop .\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth loop.fs 2>/dev/null | grep '^55')
rm -rf "$mk_dir"

# --- booting?: is this load STARTING the program, or starting it OVER? ---
# So a module can launch itself on a real start without relaunching on edits.
mk_dir="$(mktemp -d)"
cat > "$mk_dir/boot.fs" <<'MKEOF'
: on-start  ." [b" booting? if ." 1" else ." 0" then ." ]" cr ;
: mk-b  1 ;
MKEOF
# boot / reload / load — start, start-over, start
mk_bootq=$( cd "$mk_dir" && printf 'reload\nload boot.fs\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth boot.fs 2>/dev/null \
    | grep -oE '\[b[01]\]' | tr '\n' ' ')
# meaningful only during the hook; false at the prompt
mk_bootout=$( cd "$mk_dir" && printf '.( O=) booting? . cr\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth boot.fs 2>/dev/null \
    | grep -oE 'O=-?[0-9]+')
# a dirty :e reloads TWICE (auto-save, then splice) — both are restarts, so a
# self-launching module must not run itself twice per edit
mk_bootedit=$( cd "$mk_dir" && printf ': mk-extra 9 ;\nedit mk-b\nbye\n' \
    | EDITOR='sed -i s/1/2/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth boot.fs 2>/dev/null \
    | grep -oE '\[b[01]\]' | tr '\n' ' ')
rm -rf "$mk_dir"

if [[ "$mk_kept" == "1" && "$mk_dropped" == "0" && "$mk_replay" == 42* ]]; then
    printf "  ${GREEN}PASS${NC}  keep logs a non-defining line; an unkept one is still dropped\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  keep capture\n    kept: %q  dropped: %q  replay: %q\n" \
        "$mk_kept" "$mk_dropped" "$mk_replay"; ((failed++))
fi
if [[ "$mk_idem" == "SAME" ]]; then
    printf "  ${GREEN}PASS${NC}  a kept line replayed from the file is inert (re-save identical)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  keep re-save not idempotent\n    %q\n" "$mk_idem"; ((failed++))
fi
if [[ -n "$mk_rows" && "$mk_transient" == "0" && "$mk_rows_idem" == "SAME" ]]; then
    printf "  ${GREEN}PASS${NC}  data rows after a create survive save (HERE moved); transient line still dropped\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  create-data capture\n    rows: %q  transient-lines: %q  re-save: %q\n" \
        "$mk_rows" "$mk_transient" "$mk_rows_idem"; ((failed++))
fi
if [[ "$mk_marker" == "0" && "$mk_keeper" == "1" ]]; then
    printf "  ${GREEN}PASS${NC}  a marker rollback (pointers move backward) is still not captured\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  marker rollback captured\n    marker-lines: %q  keeper: %q\n" "$mk_marker" "$mk_keeper"; ((failed++))
fi
if [[ "$mk_verbs" == "0" ]]; then
    printf "  ${GREEN}PASS${NC}  the module verbs do not capture themselves\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  a module verb leaked into the file\n    matched lines: %q\n" "$mk_verbs"; ((failed++))
fi
if [[ -n "$mk_tbl" ]]; then
    printf "  ${GREEN}PASS${NC}  keep preserves data rows laid down after a create\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  keep after create\n    Expected '1 2 3'\n    Got: %q\n" "$mk_tbl"; ((failed++))
fi
if [[ "$mk_boot" == "1" ]]; then
    printf "  ${GREEN}PASS${NC}  on-start runs for a module given on the command line\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  on-start at startup\n    [start] count: %q\n" "$mk_boot"; ((failed++))
fi
if [[ "$mk_seq" == "[start] [stop] [start] [stop] " ]]; then
    printf "  ${GREEN}PASS${NC}  load/reload/new fire the hooks in order (stop before start)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  hook order\n    Expected '[start] [stop] [start] [stop] '\n    Got: %q\n" "$mk_seq"; ((failed++))
fi
if [[ "$mk_depth" == "D=0" ]]; then
    printf "  ${GREEN}PASS${NC}  a reload leaves the stack balanced\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reload leaked stack cells\n    Expected 'D=0'\n    Got: %q\n" "$mk_depth"; ((failed++))
fi
if [[ "$mk_plain" == 99* ]]; then
    printf "  ${GREEN}PASS${NC}  a module defining no hooks reloads unchanged\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  hookless module\n    Expected '99'\n    Got: %q\n" "$mk_plain"; ((failed++))
fi
if [[ "$mk_bad" == *"error in on-start hook: -9"* && "$mk_bad" == *77* ]]; then
    printf "  ${GREEN}PASS${NC}  a throwing hook reports and leaves the module usable\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  throwing hook\n    Got: %q\n" "$mk_bad"; ((failed++))
fi
if [[ "$mk_loop" == 55* ]]; then
    printf "  ${GREEN}PASS${NC}  a hook that reloads does not recurse\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  hook re-entrancy\n    Expected '55'\n    Got: %q\n" "$mk_loop"; ((failed++))
fi
if [[ "$mk_bootq" == "[b1] [b0] [b1] " ]]; then
    printf "  ${GREEN}PASS${NC}  booting? true at startup and for load, false for reload\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  booting?\n    Expected '[b1] [b0] [b1] '\n    Got: %q\n" "$mk_bootq"; ((failed++))
fi
if [[ "$mk_bootout" == "O=0" ]]; then
    printf "  ${GREEN}PASS${NC}  booting? is false outside the hook\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  booting? outside the hook\n    Expected 'O=0'\n    Got: %q\n" "$mk_bootout"; ((failed++))
fi
if [[ "$mk_bootedit" == "[b1] [b0] [b0] " ]]; then
    printf "  ${GREEN}PASS${NC}  both reloads of a dirty :e are restarts, not boots\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  booting? across a dirty :e\n    Expected '[b1] [b0] [b0] '\n    Got: %q\n" "$mk_bootedit"; ((failed++))
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
section "Help system (help / tutorials / apropos)"
# =========================================================================

# Build a throwaway docs directory with two .md topics plus a non-.md file
# that must be ignored. Widgets.md follows the reference-page convention:
# a preamble (title + intro, what `help widgets` prints) up to the first
# "## " heading, then one "## <word> ( effect )" entry block per word.
docs_dir="$(mktemp -d)"
cat > "$docs_dir/Widgets.md" <<'EOF'
# Widgets
The widget subsystem and its gears.

## spin ( n -- )
Spin the widget n times, greased by gears.

    3 spin

## grease oil ( -- )
Lubricate the widget works.

## spin faster ( -- )
Spin at full speed.
EOF
printf '# Sound\nNothing relevant in this one.\n\n## oil ( -- )\nOil the speaker bearings.\n' > "$docs_dir/Sound.md"
printf 'ignore me\n'                              > "$docs_dir/notes.txt"
printf '# Big Topic\nfolded topic body here.\n'   > "$docs_dir/Big_Topic.md"

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

docs_check "help lists .md topics"         "help" "Widgets"
docs_check "help lists every topic"        "help" "Sound"
docs_check "help footer names both forms"  "help" "help <word>"
docs_check "help points at tutorials"      "help" "tutorials"
docs_check "help <topic> prints preamble"  "help Widgets" "widget subsystem and its gears"
docs_check "help topic is case-insensitive" "help widgets" "widget subsystem and its gears"
docs_check "help topic folds - and _"      "help big-topic" "folded topic body here"
docs_check "help <word> prints its entry"  "help spin" "Spin the widget n times"
docs_check "help word is case-insensitive" "help SPIN" "Spin the widget n times"
docs_check "help word entry shows heading" "help spin" "## spin ( n -- )"
docs_check "help shared heading, 1st word" "help grease" "Lubricate the widget works"
docs_check "help shared heading, 2nd word" "help oil" "Lubricate the widget works"
docs_check "help on missing name"          "help nope" "no help for nope"
docs_check "stack-effect tokens are not words" "help n" "no help for n"
docs_check "man is retired"                "man Widgets" "? man"
docs_check "topics is retired"             "topics" "? topics"
docs_check "apropos finds a match"         "apropos gears" "Widgets"
docs_check "apropos is case-insensitive"   "apropos GEARS" "Widgets"

# help <topic> stops at the first "## " heading (preamble only, no entries)
pre_out=$(printf 'help Widgets\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$pre_out" == *"widget subsystem"* && "$pre_out" != *"Spin the widget"* ]]; then
    printf "  ${GREEN}PASS${NC}  help <topic> stops at the first entry\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help <topic> stops at the first entry\n"
    printf "    Got:      %s\n" "$(echo "$pre_out" | head -6)"; ((failed++))
fi

# help <word> prints only matching entry blocks (heading to next "## "),
# but ALL of them — `spin` heads two entries, like `begin` in the real docs
ent_out=$(printf 'help spin\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$ent_out" == *"3 spin"* && "$ent_out" == *"Spin at full speed"* \
   && "$ent_out" != *"Lubricate"* && "$ent_out" != *"widget subsystem"* ]]; then
    printf "  ${GREEN}PASS${NC}  help <word> prints every matching entry, only those\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help <word> prints every matching entry, only those\n"
    printf "    Got:      %s\n" "$(echo "$ent_out" | head -10)"; ((failed++))
fi

# ...including entries on different pages: oil is in Widgets.md AND Sound.md
oil_out=$(printf 'help oil\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$oil_out" == *"Lubricate"* && "$oil_out" == *"speaker bearings"* ]]; then
    printf "  ${GREEN}PASS${NC}  help <word> gathers entries across pages\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help <word> gathers entries across pages\n"
    printf "    Got:      %s\n" "$(echo "$oil_out" | head -8)"; ((failed++))
fi

# Each file's group of entries is labeled with the topic page it came from:
# a "<Topic>:" header before the FIRST matched entry — once per file, even
# when the file contributes several entries (spin heads two in Widgets.md)
if [[ $(echo "$ent_out" | grep -c "^Widgets:$") -eq 1 ]]; then
    printf "  ${GREEN}PASS${NC}  help <word> names the topic page, once per file\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help <word> names the topic page, once per file\n"
    printf "    Got:      %s\n" "$(echo "$ent_out" | head -8)"; ((failed++))
fi

# ...and a word documented on two pages gets both headers, each ahead of
# its own group (Widgets: before Lubricate, Sound: before speaker bearings)
w_at=$(echo "$oil_out" | grep -n "^Widgets:$" | head -1 | cut -d: -f1)
s_at=$(echo "$oil_out" | grep -n "^Sound:$"   | head -1 | cut -d: -f1)
lub_at=$(echo "$oil_out" | grep -n "Lubricate"        | head -1 | cut -d: -f1)
spk_at=$(echo "$oil_out" | grep -n "speaker bearings" | head -1 | cut -d: -f1)
if [[ -n "$w_at" && -n "$s_at" && -n "$lub_at" && -n "$spk_at" \
   && "$w_at" -lt "$lub_at" && "$s_at" -lt "$spk_at" ]]; then
    printf "  ${GREEN}PASS${NC}  cross-page entries: each group led by its own topic header\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  cross-page entries: each group led by its own topic header\n"
    printf "    Got:      %s\n" "$(echo "$oil_out" | head -10)"; ((failed++))
fi

# The real-docs case that motivated multi-entry help: `help begin` must show
# all three indefinite-loop entries from Language-Reference/Loops.md
# timeout 5 (not 2): help begin scans the whole Language-Reference corpus,
# which keeps growing; 2 s is marginal under qemu when the host is loaded.
begin_out=$(printf 'help begin\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$REPO_ROOT/docs/Language-Reference" timeout 5 $FORTH 2>&1)
if [[ $(echo "$begin_out" | grep -c "^## begin") -eq 3 ]]; then
    printf "  ${GREEN}PASS${NC}  help begin shows all three begin entries\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help begin shows all three begin entries\n"
    printf "    Got %s '## begin' headings\n" "$(echo "$begin_out" | grep -c '^## begin')"; ((failed++))
fi
if [[ $(echo "$begin_out" | grep -c "^Loops:$") -eq 1 ]]; then
    printf "  ${GREEN}PASS${NC}  help begin: one Loops: header for the whole group\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help begin: one Loops: header for the whole group\n"
    printf "    Got %s 'Loops:' headers\n" "$(echo "$begin_out" | grep -c '^Loops:$')"; ((failed++))
fi

# Markdown rendering is tty-only: piped help output must stay byte-identical
# to the file — no escape bytes, and the ## / `` / ** markers intact. (The
# rendered path is exercised by the PTY suite on a real terminal.)
esc_out=$(printf 'help spin\nhelp Widgets\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$esc_out" != *$'\x1b'* && "$esc_out" == *'## spin ( n -- )'* ]]; then
    printf "  ${GREEN}PASS${NC}  piped help: no escape bytes, markdown intact\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  piped help: no escape bytes, markdown intact\n"; ((failed++))
fi

# The attribute words themselves are silent on a piped stdout (the primitive
# checks isatty), so they are safe in scripts and filters.
attr_out=$(printf '10 color bold reverse italic ." visible" normal cr bye\n' | \
    BASICFORTH_PATH="$FORTH_LIB" timeout 2 $FORTH 2>&1)
if [[ "$attr_out" != *$'\x1b'* && "$attr_out" == *"visible"* ]]; then
    printf "  ${GREEN}PASS${NC}  color/bold/reverse/italic/normal: silent when piped\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  color/bold/reverse/italic/normal: silent when piped\n"; ((failed++))
fi

# notes.txt is not a topic
notes_out=$(printf 'help\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$notes_out" != *"notes"* ]]; then
    printf "  ${GREEN}PASS${NC}  help excludes notes.txt\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help excludes notes.txt\n"; ((failed++))
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
unset_out=$(printf 'help\nhelp stack\ntutorials\n' | BASICFORTH_PATH="$FORTH_LIB" \
    env -u BASICFORTH_DOCS timeout 2 $FORTH 2>&1)
if [[ $(echo "$unset_out" | grep -c "BASICFORTH_DOCS not set") -eq 3 ]]; then
    printf "  ${GREEN}PASS${NC}  help/tutorials with no BASICFORTH_DOCS\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help/tutorials with no BASICFORTH_DOCS\n"
    printf "    Got:      %s\n" "$(echo "$unset_out" | head -4)"; ((failed++))
fi

# Long docs path must not overflow the internal path buffer. Pad the directory
# with resolvable "/." segments so the directory still opens (the kernel/open
# clamp keeps it valid) while the segment length exceeds the path-build buffer.
# Before the bounds check this corrupted the dictionary; now help/apropos just
# find nothing and the REPL stays alive.
long_docs="$docs_dir"
while [ "${#long_docs}" -lt 600 ]; do long_docs="$long_docs/."; done
long_out=$(printf 'help Widgets\nhelp spin\napropos gears\n42 .\nbye\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$long_docs" timeout 2 $FORTH 2>&1)
long_status=$?
if [ "$long_status" -eq 0 ] && [[ "$long_out" == *"42"* ]] && [[ "$long_out" == *"Goodbye!"* ]]; then
    printf "  ${GREEN}PASS${NC}  long docs path does not corrupt memory\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  long docs path does not corrupt memory\n"
    printf "    exit %s, output: %s\n" "$long_status" "$(echo "$long_out" | head -3)"; ((failed++))
fi

# Section grouping: help groups topics under their directory (section) name,
# and apropos labels each hit with its section. A directory named "Tutorial"
# is excluded from bare help (it belongs to `tutorials`); an empty section
# (no .md) prints no header.
sec_base="$(mktemp -d)"
mkdir -p "$sec_base/RefSec" "$sec_base/Tutorial" "$sec_base/EmptySec"
printf '# Alpha\nwidget gear\n' > "$sec_base/RefSec/Alpha.md"
printf '# Beta\nmore widget\n'  > "$sec_base/RefSec/Beta.md"
printf '# Lesson\nnothing\n'    > "$sec_base/Tutorial/Lesson.md"
printf '# Grok — Learn widgets fast\nintro\n' > "$sec_base/Tutorial/Grok.md"
printf 'no title here\n'        > "$sec_base/Tutorial/Plain.md"
printf 'not a topic\n'          > "$sec_base/EmptySec/readme.txt"
sec_docs="$sec_base/RefSec:$sec_base/Tutorial:$sec_base/EmptySec"

sec_out=$(printf 'help\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sec_docs" timeout 2 $FORTH 2>&1)
if [[ "$sec_out" == *"RefSec"* ]] && [[ "$sec_out" == *"Alpha"* ]] \
   && [[ "$sec_out" == *"Beta"* ]]; then
    printf "  ${GREEN}PASS${NC}  help groups under section headers\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help groups under section headers\n"
    printf "    Got:      %s\n" "$(echo "$sec_out" | head -6)"; ((failed++))
fi

# The Tutorial section is bare help's one exclusion — `tutorials` lists it
if [[ "$sec_out" != *"Lesson"* ]]; then
    printf "  ${GREEN}PASS${NC}  help excludes the Tutorial section\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help excludes the Tutorial section\n"; ((failed++))
fi
tuts_out=$(printf 'tutorials\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sec_docs" timeout 2 $FORTH 2>&1)
if [[ "$tuts_out" == *"Lesson"* ]] && [[ "$tuts_out" == *"tutorial <name>"* ]] \
   && [[ "$tuts_out" != *"Alpha"* ]]; then
    printf "  ${GREEN}PASS${NC}  tutorials lists only the Tutorial section\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tutorials lists only the Tutorial section\n"
    printf "    Got:      %s\n" "$(echo "$tuts_out" | head -4)"; ((failed++))
fi

# The listing shows each tutorial's title line ("# Name — description"
# convention, hashes stripped); a file with no title falls back to its name.
if [[ "$tuts_out" == *"Grok — Learn widgets fast"* ]]; then
    printf "  ${GREEN}PASS${NC}  tutorials shows the title-line description\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tutorials shows the title-line description\n"
    printf "    Got:      %s\n" "$(echo "$tuts_out" | head -5)"; ((failed++))
fi
if [[ "$tuts_out" == *"Plain"* && "$tuts_out" != *"no title here"* ]]; then
    printf "  ${GREEN}PASS${NC}  tutorials falls back to the file name\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tutorials falls back to the file name\n"
    printf "    Got:      %s\n" "$(echo "$tuts_out" | head -5)"; ((failed++))
fi

# An empty section (no .md) must not print a header
if [[ "$sec_out" != *"EmptySec"* ]]; then
    printf "  ${GREEN}PASS${NC}  help omits empty section header\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help omits empty section header\n"; ((failed++))
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

# help sorts names alphabetically within a section (regardless of filesystem
# order) and lays them out three to a row, aligned on a fixed field width.
sort_base="$(mktemp -d)"
for n in Zebra Apple Mango Kiwi; do printf '# %s\n' "$n" > "$sort_base/$n.md"; done
sort_out=$(printf 'help\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sort_base" timeout 2 $FORTH 2>&1)
if echo "$sort_out" | grep -Eq '^  Apple +Kiwi +Mango$' \
   && echo "$sort_out" | grep -Eq '^  Zebra$'; then
    printf "  ${GREEN}PASS${NC}  help sorts names into three columns\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help sorts names into three columns\n"
    printf "    Got:      %s\n" "$(echo "$sort_out" | head -4)"; ((failed++))
fi
rm -rf "$sort_base"

# `tutorial <name>` resolves only in Tutorial sections — a reference page with
# the same name (e.g. Strings.md in both Language-Reference and Tutorial) must
# not shadow the lesson, even when its directory comes first in the path.
printf '# Grok reference page\nREFBODY\n' > "$sec_base/RefSec/Grok.md"
tut_shadow=$(printf 'tutorial Grok\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$sec_docs" timeout 2 $FORTH 2>&1)
if [[ "$tut_shadow" == *"Learn widgets fast"* && "$tut_shadow" != *"REFBODY"* ]]; then
    printf "  ${GREEN}PASS${NC}  tutorial ignores same-named reference pages\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tutorial ignores same-named reference pages\n"
    printf "    Got:      %s\n" "$(echo "$tut_shadow" | head -4)"; ((failed++))
fi

rm -rf "$sec_base"

# A "topic" that is actually a directory: open() succeeds but read() returns
# EISDIR. help must report it via "(read error)" and the REPL must keep
# running afterward — a regression guard for the preamble pager not aborting
# through (ht-in) (which would skip its directory-fd cleanup and leak it).
mkdir "$docs_dir/Brokendir.md"
brk_out=$(printf 'help Brokendir\n9 9 + .\nbye\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$docs_dir" timeout 2 $FORTH 2>&1)
if [[ "$brk_out" == *"(read error)"* && "$brk_out" == *"18"* ]]; then
    printf "  ${GREEN}PASS${NC}  help on a directory-topic reports read error, REPL survives\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help on a directory-topic (pager cleanup)\n    Got: %s\n" "$(echo "$brk_out" | head -5)"; ((failed++))
fi

rm -rf "$docs_dir"

# Reference coverage audit: every user-facing word in the live dictionary
# must have a "## " heading entry in some docs/Language-Reference page —
# the `help <word>` contract. Parenthesized names are internal by
# convention; the exclusion list is the eight deliberate internals.
# (set -f: the dictionary contains `*` and `*/`, which must not glob.)
audit_words=$(printf 'words\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 \
    | sed -n '2p' | sed 's/ ok *$//')
audit_heads=$(awk '/^## /{ for(i=2;i<=NF;i++){ if($i=="("){ if(i==2) print "("; else break } else print tolower($i) } }' \
    "$REPO_ROOT"/docs/Language-Reference/*.md | sort -u)
audit_missing=""
set -f
for w in $audit_words; do
    case "$w" in \(*) continue;; esac
    lw=$(printf '%s' "$w" | tr 'A-Z' 'a-z')
    case " hld lit >digit >digit? fill32 einval page-file chdir " in
        *" $lw "*) continue;;
    esac
    printf '%s\n' "$audit_heads" | grep -qxF -e "$lw" || audit_missing="$audit_missing $w"
done
set +f
if [ -n "$audit_words" ] && [ -z "$audit_missing" ]; then
    printf "  ${GREEN}PASS${NC}  every word has a Language-Reference entry\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  every word has a Language-Reference entry\n"
    printf "    Undocumented:%s\n" "${audit_missing:- (no words output)}"; ((failed++))
fi

# The same audit for the AUDIO library words, which the core sweep above cannot
# see: they only exist after `require wav.fs`, so sound.fs/wavcore.fs/wav.fs
# could add public names with no help entry and nothing would notice. Found
# that way -- snd-dev and snd-stream were public-looking names for raw SDL
# handles. Parenthesised names are internal by convention and skipped, as above.
if [[ "$FORTH" == *qemu* ]] || ! ldconfig -p 2>/dev/null | grep -q libSDL3; then
    printf "  ${YELLOW}SKIP${NC}  every audio library word has a reference entry (needs libSDL3)\n"
else
    lib_words=$(printf 'require wav.fs\nwords\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 10 $FORTH 2>&1 \
        | sed -n '3p' | sed 's/ ok *$//')
    lib_core=$(printf 'words\n' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1 \
        | sed -n '2p' | sed 's/ ok *$//')
    lib_missing=""
    set -f
    for w in $lib_words; do
        case "$w" in \(*) continue;; esac
        case " $lib_core " in *" $w "*) continue;; esac
        lw=$(printf '%s' "$w" | tr 'A-Z' 'a-z')
        printf '%s\n' "$audit_heads" | grep -qxF -e "$lw" || lib_missing="$lib_missing $w"
    done
    set +f
    if [ -n "$lib_words" ] && [ -z "$lib_missing" ]; then
        printf "  ${GREEN}PASS${NC}  every audio library word has a reference entry\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  every audio library word has a reference entry\n"
        printf "    Undocumented:%s\n" "${lib_missing:- (no words output)}"; ((failed++))
    fi
fi

# Reference lint: an entry with NO TEXT under it is blank at the prompt, since
# help shows one heading and the body beneath it. Stacking two headings does
# that, and so does a heading followed only by a blank line -- both read fine
# in the file and are broken where it counts. Six entries shipped that way.
# Only WORD entries are checked: a heading carrying a stack effect "( ... )".
# Headings without one are section titles ("## Constants") that legitimately
# have nothing but more headings under them.
stack_bad=$(awk '
    function flush() { if (pend != "" && !content) print pfile":"pline"  "pend }
    FNR==1 { flush(); pend=""; content=0 }
    /^## / { flush(); content=0; pend=""
             if ($0 ~ /\(/) { pend=$0; pfile=FILENAME; pline=FNR }
             next }
           { if ($0 ~ /[^ \t]/) content=1 }
    END    { flush() }' "$REPO_ROOT"/docs/Language-Reference/*.md)
if [ -z "$stack_bad" ]; then
    printf "  ${GREEN}PASS${NC}  no reference entry is left empty\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  reference entries with no text under them\n"
    printf "    %s\n" "$stack_bad"; ((failed++))
fi

# Markdown lint: a bare intraword asterisk in help prose is emphasis, not
# multiplication — CommonMark (and our pager) turn "w*h*4" into "w<i>h</i>4",
# eating the asterisks, and a lone "w*4" italicises the rest of the line.
# `help grab` shipped reading "(wh4 bytes)" until 2026-07-20. Wrap such text
# in backticks. Skipped: indented lines (code blocks) and "#" headings, both
# of which the renderer passes through verbatim; `...` spans are stripped
# first because their contents are already safe.
md_star=$(for f in "$REPO_ROOT"/docs/Language-Reference/*.md "$REPO_ROOT"/docs/Tutorial/*.md; do
    sed -e 's/`[^`]*`//g' "$f" | grep -nE '^[^ #].*[A-Za-z0-9]\*[A-Za-z0-9]' \
        | sed "s|^|$(basename "$f"):|"
done)
if [ -z "$md_star" ]; then
    printf "  ${GREEN}PASS${NC}  help prose has no unbackticked intraword '*'\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  help prose has no unbackticked intraword '*'\n"
    printf "    Would render as italics:\n%s\n" "$md_star"; ((failed++))
fi

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
# The footer shows progress: the scan counts the file's headings to EOF.
tut_check "footer shows the step total"    "tutorial Lesson"                 "step 1/3"
tut_check "footer total on a jump"         $'tutorial Lesson\nstep 3'        "step 3/3"
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
tut_check "step before start hints"        "step"                            "start a tutorial first"
tut_check "unknown tutorial name"          "tutorial nope"                   "no tutorial named nope"
tut_check "tutorial name+step starts there" "tutorial Lesson 2"              "content TWO here"
tut_check "tutorial step arg in footer"    "tutorial Lesson 3"               "step 3"
tut_check "step N jumps"                   $'tutorial Lesson\nstep 3'        "content THREE here"
tut_check "step past end reports end"      $'tutorial Lesson\nstep 9'        "end of 'Lesson'"
tut_check "step non-number is un-parsed"   $'tutorial Lesson\nstep cr 7 8 + .'  "15"
tut_check "tutorial takes a value bookmark" $'3 value spot\ntutorial Lesson spot' "content THREE here"
tut_check "step takes a value name"        $'tutorial Lesson\n2 value spot\nstep spot' "content TWO here"
tut_check "step refuses a variable"        $'tutorial Lesson\nvariable vv 2 vv !\nstep vv drop .( VOK=1)' "VOK=1"
tut_check "end-tutorial confirms"          $'tutorial Lesson\nend-tutorial'  "tutorial ended"
tut_check "end-tutorial then next hints"   $'tutorial Lesson\nend-tutorial\nnext' "start a tutorial first"
tut_check "end-tutorial with none started" "end-tutorial"                    "no tutorial in progress"

# step replays the current step: after next + step, step 2's content printed twice
tut_replay=$(printf 'tutorial Lesson\nnext\nstep\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$tut_dir" timeout 2 $FORTH 2>&1)
if [[ $(echo "$tut_replay" | grep -c "content TWO here") -eq 2 ]]; then
    printf "  ${GREEN}PASS${NC}  step replays the current step\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  step replays the current step\n"
    printf "    Expected 'content TWO here' twice, got: %s\n" "$(echo "$tut_replay" | grep -c 'content TWO here')"; ((failed++))
fi

# back at step 1 stays at step 1 (does not underflow)
tut_b1=$(printf 'tutorial Lesson\nback\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$tut_dir" timeout 2 $FORTH 2>&1)
if [[ "$tut_b1" == *"step 1"* ]] && [[ "$tut_b1" != *"step 0"* ]]; then
    printf "  ${GREEN}PASS${NC}  back at step 1 stays at step 1\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  back at step 1 stays at step 1\n"
    printf "    Got:      %s\n" "$(echo "$tut_b1" | head -4)"; ((failed++))
fi

# Interactive sessions clear the screen per step, but piped input must stay
# plain text: no escape bytes from the (tty?)-guarded page in (print-step).
tut_esc=$(printf 'tutorial Lesson\nnext\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$tut_dir" timeout 2 $FORTH 2>&1)
if [[ "$tut_esc" != *$'\x1b'* ]]; then
    printf "  ${GREEN}PASS${NC}  piped tutorial output has no escape codes\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  piped tutorial output has no escape codes\n"
    printf "    Got escape bytes in: %s\n" "$(echo "$tut_esc" | cat -v | head -3)"; ((failed++))
fi

# The --more-- pager pause is interactive-only: a piped help of a file longer
# than the screen (all preamble — no "## " heading) must print every line
# straight through, with no pause swallowing input and no "-- more" prompt.
for i in $(seq 1 40); do echo "filler line $i"; done > "$tut_dir/Longpage.md"
tut_pager=$(printf 'help Longpage\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$tut_dir" timeout 2 $FORTH 2>&1)
if [[ "$tut_pager" == *"filler line 40"* && "$tut_pager" != *"-- more"* ]]; then
    printf "  ${GREEN}PASS${NC}  piped help never pauses at --more--\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  piped help never pauses at --more--\n"
    printf "    Got:      %s\n" "$(echo "$tut_pager" | tail -3)"; ((failed++))
fi

# The shipped Arrays lesson: starts, has its 14 steps, and its examples run.
arrays_out=$(printf 'tutorial Arrays\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$REPO_ROOT/docs/Tutorial" timeout 2 $FORTH 2>&1)
if [[ "$arrays_out" == *"no built-in array type"* && "$arrays_out" == *"step 1/14"* ]]; then
    printf "  ${GREEN}PASS${NC}  Arrays lesson opens with 14 steps\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  Arrays lesson opens with 14 steps\n"
    printf "    Got:      %s\n" "$(echo "$arrays_out" | head -4)"; ((failed++))
fi
assert_output "Arrays lesson examples work" \
    $'create nums 5 cells allot\n: nth ( i -- addr ) cells nums + ;\n: init 5 0 do i i * i nth ! loop ;\ninit\n: show 5 0 do i nth @ . loop cr ;\nshow' \
    "0 1 4 9 16"
assert_output "Arrays lesson table example"  \
    $'create days 31 , 28 , 31 , 30 , 31 , 30 , 31 , 31 , 30 , 31 , 30 , 31 ,\n: days-in ( month -- n ) 1- cells days + @ ;\n2 days-in .' \
    "28"

# The shipped Strings lesson: opens with 11 steps, and its examples run.
strings_out=$(printf 'tutorial Strings\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$REPO_ROOT/docs/Tutorial" timeout 2 $FORTH 2>&1)
if [[ "$strings_out" == *"Text on the Stack"* && "$strings_out" == *"step 1/11"* ]]; then
    printf "  ${GREEN}PASS${NC}  Strings lesson opens with 11 steps\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  Strings lesson opens with 11 steps\n"
    printf "    Got:      %s\n" "$(echo "$strings_out" | head -4)"; ((failed++))
fi
assert_output "Strings lesson compare example" \
    $': yes? ( c-addr u -- flag ) s" yes" compare 0= ;\ns" yes" yes? . s" nope" yes? .' \
    "-1 0"
# The transient-buffer round-robin the lesson teaches: two live at once, the
# third s" reuses the oldest slot.
assert_output "Strings lesson transient-buffer example" \
    $'s" AAAA" s" BBBB" s" CCCC"\ntype space type space type' \
    "CCCC BBBB CCCC"
assert_output "Strings lesson keep-a-string example" \
    $'create name 16 allot variable name-len\n: name! ( c-addr u -- ) dup name-len ! name swap cmove ;\n: name@ ( -- c-addr u ) name name-len @ ;\ns" Ada" name!\ns" x" s" y" s" z" 2drop 2drop 2drop\n: greet ." Hello, " name@ type ." !" cr ;\ngreet' \
    "Hello, Ada!"

# The shipped Sprites lesson: opens with 14 steps, and its examples run. The
# drawing examples need SDL, but the art table and the frame-picking idiom are
# pure Forth over an off-screen surface, so they run everywhere (incl. QEMU).
sprites_out=$(printf 'tutorial Sprites\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$REPO_ROOT/docs/Tutorial" timeout 2 $FORTH 2>&1)
if [[ "$sprites_out" == *"Pixel Art That Moves"* && "$sprites_out" == *"step 1/14"* ]]; then
    printf "  ${GREEN}PASS${NC}  Sprites lesson opens with 14 steps\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  Sprites lesson opens with 14 steps\n"
    printf "    Got:      %s\n" "$(echo "$sprites_out" | head -4)"; ((failed++))
fi
# The lesson's two-character color names typed as an art table, keyed blit:
# the __ pixel leaves the red background, the GG pixel paints green.
assert_output "Sprites lesson art table + transparency" "$GRP
magenta constant __
green   constant GG
: inv-art __ l, GG l, ;
create inv inv-art
: g s red 0 0 8 6 fill-rect  magenta inv 0 0 2 1 blit-key  0 0 p 1 0 p ; g" \
    "16711680 65280"
# The animation idiom: frame counter divided down, then alternating.
assert_output "Sprites lesson frame-picking idiom" \
    $': pick 16 0 do i 8 / 2 mod if 1 else 0 then . loop ;\npick' \
    "0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1"

# The shipped Bitmaps lesson: opens with 19 steps, and its examples run. The
# art and the colour-per-call payoff are pure Forth over an off-screen
# surface, so they run everywhere (incl. QEMU) without SDL.
bitmaps_out=$(printf 'tutorial Bitmaps\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$REPO_ROOT/docs/Tutorial" timeout 2 $FORTH 2>&1)
if [[ "$bitmaps_out" == *"Sprites You Type in Binary"* && "$bitmaps_out" == *"step 1/19"* ]]; then
    printf "  ${GREEN}PASS${NC}  Bitmaps lesson opens with 19 steps\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  Bitmaps lesson opens with 19 steps\n"
    printf "    Got:      %s\n" "$(echo "$bitmaps_out" | head -4)"; ((failed++))
fi
# The lesson's alien, stamped in two colours from one piece of art.
assert_output "Bitmaps lesson one shape two colours" "$GRP
: a-art %11000000 c, %01100000 c, ;
create a a-art
: g s red a 0 0 2 2 stamp  green a 0 3 2 2 stamp
  0 0 p 1 1 p 0 3 p 1 4 p ; g"   "16711680 16711680 65280 65280"
# The palette table the lesson indexes with cells (one line, so save keeps it).
assert_output "Bitmaps lesson palette table" "include $GR
create palette  red , green , blue , yellow , cyan , magenta ,
: pick ( i -- ) cells palette + @ . ;
0 pick 3 pick 5 pick"   "16711680 16776960 16711935"

# The real-docs listing shows each tutorial's "# Name — description" title
real_tuts=$(printf 'tutorials\n' | BASICFORTH_PATH="$FORTH_LIB" \
    BASICFORTH_DOCS="$REPO_ROOT/docs/Tutorial" timeout 2 $FORTH 2>&1)
if [[ "$real_tuts" == *"Arrays — Your First Data Structure"* \
   && "$real_tuts" == *"Strings — Text on the Stack"* \
   && "$real_tuts" == *"Sprites — Pixel Art That Moves"* \
   && "$real_tuts" == *"Bitmaps — Sprites You Type in Binary"* \
   && "$real_tuts" == *"Snake — Build Your First Game"* ]]; then
    printf "  ${GREEN}PASS${NC}  tutorials lists real titles with descriptions\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  tutorials lists real titles with descriptions\n"
    printf "    Got:      %s\n" "$(echo "$real_tuts" | head -5)"; ((failed++))
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
# -v / --version print the VERSION LINE to stdout and exit 0, before any
# startup work — and unlike the interactive banner, they are NOT gated on a tty
# (so the output is captured here through a pipe). The `version` word prints the
# same line at the REPL. The interactive banner adds a copyright/warranty line
# and a what-to-type-next line, but those live in main.s rather than the
# generated version.inc precisely so that -v stays one line for scripts.

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

# the `version` word prints the version line at the REPL
assert_output "version word"       "version"             "*** BasicForth"

# -v must stay exactly ONE line: scripts parse it, and the interactive banner's
# extra two lines must not leak into it.
if [[ "$(printf '' | timeout 2 $FORTH -v 2>&1 | wc -l)" == "1" ]]; then
    printf "  ${GREEN}PASS${NC}  -v is exactly one line\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  -v is exactly one line\n"
    printf "    Got:      %s lines\n" "$(printf '' | timeout 2 $FORTH -v 2>&1 | wc -l)"; ((failed++))
fi

# `license` — the word the startup banner tells you to type. It must exist (a
# banner promising a word that errors is worse than no banner) and must carry
# both halves of the GPL notice.
assert_output "license names the GPL" "license"  "GNU General Public License"
assert_output "license disclaims"     "license"  "WITHOUT ANY WARRANTY"
assert_output "license is copyright"  "license"  "Copyright (C) 2026 Brandon Blodget"
assert_output "license stack clean"   "license depth ."  "0"

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

# assert_editor_absent: editor forced on; the output must NOT contain a needle.
assert_editor_absent() {
    local name="$1" input_fmt="$2" needle="$3"
    local output
    output=$(printf "$input_fmt" | BASICFORTH_EDITOR=1 timeout 2 $FORTH 2>&1)
    if [[ "$output" != *"$needle"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s (unexpected '%s')\n" "$name" "$needle"; ((failed++))
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
section "EDIT (external editor)"
# =========================================================================
# `edit <word>` writes the word's source to a temp file, opens it in $EDITOR, and
# on a clean exit splices the new text into the module file and reloads. We drive
# it non-interactively by pointing $EDITOR at a `sed` (or `true`/`false`) instead
# of a real editor. The bad-name paths fail before any editor is spawned.

# Errors before spawning: not-found and primitive (no $EDITOR needed).
ed_pn=$(printf 'edit dup\nbye\n'       | BASICFORTH_SESSION=1 timeout 2 $FORTH 2>&1)
[[ "$ed_pn" == *"edit: dup is a primitive"* && "$ed_pn" == *"try: help dup"* ]] \
    && { printf "  ${GREEN}PASS${NC}  edit reports a primitive and points at help\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  edit reports a primitive\n    Got: %s\n" "$(echo "$ed_pn"|head -3)"; ((failed++)); }
ed_nf=$(printf 'edit nosuchxyz\nbye\n' | BASICFORTH_SESSION=1 timeout 2 $FORTH 2>&1)
[[ "$ed_nf" == *"edit: nosuchxyz not found"* ]] \
    && { printf "  ${GREEN}PASS${NC}  edit reports not found\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  edit reports not found\n    Got: %s\n" "$(echo "$ed_nf"|head -3)"; ((failed++)); }

# An external edit takes effect: sed rewrites ee's body from 1 to 7 in the
# module file, and the reload makes it live. (edit needs a module file: a
# scratch-session word is refused with "save <name> first".)
ed_dir=$(mktemp -d)
printf ': ee 1 ;\n' > "$ed_dir/mod.fs"
ed_ch=$( cd "$ed_dir" && printf 'edit ee\nee .\nbye\n' \
    | EDITOR='sed -i s/1/7/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1)
rm -rf "$ed_dir"
[[ "$ed_ch" == *"7  ok"* ]] \
    && { printf "  ${GREEN}PASS${NC}  edit applies an external editor's changes\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  edit applies an external edit\n    Got: %s\n" "$(echo "$ed_ch"|head -5)"; ((failed++)); }

# An aborting editor (non-zero exit) leaves the word (and file) unchanged.
ed_dir=$(mktemp -d)
printf ': eb 1 ;\n' > "$ed_dir/mod.fs"
ed_ab=$( cd "$ed_dir" && printf 'edit eb\neb .\nbye\n' \
    | EDITOR=false BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth mod.fs 2>&1)
rm -rf "$ed_dir"
[[ "$ed_ab" == *"edit: editor exited with status 1"* && "$ed_ab" == *"1  ok"* ]] \
    && { printf "  ${GREEN}PASS${NC}  edit reports an aborted editor, word unchanged\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  edit aborted-editor handling\n    Got: %s\n" "$(echo "$ed_ab"|head -5)"; ((failed++)); }

# Multi-line formatting survives the round-trip: load a multi-line, commented word
# from a file, edit it with a no-op editor (true), and confirm SEE still shows it
# across lines with the `\` comment intact (the old inline edit flattened it).
cc_dir=$(mktemp -d)
cat > "$cc_dir/cc.fs" <<'FS'
: dbl ( n -- n+n )
  \ doubles the input
  dup + ;
FS
cc_out=$(printf 'edit dbl\nsee dbl\n5 dbl .\nbye\n' \
    | EDITOR=true BASICFORTH_SESSION=1 timeout 2 $FORTH "$cc_dir/cc.fs" 2>&1)
rm -rf "$cc_dir"
if [[ "$cc_out" == *"\ doubles the input"* && "$cc_out" == *"10  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  edit preserves multi-line formatting\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  edit preserves multi-line formatting\n"
    printf "    Got: %s\n" "$(echo "$cc_out" | head -6)"; ((failed++))
fi

# =========================================================================
section "Shelling out (sh / (system))"
# =========================================================================
# `sh <line>` runs the rest of the line via /bin/sh; the interpreter resumes
# after it (so a following Forth token still runs).
sh_out=$(printf 'sh echo hi-from-sh\n42 .\nbye\n' | timeout 2 $FORTH 2>&1)
[[ "$sh_out" == *"hi-from-sh"* && "$sh_out" == *"42  ok"* ]] \
    && { printf "  ${GREEN}PASS${NC}  sh runs a command, interpreter resumes after it\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  sh basic\n    Got: %s\n" "$(echo "$sh_out"|head -4)"; ((failed++)); }
# The child writes to fd 1 ITSELF, so none of our write paths run -- the owed
# newline has to be settled before the fork or the child's first line lands on
# the echoed command line ("sh echo hellohello"). Same for open-pipe with w/o,
# whose child keeps the terminal for stdout. The echo line must therefore end
# right after the command, with the output on the line below.
sh_nl=$(printf 'sh echo hi-from-sh\nbye\n' | timeout 2 $FORTH 2>&1)
if printf '%s' "$sh_nl" | grep -qx '> sh echo hi-from-sh' \
   && printf '%s' "$sh_nl" | grep -qx 'hi-from-sh'; then
    printf "  ${GREEN}PASS${NC}  sh output starts on its own line, not the command's\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  sh output ran onto the command line\n    Got: %s\n" "$(echo "$sh_nl"|head -3)"; ((failed++))
fi
# An R/O pipe pays too. Its child's stdout is the pipe, but it still inherits
# STDERR -- so it can dirty the terminal line, and without paying, the error
# lands on the command line ("> tls: cannot access ..."). The cost is one line
# break on a line that captures silently, which is what any line producing
# output pays; mashed-up error text is worse. The question is never "does this
# fork" but "can anything reach the TERMINAL that we will not write ourselves".
po_nl=$(printf ': t s" ls /definitely-no-such-path" r/o open-pipe drop close-pipe 2drop ;\nt\nbye\n' \
    | timeout 5 $FORTH 2>&1)
if printf '%s' "$po_nl" | grep -qx '> t' \
   && printf '%s' "$po_nl" | grep -q '^ls: cannot access'; then
    printf "  ${GREEN}PASS${NC}  an r/o child's stderr starts on its own line\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  r/o child stderr ran onto the command line\n    Got: %s\n" "$(echo "$po_nl"|head -4)"; ((failed++))
fi
# Bare `sh` with no command prints usage, doesn't choke.
sh_use=$(printf 'sh\nbye\n' | timeout 2 $FORTH 2>&1)
[[ "$sh_use" == *"usage: sh <command>"* ]] \
    && { printf "  ${GREEN}PASS${NC}  bare sh prints usage\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  sh usage\n    Got: %s\n" "$(echo "$sh_use"|head -3)"; ((failed++)); }
# (system) returns the child's exit status: /bin/true -> 0, /bin/false -> 1.
sy_out=$(printf ': st0 s" true"  (system) . ;\n: st1 s" false" (system) . ;\nst0 st1\nbye\n' \
    | timeout 2 $FORTH 2>&1)
[[ "$sy_out" == *"0 1"* || ( "$sy_out" == *"0 "* && "$sy_out" == *"1 "* ) ]] \
    && { printf "  ${GREEN}PASS${NC}  (system) returns the child exit status\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  (system) status\n    Got: %s\n" "$(echo "$sy_out"|head -4)"; ((failed++)); }

# =========================================================================
section "Pipes (open-pipe / close-pipe)"
# =========================================================================
# r/o pipe: read a command's stdout with the ordinary read-line, EOF is a
# clean 0/false/0, and close-pipe reaps the child (wretval wior = 0 0).
pp_out=$(printf 'variable pf\ns" printf %s" r/o open-pipe . pf !\npad 80 pf @ read-line drop drop pad swap type cr\npad 80 pf @ read-line drop drop pad swap type cr\npad 80 pf @ read-line . . . cr\npf @ close-pipe . .\nbye\n' \
    "'aa\\nbb\\n'" | timeout 5 $FORTH 2>&1)
[[ "$pp_out" == *"aa"* && "$pp_out" == *"bb"* && "$pp_out" == *"0 0 0 "* && "$pp_out" == *"0 0  ok"* ]] \
    && { printf "  ${GREEN}PASS${NC}  r/o pipe: read-line captures output, clean EOF, clean close\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  r/o pipe capture\n    Got: %s\n" "$(echo "$pp_out"|head -8)"; ((failed++)); }
# close-pipe returns the child's exit status as wretval ( -- wretval wior ).
assert_output "close-pipe returns the child exit status" \
    's" exit 3" r/o open-pipe drop close-pipe . .' "0 3"
# w/o pipe: what we write-line becomes the child's stdin.
pw_dir="$(mktemp -d)"
pw_out=$(printf 's" cat > %s/pipe.txt" w/o open-pipe . variable pw pw !\ns" fed through a pipe" pw @ write-line .\npw @ close-pipe . .\nbye\n' \
    "$pw_dir" | timeout 5 $FORTH 2>&1)
pw_file="$(cat "$pw_dir/pipe.txt" 2>/dev/null)"
rm -rf "$pw_dir"
[[ "$pw_out" == *"0 0  ok"* && "$pw_file" == "fed through a pipe" ]] \
    && { printf "  ${GREEN}PASS${NC}  w/o pipe: write-line feeds the child's stdin\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  w/o pipe\n    File: %q\n    Got: %s\n" "$pw_file" "$(echo "$pw_out"|head -5)"; ((failed++)); }
# Two pipes can be open at once; each close reaps its own child.
p2_out=$(printf 'variable p1 variable p2\ns" echo one" r/o open-pipe drop p1 !\ns" echo two" r/o open-pipe drop p2 !\npad 80 p1 @ read-line drop drop pad swap type cr\npad 80 p2 @ read-line drop drop pad swap type cr\np1 @ close-pipe + . p2 @ close-pipe + .\nbye\n' \
    | timeout 5 $FORTH 2>&1)
[[ "$p2_out" == *"one"* && "$p2_out" == *"two"* ]] \
    && { printf "  ${GREEN}PASS${NC}  two pipes open at once, each reads its own child\n"; ((passed++)); } \
    || { printf "  ${RED}FAIL${NC}  two pipes\n    Got: %s\n" "$(echo "$p2_out"|head -6)"; ((failed++)); }
# r/w is refused with EINVAL (deadlock trap), and an fd that never came from
# open-pipe gets EBADF from close-pipe (close-file would leak a zombie).
assert_output "open-pipe r/w -> EINVAL" 's" true" r/w open-pipe swap drop einval = .' "-1"
assert_output "close-pipe on a non-pipe fd -> EBADF" '99 close-pipe . .' "9 0"

# =========================================================================
section "REQUIRE (load a file only once)"
# =========================================================================
# A load records a sentinel word (inc:<basename>); require skips a file whose
# sentinel is findable. rlib.fs bumps a REPL-defined counter so the number of
# actual loads is observable.
req_dir="$(mktemp -d)"
echo '1 cnt +!' > "$req_dir/rlib.fs"
printf 'require %s/rlib.fs\n' "$req_dir" > "$req_dir/rtop.fs"

assert_output "require loads once"          "variable cnt 0 cnt !
require $req_dir/rlib.fs
require $req_dir/rlib.fs
cnt @ ."  "1"
assert_output "required (string form) skips" "variable cnt 0 cnt !
require $req_dir/rlib.fs
s\" $req_dir/rlib.fs\" required
cnt @ ."  "1"
assert_output "include still force-reloads"  "variable cnt 0 cnt !
require $req_dir/rlib.fs
include $req_dir/rlib.fs
cnt @ ."  "2"
assert_output "require by bare name skips a path-loaded file" "variable cnt 0 cnt !
include $req_dir/rlib.fs
require rlib.fs
cnt @ ."  "1"
assert_output "nested require dedups"        "variable cnt 0 cnt !
require $req_dir/rtop.fs
require $req_dir/rlib.fs
cnt @ ."  "1"
assert_output "marker rollback -> require reloads" "variable cnt 0 cnt !
marker mm
require $req_dir/rlib.fs
mm
require $req_dir/rlib.fs
cnt @ ."  "2"
assert_error  "require of a missing file errors"  "require zz-no-such-file.fs"  "cannot open"
assert_error  "include of a missing file errors"  "include zz-no-such-file.fs"  "cannot open"
assert_output "require alone shows usage"    "require"  "usage: require <file>"

# Cycle guard: the sentinel marks a file loaded only after it finishes, so a
# file that loads itself (directly, or around a ring) used to recurse until the
# data stack hit its guard page. A load already in progress is skipped, so the
# body still runs exactly once and the session survives.
printf 'require %s/rself.fs\n1 cnt +!\n'  "$req_dir" > "$req_dir/rself.fs"
printf 'require %s/rb.fs\n1 acnt +!\n'    "$req_dir" > "$req_dir/ra.fs"
printf 'require %s/ra.fs\n1 bcnt +!\n'    "$req_dir" > "$req_dir/rb.fs"

assert_output "self-require is a no-op, body loads once" "variable cnt 0 cnt !
require $req_dir/rself.fs
.( n=) cnt @ ."  "n=1"
assert_output "self-include cannot recurse either" "variable cnt 0 cnt !
include $req_dir/rself.fs
.( n=) cnt @ ."  "n=1"
# The skip says so: silence would surface only as an unexplained `? name`
# wherever the missing library word is first used.
assert_output "a skipped cycle is reported" "variable cnt 0 cnt !
require $req_dir/rself.fs"  "is already loading — skipped"
assert_output "a require ring loads each file once" "variable acnt 0 acnt !
variable bcnt 0 bcnt !
require $req_dir/ra.fs
.( ring=) acnt @ 10 * bcnt @ + ."  "ring=11"
# The guard is scoped to the load: once it finishes, the file is an ordinary
# candidate again (include still force-reloads it).
assert_output "the loading mark does not outlive the load" "variable cnt 0 cnt !
require $req_dir/rself.fs
include $req_dir/rself.fs
.( n=) cnt @ ."  "n=2"
# ...including when the load ends in the cannot-open ABORT, which leaves
# through a different exit than the normal one.
assert_error  "a missing file stays reportable"  "require zz-no-such-file.fs
require zz-no-such-file.fs"  "cannot open"
# A startup file is loaded by main.s calling the assembly INCLUDED directly,
# so nothing is on the loading list when its first line runs. (ldg-seed) puts
# it there from (cur-src); without that, `basicforth m.fs` where m.fs requires
# m.fs ran the whole body twice (every definition, and every error, doubled).
printf 'require %s/rboot.fs\n.( BODY) cr\n' "$req_dir" > "$req_dir/rboot.fs"
rboot_out=$(printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH "$req_dir/rboot.fs" 2>&1)
if [[ "$(grep -c BODY <<< "$rboot_out")" == "1" ]]; then
    printf "  ${GREEN}PASS${NC}  a startup file that requires itself runs once\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  startup self-require\n    Got: %q\n" "$rboot_out"; ((failed++))
fi

# Deeper than the loading list can hold: a clear message beats a stack
# overflow. Long basenames fill the 1024-byte list in 9 files, so 12 links
# reach the limit before the ring closes.
deep_pfx=$(printf 'd%.0s' $(seq 110))
for i in 0 1 2 3 4 5 6 7 8 9 10 11; do
    printf 'require %s/%s%d.fs\n' "$req_dir" "$deep_pfx" "$(( (i+1) % 12 ))" \
        > "$req_dir/$deep_pfx$i.fs"
done
assert_error  "a load chain too deep to track aborts cleanly" \
              "require $req_dir/${deep_pfx}0.fs"  "nested too deep"
rm -rf "$req_dir"

# =========================================================================
section "Dirty guard"
# =========================================================================
# (dirty) tracks unsaved log changes: clean at start, set by a definition,
# cleared by save — and an edit ends CLEAN too (it writes the file and
# reloads, which reseeds the log). The save-first prompt itself only
# engages at a real terminal (PTY suite); here we verify the bookkeeping.
dg_dir="$(mktemp -d)"
dg_out=$( cd "$dg_dir" && printf '(dirty) @ .\n: dgw 1 ;\n(dirty) @ .\nsave m.fs\n(dirty) @ .\nedit dgw\n(dirty) @ .\ndgw .\nbye\n' \
    | EDITOR='sed -i s/1/2/' BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
rm -rf "$dg_dir"
if [[ "$dg_out" == *"0  ok"*"-1  ok"*"saved to"*"0  ok"*"0  ok"*"2  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  (dirty) tracks define / save; edit ends clean (reloaded)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  (dirty) bookkeeping\n    Expected 0, -1, saved, 0, 0, 2\n    Got: %q\n" "$dg_out"; ((failed++))
fi
# In a pipe the guard never prompts: a dirty new/bye proceeds silently (no
# prompt text, no byte of input consumed as an answer).
dg2_out=$( printf ': dgx 1 ;\nnew\n.module\nbye\n' \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1 )
if [[ "$dg2_out" == *"(empty module"* && "$dg2_out" != *"save first"* ]]; then
    printf "  ${GREEN}PASS${NC}  piped input never prompts (new/bye proceed silently)\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  pipe silence\n    Got: %q\n" "$dg2_out"; ((failed++))
fi

# =========================================================================
section "SHELLUTIL (shell-command plumbing)"
# =========================================================================
# the composition layer other libraries require before shelling out
shu_pre="include $FORTH_LIB/shellutil.fs"
assert_output "shellutil quotes embedded quotes" \
    "$(printf "%s\n(cmd0) s\" a b'c\" (cmd+q) (cmd\$) type" "$shu_pre")" \
    "'a b'\\''c'"
assert_output "shellutil hex append" \
    "$(printf '%s\n(cmd0) 255 (cmd+x) (cmd$) type' "$shu_pre")"  "0xFF"
assert_output "shellutil line capture" \
    "$(printf '%s\n: t (cmd0) s" echo hello" (cmd+) (cmd-line1) if (cmd-ln) swap type then ; t' "$shu_pre")" \
    "hello"
shu_forth="${FORTH/.\//$PWD/}"        # absolute, so it survives a cd
# a shell-syntax stem must be refused outright. The payload is a harmless
# canary: if the guard ever regresses, the evidence is a file appearing in
# a private directory — never a destructive command.
shu_inj="$(mktemp -d)"
shu_io=$( cd "$shu_inj" && printf '%s\n: t s" x$(touch pwn)x" (sh-mktemp) . ; t\n' "$shu_pre" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $shu_forth 2>&1 )
if printf '%s' "$shu_io" | grep -q "0  ok" && [ ! -e "$shu_inj/pwn" ]; then
    printf "  ${GREEN}PASS${NC}  shellutil rejects a shell-syntax mktemp stem\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  shellutil stem rejection\n    Got: %q\n" "$shu_io"; ((failed++))
fi
rm -rf "$shu_inj"
# an overflowed command must refuse to run, not execute truncated
shu_ovf="$(mktemp -d)"
shu_oo=$( cd "$shu_ovf" && printf '%s\n: t (cmd0) 300 0 do s" 0123456789abcdef" (cmd+) loop s" touch pwn" (cmd+) (cmd-run) . ; t\n' "$shu_pre" \
    | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $shu_forth 2>&1 )
if printf '%s' "$shu_oo" | grep -q -- "-1" && [ ! -e "$shu_ovf/pwn" ]; then
    printf "  ${GREEN}PASS${NC}  shellutil refuses to run an overflowed command\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  shellutil overflow refusal\n    Got: %q\n" "$shu_oo"; ((failed++))
fi
rm -rf "$shu_ovf"
# mktemp round-trip: file exists after (sh-mktemp), gone after (sh-rm)
shu_tmp="$(mktemp -d)"
shu_out=$(printf '%s\n: t s" shtest" (sh-mktemp) if (cmd-ln) swap 2dup type cr (sh-rm) then ; t\n' "$shu_pre" \
    | TMPDIR="$shu_tmp" BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1)
if printf '%s' "$shu_out" | grep -q "shtest-" \
   && [ -z "$(ls -A "$shu_tmp" 2>/dev/null)" ]; then
    printf "  ${GREEN}PASS${NC}  shellutil mktemp + rm round-trip\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  shellutil mktemp + rm round-trip\n    Got: %q\n" "$shu_out"; ((failed++))
fi
rm -rf "$shu_tmp"

# =========================================================================
section "DIS (disassembler)"
# =========================================================================
# dis shells out to objdump, so it needs binutils; under qemu the child
# processes run natively, so decoding the aarch64 guest needs the cross
# objdump (same package as the cross assembler this build already used).
if ! command -v objdump >/dev/null 2>&1; then
    printf "  ${YELLOW}SKIP${NC}  dis tests (objdump not installed)\n"
elif [[ "$FORTH" == *qemu* ]] && ! command -v aarch64-linux-gnu-objdump >/dev/null 2>&1; then
    printf "  ${YELLOW}SKIP${NC}  dis tests (no aarch64-capable objdump on the host)\n"
else
    dis_pre="include $FORTH_LIB/disasm.fs"
    assert_output "dis colon word: banner" \
        "$(printf '%s\n: sq dup * ;\ndis sq' "$dis_pre")"  "bytes at"
    assert_output "dis colon word: call targets annotated" \
        "$(printf '%s\n: sq dup * ;\ndis sq' "$dis_pre")"  '\ dup'
    assert_output "dis colon word: ends at ret" \
        "$(printf '%s\n: sq dup * ;\ndis sq' "$dis_pre")"  "ret"
    assert_output "dis primitive: bounded by symbol" \
        "$(printf '%s\ndis dup' "$dis_pre")"  "<forth_dup>:"
    assert_output "dis primitive: banner" \
        "$(printf '%s\ndis dup' "$dis_pre")"  "(in the binary)"
    # stage 2: inline data is split out of the stream, not decoded as code
    assert_output "dis shows a literal's value" \
        "$(printf '%s\n: five 5 ;\ndis five' "$dis_pre")"  "literal: 5"
    assert_output "dis keeps the ret after a literal" \
        "$(printf '%s\n: five 5 ;\ndis five' "$dis_pre")"  "ret"
    assert_output "dis decodes inline strings" \
        "$(printf '%s\n: greet ." hi there" ;\ndis greet' "$dis_pre")"  's" hi there"'
    assert_output "dis names an xt literal" \
        "$(printf "%s\n: runner ['] dup execute ;\ndis runner" "$dis_pre")"  "xt: dup"
    assert_error  "dis unknown word" \
        "$(printf '%s\ndis nosuchword' "$dis_pre")"  "? nosuchword"
    assert_output "dis without a name" \
        "$(printf '%s\ndis' "$dis_pre")"  "usage: dis <word>"
    # the temp file (dictionary path) must not survive the command; a private
    # TMPDIR keeps this assertion blind to other sessions' files in /tmp
    dis_tmp="$(mktemp -d)"
    printf '%s\n: sq dup * ;\ndis sq\n' "$dis_pre" \
        | TMPDIR="$dis_tmp" BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH >/dev/null 2>&1
    if [ -n "$(ls -A "$dis_tmp" 2>/dev/null)" ]; then
        printf "  ${RED}FAIL${NC}  dis cleans up its temp file\n    Left: %s\n" \
            "$(ls "$dis_tmp")"; ((failed++))
    else
        printf "  ${GREEN}PASS${NC}  dis cleans up its temp file\n"; ((passed++))
    fi
    rm -rf "$dis_tmp"
    # an overlong TMPDIR (path won't fit dis's buffers) must fail with a
    # message and leave no file behind — the child shell removes its own
    # mktemp file, so no leak even though Forth never saw the full path
    dis_deep="$(mktemp -d)"; dis_c="$(printf 'x%.0s' {1..150})"
    mkdir -p "$dis_deep/$dis_c/$dis_c"
    dis_lo=$(printf '%s\n: sq dup * ;\ndis sq\n' "$dis_pre" \
        | TMPDIR="$dis_deep/$dis_c/$dis_c" BASICFORTH_PATH="$FORTH_LIB" timeout 5 $FORTH 2>&1)
    if printf '%s' "$dis_lo" | grep -q "cannot create a temp file" \
       && [ -z "$(find "$dis_deep" -type f 2>/dev/null)" ]; then
        printf "  ${GREEN}PASS${NC}  dis overlong TMPDIR: clean failure, no leak\n"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  dis overlong TMPDIR\n    Got: %q\n" "$dis_lo"; ((failed++))
    fi
    rm -rf "$dis_deep"
fi

# =========================================================================
section "TIME (benchmarking at the prompt)"
# =========================================================================
# Elapsed time is not reproducible, so the assertions pin the format and the
# stack contract, never an exact duration: "0.00" matches 0.000-0.009 s, so a
# few ms of scheduler jitter can't make the fast case flaky, and the 100 ms
# sleep would need a 100 ms overshoot to stop reading as "0.1".

assert_output "time prints S.mmm s" \
    ": q ;
time q"                                                  "0.00"
assert_output "time reports a real duration" \
    ": nap 100 ms ;
time nap"                                                "0.1"
assert_output "time leaves the word's results on the stack" \
    ": q 42 ;
time q ."                                                "42"
assert_output "time passes arguments through" \
    ": sink drop 7 ;
5 time sink ."                                           "7"
assert_output "time works on a primitive" "1 time 1+ ."   "2"
# a duration is always decimal: .r and u.0r follow BASE, so in hex the 100 ms
# sleep would misprint as 0.064 s. BASE itself must survive unchanged.
assert_output "time prints decimal whatever BASE is" \
    ": nap 100 ms ;
hex
time nap"                                                "0.1"
assert_output "time leaves BASE alone" \
    ": q ;
hex
time q
ff ."                                                    "FF"
assert_error  "time unknown word" "time nosuchword"       "time: nosuchword not found"
assert_output "time without a name" "time"                "time: needs a word name"

# =========================================================================
section "UNCLOSED DEFINITION AT END OF FILE"
# =========================================================================
# A file that stops mid-definition — a missing ';', nearly always — used to
# load "successfully" and leave the caller compiling: every line typed after
# it was swallowed into the unterminated word, `bye` included, so the session
# could only be escaped with Ctrl-D. It is now a load error, recovered exactly
# the way a line error inside a definition already was.
unc_dir="$(mktemp -d)"
printf ': good 1 ;\n: bad 2 3 +\n' > "$unc_dir/unc.fs"
printf ': ok1 1 ;\n]\n'            > "$unc_dir/brk.fs"
printf ': fine 4 ;\n'              > "$unc_dir/fine.fs"
printf '\\ defines nothing\n1 drop\n' > "$unc_dir/nodef.fs"
printf ': good 1 ;\n: bad\n  2 3 +\n'  > "$unc_dir/multi.fs"
printf 'include %s/unc.fs\n: outer 5 ;\n' "$unc_dir" > "$unc_dir/nest.fs"

# The report names the unfinished word — in a long file that is the question
# you actually have. (A line number would point one line past the end.)
unc_out=$(printf 'bye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" \
    timeout 5 $sv_forth "$unc_dir/unc.fs" 2>&1)
if [[ "$unc_out" == *"definition not closed: bad (missing ;)"* ]]; then
    printf "  ${GREEN}PASS${NC}  unclosed definition is reported, and names the word\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  unclosed definition report\n    Got: %q\n" "$unc_out"; ((failed++))
fi
# Interactive: the session is usable — STATE back to interpret, definitions
# completed before the bad one intact, the partial one discarded.
unr_out=$(printf 'state @ .\ngood .\nbad .\nbye\n' | BASICFORTH_SESSION=1 \
    BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth "$unc_dir/unc.fs" 2>&1)
if [[ "$unr_out" == *"0  ok"* && "$unr_out" == *"1  ok"* && "$unr_out" == *"? bad"* \
      && "$unr_out" == *"Goodbye"* ]]; then
    printf "  ${GREEN}PASS${NC}  unclosed definition recovers: interpret mode, partial word gone\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  unclosed definition recovery\n    Got: %q\n" "$unr_out"; ((failed++))
fi
# A script (not a terminal, session off) exits non-zero, like any load error.
printf '' | BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth "$unc_dir/unc.fs" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    printf "  ${GREEN}PASS${NC}  unclosed definition exits non-zero as a script\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  unclosed definition should exit non-zero\n"; ((failed++))
fi
# Same from an interactive include, and the session stays usable afterwards.
uni_out=$(printf 'include %s/unc.fs\nstate @ .\ngood .\nbye\n' "$unc_dir" \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1)
if [[ "$uni_out" == *"definition not closed"* && "$uni_out" == *"0  ok"* \
      && "$uni_out" == *"1  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  include of an unclosed file reports and stays usable\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  include of an unclosed file\n    Got: %q\n" "$uni_out"; ((failed++))
fi
# A file that merely leaves STATE set (a stray `]`) has no definition to name
# and nothing to roll back — it must still report, and must not restore the
# dictionary from a stale colon_dsp/saved_here.
unb_out=$(printf 'state @ .\nok1 .\nbye\n' | BASICFORTH_SESSION=1 \
    BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth "$unc_dir/brk.fs" 2>&1)
if [[ "$unb_out" == *"definition not closed (missing ;)"* && "$unb_out" == *"0  ok"* \
      && "$unb_out" == *"1  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  a stray ] at end of file reports, with no name and no rollback\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  stray ] at end of file\n    Got: %q\n" "$unb_out"; ((failed++))
fi
# Nested: the inner file reports, and the outer load carries on — same as a
# line error in a nested file.
unn_out=$(printf 'outer .\ngood .\nbye\n' | BASICFORTH_SESSION=1 \
    BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth "$unc_dir/nest.fs" 2>&1)
if [[ "$unn_out" == *"definition not closed"* && "$unn_out" == *"5  ok"* \
      && "$unn_out" == *"1  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  unclosed nested include reports; the outer load continues\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  unclosed nested include\n    Got: %q\n" "$unn_out"; ((failed++))
fi
# A load can BEGIN inside an open definition (`: foo [ include lib.fs ] ;`).
# That definition belongs to the caller, not to the file, so the file must not
# be blamed for it — and must certainly not roll it back, which would destroy
# work in progress. Checked with a file that defines nothing, so the only
# thing open at its EOF is the caller's.
unp_out=$(printf ': pfoo [ include %s/nodef.fs ] 42 ;\nbye\n' "$unc_dir" \
    | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth 2>&1)
if [[ "$unp_out" != *"not closed"* && "$unp_out" != *"underflow"* ]]; then
    printf "  ${GREEN}PASS${NC}  a load inside an open definition is not blamed for it\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  inherited-definition false positive\n    Got: %q\n" "$unp_out"; ((failed++))
fi
# A definition spanning LINES leaves a half-built header that the recovery
# snapshot points AT rather than before, so the rollback alone preserves its
# HIDDEN bit — and every "is a definition open?" test then answers yes for the
# rest of the session (ok suppression stuck, Ctrl-D silently dead). The `ok`
# after recovery is the observable proof the header was dropped.
unm_out=$(printf 'state @ .\ngood .\nbye\n' | BASICFORTH_SESSION=1 \
    BASICFORTH_PATH="$FORTH_LIB" timeout 5 $sv_forth "$unc_dir/multi.fs" 2>&1)
if [[ "$unm_out" == *"definition not closed: bad"* && "$unm_out" == *"0  ok"* \
      && "$unm_out" == *"1  ok"* ]]; then
    printf "  ${GREEN}PASS${NC}  a multi-line unclosed definition drops its partial header\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  multi-line unclosed partial header\n    Got: %q\n" "$unm_out"; ((failed++))
fi
# ...and dropping that header must not reach an INHERITED one. saved_latest
# can BE the caller's still-open definition, since the included file's own `:`
# is what recorded it — unlinking that deletes work in progress and leaves `;`
# with a broken chain (it segfaulted). The file is included twice on purpose:
# the second load adds no require sentinel, so LATEST is not shifted and
# saved_latest lands squarely on the caller's open definition.
unh_dir="$(mktemp -d)"
printf ': cbad 1\n' > "$unh_dir/inner.fs"
printf 'include %s/inner.fs\n: keeper 7 ;\n: foo [ include %s/inner.fs ] 42 ;\nkeeper .\n' \
    "$unh_dir" "$unh_dir" > "$unh_dir/outer.fs"
unh_out=$(printf 'bye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" \
    timeout 5 $sv_forth "$unh_dir/outer.fs" 2>&1)
rm -rf "$unh_dir"
if [[ "$unh_out" == *"7"* && "$unh_out" == *"Goodbye"* && "$unh_out" != *"dumped core"* ]]; then
    printf "  ${GREEN}PASS${NC}  dropping a partial header never unlinks an inherited one\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  inherited header unlinked\n    Got: %q\n" "$unh_out"; ((failed++))
fi
# False-positive guard: a well-formed file says nothing and returns success.
unf_out=$(printf 'fine .\nbye\n' | BASICFORTH_SESSION=1 BASICFORTH_PATH="$FORTH_LIB" \
    timeout 5 $sv_forth "$unc_dir/fine.fs" 2>&1)
if [[ "$unf_out" == *"4  ok"* && "$unf_out" != *"not closed"* ]]; then
    printf "  ${GREEN}PASS${NC}  a well-formed file loads silently\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  well-formed file false positive\n    Got: %q\n" "$unf_out"; ((failed++))
fi
rm -rf "$unc_dir"

# =========================================================================
section "THREADS (OS threads via pthreads)"
# =========================================================================
# require threads.fs is opt-in, so none of this runs at startup. A worker gets
# its own data and return stacks from the trampoline; BASE, depth and the CATCH
# chain are per-thread (TLS). See docs/Threading.md.
thr_run() {
    printf '%s\n' "$1" | BASICFORTH_PATH="$FORTH_LIB" timeout 30 $FORTH 2>&1
}
thr_check() {
    local name="$1" input="$2" expected="$3" out
    out=$(thr_run "$input")
    if [[ "$out" == *"$expected"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"; ((passed++))
    else
        printf "  ${RED}FAIL${NC}  %s\n    Want: %q\n    Got:  %q\n" "$name" "$expected" "$out"; ((failed++))
    fi
}

thr_check "a worker runs a Forth word to completion" \
'require threads.fs
variable c
: work  1000 0 do 1 c +! loop ;
: go    ['"'"'] work thread drop join 2drop  c @ . ;
go' \
"1000"

# The anti-regression for the bug that motivated the trampoline: handing an xt
# straight to pthread_create leaves DSP holding glibc startup garbage, and the
# worker silently writes Forth cells to random memory. depth reported
# -17590946912746. A correct trampoline gives the worker its own stack, so an
# empty worker stack reads exactly 0.
thr_check "a worker's data stack is its own (depth reads 0, not garbage)" \
'require threads.fs
variable d
: probe  depth d ! ;
: go     ['"'"'] probe thread drop join 2drop  d @ . ;
go' \
"0"

thr_check "BASE is per-thread: a worker going hex leaves the REPL decimal" \
'require threads.fs
: w   hex ;
: go  ['"'"'] w thread drop join 2drop  base @ . ;
go' \
"10"

thr_check "an uncaught THROW in a worker surfaces as the join result" \
'require threads.fs
: boom  42 throw ;
: go    ['"'"'] boom thread drop join drop . ;
go' \
"42"

thr_check "CATCH works inside a worker" \
'require threads.fs
variable got
: boom     42 throw ;
: catcher  ['"'"'] boom catch got ! ;
: go       ['"'"'] catcher thread drop join drop .  got @ . ;
go' \
"0 42"

# The one Codex caught: per-thread `handler` is necessary but not sufficient.
# A CATCH frame also snapshots ten shared globals (input source + file-error
# context) that THROW writes back. Without the is_repl gate, a worker throwing
# while the REPL parses restores its stale snapshot over the REPL's input
# source and the REPL re-parses fragments of its own line -- verified by
# disabling the gate, which turns the line below into garbage.
thr_check "a worker throwing cannot corrupt the REPL's input source" \
'require threads.fs
variable t
: boom    42 throw ;
: hammer  20000 0 do ['"'"'] boom catch drop loop ;
: churn   0 400 0 do s" 1 2 + " evaluate + loop ;
: go      ['"'"'] hammer thread drop t !  churn .  t @ join drop . ;
go' \
"1200 0"

# The trampoline is a C function to glibc's start_thread, so it owes the ABI
# every callee-saved register (RBX/RBP/R12-R15; X19-X28 on ARM64) -- it clobbers
# DSP, HERE and LATEST itself, and glibc's thread teardown runs after it
# returns. Many create/join cycles exercise that teardown path repeatedly.
thr_check "many create/join cycles leave the engine intact" \
'require threads.fs
variable c
: work   100 0 do 1 c +! loop ;
: churn  100 0 do ['"'"'] work thread drop join 2drop loop ;
: go     churn  c @ .  6 7 * .  depth . ;
go' \
"10000 42 0"

# A failed pthread_join must NOT free the block: the worker may still be running
# and its stacks live inside it, so freeing there unmaps memory a live thread is
# executing on. Forced deterministically -- a worker joining ITSELF gets EDEADLK
# (35), which lands in the STATUS half of join's result. With the old
# free-on-failure path this segfaults with a core dump. The rightful owner
# must still be able to join afterwards, so the handle stays registered.
thr_check "a failed join does not free a live worker's stacks" \
'require threads.fs
variable h  variable r
: self-join  begin h @ until  h @ join r ! drop ;
: go   ['"'"'] self-join thread drop h !
       h @ join drop .  r @ .  6 7 * . ;
go' \
"0 35 42"

# The registry turns a second join from a use-after-free into an honest error.
thr_check "joining a spent handle reports instead of crashing" \
'require threads.fs
variable t
: work  1 drop ;
: go    ['"'"'] work thread drop t !
        t @ join 2drop
        t @ join swap drop . ;   \ status of the second join
go' \
"-60"

# The reason join returns two values. A worker throwing 35 and a join failing
# with EDEADLK 35 are different events; one ior could not tell them apart.
thr_check "a worker throwing 35 is distinguishable from EDEADLK 35" \
'require threads.fs
: t35   35 throw ;
: go    ['"'"'] t35 thread drop join . . ;   \ result then status
go' \
"0 35"

# threads lists live handles and drops them as they are joined.
thr_check "threads lists a live worker and forgets it once joined" \
'require threads.fs
variable t
: work  1 drop ;
: go    threads
        ['"'"'] work thread drop t !
        t @ join 2drop  threads ;
go' \
"(no threads)"

# The trampoline publishes ctx.state with store-RELEASE and threads reads it
# with (acq@) -- an acquire load. Both halves are needed: with plain loads on
# the reader, ARM64 may hoist the result load above the state load and report
# the initial 0 for a worker that actually threw. This polls state then reads
# result, which is precisely that pattern.
thr_check "a finished worker lists its real result, not a stale one" \
'require threads.fs
variable t
: t42   42 throw ;
: wait  begin t @ (t>ctx) (t-state) (acq@) finished = until ;
: go    ['"'"'] t42 thread drop t !  wait  threads  t @ join . . ;
go' \
"finished  42"

# A worker's stacks are fenced with PROT_NONE pages below the data stack,
# between the two stacks, and above the return stack. Without them the two
# stacks are neighbours: a return stack that overflows walks into the data
# stack, and a data stack popped past empty reads the return stack -- wrong
# answers with no crash. Popping an empty stack and touching it must now die
# loudly. Verified: unfenced, the line below prints SURVIVED-SILENTLY.
thr_out=$(printf '%s\n' 'require threads.fs
: under  drop dup ;
: go     ['"'"'] under thread drop join 2drop ;
go
." REACHED-THE-END"' | BASICFORTH_PATH="$FORTH_LIB" timeout 30 $FORTH 2>&1)
thr_status=$?
# The REPL echoes its input, so a marker string appears in the output either
# way -- the exit status is what distinguishes a fenced fault from surviving.
if [ "$thr_status" -ne 0 ]; then
    printf "  ${GREEN}PASS${NC}  a worker stack overrun faults instead of corrupting its neighbour\n"; ((passed++))
else
    printf "  ${RED}FAIL${NC}  worker stack overrun was not fenced (exit %s)\n" "$thr_status"; ((failed++))
fi

thr_check "two workers run concurrently and both complete" \
'require threads.fs
variable a  variable b  variable t1  variable t2
: w1  5000 0 do 1 a +! loop ;
: w2  5000 0 do 1 b +! loop ;
: go  ['"'"'] w1 thread drop t1 !  ['"'"'] w2 thread drop t2 !
      t1 @ join 2drop  t2 @ join 2drop  a @ .  b @ . ;
go' \
"5000 5000"

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
