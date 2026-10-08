# How to use a C extension

This guide shows you how to build a program that uses a gem's real C
extension, such as msgpack's or nokogiri's. zr compiles your Ruby, and
the binary runs the gem's C code as ruby 4.0 would run it.

By default, zr does not do this. For a gem with a C extension, zr uses
its own port of the C part when it has one (json, strscan, openssl and
others, see [How to use a library or a gem](use-a-library-or-gem.md)).
You opt in to the real extension for each gem with `--native-ext`.

## Before you start

- Run zr under ruby 4.0. zr's C API is ruby 4.0's, and the build stops
  under any other ruby.
- Install the gem in that ruby with `gem install`, as for ruby. zr uses
  what the install left: the compiled objects, the built bundle, or the
  precompiled bundle of a platform gem.
- Install a C compiler (`cc`). A static build links the extension's
  objects with it, and zr compiles a gem that has no compiled code.

`zr doctor` tells you which installed gems are ready:

```
$ zr doctor
...
ok    C extensions       35 of 61 installed gems with one need nothing more of zr's C API: bcrypt, msgpack, nio4r, ...
```

## Build with the gem's C extension

Give the gem to `--native-ext`, with the gem itself (`--gem`, or your
Gemfile.lock):

```
$ cat app.rb
require "msgpack"
p MessagePack.unpack({ "a" => [1, 2.5] }.to_msgpack)
$ zr build app.rb --gem msgpack --native-ext msgpack
$ ./app
{"a" => [1, 2.5]}
```

`--native-ext` takes several gems, separated by commas, and a version
for each: `--native-ext msgpack,nokogiri=1.19.4`. The environment
variable `ZR_NATIVE_EXT` does the same.

## Choose how the binary runs the extension

`--ext` (or `ZR_EXT`) selects one of three modes:

| Mode | What the build does | Use it when |
|---|---|---|
| `static` (the default) | Links the extension's objects into a bundle with `cc`, and puts the bundle in the binary. Each extension keeps its own names. | Almost always. The binary needs no file at run time. |
| `embed` | Puts the gem's own bundle in the binary with zr's linker. Nothing loads at run time. | The gem has only a bundle, as a precompiled platform gem has. A gem with no objects uses this mode by itself. |
| `dynamic` | Loads the bundle with `dlopen` where the `require` runs. The bundle must stay at its path. | The extension's C++ throws exceptions, uses thread-local variables, or links a library that is not part of macOS. The build tells you so. |

## Configure an extension that zr builds

When the install left no compiled code, zr builds the extension itself:
the host ruby runs the gem's `extconf.rb` in zr's cache, then zr runs
`cc` for each source file. To give `extconf.rb` its options, use
`--ext-config`:

```
$ zr build app.rb --gem nokogiri --native-ext nokogiri --ext-config nokogiri=--use-system-libraries
```

zr keeps the build for the gem's sources, the options and the ruby, and
builds again only when one of them changes.

## When the build stops

The build checks each function and data word that the extension uses
against zr's C API ([The C API](../reference/c-api.md)) before anything
runs. If one is missing, the build stops with exit status 3 and names
it:

```
zr: foo.bundle: zr's C API has no rb_foo yet (`zr-dev ext imports foo.bundle` lists what it uses)
```

Do one of these:

- Use the gem without `--native-ext`. If zr has a port, it uses the port.
  If it has none, the gem's Ruby files compile, and a `require` of its C
  part raises `LoadError` if it runs.
- Report the missing name, with the gem and its version, at
  <https://github.com/ryanseys/zr/issues>.

A build in `static` or `embed` mode also stops, and tells you to use
`--ext=dynamic`, for an extension whose C++ throws exceptions, that uses
thread-local variables, or that links a library outside macOS.

## What is different from ruby

- C that runs holds every green thread, as it holds the GVL in ruby.
  C that releases the GVL (`rb_thread_call_without_gvl`) runs on a worker
  thread, and the other threads run meanwhile.
- `TYPE()` of an Exception, a Proc, a Method or a Fiber is not ruby's:
  zr keeps its own tags for them. C that reads them through functions
  (`rb_obj_is_proc`) gets ruby's answer.
- An extension that hooks trace events (`rb_tracepoint_new`, as
  ruby-prof does) or reads the frames (`rb_debug_inspector_open`, as
  byebug does) makes zr build the program with its trace events, as
  `--trace` does. The program is then larger and slower.
- The sampling profiler C API (`rb_profile_frames`,
  `rb_postponed_job_*`) is not there, so stackprof and vernier do not
  build.
- zr runs C extensions on macOS on Apple silicon. Other targets use
  ports only.

The full list of functions is in [The C API](../reference/c-api.md).
