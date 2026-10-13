# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # The points where a traced program fires TracePoint events: a
      # statement's `:line`, and a scope's opening and closing events.
      # Each one tests the kernel's event mask, so if all TracePoints are
      # disabled, each point costs one load and one branch.
      module Tracing
        # @type instance: Function
        # @rbs @def: Hir::owner?
        # @rbs @f: IR::Function
        # @rbs @kind: Function::kind
        # @rbs @l: Lower
        # @rbs @qnil: String
        # @rbs @ensure_path: Symbol
        # @rbs @jump_line: Integer?
        # @rbs @body: Hir::node?

        # ruby's RUBY_EVENT_* bits.
        EVENTS = { line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, b_call: 0x100, b_return: 0x200 }.freeze #: Hash[Symbol, Integer]
        # The event that a scope fires when it starts, and the one that it
        # fires when it leaves (also when a raise unwinds it).
        # A `class << obj` body fires neither :class nor :end, as in ruby.
        OPENING = { def: :call, block: :b_call, class: :class, module: :class }.freeze #: Hash[Symbol, Symbol]
        CLOSING = { def: :return, block: :b_return, class: :end, module: :end }.freeze #: Hash[Symbol, Symbol]
        LAMBDA = 1 << 32

        private

        #: () -> bool
        def traced?
          @l.traced? && !@l.internal? && !@l.support?
        end

        # `Hir::Trace`: the `:line` event, on the line the statement starts.
        # The event of a silent ensure body fires only on its path
        # (`Hir::Trace#line_on`).
        #: (Hir::Trace node) -> String
        def trace_line(node)
          line = node.line_on(@ensure_path, @jump_line)
          return @qnil unless line

          line == node.line ? at_node(node) : at_line(line)
          fire(:line) if traced?
          @qnil
        end

        # `Hir::Cover`: counts one run of a branch that Coverage measures.
        # The kernel keeps the counters, so this is only a call.
        #: (Hir::Cover node) -> String
        def cover_branch(node)
          at_node(node)
          cover(node.id)
          @qnil
        end

        #: (Integer id) -> void
        def cover(id) = kernel("zr_coverage_branch", imm(id))

        # Counts one run of the method that this scope makes, as CRuby
        # counts on the :call event. The method entry of the call
        # identifies the coverage entry, so an alias and a method copied
        # by `define_method` both count for the original.
        #: () -> void
        def cover_method = kernel("zr_coverage_method", arg_entry)

        # The scope's opening event, once its parameters are bound. It fires
        # on the scope's own line, while the frame is on the line of the
        # body's first statement, as ruby's frame is when its hooks run (a
        # backtrace or a debugger reads that line).
        #: () -> void
        def trace_open
          event = OPENING[@kind]
          return unless event && traced?

          on = @f.label
          off = @f.label
          @f.brif(armed?(event), on, off)
          switch(on)
          checked(kernel("zr_trace_open", event_word(event), imm(entry_word)))
          @f.jump(off)
          switch(off)
        end

        # The frame's line word while the opening hooks run: the line of the
        # body's first statement, and for a def, block or lambda its node id
        # marked as its entry (Hir::Spots::ENTRY), whose range is that
        # statement. 0 keeps the frame's word.
        #: () -> Integer
        def entry_word
          first = Hir::Trace.first_line(@body)
          d = @def
          node_id = %i[def block].include?(@kind) && d ? @l.node_id(d) : 0
          return first || 0 if node_id.zero? || d.nil?

          ((first || d.line) & LINE_MASK) | ((node_id | Hir::Spots::ENTRY) << 32)
        end

        # The scope's closing event, with its return value. The line is
        # the line of its `return`, else its `end` line, or the line where
        # a raise unwinds it. Returns that value, or undef if a hook raised.
        #: (String value, bool unwinding, Integer? line) -> String
        def trace_close(value, unwinding, line)
          event = CLOSING[@kind]
          return value unless event && traced?

          line ||= @def&.end_line
          at_line(line) unless unwinding || line.nil?
          on = @f.label
          off = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(armed?(event), on, off)
          switch(on)
          @f.jump(merge, [kernel("zr_trace_fire", event_word(event), value)])
          switch(off)
          @f.jump(merge, [value])
          switch(merge)
          result
        end

        #: (Symbol event) -> void
        def fire(event)
          on = @f.label
          off = @f.label
          @f.brif(armed?(event), on, off)
          switch(on)
          checked(kernel("zr_trace_fire", event_word(event), @qnil))
          @f.jump(off)
          switch(off)
        end

        # The event's bit. A block's :b_call and :b_return also carry
        # whether the block is a lambda (the kernel's TRACE_LAMBDA).
        #: (Symbol event) -> String
        def event_word(event)
          bit = EVENTS.fetch(event)
          return imm(bit) unless @kind == :block && (event == :b_call || event == :b_return)

          @f.csel(lambda?, imm(bit | LAMBDA), imm(bit))
        end

        # Whether an enabled TracePoint listens for `event`.
        #: (Symbol event) -> String
        def armed?(event)
          mask = @f.fetch("i64", static("trace_events"), 0)
          @f.icmp("ne", @f.band(mask, imm(EVENTS.fetch(event))), imm(0))
        end
      end
    end
  end
end
