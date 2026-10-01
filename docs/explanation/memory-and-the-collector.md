# Memory and the collector

This page explains how a compiled program allocates objects and frees
them, and why the collector has its design. The layouts that it uses
are in [Runtime layouts](../reference/runtime-layouts.md).

## A precise collector

zr's collector is a mark-sweep collector that does not move objects.
It is *precise*: it knows every place where a live `Value` can be, and
it reads only those places. It never scans the machine stack for words
that look like pointers.

A precise collector needs help from the compiler, and zr is the
compiler, so it can give that help. The alternative, a conservative
scan of the stack, keeps garbage alive when an integer looks like a
pointer, and a missed root then fails rarely and at random. With
precise roots, a missed root fails at once under `ZR_GC_STRESS=1`.

## Frame records: where the roots are

Every compiled Ruby function keeps a *frame record* in its machine
frame. The record contains the function's self, its line, and a slot
for every `Value` that the function keeps: its locals, and the
receiver and arguments of a send while the next argument is evaluated.
Each record links to the record of its caller, and the task keeps the
newest one. The collector walks that chain.

This gives one rule that the whole compiler obeys: **no `Value` is
only in a register across a call that can allocate or raise.** A
function stores the value in its record first. The IR passes keep that
store, because the collector reads it.

The kernel obeys the same rule. A kernel def that can reach the
collector (`collects :name`, followed through the call graph) gets a
root frame, and every `Value` that it keeps is in a slot of that frame.

## Blocks and captured locals

A block literal does not allocate a Proc when the send that has it
runs. The send writes the block's image into a slot of its own frame
record. The image is marked as a stack object, so the collector does
not trace through it. The frame already roots everything that the
image refers to.

A block becomes a Proc cell only when something keeps it after the
call: a `&block` parameter, `proc` or `lambda`, a Binding, a Fiber, a
`define_method` body. At that time, the runtime copies the image to
the heap. Thus no heap object points into a stack.

A `&block` parameter makes that cell only when the method keeps the
block. The compiler reads every use of the name (`Hir::Escape`). If a
method only calls the block (`block.call(x)`), gives it to another
call (`each(&block)`, `super`) or tests it (`if block`,
`block && ...`), the parameter is the block as it came, still on the
caller's stack. Then `block.call` runs it as `yield` does. Any other use (stored, returned, given as
a plain argument, the receiver of another method) makes the Proc in
the prologue. A block inside such a method can also read the
parameter: when the method's scope escapes to a heap Env, the Env gets
a Proc cell in place of the parameter (`zr_env_escape`).

Locals that a block captures follow the same pattern. They start in the
frame's record, and move to a heap Env the first time the scope
escapes.

## The heap

The heap has cells of four sizes: 32, 64, 128 and 256 bytes. Each size
has its own arenas of 8,192 cells. Each arena is aligned, so the arena
of a cell is its address with the low bits cleared. An allocation uses
the smallest size that contains the object and its contents. Short
Strings and small Arrays fit in their cell. Larger contents go to a
malloc block that the sweep frees.

Each arena has four bitmaps before its cells, one bit for each cell:
the marks, the ages, the remembered set, and the allocated cells. The
state of a cell is in the bitmaps, never in the cell. Thus a new arena
costs only its bitmaps, a collection does not write the pages that a
fork shares, and every walk of the heap's objects steps through the
allocated bitmap.

Each kernel constructor allocates inline. Each size class has a cursor
at a word of an allocated bitmap. The constructor finds the first
clear bit of the word (`ctz` of its complement), sets it, and writes
the header at the cell of that bit. The constructor also tests for a
full word and for a slow heap. The slow path moves the cursor: along
its arena, then through the arenas that the last sweep left with free
cells, then to a reserved arena, and only then to a collection. Every
constructor writes every field of its object before anything can
collect or read it, so the heap never spends time to zero cells.

## When the collector runs

The collector runs only inside an allocation:

- when the arenas of a size have no free cell and none is reserved;
- when the malloc contents pass their limit (64 MiB, or two times the
  live contents at the last collection);
- at `GC.start`;
- at every allocation, under `ZR_GC_STRESS=1`.

A collection is minor or major. A **major** collection marks from the
roots: the frame chain of every task, the kernel's root frames, the
globals, the constant and symbol tables, and the finalizer queue. A
**minor** collection starts its marks from the ages (what the last
collection found live), so the trace stops at everything that the last
collection kept and reaches only what the program allocated since
then. It reads again the arenas that the write barrier marked, for an
old object that now refers to a young one. A minor collection keeps
some garbage and frees no old dead objects. Both wait for the next
major collection. This is the usual generational trade.

A major collection runs:

- when the old generation has doubled;
- after sixteen minor collections;
- after four minor collections, when the cells have reached their share
  of the machine's memory, while the last major collection freed at
  least a sixteenth of what stayed live. A major collection that freed
  less shows that the heap is full of live objects, and the next one
  waits for sixteen.

If a minor collection leaves the size class that ran out still short
of free cells, a major collection follows at once, because the heap
did not fill with young dead objects. The exception: if a major
collection ran in the last three collections, it already showed that
live objects fill the class, so the class grows by its whole step. CRuby
also delays a NOFREE major collection for `RVALUE_OLD_AGE`
collections.

Both kinds sweep every arena one word of bitmaps at a time. The cells
that are allocated and not marked died in this collection, and the
sweep releases each one by its bit. The marks become the allocated
bitmap and the ages, and the remembered set goes to zero. The sweep
never touches a free cell, and a word of live cells costs four stores.
After the sweep, each size class grows to half free, or to a fifth
free when the heap has reached its share of the machine. Finalizers run
later, at a safe point, never inside the sweep.

## Making a missed root visible

zr poisons a freed cell, and marking stops the program if it reaches
one: a live object that refers to a freed cell is a root that the
compiler missed. Under `ZR_GC_STRESS=1`, allocation continues after the
last cell it gave out, so a stale pointer finds the poison and not a
new object. A constructor that does not write a field also reads the
poison.

## Read the collector trace

`ZR_GC_TRACE=1` prints one line to stderr for each collection, at its
end:

    zr_gc 61 major every malloc pressed heap 8123 live 7900 -> 6100 malloced 3001 of 3129 MB mark 3870 sweep 210 ms

| Field | Meaning |
|---|---|
| `61` | `GC.count` |
| `major` or `minor` | the kind of collection |
| `old`, `every`, `short`, `asked` | for a major collection, why: the old generation doubled; the count of minor collections before it; the minor collection before it left the size class short; `GC.start` or stress |
| `room` or `malloc` | what started it: a size class with no free cells, or the malloc contents past their limit |
| `pressed` | the cells have reached their share of the machine |
| `heap 8123` | the arenas |
| `live 7900 -> 6100` | the live bytes that the last collection found, and that this one leaves |
| `malloced 3001 of 3129 MB` | the malloc contents, and the limit that the collection set |
| `mark 3870 sweep 210 ms` | the time of the trace and of the sweep |

`GC.stat` contains the same totals (`marking_time`, `sweeping_time`,
`major_gc_count`), and `ZR_TIMING=1` prints them for each phase of a
build.

## What zr does not do

zr has no compaction, no parallel marking, and no nursery. A minor
collection here is the sticky-mark-bit kind: it finds the young
objects from the marks of the last collection, not from a space of
their own. Nothing moves, so nothing needs a read barrier. These
features are possible later, because the roots are precise.
