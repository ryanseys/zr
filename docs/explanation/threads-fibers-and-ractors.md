# Threads, fibers and ractors

This page explains how ze0 runs concurrent Ruby code, and why every
kind of concurrency runs on one kind of task.

## One building block: the task

A *task* is a machine stack with its own Ruby state: the frame chain,
the pending signal, the thread and fiber locals. A switch between two
tasks is a small stub, `zr_switch`, that saves the callee-saved
registers and the stack pointer of one task and loads those of the
other. It is machine code that ze0's own assembler writes.

Ruby frames are native frames in ze0, so a task's stack must be large:
10,000 frames of a plain method need about 36 MiB. The stack is
reserved in full, and the OS gives it pages only as it grows.

## Fibers

A `Fiber` is a task. `resume` and `yield` switch to it and back. This is
the direct mapping, and it is fast: there is no copying of stacks.

## Threads

A `Thread` is green: each one runs on a fiber of its own, and one thread
runs at a time. A scheduler in the core library (`rt/core/thread.rb`)
keeps the run queue, the sleepers, and the threads that wait on a
descriptor. A thread gives up its turn when it blocks: on `join`,
`sleep`, a `Queue`, a `Mutex`, or a read that would wait.

A thread that never blocks is preempted. When a program starts its
second thread, the runtime starts a timer thread that sets the *poll
word* every 100 ms, which is CRuby's quantum too. Compiled code reads
the word at safe points and hands the turn to the scheduler.

### Why green threads

CRuby runs one thread at a time too, under its GVL. A program that
runs on CRuby has not depended on parallel threads, so green threads
give it the same answers. They also make every kernel operation atomic
with no locks, and they keep the collector simple: it stops nothing,
because nothing else runs.

## Ractors

A `Ractor` is a task with a boundary around it. Every value that
crosses the boundary is shareable or a deep copy, and a moved object
becomes unusable in the sender, as in CRuby. The isolation rules are
CRuby's: a non-main ractor that uses a global or a class variable as
CRuby forbids gets `Ractor::IsolationError`.

Ractors run on green tasks, as threads do. A program gets ruby's
answers, but not parallel speed.

## On WebAssembly

A WASI module has one stack, which the engine keeps, and no call can
switch it. So on `wasm32-wasi`, `Fiber.new` raises `FiberError`, and
threads and ractors, which run on fibers, are not available. There is
no timer thread either: the safe points count down a word instead.
