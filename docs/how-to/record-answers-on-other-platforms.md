# How to record answers on other platforms

This guide shows you how to record where a case's answer on Linux or
WASI differs from its answer on macOS. The format of these sections is
in [The test format](../reference/test-format.md).

A case always has macOS's answer first. Record it on a Mac:

```console
$ ruby tools/record.rb core/io/a_case.rb
```

## Record the Linux answer

Run the same tool on a Linux machine, with ruby 4.0.6, and name the OS:

```console
$ ruby tools/record.rb --os linux core/io/a_case.rb
```

The tool writes only the sections where Linux's answer differs, such as
`#@ linux stdout`. A case that answers the same on both platforms does
not change.

To use the Alpine container that CI uses:

```console
$ docker run -d --name alpine -v "$PWD:/ze0" -w /ze0 ruby:4.0.6-alpine sleep infinity
$ docker exec alpine apk add --no-cache build-base git
$ docker exec alpine bundle install
$ docker exec alpine ruby tools/record.rb --os linux core/io/a_case.rb
```

## Record the WASI answer

The oracle for WASI is ruby 4.0.6's ruby.wasm under wasmtime. Name the
command that runs it with `--ruby`. The tool adds the case's path and
arguments after that command:

```console
$ ruby tools/record.rb --os wasi --ruby "<command that runs ruby.wasm>" core/io/a_case.rb
```

## Run a case on one platform only

When a case cannot mean the same thing on another platform, limit it
with a directive above `__END__`:

```ruby
#@ only: macos linux
```

## Check a target against its baseline

A target that does not pass the whole corpus yet has a baseline: the
list of rows it is allowed to fail. Run it with the baseline:

```console
$ bin/ze0 test ze0:: --target wasm32-wasi --baseline test/baselines/wasm32-wasi.txt
```

When a change fixes rows, write the baseline again from the sweep's
output, `tmp/sweep.txt`.
