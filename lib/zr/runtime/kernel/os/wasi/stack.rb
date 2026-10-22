# WASI machine stacks. A module has two: the engine's, which holds the
# wasm frames and whose limit the engine does not tell the module, and
# the shadow stack in linear memory, which holds zr's frame records and
# slots and grows down to its base (backend/wasm/codegen.rb). A module
# cannot map memory for a second stack.

module Zr::Kern
  #: (i32, ptr) -> i32
  def zr_os_main(argc, argv)
    zr_wasi_start_cwd()
    zr_main(argc, argv)
  end

  # The shadow stack's base: the main task's stack limit is a margin above
  # it (zr_main_stack_limit), so a recursion that is too deep raises
  # SystemStackError, where the engine would trap. The engine's limit
  # must hold more wasm frames than the shadow stack holds records
  # (`-W max-wasm-stack`, test/support/harness/wasmtime.rb).
  #: () -> word
  def zr_os_stack_low
    Libc.zr_wasm_stack_low()
  end

  # 0: the module cannot get access to the engine's stack.
  #: () -> word
  def zr_os_stack_high
    0
  end

  #: (word) -> ptr
  def zr_os_stack_map(bytes)
    zr_os_set_errno(WASI_ENOSYS)
    Machine.ptr(0)
  end

  # There is no timer thread. The preemption count is the clock (send.rb).
  #: () -> void
  def zr_os_poll_start
  end
end
