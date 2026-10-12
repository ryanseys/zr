# Known gaps

Each `<name>.rb` here is a small program where zr's output is not yet
ruby's. `<name>.rb.expected` is ruby's stdout
(`ruby <name>.rb > <name>.rb.expected`). The name says what ruby does, and
the comment at the top says what zr does instead.

The program tier does not run these files. To see which gaps are still
open, run them under ruby and as zr binaries:

    bin/zr-dev probe test/gaps -j 2

`SAME` means that zr now gives ruby's output. Move that program to
`test/programs/<area>/`, add edge cases, write its sidecars with
`bin/zr-dev expect`, and delete its `.expected` file here.
