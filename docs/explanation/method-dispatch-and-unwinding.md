# Method dispatch and unwinding

This page explains how a compiled send finds its method, and how
exceptions, `break`, `return` and `throw` move through compiled code.

## A send, from the site

In CRuby, a method call goes through the interpreter's call cache. zr
has no interpreter, so each send site in compiled code owns its inline
cache, in `.bss`: four `CallCache` entries.

A cache entry has two keys: the receiver's class, and the global
*method stamp*. Every change to a method table or an ancestor chain
changes the stamp. The site itself tests the first entry. When the
class and the stamp match, the site calls the method's code directly,
with `(recv, argc, argv, entry, blk, found)`. The callee checks its own
arity.

When the first entry misses, the kernel tests the other three, then a
global cache, and then walks the ancestors. The walk applies
refinements, boxes and visibility, uses `method_missing` if it finds
no method, and fills an entry with the result.

zr fills an entry only when nothing else decides the result: no
refinement in use, and no box that shadows the class. A site under
`using` always calls the kernel.

### Why one global stamp

A stamp for each class would miss less after a change. But a global
stamp is simple to keep correct, and Ruby programs change methods
mostly while they start. The collector also changes the stamp when it
frees a class, because a new class can get the freed address. A
measurement showed that this costs one miss for each site after each
collection, and no profile shows that cost.

## Fast paths without dispatch

Some operations do not send while nobody changed them:

- Integer `+ - * < <= > >= ==` and Float arithmetic are inline at the
  site, behind a *gate*. The gate word is in a register of its own
  (`x28`), so the test is one bit test. A redefinition of one of these
  methods on a core class sets its gate for the rest of the run.
- `recv[i]`, `recv[i] = v` and `recv << v` test for a core Array, Hash
  or String at the site.
- `!` is inline for nil, true and false.
- `is_a?`, `kind_of?`, `Mod === obj` (a `case` arm) and `nil?` use only
  the classes while no class defines the name (a gate for each). A
  class has a rank table of its ancestors from its creation, and a flag
  (`FL_RANKED`) that tells that it is in Object's family and that no box
  changed it. Then `klass.is_a?(mod)` is two ranks and one load, inline
  at the site. A module, or a class without ranks, does the call.
- A cache entry for an attribute reader or writer, `nil?`, `frozen?`,
  `Array#size`, BasicObject's `==`/`!=` or one of the type checks has a
  *shape*. The site then does the body in place, with the entry's own
  guards.

## A small def inlined at its site

zr copies a def into each site that calls it
(`Zr::Lower::Function::Inline`) when the def is in the same file, has
only required positional parameters, and has a body of reads: self's
instance variables, readers and type checks of its arguments, fixnum
arithmetic, branches and a return. The site keeps its cache entry and
its class-and-stamp test. When the direct entry of the hit is the def's
own body, the copy runs with no frame.

Every guard inside the copy jumps to the ordinary call, which runs the
def from its start: an entry that misses, a receiver of another kind,
an operator result that is not a fixnum, a gate that is set. Thus the
copy can contain nothing that leaves a trace: no call, no store, no
allocation. The copy and the def's function share the def's cache
entries, so the call after a miss fills what the copy reads the next
time. A program sees no frame for the def, and thus no
`SystemStackError` from it. Nothing in a copy raises, so no backtrace
is taken inside one.

## An iterator run at its site

`ary.each { |x| ... }`, `n.times { |i| ... }` and
`(a..b).each { |i| ... }` with a block literal run in place
(`Zr::Lower::Function::Iterators`): the loop is at the site, and the
block's body is in the site's own function, where the block's locals
are record slots of the site. The site tests the receiver one time: an
Array, a fixnum, or a Range of fixnums, with the method's gate clear.
Any other receiver does the call with the block descriptor.

A block call costs the descriptor, the builtin's frame, the yield, the
block's prologue and its record. In place, zr pays these one time for
each loop. Two frames, the builtin's and the block's, stay under the
caller's frame while the loop runs, and the body's lines go to the
block's frame, so a backtrace from inside is the same as without this.
A pending unwind from the body goes to a region of the site, which puts
the caller's frame back on top before it continues. Only a block with
at most one parameter, no block of its own inside, no binding, no
`super` and no `def` runs this way (`Lower::Scope#iterator_template?`).

Constants and instance variables have cache entries too. The entry of
a constant has two keys: the scope, and a constant stamp. The entry of
an instance variable contains a guess: the slot where the name was
last time. Every use checks the guess, so the guess can be wrong, but
never stale.

## Testing the caches

A wrong cache entry gives a wrong result without an error, so both
values of `ZR_MCACHE` exist to test the caches. `ZR_MCACHE=0` turns
off every entry. `ZR_MCACHE=verify` checks every hit against a fresh
lookup and stops at the first difference.

## Unwinding without unwind tables

zr does not use the platform's unwinder. Every compiled function
returns a `Value`, and the special value undef (`0x34`) means that an
unwind is pending. The task records the kind: a raise, a `break`, a
`return` or a `throw`.

After each call that can fail, the caller tests for undef. If it finds
undef, it goes to its landing block: a `rescue` reads the kind and
takes the exception, an `ensure` runs and then continues the unwind,
and any other frame returns undef to its own caller.

This design is portable. It works the same on aarch64 and on
WebAssembly, which has no unwinder that a program can use. The cost is
one compare and one branch after a call, and the backend lets the
branch read the flags of the compare directly.

A `break` or a `return` from a block gives its *home*: the frame that
it goes back to, by address and serial number. If that frame is gone,
the unwind becomes the `LocalJumpError` that CRuby raises. zr reads a
backtrace from the frame chain at the time of the raise.

## Safe points

Some work must wait until compiled code is at a known point: switching
threads, running POSIX signal handlers, running finalizers. Compiled
code reads a *poll word* at safe points: loop back edges, `next` and
`redo`, and the entry of a program's methods. A timer, a POSIX signal
or the collector sets the word. See
[Threads, fibers and ractors](threads-fibers-and-ractors.md).
