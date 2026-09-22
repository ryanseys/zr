# frozen_string_literal: true

module Ze0
  module IR
    # What a call may write, and what a load or a store touches: a bit a
    # region of memory. A pass that keeps a value it read from memory
    # across an instruction asks whether the instruction can write the
    # value's region; a load of the `volatile` region is never kept
    # across anything, since a timer thread or a signal handler writes
    # it between any two instructions.
    #
    # The regions:
    # - `gates`: the gate word (`zr_static_gates`), which a redefinition
    #   of an operator sets a bit of;
    # - `stamps`: the site, constant and method-cache stamps, which a
    #   definition moves, and the collector too when it frees a class;
    # - `task`: the task pointer, the current fiber, the root chain;
    # - `heap`: a field of a cell;
    # - `malloc`: a payload the allocator hands out (a String's bytes,
    #   an Array's elements, a table's rows);
    # - `statics`: every other static word of the kernel;
    # - `volatile`: the poll word beside the task pointer, the preempt
    #   count and the signal words.
    #
    # A stack slot is no region: a frame is the function's own, and
    # `Forward` and `Mem2Reg` reason about it by address.
    #
    # A kernel def's effects are the union over its body, closed over
    # the defs it calls (`Machine::Lower#assign_effects`); a call
    # through a pointer and a program function write `ALL`. An import
    # writes what a pointer can reach: libc never holds a guard word's
    # address, and a signal handler it lets in writes the volatile
    # words, which nothing keeps. The imports that run ze0's own code
    # before they answer -- a thread start, a library's constructors, a
    # program's entry -- write `ALL`.
    module Effects
      BITS = {
        gates: 1, stamps: 2, task: 4, heap: 8, malloc: 16, statics: 32, volatile: 64, slot: 0
      }.freeze
      ALL = 127
      NONE = 0
      # What a store through an address the lowering cannot place may
      # write: any word a pointer can reach. A guard word is one only
      # when its address escapes as a value, which `Machine::Lower`
      # adds when it sees one.
      UNKNOWN = BITS.fetch(:heap) | BITS.fetch(:malloc) | BITS.fetch(:statics)

      # `zr_static_<name>` to its region; the task slot holds the
      # pointer at 0 and the poll word at 8.
      STATICS = {
        "gates" => :gates,
        "site_stamp" => :stamps, "const_stamp" => :stamps, "mcache_stamp" => :stamps,
        "current_task" => :task, "current_fiber" => :task, "kroots" => :task,
        "preempt_count" => :volatile, "signal_pending" => :volatile, "signal_counts" => :volatile,
        "signal_taken" => :volatile, "preempt_to" => :volatile, "preempt_busy" => :volatile,
        "preempt_mid" => :volatile, "cont_side_ready" => :volatile, "cont_side_ctx" => :volatile,
        "chld_count" => :volatile, "chld_pipe" => :volatile
      }.freeze
      PREFIX = "zr_static_"
      # The imports that may run ze0 code before they return.
      CALLBACKS = %w[pthread_create dlopen dlsym].freeze

      module_function

      # What a call of the import or raw function `symbol` may write.
      def import(symbol) = symbol.start_with?("zr_") || CALLBACKS.include?(symbol) ? ALL : UNKNOWN

      def bit(region) = BITS.fetch(region)

      # The region of the word at `offset` of the static `symbol`, or
      # nil when the symbol is not a static's.
      def static_region(symbol, offset = 0)
        return nil unless symbol.start_with?(PREFIX)

        name = symbol.delete_prefix(PREFIX)
        return :volatile if name == "current_task" && offset >= 8

        STATICS.fetch(name, :statics)
      end

      # Whether `effects` can write a word of `region`.
      def writes?(effects, region) = (effects & BITS.fetch(region)) != 0
    end
  end
end
