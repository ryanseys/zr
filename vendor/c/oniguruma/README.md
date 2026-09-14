# Oniguruma 6.9.10, the UTF-8 and ASCII subset

The regexp engine, from https://github.com/kkos/oniguruma (BSD-2-Clause,
see COPYING). Only the sources the runtime needs are here: the parser,
compiler and matcher, the Unicode tables, and the UTF-8 and ASCII
encodings. `ze0 deps build` compiles them into vendor/build/libonig.a,
which every native binary links.

Some changes are ze0's own, marked `ze0:`. In oniguruma.h and regexec.c,
`onig_ze0_set_time_limit` names how long the matches that follow may
take, and a backtrack past that deadline stops the match with
`ONIGERR_TIME_LIMIT_OVER`; a match under a limit is not held to the
retry limit as well. That is what `Regexp.timeout` needs, which
Onigmo, CRuby's fork, checks in its matcher the same way.

In regparse.c, a group name holds any character and a `+` at its start
is part of the name, not a relative reference: Onigmo reads a name that
way for Ruby, so `(?<)>x)` names a group `)`.

Also in regparse.c, an anchor takes a quantifier (`(?:(?!a))*`), as
Onigmo lets Ruby write one; and a parse keeps its warnings, in Onigmo's
words, for `onig_ze0_take_warnings` to hand the runtime, which prints
them where ruby does.
