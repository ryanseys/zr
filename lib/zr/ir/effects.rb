# frozen_string_literal: true

module Zr
  module IR
    # Memory regions, one bit each. The effects of a call are the
    # regions that it can write. A pass that keeps a loaded value across
    # an instruction checks if the instruction can write that region. A
    # pass never keeps a `volatile` load, because a timer thread or a
    # signal handler can write it at any time.
    #
    # The regions:
    # - `gates`: the gate word (`zr_static_gates`). A redefinition of an
    #   operator sets a bit in it.
    # - `stamps`: the site, constant and method-cache stamps. A definition
    #   changes them, and the collector also does when it frees a class.
    # - `task`: the task pointer, the current fiber, the root chain.
    # - `heap`: a field of a cell.
    # - `malloc`: a payload from the allocator (String bytes, Array
    #   elements, table entries).
    # - `statics`: all other static words of the kernel.
    # - `volatile`: the poll word next to the task pointer, the preempt
    #   count and the signal words.
    # A stack slot is not a region. `Forward` and `Mem2Reg` handle slots
    # by address.
    #
    # The effects of a kernel def are the union over its body and the
    # defs it calls (`Machine::Lower#assign_effects`). An indirect call
    # and a program function write `ALL`. An import writes `UNKNOWN`,
    # because libc never has the address of a guard word. An import
    # that can run zr code before it returns (`CALLBACKS`) writes `ALL`.
    module Effects
      BITS = {
        gates: 1, stamps: 2, task: 4, heap: 8, malloc: 16, statics: 32, volatile: 64, slot: 0
      }.freeze #: Hash[region, Integer]
      ALL = 127
      # The regions that a store through an unknown address can write:
      # each word that a pointer can reach. A pointer can reach a guard
      # word only if its address escapes as a value. `Machine::Lower`
      # adds that region when it finds such an escape.
      UNKNOWN = BITS.fetch(:heap) | BITS.fetch(:malloc) | BITS.fetch(:statics)

      # `zr_static_<name>` to its region. The task static contains the
      # task pointer at offset 0 and the poll word at offset 8.
      STATICS = {
        "gates" => :gates,
        "site_stamp" => :stamps, "const_stamp" => :stamps, "mcache_stamp" => :stamps,
        "current_task" => :task, "current_fiber" => :task, "kroots" => :task,
        "preempt_count" => :volatile, "signal_pending" => :volatile, "signal_counts" => :volatile,
        "signal_taken" => :volatile, "preempt_to" => :volatile, "preempt_busy" => :volatile,
        "preempt_mid" => :volatile, "cont_side_ready" => :volatile, "cont_side_ctx" => :volatile,
        "chld_count" => :volatile, "chld_pipe" => :volatile
      }.freeze #: Hash[String, region]
      PREFIX = "zr_static_"
      # The imports that can run zr code before they return.
      CALLBACKS = %w[pthread_create dlopen dlsym].freeze

      module_function

      # The regions that a call of the import or raw function `symbol`
      # can write.
      #: (String symbol) -> Integer
      def import(symbol) = symbol.start_with?("zr_") || CALLBACKS.include?(symbol) ? ALL : UNKNOWN

      # A nil `region` raises KeyError. The type takes nil, because a
      # caller passes `Inst#region` or `static_region` after a check that
      # Steep cannot follow.
      #: (region? region) -> Integer
      def bit(region) = BITS.fetch(region)

      # The region of the word at `offset` of the static `symbol`, or
      # nil when the symbol is not a static.
      #: (String symbol, ?Integer offset) -> region?
      def static_region(symbol, offset = 0)
        return nil unless symbol.start_with?(PREFIX)

        name = symbol.delete_prefix(PREFIX)
        return :volatile if name == "current_task" && offset >= 8

        # The block form lets Steep check the default against `region`.
        STATICS.fetch(name) { :statics }
      end

      # Whether `effects` can write a word of `region`.
      # A nil `region` raises KeyError, as in `bit`.
      #: (Integer effects, region? region) -> bool
      def writes?(effects, region) = (effects & BITS.fetch(region)) != 0
    end
  end
end
