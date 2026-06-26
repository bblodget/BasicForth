# Stack Manipulation

Words that rearrange items on the data stack — the heart of working in Forth.

Stack effects are written `( before -- after )`, with the **top of the stack on
the right**. So `( x1 x2 -- x2 x1 )` means two items go in and come back
swapped. `.s` prints the stack non-destructively as `<count> bottom ... top`,
which the examples below use to show the result. Each example assumes you start
with an empty stack.

## dup        ( x -- x x )
Duplicate the top item.

    1 2 dup .s        \ <3> 1 2 2

## drop       ( x -- )
Discard the top item.

    1 2 drop .s       \ <1> 1

## swap       ( x1 x2 -- x2 x1 )
Exchange the top two items.

    1 2 swap .s       \ <2> 2 1

## over       ( x1 x2 -- x1 x2 x1 )
Copy the second item to the top.

    1 2 over .s       \ <3> 1 2 1

## rot        ( x1 x2 x3 -- x2 x3 x1 )
Rotate the third item up to the top.

    1 2 3 rot .s      \ <3> 2 3 1

## -rot       ( x1 x2 x3 -- x3 x1 x2 )
Rotate the top item down to third place — the inverse of `rot`.

    1 2 3 -rot .s     \ <3> 3 1 2

## ?dup       ( x -- x x | x )
Duplicate the top item only if it is non-zero. Handy before a test that should
leave one copy for an action and consume another.

    5 ?dup .s         \ <2> 5 5
    0 ?dup .s         \ <1> 0

## nip        ( x1 x2 -- x2 )
Drop the second item, keeping the top. (`swap drop`.)

    1 2 nip .s        \ <1> 2

## tuck       ( x1 x2 -- x2 x1 x2 )
Copy the top item underneath the second. (`swap over`.)

    1 2 tuck .s       \ <3> 2 1 2

## pick       ( xu ... x0 u -- xu ... x0 xu )
Copy the u-th item to the top, counting from 0. `0 pick` is `dup`, `1 pick` is
`over`.

    10 20 30 2 pick .s    \ <4> 10 20 30 10

## depth      ( -- +n )
Push the number of items currently on the stack (before `depth` ran).

    1 2 3 depth .s    \ <4> 1 2 3 3

## 2dup       ( x1 x2 -- x1 x2 x1 x2 )
Duplicate the top *pair* of items.

    1 2 2dup .s       \ <4> 1 2 1 2

## 2drop      ( x1 x2 -- )
Discard the top pair of items.

    1 2 3 4 2drop .s  \ <2> 1 2

## 2over      ( x1 x2 x3 x4 -- x1 x2 x3 x4 x1 x2 )
Copy the second pair to the top.

    1 2 3 4 2over .s  \ <6> 1 2 3 4 1 2

## 2swap      ( x1 x2 x3 x4 -- x3 x4 x1 x2 )
Exchange the top two pairs.

    1 2 3 4 2swap .s  \ <4> 3 4 1 2

## See Also

- `man getting-started` — the tutorial introduction to the stack.
- The return stack (`>r`, `r>`, `r@`) is documented separately.
- `.s` and `.` are described in the I/O reference.
