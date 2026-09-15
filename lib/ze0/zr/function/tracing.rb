# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # The points a traced program fires TracePoint events from: a
      # statement's `:line`, a scope's opening and closing events, each a
      # test of the kernel's event mask, so a program whose TracePoints are
      # all disabled pays one load and one branch at each.
      module Tracing
        # ruby's RUBY_EVENT_* bits.
        EVENTS = { line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, b_call: 0x100, b_return: 0x200 }.freeze
        # The event a scope fires as it starts, and the one it fires as it
        # leaves, a raise unwinding it included.
        OPENING = { def: :call, block: :b_call, class: :class, module: :class, sclass: :class }.freeze
        CLOSING = { def: :return, block: :b_return, class: :end, module: :end, sclass: :end }.freeze

        private

        def traced?
          @l.traced? && !@l.internal?
        end

        # `Hir::Trace`: the `:line` event, on the line the statement starts.
        def trace_line(node)
          at_node(node)
          fire(:line) if traced?
          @qnil
        end

        # The scope's opening event, once its parameters are bound.
        def trace_open
          event = OPENING[@kind]
          fire(event) if event && traced?
        end

        # The scope's closing event, with the value it leaves with: on the
        # line of its `return`, else its `end` line, or on the line a raise
        # unwinds it from. Answers that value, or undef when a hook raised.
        def trace_close(value, unwinding, line)
          event = CLOSING[@kind]
          return value unless event && traced?

          line ||= @def.end_line
          at_line(line) unless unwinding || line.nil?
          on = @f.label
          off = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(armed?(event), on, off)
          switch(on)
          @f.jump(merge, [kernel("zr_trace_fire", imm(EVENTS.fetch(event)), value)])
          switch(off)
          @f.jump(merge, [value])
          switch(merge)
          result
        end

        def fire(event)
          on = @f.label
          off = @f.label
          @f.brif(armed?(event), on, off)
          switch(on)
          checked(kernel("zr_trace_fire", imm(EVENTS.fetch(event)), @qnil))
          @f.jump(off)
          switch(off)
        end

        # Whether some enabled TracePoint asks for `event`.
        def armed?(event)
          mask = @f.fetch("i64", static("trace_events"), 0)
          @f.icmp("ne", @f.band(mask, imm(EVENTS.fetch(event))), imm(0))
        end
      end
    end
  end
end
