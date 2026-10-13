# Threads, fibers and ractors

This page explains how zr runs concurrent Ruby code, and why all kinds
of concurrency run on one kind of task.

## One building block: the task

A *task* is a machine stack with its own Ruby state: the frame chain,
the pending unwind, the thread and fiber locals. A switch between two
tasks is a small stub, `zr_switch`, that saves the callee-saved
registers and the stack pointer of one task and loads those of the
other. It is machine code that zr's own assembler writes.

Ruby frames are native frames in zr, so a task's stack must be large:
zr maps 64 MiB for each one (`MAIN_STACK_BYTES`, `FIBER_STACK_BYTES`),
about 300,000 frames of a plain method. zr reserves the whole stack,
and the OS gives it pages only when it grows.

## Fibers

A `Fiber` is a task. `resume` and `yield` switch to it and back. This
is the direct mapping, and it is fast: zr does not copy stacks.

## Threads

A `Thread` is green: each one runs on a fiber of its own, and one
thread runs at a time. A scheduler in the core library
(`lib/zr/runtime/core/thread.rb`) keeps the run queue, the sleeping threads,
and the threads that wait on a descriptor. A thread yields to the
scheduler when it blocks: on `join`, `sleep`, a `Queue`, a `Mutex`, or
a read that must wait.

A thread that never blocks is preempted. When a program starts its
second thread, the runtime starts a timer thread that sets the *poll
word* every 100 ms, which is also CRuby's quantum. Compiled code reads
the word at safe points and yields to the scheduler.

### Why green threads

CRuby also runs one thread at a time, under its GVL. A program that
runs on CRuby does not depend on parallel threads, so green threads
give it the same results. They also make every kernel operation atomic
without locks, and they keep the collector simple: it stops nothing,
because nothing else runs.

## Ractors

A `Ractor` is a task with a boundary around it. Every value that goes
across the boundary is shareable or a deep copy, and a moved object is
not usable in the sender, as in CRuby. The isolation rules are CRuby's:
a non-main ractor that uses a global or a class variable that CRuby
forbids gets `Ractor::IsolationError`. Each class and module belongs to
the ractor that made it: another ractor that changes it gets
`Ractor::IsolationError` too.

All ractors share one heap. Thus `ObjectSpace.each_object` in a ractor
also finds the objects of the others, and `GC.stat` counts the whole
heap ([Differences from ruby](../reference/differences-from-ruby.md#details-that-zr-does-not-copy)).

Ractors run on green tasks, as threads do. A program gets ruby's
results, but not parallel speed.

## On WebAssembly

A WASI module has one stack, which the engine keeps, and no call can
switch it. Thus on `wasm32-wasi`, `Fiber.new` raises `FiberError`, and
threads and ractors, which run on fibers, are not available. There is
no timer thread either: the safe points count down a word.
