# Ports and native extensions

zr can run the C part of some gems in two ways:

- **The port**: zr's own Ruby version of the gem's C, in
  `lib/zr/runtime/ext/`. This is the default.
- **The native extension**: the gem's real C, which the binary runs
  through zr's C API (`--native-ext`, see
  [How to use a C extension](../how-to/use-a-c-extension.md)).

This page compares the two ways for the gems that have both: json,
stringio and strscan. zr keeps each port as the default until a person
decides otherwise. No entry of `Library::Ports::ALL` prefers the
native extension.

## How the table is made

`zr-dev ext compare json stringio strscan` makes the table
([Tools](tools.md)):

- **Programs**: each program in `test/programs/stdlib/<gem>/`, less
  the ones that pin their own gem version (a `.gems` file).
- **Builds**: each program is built two times. The port build uses no
  flag. The native build uses `--native-ext <gem> --gem <gem>=<version>`,
  where the version is the newest installed one. So the gem's own Ruby
  files come with its C.
- **Pass**: the number of programs whose output and exit status are the
  same as ruby's recorded output (`<program>.expected`). Addresses and
  paths are masked, as the program tests mask them.
- **Time**: each binary runs three times. The table gives the sum of the
  fastest wall time of each program that built.
- **Size**: the mean size of the binaries.

## Results

Measured on 2026-10-08, aarch64-apple-darwin, ruby 4.0.7. The gem
versions: json 3.0.2, stringio 3.2.0 and strscan 3.1.8.

| Gem | Programs | Pass (port) | Pass (native) | Time (port) | Time (native) | Size (port) | Size (native) |
|---|---|---|---|---|---|---|---|
| json | 33 | 33 | 33 | 2.44 s | 1.41 s | 138.1 MB | 49.8 MB |
| stringio | 11 | 11 | 11 | 0.66 s | 0.67 s | 52.4 MB | 49.4 MB |
| strscan | 20 | 20 | 20 | 0.91 s | 0.93 s | 45.7 MB | 138.4 MB |

## What the results show

- **Output**: both ways give ruby's output for every program.
- **json**: the native extension is faster: 1.41 s, against 2.44 s for
  the port. Its binaries are smaller: 49.8 MB, against 138.1 MB. The
  port's binaries carry eval support (`zr inspect` lists irb and
  fileutils in them); the native ones do not.
- **stringio**: the two ways take the same time (0.66 s and 0.67 s).
  The native binaries are 3 MB smaller.
- **strscan**: the two ways take almost the same time (0.91 s for the
  port, 0.93 s for the native extension). The native binaries are
  larger: 138.4 MB, against 45.7 MB. strscan 3.1.8's `lib/strscan.rb`
  has a `$LOAD_PATH.delete` in its branch for truffleruby. zr cannot
  follow that change, so the program carries eval support, though the
  branch never runs.

## Bugs that the comparison found

The first runs found these bugs in zr. Each one is fixed and has a test:

- A linked C extension did not replace zr's port of the same feature.
- json's ensure function returns `Qundef`, which `rb_ensure` read as an
  unwind.
- `rb_class_new_instance` sent `new`, which `StringIO.new` itself is.
- An enumerator from C (`each_line(chomp: true)`) lost its keywords.
- `rb_str_new` with a negative length crashed (strscan's `peek(-1)`).
- `rb_convert_type(x, T_DATA, "Proc", "to_proc")` refused a Proc.
- A require from a gem's C found the port's file at run time.
- Eval support, which the cache shares, took a build's C extensions.
- strscan's C needed Onigmo's regex API (`onig_search`, `OnigRegion`).
