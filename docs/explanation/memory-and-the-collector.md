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

A `&block` parameter pays that cell only when the method keeps the
block. The compiler reads every use of the name (`Hir::Escape`): a
method that only calls it (`block.call(x)`), hands it on (`each(&block)`,
`super`) or tests it (`if block`, `block && ...`) binds the parameter
to the block as it came, still on the caller's stack, and a
`block.call` runs it as `yield` would while `Proc#call` is the
program's own. Any other use -- stored, returned, passed as a plain
argument, the receiver of another method -- makes the Proc in the
prologue as before. A block nested in such a method may read the
parameter too: when the method's scope escapes to a heap Env, the Env
takes a Proc cell in the parameter's place (`zr_env_escape`), so no
heap object ever points into a stack.

Locals that a block captures follow the same pattern. They start in the
frame's record, and move to a heap Env the first time the scope escapes.

## The heap

The heap has cells of four sizes: 32, 64, 128 and 256 bytes. Each size
has its own arenas of 8,192 cells, and each arena is aligned so that a
cell's arena is its address with the low bits cleared. An allocation
takes the smallest size that holds the object and its contents. Short
Strings and small Arrays live whole in their cell; larger payloads go
to a malloc'd block that the sweep frees.

Each arena carries four bitmaps ahead of its cells, a bit a cell: the
marks, the ages, the remembered set, and the cells allocated. A cell's
state is in the maps and never in the cell, so a new arena costs its
maps and none of its pages, a collection leaves the pages a fork
shares untouched, and every walk of the heap's objects steps by the
allocated map.

Allocation is inline in each kernel constructor: each size class has a
cursor at a word of an allocated map, and the constructor takes the
word's first clear bit -- `ctz` of its complement -- sets it, and
writes the header at the cell the bit names. The test for a full word
and for a slow heap is there, and the slow path moves the cursor on:
along its arena, then through the arenas the last sweep left with
room, then a reserved arena, and only then a collection. Every
constructor writes every field of its object before anything can
collect or read it, so the heap never spends time zeroing cells.

## When the collector runs

The collector runs only inside an allocation:

- when a size's arenas have no free cell left and none is reserved;
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
machine, and only a major can give any of it back -- when four have,
for as long as the last major freed a sixteenth of what stayed live;
one that freed less says the heap is full of what the program holds,
and the next waits the sixteen.
A minor that leaves the size class that ran out still short of free
cells is followed by a major at once, since what filled the heap was
then not the young dead -- unless a major ran within the last three
collections, which has already shown what fills the class live: the
class then grows by its whole step instead, as CRuby holds a NOFREE
major off for `RVALUE_OLD_AGE` collections.

Either kind sweeps every arena a word of its maps at a time: the cells
allocated and not marked died in this collection, and each is released
by its bit; the marks become the allocated map and the ages, and go to
zero with the remembered set. A cell that was free is never touched,
and a word of live cells costs four stores. The growth that follows
takes each size class to half free, or to a fifth where the heap has
reached its share of the machine. Finalizers run later, at a safe
point, never inside the sweep.

## Making a missed root loud

A freed cell is poisoned, and marking stops the program if it reaches
one: a live object that points at a freed cell is a root the compiler
missed. Under `ZR_GC_STRESS=1`, allocation goes on past the last cell
handed out, so a stale pointer meets the poison and not a new object.
A constructor that forgets a field reads the poison too.

## Reading the collector

`ZR_GC_TRACE=1` prints one line to stderr a collection, as it ends:

    zr_gc 61 major every malloc pressed heap 8123 live 7900 -> 6100 malloced 3001 of 3129 MB mark 3870 sweep 210 ms

The number is `GC.count`; `major` or `minor` is the kind, and a major
says why (`old`: the old generation doubled, `every`: the minors
before it ran, `short`: the minor before it left the size class short,
`asked`: `GC.start` or stress); `room` or `malloc` is what ran it (a
size class out of cells, or the payload past its limit), and
`pressed` says the cells have reached their share of the machine. Then
the arenas held, the live bytes the last collection found and this one
leaves, the payload against the limit the collection set, and what the
trace and the sweep took. `GC.stat` holds the same totals
(`marking_time`, `sweeping_time`, `major_gc_count`), and `ZE0_TIMING=1`
prints them a phase of a build.

## What ze0 does not do

There is no compaction, no parallel marking, and no nursery: a minor
collection here is the sticky-mark-bit kind, which reaches the young by
starting from the last collection's marks rather than by keeping them
in a space of their own. Nothing is moved, so nothing needs a read
barrier. These are possible later, because the roots are precise.
