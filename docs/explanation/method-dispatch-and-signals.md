# Method dispatch and signals

This page explains how a compiled send finds its method, and how
exceptions, `break`, `return` and `throw` move through compiled code.

## A send, from the site

In CRuby, a method call runs through the interpreter's call cache. In
zr there is no interpreter, so each send site in compiled code owns
its caches, in `.bss`: four `CallCache` cells.

A cell is keyed on two things: the receiver's class, and a global
*method stamp*. Every change to any method table or ancestor chain
moves the stamp. The site itself tests the first cell. When the class
and the stamp match, the site calls the method's code directly, with
`(recv, argc, argv, entry, blk, found)`. The callee checks its own
arity.

When the first cell misses, the kernel tests the other three, then a
global cache, and then walks the ancestors. The walk applies
refinements, boxes and visibility, falls back to `method_missing`, and
fills a cell with the answer.

A cell is filled only when nothing else decided the answer: no
refinement in use and no box that shadows the class. A site under
`using` always asks the kernel.

### Why one global stamp

A stamp per class would miss less after a change. But a global stamp
is simple to keep correct, and Ruby programs change methods mostly as
they boot. The collector moves the stamp too, when it frees a class,
because a new class can take the freed address. A measurement showed
that this costs one miss for each site after each collection, and no
profile shows that cost.

## Fast paths without dispatch

Some operations skip the send when nobody changed them:

- Integer `+ - * < <= > >= ==` and Float arithmetic are inline at the
  site, behind a *gate* word, which lives in a register of its own
  (`x28`), so the test is one bit test of it. Redefining one of these
  methods on a core class closes its gate for the rest of the run.
- `recv[i]`, `recv[i] = v` and `recv << v` test for a core Array, Hash
  or String at the site.
- `!` answers inline for nil, true and false.
- `is_a?`, `kind_of?`, `Mod === obj` (a `case` arm) and `nil?` answer
  from the classes alone while no class defines the name (a gate
  each). A class carries a rank table of its ancestors from birth, and
  a flag (`FL_RANKED`) that says it is in Object's family and no box
  has touched it; then `klass.is_a?(mod)` is two ranks and one load,
  written out at the site. A module, or a class not yet ranked, takes
  the call.
- A cell whose entry is an attribute reader or writer, `nil?`,
  `frozen?`, `Array#size`, BasicObject's `==`/`!=` or one of the type
  questions carries a *shape*, and the site does the body in place
  with the entry's own guards.

## A small def inlined at its site

A def of the same file with required positionals alone and a body of
reads -- self's instance variables, readers and type questions of its
arguments, fixnum arithmetic, branches and a return -- is copied into
each site that calls it (`Zr::Function::Inline`). The site keeps its
cell and its class-and-stamp test; when the hit's direct entry is the
def's own body, the copy runs with no frame. Every guard inside the
copy -- a cell that misses, a receiver of another kind, an operator
past the fixnums, a gate closed -- jumps to the ordinary call, which
runs the def from its start, so the copy may hold nothing that leaves
a trace: no call, no store, no allocation. The copy and the def's
function share the def's site cells, so the call that a miss takes
fills what the copy reads next time. A program sees no frame for the
def, and so no `SystemStackError` from it; nothing in a copy raises,
so no backtrace is ever taken inside one.

## An iterator run at its site

`ary.each { |x| ... }`, `n.times { |i| ... }` and `(a..b).each { |i|
... }` with a block literal run in place (`Zr::Function::Iterators`):
the loop at the site, and the block's body in the site's own function,
where the block's locals are record slots of the site's. The receiver
is tested once -- an Array, a fixnum or a Range of fixnums, with the
method's gate clear -- and anything else takes the call with the block
descriptor as before. What a block call cost a turn (the descriptor,
the builtin's frame, the yield, the block's prologue and record) is
paid once a loop: two frames, the builtin's and the block's, stand
under the caller's for the loop's duration, and the body's lines go to
the block's, so a backtrace from inside reads as before. A signal from
the body lands in a region of the site's own, which puts the caller's
frame back on top before passing it on. Only a block a parameter at
most, with no block of its own inside, no binding, no super and no
def, runs this way (`Scope.iterator_template?`).

Constants and instance variables have cells of their own. A constant's
cell keys on the scope and a constant stamp. An instance variable's
cell holds a guess of the row the name was in last time, which every
use checks, so the guess is never stale, only wrong.

## Checking the caches

The caches are the place where a wrong answer would be quiet, so both
modes of `ZR_MCACHE` exist to test them. `ZR_MCACHE=0` turns every cell
off. `ZR_MCACHE=verify` checks every hit against a fresh lookup and
stops at the first difference.

## Signals: exceptions without unwinding tables

zr does not use the platform's unwinder. Every compiled function
answers a `Value`, and the special value `undef` (`0x34`) means a
*signal* is pending. The task records which kind: a raise, a `break`,
a `return` or a `throw`.

After each call that can fail, the caller tests for `undef`. If it
sees one, it takes its landing block: a `rescue` reads the kind and
takes the exception, an `ensure` runs and then passes the signal on,
and anything else returns `undef` to its own caller.

This design is portable. It works the same on aarch64 and on
WebAssembly, which has no unwinder a program can use. The cost is one
compare and branch after a call, and the backend lets the branch read
the compare's flags directly.

A `break` or a `return` from a block names its *home*: the frame it
goes back to, by address and serial number. When that frame is gone,
the signal becomes the `LocalJumpError` that CRuby raises. A backtrace
is read from the frame chain at the moment of the raise.

## Safe points

Some work must wait until compiled code is at a known point: switching
threads, running signal handlers, running finalizers. Compiled code
reads a *poll word* at safe points: loop back edges, `next` and `redo`,
and the entry of a program's methods. A timer, a signal or the
collector sets the word. See [Threads, fibers and ractors](threads-fibers-and-ractors.md).
