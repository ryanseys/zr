# Memory and the collector

This page explains how a compiled program allocates objects and frees
them, and why the collector is designed as it is. The layouts it uses
are in [Runtime layouts](../reference/runtime-layouts.md).

## A precise collector

ze0's collector is a mark-sweep collector that does not move objects.
It is *precise*: it knows every place a live `Value` can be, and it
reads only those places. It never scans the machine stack for words
that look like pointers.

A precise collector needs the compiler's help, and ze0 is the compiler,
so it can give that help. The alternative, a conservative scan of the
stack, keeps garbage alive when an integer looks like a pointer, and
it makes a missed root a rare, random failure. With precise roots, a
missed root fails at once under `ZR_GC_STRESS=1`.

## Frame records: where the roots are

Every compiled Ruby function keeps a *frame record* in its machine
frame. The record holds the function's self, its line, and a slot for
every `Value` the function holds: its locals, and the receiver and
arguments of a send while the next argument is evaluated. Each record
links to its caller's, and the task keeps the newest. The collector
walks that chain.

This gives one rule that the whole compiler keeps: **no `Value` lives
only in a register across a call that can allocate or raise.** A
function stores the value in its record first. The IR passes keep that
store, because the collector reads it.

The kernel follows the same rule. A kernel def that can reach the
collector (`Machine.collects`, followed through the call graph) gets a
root frame, and every `Value` it holds lives in a slot of that frame.

## Blocks and captured locals

A block literal does not allocate a Proc when the send that carries it
runs. The send writes the block's image into a slot of its own frame
record. The image is marked as a stack object, so the collector does
not trace through it; the frame already roots everything it names.

A block becomes a real Proc cell only when something keeps it past the
call: a `&block` parameter, `proc` or `lambda`, a Binding, a Fiber, a
`define_method` body. At that point, the runtime copies the image to
the heap. So no heap object ever points into a stack.

The parameter is bound in the prologue, so a method that names one pays
that cell whatever the body does with the block -- handing it straight
on costs as much as keeping it. A core method that only hands its block
on therefore relays it through a block of its own:
`meeting(...) { |x| yield x }` costs nothing where
`meeting(..., &block)` costs a Proc a call. `Array#any?` and
`Enumerable#each_with_index` are written that way, and so should be any
method the compiler reaches a million times.

Locals that a block captures follow the same pattern. They start in the
frame's record, and move to a heap Env the first time the scope escapes.

## The heap

The heap has cells of four sizes: 32, 64, 128 and 256 bytes. Each size
has its own arenas of 8,192 cells, and each arena is aligned so that a
cell's arena is its address with the low bits cleared. An allocation
takes the smallest size that holds the object and its contents. Short
Strings and small Arrays live whole in their cell; larger payloads go
to a malloc'd block that the sweep frees.

Allocation is inline in each kernel constructor: the test for an empty
free list and for a slow heap is there, and two short calls pick the
size and take the list's head and write the header. Every constructor then writes every field
of its object before anything can collect or read it, so the heap never
spends time zeroing cells.

## When the collector runs

The collector runs only inside an allocation:

- when a size's free list and its spare arenas are empty;
- when the malloc'd payload passes its limit (64 MiB, or twice the
  payload found live at the last collection);
- at `GC.start`;
- at every allocation, under `ZR_GC_STRESS=1`.

A collection is minor or major. A **major** one marks from the roots:
every task's frame chain, the kernel's root frames, the globals, the
constant and symbol tables, and the finalizer queue. A **minor** one
starts its marks from the ages -- what the last collection finished
with -- so the trace stops at everything that survived it and reaches
only what has been allocated since; the arenas the write barrier
flagged are read again, for an old object that has come to hold a young
one. A minor accepts floating garbage and frees no old dead graph, and
both wait for the next major. That is the ordinary generational trade.

A major runs when the old generation has doubled, when sixteen minors
have gone by, or -- where the cells have reached their share of the
machine, and only a major can give any of it back -- when four have.
A minor that leaves the size class that ran out still short of free
cells is followed by a major at once, since what filled the heap was
then not the young dead.

Either kind sweeps every arena, and the growth that follows takes each
size class to half free, or to a fifth where the heap has reached its
share of the machine. Finalizers run later, at a safe point, never
inside the sweep.

## Making a missed root loud

A freed cell is poisoned, and marking stops the program if it reaches
one: a live object that points at a freed cell is a root the compiler
missed. Under `ZR_GC_STRESS=1`, each free list starts past the last
cell handed out, so a stale pointer meets the poison and not a new
object. A constructor that forgets a field reads the poison too.

## What ze0 does not do

There is no compaction, no parallel marking, and no nursery: a minor
collection here is the sticky-mark-bit kind, which reaches the young by
starting from the last collection's marks rather than by keeping them
in a space of their own. Nothing is moved, so nothing needs a read
barrier. These are possible later, because the roots are precise.
