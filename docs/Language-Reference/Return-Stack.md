# Return Stack

Besides the data stack, BasicForth has a second stack — the **return stack** —
which normally holds the return addresses of called words. You can borrow it for
short-term storage, which is handy when the value you need is buried under others
on the data stack.

Stack effects show both stacks: `( data -- data )` and `( R: before -- after )`.

At a glance:

    >r   ( x -- ) ( R: -- x )       move top item to the return stack
    r>   ( -- x ) ( R: x -- )       move it back to the data stack
    r@   ( -- x ) ( R: x -- x )     copy it back, leaving it there

**These words are compile-only** — use them inside a `:` definition, not at the
interactive prompt. Three rules keep the return stack safe:

- **Balance them.** Every `>r` needs a matching `r>` in the same definition,
  before it returns — otherwise the word returns to the wrong place and crashes.
- **Don't straddle a `;` or a word call** with an unbalanced item.
- The loop index `i` lives on the return stack, so pair any `>r`/`r>` *within* a
  single pass of a `do … loop`.

## >r ( x -- ) ( R: -- x )
Move the top data-stack item to the return stack ("to-R").

    : foo  10 >r  20  r> + ;     \ 10 set aside, 20 pushed, brought back, added
    foo .                         \ 30

## r> ( -- x ) ( R: x -- )
Move the top return-stack item back to the data stack ("R-from").

    : foo  10 >r  20  r> + ;
    foo .                         \ 30

## r@ ( -- x ) ( R: x -- x )
Copy the top return-stack item to the data stack, leaving it on the return stack
("R-fetch"). Use it to peek at a stashed value without consuming it.

    : bar  5 >r  r@ r> + ;       \ copy 5, then bring the original back, add
    bar .                         \ 10

## See Also

- `help stack` — the data stack and its rearranging words.
- `help loops` — `do … loop` and the index words `i`/`j`, which use the
  return stack.
