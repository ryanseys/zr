# ze0: a Ruby compiler, written in Ruby

ze0 compiles Ruby programs to native binaries, and is itself written in
Ruby. The contract is CRuby's: a program answers exactly what ruby 4.0.6
answers, or ze0 refuses it by name at the line. ruby is the only oracle.

Nothing ze0 owns is written in C, Rust or assembler. prism parses,
`lib/ze0/hir/` builds a tree HIR, `lib/ze0/zr/` and `lib/ze0/machine/`
lower it to one SSA IR, and three emitters take it from there: the
aarch64 backend writes machine code, the Mach-O writer writes the object,
and the wasm emitter writes a WASI module. `docs/plan.md` is the road.

## Installation

```console
$ gem install ze0
```

ze0 needs ruby 4.0.6 or a later 4.0 release. On an Apple Silicon Mac, it
also needs the Xcode Command Line Tools (`xcode-select --install`) for
native binaries. The install builds the vendored C (prism, oniguruma and
zlib) into the gem, which takes a few seconds.

## Usage

```console
$ ze0 run app.rb                          # compile a Ruby program, and run it
$ ze0 build app.rb -o app                 # compile it to a native binary
$ ze0 build app.rb -o app.wasm --emit wasm && wasmtime app.wasm
$ ze0 build app.rb -o app.o --emit obj    # a Mach-O object, not linked
$ ze0 machine kernel.rb -o kernel         # compile a kernel-dialect file alone
$ ze0 help
```

A command exits with status 3 when ze0 refuses a program. The message
names the form it refused and the line.

### What each host can build

The gem installs on any host. What it can build depends on the host:

| Output | Host |
|---|---|
| native binary (`aarch64-apple-darwin`) | an Apple Silicon Mac with `cc` and `ar` |
| WASI module (`--emit wasm`) | any host |
| Mach-O object (`--emit obj`) | any host |
| ELF object (`--emit obj --target aarch64-linux-musl`) | any host |

On a host that cannot link a native binary, the install skips the
vendored C, and `ze0 build` without `--emit` refuses with status 3.

### Where ze0 writes

| What | Where | Override |
|---|---|---|
| the runtime cache (the compiled runtime, symbol tables) | `~/Library/Caches/ze0/rt` on macOS, `$XDG_CACHE_HOME/ze0/rt` or `~/.cache/ze0/rt` elsewhere; `tmp/rt` in a checkout | `ZE0_CACHE` |
| the vendored C archives | the gem's `vendor/build/aarch64-apple-darwin`, built at install | `ZE0_BUILD` |

ze0 never writes into an installed gem after the install. If the
archives are missing, `gem pristine ze0` builds them again.

### Linking

`ZE0_LINK` picks the linker: `ruby` for `Obj::MachO::Executable` alone, which names
what it cannot link; `cc` for the system linker; unset to take `Obj::MachO::Executable`
where it reaches and `cc` for a program that needs the vendored archives.

ze0 runs `cc` and `ar` with `DEVELOPER_DIR` and `SDKROOT` set to the
install the SDK comes from, so an Xcode older than the Command Line
Tools does not pair its `ld` with an SDK it cannot read. A
`DEVELOPER_DIR` or `SDKROOT` you set yourself stands.

### Known limitation

A binary that calls `eval` carries the compiler, and the absolute paths
of the gem's `vendor/lib`, `rt/ext` and `vendor/ext/*/lib`. A `require`
of a computed name in such a binary works only while that version of
the gem stays installed.

## Development

```console
$ bundle install
$ bin/ze0 zr build test/zr/hello.rb -o hello   # a kernel-dialect file to a binary
$ bin/ze0 zr run test/programs/hello.rb        # a Ruby program, compiled and run
$ bin/ze0 zr build test/zr/gc.rb -o gc.wasm --emit wasm && wasmtime gc.wasm
$ bin/ze0 test ze0::                           # the ze0 corpus against ruby's recordings
$ bin/ze0 test lang/blocks/ --show 40          # any corpus directory
$ bin/ze0 check                                # the repo's own checks, a process a file
$ bin/ze0 check exe interp                     # just the ones whose names match
$ bin/ze0 stage1                               # ze0 compiles itself twice to the same bytes
$ bin/ze0 deps build                           # build the vendored C dependencies
$ bundle exec rake                             # rake check; also compile, corpus, stage1, stage2, build
```

`bin/ze0` is the checkout's command: it adds `test`, `bench`, `check`,
`stage1` and `stage2` to the gem's `exe/ze0` commands. Those need the
corpus and `tools/`, which the gem does not ship.

### Layout

```
exe/ze0                  the gem's CLI; lib/ze0/cli.rb holds its commands
bin/ze0                  the checkout's CLI: the gem's commands and the corpus ones
ext/ze0/extconf.rb       builds the vendored C as the gem installs
ze0.gemspec, Rakefile    the gem, and the tasks over bin/ze0
lib/ze0.rb               the entry: version, paths and targets
lib/ze0/paths.rb         where ze0 reads its sources and writes its builds
lib/ze0/target.rb        the targets ze0 emits, and what this host can build
lib/ze0/hir/             the tree HIR: prism in, analyses and a dump out
lib/ze0/zr/              the lowering from HIR to IR
lib/ze0/machine/         the kernel dialect: typed Ruby that lowers straight to IR
lib/ze0/ir/              the IR, its verifier, and an interpreter the backends owe nothing to
lib/ze0/backend/aarch64/ the aarch64 backend: our own encoder, linear-scan registers, zr_switch, a listing
lib/ze0/backend/wasm/    the wasm32 emitter: one WASI module, a br_table dispatch loop
lib/ze0/obj/             the object model, the relocation layout, the JIT loader
lib/ze0/obj/macho/       the Mach-O object and executable writers, and the libSystem list
lib/ze0/obj/elf/         the ELF64 relocatable object writer, for aarch64-linux-musl
lib/ze0/native/          the build driver and the toolchain
lib/ze0/native/link/     one linker per target: darwin (ze0's own, else cc) and static (cc -static)
lib/ze0/harness/         the corpus runner: the test-file format and the sweep (not in the gem)
rt/kernel/               the runtime's kernel, in the kernel dialect; os.rb names the OS layer's calls
rt/kernel/os/<os>/       one OS layer: errno, the variadic calls, struct layouts, stacks, the JIT;
                         on wasi, the libc calls themselves over WASI preview 1
rt/kernel/arch/<arch>/   one machine layer: the context zr_switch saves and loads; on wasm32,
                         what a module without C or a second stack answers
rt/core/                 the core library, in ordinary Ruby
rt/core/os/<os>/         the numbers an OS gives errno, File, IO and Process constants
rt/ext/                  the native halves of extensions, in ordinary Ruby
rt/ext/os/<os>/          an OS's extension tables (fcntl, etc, socket) and the eval description
vendor/c/                the three vendored C libraries
vendor/ext/<gem>/lib     the Ruby halves of extension gems
vendor/lib/              ruby's pure-Ruby standard library and bundled gems, unedited
test/lang, core, ...     the corpus: one program per file, ruby's answer under __END__
test/ze0/                the programs ze0's own subset is held to
test/native/fixtures.rb  IR written by hand, the floor every runtime program stands on
test/zr/                 kernel-dialect programs; test/zr/refused/ names each refusal
test/programs/           Ruby programs on the runtime, against a live ruby
```

`rt/` and `vendor/` sit beside `lib/`, not in it. They are what ze0
compiles into a program, not code the host ruby loads, and files such
as `rt/ext/rbconfig.rb` and `vendor/lib/set.rb` must never shadow ruby's
own. The gem's only require path is `lib/`.

### The test format

One `.rb` file is one program, and ruby's recorded answer sits under
`__END__`: stdout, then `#@ stderr`, `#@ exit N` or `#@ signal N` markers.
`#@ key: value` lines above `__END__` are directives (`args`, `stdin`,
`env`, `only`, ...). `docs/test-format.md` is the reference. A program may
not read `DATA` or `__FILE__`: ruby would hand it its own trailer.

## Requirements

ze0 emits `aarch64-apple-darwin` binaries and WASI modules.

### To build and run ze0

| Dependency | Why | Where |
|---|---|---|
| ruby 4.0.6 (`.ruby-version`) | the stage-0 host, and the only oracle | everywhere |
| `prism` gem ~> 1.9.0 | parses Ruby | `lib/ze0/hir/build.rb` |
| `minitest` gem ~> 6.0 | runs `bin/ze0 check` (development) | `test/checks/` |
| `aarch64` gem ~> 3.0 | pure Ruby, generated from the ARM specification: the authority our own encoder is held to. It never enters a compiled program. (development) | `test/checks/aarch64_test.rb` |
| `fiddle` gem ~> 1.1 | loads code into the checks' own process (development) | `lib/ze0/obj/jit/fiddle.rb` |
| `cc` | **compiles** the vendored C, and **links** a binary that reaches it | `lib/ze0/deps.rb`, `lib/ze0/native/link.rb` |
| `ld` | invoked by `cc` for those binaries | through `cc` |
| `ar` | archives the vendored C into `vendor/build/<target>/*.a` | `lib/ze0/deps.rb` |
| libSystem | the only dylib a ze0 binary loads | every binary |

`Obj::MachO::Executable` (`lib/ze0/obj/macho/executable.rb`) writes the executable itself -- the
Mach-O image, the chained fixups a position-independent program is
rebased and bound through, and the ad-hoc code signature Apple Silicon
will not run a binary without. It links every program whose imports are
all libSystem's, which is all of `test/native` and `test/zr`. Which names
are libSystem's comes from `lib/ze0/obj/macho/libsystem.rb`, which
`tools/libsystem.rb` writes, so the answer is the same on every host.

A program that reaches oniguruma or zlib still needs a linker that reads
archives, and that is `cc`. `ZE0_LINK=ruby` refuses such a program by
naming the symbol instead of falling back, and `ZE0_LINK=cc` takes the
system linker throughout.

### Vendored C, built as the gem installs or by `ze0 deps build`

| Library | Why it is C |
|---|---|
| prism (`vendor/c/prism`) | the parser ruby itself uses. Matching ruby's answers means matching ruby's parser, and prism has no Ruby implementation. |
| oniguruma (`vendor/c/oniguruma`) | the engine CRuby's `Regexp` semantics are defined by, down to its backtracking limits and its character tables. |
| zlib (`vendor/c/zlib`) | the library ruby's `zlib` extension wraps. Matching ruby's answers means writing the bytes its deflate writes, which only the same version of zlib does. |

Each archive has a stamp beside it: the digest of its inputs' bytes, the
flags and the toolchain. An archive whose stamp differs is built again.

### Optional

| Dependency | Why |
|---|---|
| `wasmtime` | runs the wasm road; `ze0 check` skips what is absent |
| `nm`, `otool` | two checks read an object and a binary back |

Everything above is a Ruby gem, a system tool, or a vendored C library
whose behaviour the contract is written against. `cc` and `ar` stay as
long as the C libraries do: compiling C needs a C compiler, and the
only way to be rid of them is to be rid of the C.

## License

ze0 is under the MIT License (`LICENSE.txt`). The vendored and derived
parts keep their own licenses; `THIRD_PARTY_NOTICES.md` names each one.
