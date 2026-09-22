# Linux's machine stacks. The main thread's grows only as far as
# RLIMIT_STACK lets it, 8 MiB unless the shell says otherwise, and a
# binary cannot ask for more. Ruby frames are machine frames here, so
# the program runs on a stack of its own, mapped as a fiber's is.
Machine.import "mmap", [Ptr, Word, I32, I32, I32, Word] => Ptr
Machine.import "mprotect", [Ptr, Word, I32] => I32

# `Native::Link::STACK`, which darwin's link gives the main thread.
MAIN_STACK_BYTES = 67108864

# The program's stack, once mapped: its lowest address, then the
# contexts the switch onto it and back off it save, and the entry's
# arguments and answer.
sig [] => Ptr
machine def zr_linux_main_cell
  Machine.static(:linux_main, 24)
end

sig [] => Ptr
machine def zr_linux_process_context
  Machine.static(:linux_process_context, CONTEXT_BYTES)
end

sig [] => Ptr
machine def zr_linux_program_context
  Machine.static(:linux_program_context, CONTEXT_BYTES)
end

# zr_main on the program's stack, and the switch back to the process's
# with its answer.
sig [] => Void
machine def zr_linux_main_start
  cell = zr_linux_main_cell()
  r = zr_main(Machine.i32(Machine.load64(cell, 8)), Machine.ptr(Machine.load64(cell, 16)))
  Machine.store64(cell, 8, Machine.word(r))
  zr_switch(zr_linux_program_context(), zr_linux_process_context())
end

# The program on a stack of MAIN_STACK_BYTES; on the process's own, with
# no stack check, when no such stack can be mapped.
sig [I32, Ptr] => I32
machine def zr_os_main(argc, argv)
  stack = zr_os_stack_map(MAIN_STACK_BYTES)
  if stack == 0
    return zr_main(argc, argv)
  end
  cell = zr_linux_main_cell()
  Machine.store64(cell, 0, Machine.word(stack))
  Machine.store64(cell, 8, Machine.word(argc))
  Machine.store64(cell, 16, Machine.word(argv))
  zr_arch_context_start(zr_linux_program_context(), Machine.addr(:zr_linux_main_start), Machine.word(stack) + MAIN_STACK_BYTES)
  zr_switch(zr_linux_process_context(), zr_linux_program_context())
  Machine.i32(Machine.load64(cell, 8))
end

# The lowest address of the program's stack, or 0 where it runs on the
# process's own.
sig [] => Word
machine def zr_os_stack_low
  Machine.load64(zr_linux_main_cell(), 0)
end

# The address just past the top of the program's stack, or 0 where it
# runs on the process's own.
sig [] => Word
machine def zr_os_stack_high
  low = Machine.load64(zr_linux_main_cell(), 0)
  low == 0 ? 0 : low + MAIN_STACK_BYTES
end

# PROT_READ | PROT_WRITE, and MAP_PRIVATE | MAP_ANONYMOUS | MAP_STACK.
STACK_PROT = 3
STACK_MAP_FLAGS = 131106
# The lowest page of each stack, which faults on touch.
STACK_GUARD_BYTES = 4096

# A stack of `bytes`, its lowest page a guard, or 0 with errno set. The
# pages arrive only as the stack grows into them.
sig [Word] => Ptr
machine def zr_os_stack_map(bytes)
  stack = mmap(0, bytes, Machine.i32(STACK_PROT), Machine.i32(STACK_MAP_FLAGS), -1, 0)
  if Machine.word(stack) == 0 - 1
    return Machine.ptr(0)
  end
  mprotect(stack, STACK_GUARD_BYTES, Machine.i32(0))
  stack
end

# The timer thread of the preemption (send.rb): once a second Ruby
# thread started, it sets the poll word every 100 ms, so that a thread
# computing with no call into the kernel hands the turn on at its next
# back edge or method entry, as CRuby's timer thread has it do.
Machine.import "pthread_create", [Ptr, Ptr, Ptr, Ptr] => I32
Machine.import "pthread_detach", [Ptr] => I32

sig [Ptr] => Ptr
machine def zr_poll_timer(arg)
  Machine.gates_enter
  ts = Machine.slot(16)
  Machine.store64(ts, 0, 0)
  Machine.store64(ts, 8, 100000000)
  while true
    nanosleep(ts, 0)
    zr_poll_set()
  end
  arg
end

sig [] => Void
machine def zr_os_poll_start
  started = Machine.static(:poll_started, 8)
  if Machine.load64(started, 0) != 0
    return
  end
  Machine.store64(started, 0, 1)
  tid = Machine.slot(8)
  if pthread_create(tid, 0, Machine.addr(:zr_poll_timer), 0) == Machine.i32(0)
    pthread_detach(Machine.ptr(Machine.load64(tid, 0)))
  end
end
