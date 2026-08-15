\ BasicForth voice.fs -- render speech to WAV files with an external engine
\ Copyright (C) 2026 Brandon Blodget
\ SPDX-License-Identifier: GPL-2.0-only
\
\ Turns text into a WAV file by driving a text-to-speech program:
\
\   require voice.fs
\   s" you win" s" voice/you-win.wav" voice-render abort" render failed"
\
\ The WAV is then an ordinary sample -- wav-load it and play it like any
\ other sound (help samples, help playing).
\
\ RENDERING IS AN OFFLINE STEP, not something to do mid-game. A neural
\ engine takes hundreds of milliseconds to load its model and speak, and a
\ 60 Hz frame is 16. A game renders its phrases once, ships the WAVs beside
\ itself, and loads them at startup. For speaking arbitrary text as you type
\ it, speech.fs synthesizes into memory instead (help speech).
\
\ This file deliberately requires NOTHING but shellutil.fs -- no FFI, no SDL,
\ no wav decoder. It runs anywhere there is a shell, including the board and
\ the QEMU aarch64 run, so rendering is testable on machines that have no
\ audio device at all. Same reasoning as wavcore.fs.
\
\ THE ENGINE IS NOT BAKED IN. voice-cmd! takes a command template with two
\ placeholders:
\
\   %t   the text to speak        %o   the output WAV path
\
\ Everything else is shell syntax, passed through verbatim. The two
\ substitutions are QUOTED, so a phrase containing an apostrophe, a $ or a
\ semicolon is data and never syntax:
\
\   s" piper -m en_US-libritts-high -f %o -- %t" voice-cmd!    \ the default
\   s" espeak-ng -w %o -- %t" voice-cmd!
\   s" printf '%s' %t | some-engine --out %o" voice-cmd!       \ stdin engines
\
\ Only %o and %t expand, so a literal printf %s passes through untouched.
\
\ The engine's own output stays on the terminal -- when a render fails, its
\ complaint is usually more specific than voice-why.

\ --- dep block: what this file needs before any of it exists ---
\ The engine is a DEFAULT, not a requirement -- voice-cmd! takes any command
\ template, so this file is useful on a machine with no piper at all. Declared
\ softly so `deps voice` names the default rather than staying silent about it.
require shellutil.fs
wants-cmd piper           the default engine; voice-cmd! takes another

\ --- the engine command ---
\ 512 is far more than any real template needs (the piper default is 41
\ characters); an overlong one is stored as NOTHING rather than truncated,
\ because half a command could have lost the flag naming its output file,
\ and "no engine command set" is a better answer than running that.
512 constant (vc-max)
create (vc-buf) (vc-max) allot
variable (vc-#)

: voice-cmd  ( -- c-addr u )  (vc-buf) (vc-#) @ ;
: voice-cmd! ( c-addr u -- )
    dup (vc-max) > if 2drop 0 (vc-#) ! exit then
    dup (vc-#) !  (vc-buf) swap cmove ;

s" piper -m en_US-libritts-high -f %o -- %t" voice-cmd!

\ ...but $VOICE_ENGINE_CMD wins, because the default above can only guess. It
\ names piper with no --data-dir, so it finds a voice only where piper happens
\ to look; setup.sh knows where the voices on THIS machine actually are.
\ Exporting the right template and having the library ignore it is a confusing
\ way to watch a render fail -- the engine's own "unable to find voice" says
\ nothing about which template it came from.
\
\ Explicit still beats both: a voice-cmd! after loading overrides whatever
\ arrived here.
\
\ An UNUSABLE variable -- unset, empty, or longer than a template can be --
\ leaves the default alone. The guard is the whole point: voice-cmd! refuses
\ both of those by storing NOTHING, which is right when a caller asked for one
\ specific template and must not silently get another, but wrong here. This
\ word is opportunistic; declining to change anything beats replacing a
\ working default with "no engine command set".
\
\ A word rather than a bare line because `if` is compile-only. Worth keeping
\ afterwards: re-run it to pick the environment back up after experimenting.
: voice-from-env ( -- )
    s" VOICE_ENGINE_CMD" getenv                     ( a u )
    dup 0=  over (vc-max) > or if 2drop exit then   \ unusable: keep what we have
    voice-cmd! ;
voice-from-env

\ --- why the last render failed ---
128 constant (vc-why-max)
create (vc-why-buf) (vc-why-max) allot
variable (vc-why-len)

: (vc-why$) ( c-addr u -- )                \ record a reason, truncating
    (vc-why-max) min  dup (vc-why-len) !
    (vc-why-buf) swap cmove ;
: voice-why ( -- c-addr u )  (vc-why-buf) (vc-why-len) @ ;

\ --- rendering ---
create (vc-text) 2 cells allot
create (vc-path) 2 cells allot

: (vc-build) ( -- )                        \ expand the template into (cmd-buf)
    (cmd0)
    voice-cmd                              ( a u )
    begin dup 0> while
        over c@ [char] % =  over 1 > and if \ u>1: the char after % is ours to read
            over 1+ c@ [char] o = if  (vc-path) 2@ (cmd+q)  2 /string else
            over 1+ c@ [char] t = if  (vc-text) 2@ (cmd+q)  2 /string else
            over c@ (cmd+c)  1 /string then then
        else
            over c@ (cmd+c)  1 /string
        then
    repeat 2drop ;

: (vc-size) ( c-addr u -- n )              \ 0 if missing, unreadable or empty
    r/o open-file if drop 0 exit then      ( fid )
    dup file-size                          ( fid lo hi ior )
    if 2drop close-file drop 0 exit then   ( fid )
    drop swap close-file drop ;            ( lo )

\ Deleting can FAIL -- a read-only directory, or a path that is a directory
\ rather than a file -- and (sh-rm) drops the shell's status, so the failure
\ is silent. A stale file that survived removal would then answer "yes, there
\ is audio here" for a render that produced none.
\
\ Existence rather than size, because existence is the question actually
\ being asked: is this path clear for the engine to write? A size check would
\ catch the same two cases (a surviving file is non-empty, and open-file
\ SUCCEEDS on a directory, which reads as 4096) and would not let a false
\ success through either -- a surviving EMPTY file still ends at "engine
\ wrote no audio". What it would lose is the accurate reason: blaming the
\ engine for output the clearance never made room for.
: (vc-gone?) ( c-addr u -- flag )          \ true if nothing is at the path
    r/o open-file if drop true exit then
    close-file drop false ;

\ An engine that exits 0 having written nothing is the failure worth catching
\ separately: piper does exactly that when the voice model is missing, and a
\ caller that trusted the status would go on to wav-load an empty file.
\
\ Which is why the output file is REMOVED before the engine runs. Without
\ that, "did this produce audio" is answered by whatever was at the path
\ already, and re-rendering a vocabulary with a broken engine reports success
\ for every phrase while leaving the previous take in place -- the worst
\ possible failure, because nothing looks wrong until you listen.
\
\ The command is composed twice for the sake of that ordering: once to learn
\ whether it even fits, and again after the removal, because (sh-rm) runs
\ through the same shared command buffer. Composing is a few hundred bytes of
\ copying, and it buys never deleting a file for a render that could not have
\ run anyway.
: voice-render ( text u path u -- ior )
    (vc-path) 2!  (vc-text) 2!
    0 (vc-why-len) !
    voice-cmd nip 0= if
        s" no engine command set (voice-cmd!)" (vc-why$) 1 exit then
    (vc-build)
    (cmd-ovf) @ if
        s" engine command too long to run" (vc-why$) 2 exit then
    (vc-path) 2@ (sh-rm)
    (vc-path) 2@ (vc-gone?) 0= if
        s" could not clear the previous output" (vc-why$) 5 exit then
    (vc-build)
    (cmd-run) if
        s" engine exited with an error" (vc-why$) 3 exit then
    (vc-path) 2@ (vc-size) 0= if
        s" engine wrote no audio" (vc-why$) 4 exit then
    0 ;
