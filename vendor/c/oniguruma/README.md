# Oniguruma 6.9.10, the UTF-8 and ASCII subset

The regexp engine, from https://github.com/kkos/oniguruma (BSD-2-Clause,
see COPYING). Only the sources the runtime needs are here: the parser,
compiler and matcher, the Unicode tables, and the UTF-8 and ASCII
encodings. `ze0 deps build` compiles them into vendor/build/libonig.a,
which every native binary links.
