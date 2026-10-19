# How to use a C extension

This guide shows you how to build a program that uses a gem's real C
extension, such as msgpack's or nokogiri's. zr compiles your Ruby, and
the binary runs the gem's C code as ruby would run it.
This works on macOS on Apple silicon and on aarch64 Linux (the static
`aarch64-linux-musl` target).

By default, zr does not do this. For a gem with a C extension, zr uses
its own port of the C part when it has one (json, strscan, openssl and
others, see [How to use a library or a gem](use-a-library-or-gem.md)).
You opt in to the real extension for each gem with `--native-ext`.

## Before you start

- Run zr under a ruby of the pinned ruby's series (`.ruby-version`).
  zr's C API is that series', and the build stops under a ruby of
  another series.
- Install the gem in that ruby with `gem install`, as for ruby. zr uses
  what the install left: the compiled objects, the built bundle, or the
  precompiled bundle of a platform gem.
- Install a C compiler (`cc`). A static build links the extension's
  objects with it, and zr compiles a gem that has no compiled code.

`zr doctor` tells you which installed gems are ready:

```
$ zr doctor
...
ok    C extensions       3 of 34 installed gems with one need nothing more of zr's C API: msgpack, nokogiri, websocket-driver
```

## Build with the gem's C extension

Give the gem to `--native-ext`. zr links the C of the newest installed
version, and the build takes the Ruby files of that version too.
`--native-ext`, `--ext`, `--ext-config` and `--link-args` are settings:
they go right after the command, before the program and its options.

```
$ cat app.rb
require "msgpack"
p MessagePack.unpack({ "a" => [1, 2.5] }.to_msgpack)
$ zr build --native-ext msgpack app.rb -o app
$ ./app
{"a" => [1, 2.5]}
```

`--native-ext` takes several gems, separated by commas, and a version
for each: `--native-ext msgpack,nokogiri=1.19.4`. The environment
variable `ZR_NATIVE_EXT` does the same.

To use a different version, put a `gem` line in the program, for
example `gem "msgpack", "1.8.0"`, or use a Gemfile; see
[How to use a library or a gem](use-a-library-or-gem.md#installed-gems-and-gemfiles).

## Choose how the binary runs the extension

`--ext` (or `ZR_EXT`) selects one of three modes:

| Mode | What the build does | Use it when |
|---|---|---|
| `static` (the default) | Links the extension's objects into the binary: on macOS through a bundle that `cc` links, on Linux as one object that `cc -r` joins. Each extension keeps its own names. | Almost always. The binary needs no file at run time. On aarch64-linux-musl it is the only mode. |
| `embed` | Puts the gem's own bundle in the binary with zr's linker. Nothing loads at run time. | The gem has only a bundle, as a precompiled platform gem has. A gem with no objects uses this mode by itself. |
| `dynamic` | Loads the bundle with `dlopen` where the `require` runs. The bundle must stay at its path. | The extension's C++ throws exceptions, uses thread-local variables, or links a library that is not part of macOS. The build tells you so. |

## Configure an extension that zr builds

When the install left no compiled code, zr builds the extension itself:
the host ruby runs the gem's `extconf.rb` in zr's cache, then zr runs
`cc` for each source file. To give `extconf.rb` its options, use
`--ext-config`:

```
$ zr build --native-ext nokogiri --ext-config nokogiri=--use-system-libraries \
    app.rb -o app
```

zr keeps the build for the gem's sources, the options and the ruby, and
builds again only when one of them changes.

## When the build stops

The build checks each function and data word that the extension uses
against zr's C API ([The C API](../reference/c-api.md)) before anything
runs. If one is missing, the build stops with exit status 3 and names
it:

```
zr: foo.bundle: zr's C API has no rb_foo yet (report it: https://github.com/ryanseys/zr/issues)
```

Do one of these:

- Use the gem without `--native-ext`. If zr has a port, it uses the port.
  If it has none, the gem's Ruby files compile, and a `require` of its C
  part raises `LoadError` if it runs.
- Report the missing name, with the gem and its version, at
  <https://github.com/ryanseys/zr/issues>.

On macOS, a build in `static` or `embed` mode also stops, and tells you
to use `--ext=dynamic`, for an extension whose C++ throws exceptions,
that uses thread-local variables, or that links a library outside macOS.

## What is different from ruby

- C holds the GVL while it runs, as in ruby. C that releases the GVL
  (`rb_thread_call_without_gvl`) runs on its thread's own OS thread, and
  the other threads run meanwhile. With green threads
  (`ZR_THREADS=green`), it runs on a worker thread instead.
- `TYPE()` of an Exception, a Proc, a Method or a Fiber is not ruby's:
  zr keeps its own tags for them. C that reads them through functions
  (`rb_obj_is_proc`) gets ruby's answer.
- An extension that hooks trace events (`rb_tracepoint_new`, as
  ruby-prof does) or reads the frames (`rb_debug_inspector_open`, as
  byebug does) makes zr build the program with its trace events, as
  `--trace` does. The program is then larger and slower.
- The private functions of ruby's instruction sequences (`rb_iseq_*`,
  `rb_iseqw_*`) give lines and no columns, and a walk of the heap for
  instruction sequences (debug's and datadog-ci's `iseq_collector`)
  finds none.
- zr runs C extensions on macOS on Apple silicon and on
  aarch64-linux-musl. A musl binary is static, so it links each
  extension from its objects: `embed` and `dynamic` are for macOS.
  A WASI module uses ports only.
- Each extension keeps its own copy of a global name that two
  extensions both define. On macOS ruby does the same. On Linux ruby
  loads each extension with `RTLD_GLOBAL`, so there the second
  extension uses the first one's copy, and zr's answer differs.

## Gems that the tests run

The tests in `test/ext` build each of these gems with its real C
extension and compare the output with ruby's, plain and with the
collector running at each allocation, on macOS and on Alpine Linux:

bcrypt, bindex, bson, byebug, cgi, debug_inspector, ed25519, erb,
escape_utils, fast_blank, google-protobuf, jaro_winkler, msgpack,
murmurhash3, nio4r, nokogiri, oj, puma, rbs, rbtree, redcarpet, rinku,
ruby-prof, stackprof, thrift, unf_ext, websocket-driver and zstd-ruby.

hiredis and yajl-ruby are not among them: they use untyped Data
(`Data_Get_Struct`), which ruby 4.1 removed, so ruby does not build them.

On Linux, the bcrypt and thrift tests skip: their Ruby requires
`openssl`, which a static binary cannot open (below).

## Build for aarch64-linux-musl

From a Mac, give the target and the gem, as for any other build:

```console
$ zr build --native-ext msgpack --target aarch64-linux-musl app.rb -o app
```

zr builds the gem's extension for the target, as `gem install` would
there. It runs the gem's `extconf.rb` with the RbConfig of the pinned
ruby for aarch64-linux-musl, whose headers zr carries, and with the
musl cross compiler (`aarch64-linux-musl-gcc`, for example from
Homebrew's `musl-cross`). mkmf's checks find the functions that zr's C
API has. A library that the extension links (`-lxml2`) must be a static
one for musl.

On an aarch64-linux-musl host, such as Alpine Linux, leave out
`--target`: the host ruby's install of the gem gives the objects, or zr
builds them from the gem's `extconf.rb` when the install did not keep
them. A static archive needs the libraries that it uses itself, which
the extension's Makefile does not name. `pkg-config --static` names
them, and `--link-args` gives them to the linker after the extension's
own. For nokogiri against Alpine's libxml2 and libxslt (`apk add
libxml2-dev libxslt-dev libxml2-static libxslt-static zlib-static
xz-static`):

```console
$ zr build --native-ext nokogiri --ext-config nokogiri=--use-system-libraries \
    --link-args "$(pkg-config --static --libs libxml-2.0 libxslt libexslt)" \
    app.rb -o app
```

Some C needs an option for Alpine. Alpine's headers check
`_FORTIFY_SOURCE`, and zstd-ruby's C does not compile with that check.
Turn it off for the gem:

```console
$ zr build --native-ext zstd-ruby --ext-config zstd-ruby=--with-cflags=-U_FORTIFY_SOURCE \
    app.rb -o app
```

A C++ extension links with Alpine's static libstdc++ (`unf_ext`, for
example). An aarch64-linux-musl binary cannot open OpenSSL, so a gem
whose Ruby or C requires `openssl` does not run on this target; its
`require "openssl"` raises `LoadError`
([Dependencies](../reference/dependencies.md)).

The full list of functions is in [The C API](../reference/c-api.md).
