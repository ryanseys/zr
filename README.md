# ze0: a Ruby compiler, written in Ruby

ze0 compiles Ruby programs to native binaries, and is itself written in
Ruby. The contract is CRuby's: a program answers exactly what ruby 4.0.6
answers, or ze0 refuses it by name at the line. ruby is the only oracle.

The front end is here today: prism parses, `lib/ze0/lower.rb` lowers to
Cranelift IR as text (`.clif`) plus a JSON sidecar (`.zeodata`), and the
result compiles itself to a fixed point. The rest of the road (an IR and a
HIR in Ruby, a Cranelift shim, a pure-Ruby aarch64 backend, a runtime in
Ruby, a wasm target) is the plan in `docs/plan.md`. Until the runtime
exists, nothing ze0 compiles links: `ze0 test` reports every compiled
program as `backend`, and only `refused`, `diverged`, `crashed` and
`timeout` name defects.

```console
$ bin/ze0 test/ze0/fib.rb -o fib.clif      # compile one program
$ bin/ze0 test ze0::                       # the ze0 corpus against ruby's recordings
$ bin/ze0 test lang/blocks/ --show 40      # any corpus directory
$ bin/ze0 scan 'test/lang/**/*.rb'         # what compiles, what is refused
$ bin/ze0 check                            # the repo's own checks
```

## Layout

```
ze0.rb, bin/ze0          the CLI; ze0.rb is the compiler's entry point
lib/ze0/                 the compiler (lower.rb, clif.rb, scope.rb, ...)
lib/ze0/harness/         the corpus runner: the test-file format and the sweep
lib/ze0/shims/           the ambient rbconfig shim
vendor/ext/<gem>/lib     the Ruby halves of the libraries a program may require
test/lang, core, ...     the corpus: one program per file, ruby's answer under __END__
test/ze0/                the programs ze0's own subset is held to
test/refused/            one fixture per named refusal
test/snapshots/          ze0's text for two programs, pinned
test/checks/             minitest checks (`bin/ze0 check`)
```

`vendor/ruby` and `vendor/gems` (rubygems, bundler, the gem store) are
fetched, not committed; a tier that is absent is skipped.

## The test format

One `.rb` file is one program, and ruby's recorded answer sits under
`__END__`: stdout, then `#@ stderr`, `#@ exit N` or `#@ signal N` markers.
`#@ key: value` lines above `__END__` are directives (`args`, `stdin`,
`env`, `only`, ...). `docs/test-format.md` is the reference. A program may
not read `DATA` or `__FILE__`: ruby would hand it its own trailer.

## Requirements

ruby 4.0.6 (`.ruby-version`), macOS on Apple Silicon. Nothing else yet.
