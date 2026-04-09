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

# Colors
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
NC="\033[0m"

# Counters
passed=0
failed=0

run_forth() {
    printf '%s\n' "$1" | timeout 2 $FORTH 2>&1
}

# assert_output: check that output contains a fixed substring
assert_output() {
    local name="$1"
    local input="$2"
    local expected="$3"

    local output
    output=$(run_forth "$input")

    if [[ "$output" == *"$expected"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"
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

    local output
    output=$(run_forth "$input")

    local lower_output lower_expected
    lower_output=$(echo "$output" | tr '[:upper:]' '[:lower:]')
    lower_expected=$(echo "$expected" | tr '[:upper:]' '[:lower:]')

    if [[ "$lower_output" == *"$lower_expected"* ]]; then
        printf "  ${GREEN}PASS${NC}  %s\n" "$name"
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

if [ "$failed" -gt 0 ]; then
    exit 1
fi
