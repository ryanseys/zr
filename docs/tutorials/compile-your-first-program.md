# Compile your first program

In this tutorial, we write a small Ruby program and compile it with
zr. We run it, we build a native binary from it, and we build a
WebAssembly module from the same file. At the end, you have one program
that runs three ways and prints the same thing each time.

You need an Apple Silicon Mac with ruby 4.0.6. The last step also needs
[wasmtime](https://wasmtime.dev).

## Install zr

Install the gem:

```console
$ gem install zr
```

Check that the command is there:

```console
$ zr version
zr 0.1.0
```

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

This is ordinary Ruby. Run it with ruby first, so you know the answer:

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
Matz writes Ruby
Ada writes Analytical Engine
2 people, 7 letters of names
```

The output is the same as ruby's. That is the whole promise of zr: a
program answers what ruby answers.

Notice that `zr run` did more than ruby did. It compiled `greet.rb` to
machine code, linked a binary, ran it, and then removed it. The very
first build takes some time, because zr compiles its runtime once and
keeps it in a cache. Every build after that takes less than a second.

## Build a binary

Now keep the binary. Use `zr build` with `-o` to name it:

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
needs no ruby and no gems. It holds your program, the Ruby core library
and the runtime, all compiled from Ruby.

## Give the program arguments

A compiled program reads `ARGV` as a script does. Write `hello.rb`:

```ruby
puts "Hello, #{ARGV.first || "world"}!"
```

With `zr run`, the words after the file name go to the program:

```console
$ zr run hello.rb Ruby
Hello, Ruby!
```

## Build a WebAssembly module

Now build `greet.rb` for WebAssembly. Add `--emit wasm`:

```console
$ zr build greet.rb -o greet.wasm --emit wasm
```

The first wasm build takes longer, because zr prepares the runtime for
wasm once. The next one is fast again.

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

- To see which targets your machine can build, run `zr targets`, or
  read [How to build for another target](../how-to/build-for-another-target.md).
- To help make zr answer more programs, follow
  [Add your first spec](add-your-first-spec.md).
- To learn why zr holds itself to ruby's answers, read
  [The contract: ruby's answer or a refusal](../explanation/the-contract.md).
