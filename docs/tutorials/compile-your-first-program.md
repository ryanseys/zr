# Compile your first program

In this tutorial, we write a small Ruby program and compile it with
zr. We run it, we build a native binary from it, and we build a
WebAssembly module from the same file. At the end, you have one program
that runs three ways and prints the same thing each time.

You need an Apple Silicon Mac (macOS 14 or later) with ruby 4.0 or later
(the latest Ruby 4 release is best). The last step also needs
[wasmtime](https://wasmtime.dev).
[How to install zr](../how-to/install.md) shows how to get them.

## Install zr

Install the gem:

```console
$ gem install zr
```

Check that the command is there:

```console
$ zr version
zr 0.1.0 (for ruby 4.x.y)
```

Check what zr can do on this Mac:

```console
$ zr doctor
```

Each line starts with `ok`, `warn` or `fail`. A `warn` line says what
zr cannot do here, and how to fix it. With no `fail` line, you can
continue.

## Write a program

Make a new directory, and write this program to `greet.rb` in it:

```ruby
Person = Struct.new(:name, :language)

people = [
  Person.new("Matz", "Ruby"),
  Person.new("Ada", "Analytical Engine"),
]

people.each do |person|
  puts "#{person.name} writes #{person.language}"
end

puts "#{people.size} people, #{people.sum { |p| p.name.length }} letters of names"
```

This is ordinary Ruby. Run it with ruby first, so that you know the correct output:

```console
$ ruby greet.rb
Matz writes Ruby
Ada writes Analytical Engine
2 people, 7 letters of names
```

## Run it with zr

Now run the same file with zr:

```console
$ zr run greet.rb
zr: building the zr runtime for aarch64-apple-darwin. This occurs one time and takes some minutes.
Matz writes Ruby
Ada writes Analytical Engine
2 people, 7 letters of names
```

The `zr:` line comes only from the first build on this Mac. zr
compiles its runtime one time and keeps it in a cache. Wait for it to
finish.

Run it again. Now only the program's output shows:

```console
$ zr run greet.rb
Matz writes Ruby
Ada writes Analytical Engine
2 people, 7 letters of names
```

The output is the same as ruby's. That is the promise of zr: a
program gives the same output as ruby.

`zr run` did more than ruby did. It compiled `greet.rb` to machine
code, linked a binary, ran it, and then deleted it. Every build after
the first takes about a second.

## Build a binary

Now keep the binary. Use `zr build` with `-o` to give its name:

```console
$ zr build greet.rb -o greet
```

Run the binary directly. No ruby is involved now:

```console
$ ./greet
Matz writes Ruby
Ada writes Analytical Engine
2 people, 7 letters of names
```

Look at what zr wrote:

```console
$ file greet
greet: Mach-O 64-bit executable arm64
```

You can copy `greet` to another Apple Silicon Mac and run it there. It
needs no ruby and no gems. It contains your program, the Ruby core
library and the runtime, all compiled from Ruby.

## Give the program arguments

A compiled program reads `ARGV` as a script does. Write `hello.rb`:

```ruby
puts "Hello, #{ARGV.first || "world"}!"
```

With `zr run`, every word after the file name goes to the program:

```console
$ zr run hello.rb Ruby
Hello, Ruby!
```

## Build a WebAssembly module

Now build `greet.rb` for WebAssembly. Add `--emit wasm`:

```console
$ zr build greet.rb -o greet.wasm --emit wasm
```

The first wasm build takes longer, because zr builds the runtime for
wasm one time. The next one is fast again.

Run the module with wasmtime:

```console
$ wasmtime greet.wasm
Matz writes Ruby
Ada writes Analytical Engine
2 people, 7 letters of names
```

The same three lines again, this time from a WASI module.

## What you did

You compiled one Ruby file three ways: with `zr run`, as a native
binary, and as a WebAssembly module. Each one printed exactly what ruby
printed.

Next steps:

- To see which targets your machine can build, run `zr doctor`, or
  read [How to build for another target](../how-to/build-for-another-target.md).
- To help zr support more programs, follow
  [Add your first program test](add-your-first-program-test.md).
- To learn why zr checks itself against ruby's output, read
  [The contract: ruby's output or a refusal](../explanation/the-contract.md).
