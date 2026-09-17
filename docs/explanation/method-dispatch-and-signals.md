# Method dispatch and signals

This page explains how a compiled send finds its method, and how
exceptions, `break`, `return` and `throw` move through compiled code.

## A send, from the site

In CRuby, a method call runs through the interpreter's call cache. In
ze0 there is no interpreter, so each send site in compiled code owns
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
  site, behind a *gate* word. Redefining one of these methods on a core
  class closes its gate for the rest of the run.
- `recv[i]`, `recv[i] = v` and `recv << v` test for a core Array, Hash
  or String at the site.
- `!` answers inline for nil, true and false.

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

ze0 does not use the platform's unwinder. Every compiled function
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
