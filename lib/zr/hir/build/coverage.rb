# frozen_string_literal: true

# `Hir::Build`'s line events and coverage counters.

module Zr
  module Hir
    class Build
      # The `:line` event that ruby's compiler puts before a statement that
      # starts a line of its scope, or nil. This is pm_compile_node's rule,
      # which reads prism's newline flag and skips a statement that starts
      # on the line of the last one (`last_line`). The event goes to the
      # next instruction and reports its line (`first_line`). A statement
      # that compiles to nothing leaves its event to the next one that
      # compiles something, even on the same line (`@pending_events`). A
      # `begin` with no statements before its rescue is on the rescue's
      # line. A statement whose first instruction is the one that the
      # event of its enclosing statement waits for shares that event
      # (`@traced_lines`), as CRuby gives one instruction one event: `x =
      # if true` with its branch's first statement, or an `if` that starts
      # a line inside an expression. `taken` says whether something uses
      # the statement's value.
      #: (Prism::node node, ?taken: bool) -> Trace?
      def line_event(node, taken: true)
        return nil unless traces_here?
        # CRuby compiles no branch that a literal condition never takes.
        return nil if @dead.positive?

        if node.newline?
          # A `begin` or parentheses start with the statement inside. Ruby
          # merges their event into that statement's event.
          return nil if node.is_a?(Prism::BeginNode) && node.statements
          return nil if node.is_a?(Prism::ParenthesesNode) && node.body
          # A `BEGIN` block runs before the program, from its own code. Its
          # line is the last, so a statement on it fires no event.
          if node.is_a?(Prism::PreExecutionNode)
            @last_lines[-1] = node.location.start_line
            return nil
          end

          rescued = node.rescue_clause.location.start_line if node.is_a?(Prism::BeginNode) && node.statements.nil? && node.rescue_clause
          start = rescued || node.location.start_line
          fresh = @last_lines.last != start
          @last_lines[-1] = start
          @pending_events[-1] ||= fresh
        end
        return nil unless @pending_events.last

        line = rescued || first_line(node, taken: taken)
        return nil if line.nil?

        if line == @traced_lines.last
          @pending_events[-1] = false
          return nil
        end
        traced(line)
      end

      # Whether this file's code fires :line events: the program traces,
      # and the file is the program's, not the core library's.
      #: () -> bool
      def traces_here? = (@loader&.tracing? || false) && !Library::Roots.runtime_file?(@file)

      # The event that waits for the next instruction, on `line`.
      #: (Integer line) -> Trace
      def traced(line)
        @pending_events[-1] = false
        @traced_lines[-1] = line
        @loader.line_event!(@file, line)
        Trace.new(:line, line)
      end

      # A statement whose value nothing uses and that compiles to nothing
      # (`silent?`) starts its line, and its event waits for the next
      # instruction (`line_event`, `jump_event`).
      #: (Prism::node node) -> nil
      def silent_line(node)
        return nil unless traces_here? && node.newline? && @dead.zero?

        start = node.location.start_line
        @pending_events[-1] ||= @last_lines.last != start
        @last_lines[-1] = start
        nil
      end

      # Plain values that CRuby's compiler drops when nothing uses them.
      SILENT = [
        Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode, Prism::StringNode, Prism::SymbolNode,
        Prism::RegularExpressionNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::SelfNode, Prism::SourceFileNode,
        Prism::SourceLineNode, Prism::SourceEncodingNode, Prism::LocalVariableReadNode, Prism::InstanceVariableReadNode,
        Prism::ClassVariableReadNode, Prism::DefinedNode
      ].freeze

      # The line of the first instruction that CRuby compiles for `node`,
      # where it puts the node's :line event: a write's value comes before
      # the write, a receiver before its call, an operand before its
      # operator, and a first element before its Array or Hash, unless the
      # whole literal is one static value. A `case` with no subject is a
      # chain of tests, the first `when`'s first. An `if` with a literal
      # condition compiles to its chosen branch alone. `taken` says whether
      # something uses the value; when nothing does and nothing compiles,
      # the line is nil.
      #: (Prism::node? node, ?taken: bool) -> Integer?
      def first_line(node, taken: true)
        case node
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::GlobalVariableWriteNode,
             Prism::ClassVariableWriteNode, Prism::ConstantWriteNode, Prism::MultiWriteNode
          first_line(node.value)
        when Prism::CallNode
          # `[...].include?(x)` on one static Array runs `x` first
          # (opt_duparray_send).
          args = node.arguments&.arguments
          if node.name == :include? && node.receiver.is_a?(Prism::ArrayNode) && node.receiver.static_literal? &&
             args&.size == 1 && node.block.nil? && !args.first.is_a?(Prism::SplatNode)
            return first_line(args.first)
          end

          node.receiver ? first_line(node.receiver) : node.location.start_line
        when Prism::ArrayNode
          first = node.elements.first
          first = first.expression if first.is_a?(Prism::SplatNode)
          first.nil? || node.static_literal? ? node.location.start_line : first_line(first)
        when Prism::HashNode
          # A run of static pairs at the start is one hidden Hash that the
          # Hash's own instruction copies (pm_compile_hash_elements).
          first = node.elements.first
          first.is_a?(Prism::AssocNode) && !first.static_literal? ? first_line(first.key) : node.location.start_line
        when Prism::InterpolatedStringNode, Prism::InterpolatedXStringNode, Prism::InterpolatedSymbolNode
          # A literal part is on the string's own line; code runs on its own.
          case (part = node.parts.first)
          when Prism::EmbeddedStatementsNode then part.statements ? first_line(part.statements.body.first) : part.location.start_line
          when Prism::EmbeddedVariableNode then part.location.start_line
          else node.location.start_line
          end
        when Prism::ParenthesesNode
          body = node.body
          body.is_a?(Prism::StatementsNode) ? statements_line(body, taken) : node.location.start_line
        when Prism::BeginNode then node.statements ? statements_line(node.statements, taken) : node.location.start_line
        when Prism::IfNode, Prism::UnlessNode
          tested = condition_line(node.predicate)
          return tested if tested

          can_be_true, = reaches(node.predicate)
          taken_branch, other = node.is_a?(Prism::IfNode) ? [node.statements, node.subsequent] : [node.else_clause, node.statements]
          branch_line(can_be_true ? taken_branch : other, node, taken)
        when Prism::CaseNode then node.predicate ? first_line(node.predicate) : tests_line(node, taken)
        when Prism::CaseMatchNode then first_line(node.predicate)
        when Prism::AndNode, Prism::OrNode then first_line(node.left)
        when Prism::RescueModifierNode then first_line(node.expression)
        when Prism::ReturnNode
          first = node.arguments&.arguments&.first
          first ? first_line(first) : node.location.start_line
        when nil then nil
        else node.location.start_line
        end
      end

      # The line of the first instruction of a condition, or nil when its
      # literals decide it and it compiles to no test
      # (compile_branch_condition): `false && x` jumps at once, and `true
      # && x` tests `x` alone.
      #: (Prism::node node) -> Integer?
      def condition_line(node)
        case node
        when Prism::AndNode, Prism::OrNode
          left = chooses?(node.left)
          return first_line(node.left) if left.nil?

          # The right side runs only where the left one decides nothing.
          condition_line(node.right) if left == node.is_a?(Prism::AndNode)
        else first_line(node) if chooses?(node).nil?
        end
      end

      # The first line of the branch of `node` that a literal condition
      # chooses. With no branch, the `if` is nil, which CRuby puts on the
      # `if`'s line when something uses it.
      #: (Prism::node? branch, Prism::node node, bool taken) -> Integer?
      def branch_line(branch, node, taken)
        case branch
        when Prism::StatementsNode then statements_line(branch, taken)
        when Prism::ElseNode then branch.statements ? statements_line(branch.statements, taken) : (node.location.start_line if taken)
        when Prism::IfNode then first_line(branch, taken: taken)
        else node.location.start_line if taken
        end
      end

      # The first line of a `case` with no subject, a chain of tests: a
      # literal test that never passes compiles to nothing, and one that
      # always does to its body.
      #: (Prism::CaseNode node, bool taken) -> Integer?
      def tests_line(node, taken)
        node.conditions.each do |clause|
          clause.conditions.each do |test|
            chosen = chooses?(test)
            next if chosen == false
            return first_line(test) if chosen.nil?

            return clause.statements ? statements_line(clause.statements, taken) : (node.location.start_line if taken)
          end
        end
        branch_line(node.else_clause, node, taken)
      end

      # The first line that `statements` compile to: a silent statement
      # whose value nothing uses compiles to nothing (`silent?`).
      #: (Prism::StatementsNode statements, bool taken) -> Integer?
      def statements_line(statements, taken)
        last = statements.body.size - 1
        statements.body.each_with_index do |statement, i|
          used = taken && i == last
          next if !used && silent?(statement)

          line = first_line(statement, taken: used)
          return line if line
        end
        nil
      end

      # The :line event of a branch's jump to the end of its construct.
      # When nothing uses the branch's value and its last statements
      # compile to nothing, their event waits (`line_event`), and CRuby
      # gives it to the next instruction: the jump, whose line is `line`
      # (the `if`, `elsif`, `when` or `in`, or the `case`). The caller asks
      # only for a branch that a jump ends, one that another branch's code
      # follows.
      #: (Prism::StatementsNode? statements, Integer line, taken: bool) -> Trace?
      def jump_event(statements, line, taken:)
        return nil if taken || statements.nil? || !traces_here? || !@pending_events.last || @dead.positive?

        traced(line)
      end

      # The branch `body` with the event of the jump that ends it.
      #: (node body, Prism::StatementsNode? statements, Integer line, taken: bool) -> node
      def jumping(body, statements, line, taken:)
        jump = jump_event(statements, line, taken: taken)
        jump ? Seq.new([body, jump], line) : body
      end

      # Whether a statement whose value nothing uses compiles to no
      # instruction, so it fires no :line event: a plain value, a static
      # Array, or a Hash, Range or parentheses of such values.
      #: (Prism::node? node) -> bool
      def silent?(node)
        case node
        when nil then true
        # `x = x` of a local is nothing to do.
        when Prism::LocalVariableWriteNode
          value = node.value
          value.is_a?(Prism::LocalVariableReadNode) && value.name == node.name && value.depth == node.depth
        when *SILENT then true
        when Prism::ArrayNode then node.static_literal?
        when Prism::HashNode then node.elements.all? { |e| e.is_a?(Prism::AssocNode) && silent?(e.key) && silent?(e.value) }
        when Prism::RangeNode then silent?(node.left) && silent?(node.right)
        when Prism::ParenthesesNode
          body = node.body
          body.is_a?(Prism::StatementsNode) ? body.body.all? { |s| silent?(s) } : silent?(body)
        else false
        end
      end

      # The id of the def-site entry that a `def` or a block uses when it
      # makes a method, or nil if coverage is not measured.
      #: (Prism::node node) -> Integer?
      def method_cover(node)
        return nil unless @loader&.covers? && !Library::Roots.runtime_file?(@file)

        @loader.def_site!(@file, method_span(node))
      end

      # The location that ruby gives a method made from this scope. A
      # lambda's span starts after its `->`, where CRuby's iseq for it
      # starts: `define_method(:a, ->(x) { x })` is located at `(x) { x }`.
      # All other scopes use their own location.
      #: (Prism::node node) -> Array[Integer]
      def method_span(node)
        return span(node.location) unless node.is_a?(Prism::LambdaNode)

        [node.operator_loc.end_line, node.operator_loc.end_column, node.location.end_line, node.location.end_column]
      end

      # A `Cover` for each branch of a construct that Coverage measures, or
      # nils if it measures nothing. `sides` are `[kind, span]` in ruby's
      # order, which is the source order, except that an `unless` puts its
      # else first. The root gets its number before its branches, as in
      # CRuby.
      #: (Symbol kind, Array[Integer] span, Array[[Symbol, Array[Integer]]] sides) -> Array[Cover?]
      def branch_covers(kind, span, sides)
        return [nil] * sides.size unless @loader&.covers? && !Library::Roots.runtime_file?(@file)

        _, root = @loader.branch!(@file, kind, span)
        sides.map do |side, where|
          id, = @loader.branch!(@file, side, where, under: root)
          Cover.new(id, where[0])
        end
      end

      # The four numbers that Coverage uses for a branch: its start and
      # end, with 0-based columns as in ruby.
      #: (Prism::Location location) -> Array[Integer]
      def span(location) = [location.start_line, location.start_column, location.end_line, location.end_column]

      # The branches of an `if`, a ternary or an `elsif`. A then with no
      # statements is at the empty width after the predicate. A missing
      # else covers the whole `if`. CRuby records the same.
      #: (Prism::IfNode node) -> Array[[Symbol, Array[Integer]]]
      def if_sides(node)
        [[:then, node.statements ? span(node.statements.location) : after(node.predicate.location)],
         [:else, node.subsequent ? span(else_location(node.subsequent)) : span(node.location)]]
      end

      # An `unless` has its then first in the source, but ruby numbers its
      # else first, so the two are in reverse order.
      #: (Prism::UnlessNode node) -> Array[[Symbol, Array[Integer]]]
      def unless_sides(node)
        [[:else, node.else_clause ? span(else_location(node.else_clause)) : span(node.location)],
         [:then, node.statements ? span(node.statements.location) : after(node.predicate.location)]]
      end

      # Each `when` or `in` clause, then the else. A `case` always has an
      # else: if the source has none, it covers the whole `case`, so a
      # subject that matched nothing is also counted.
      #: (Prism::CaseNode | Prism::CaseMatchNode node, Symbol kind) -> Array[[Symbol, Array[Integer]]]
      def case_sides(node, kind)
        sides = node.conditions.map { |c| [kind, span(c.statements&.location || c.location)] } #: Array[[Symbol, Array[Integer]]]
        sides << [:else, span(node.else_clause ? else_location(node.else_clause) : node.location)]
      end

      # A loop has one branch: its body, or the whole loop if it has no
      # body.
      #: (Prism::WhileNode | Prism::UntilNode node) -> Array[[Symbol, Array[Integer]]]
      def loop_sides(node) = [[:body, span(node.statements&.location || node.location)]]

      # An `else` has the location of its statements, or of the whole
      # clause if it has none. An `elsif` is its own branch, with its own
      # location.
      #: (Prism::node node) -> Prism::Location
      def else_location(node)
        return node.location unless node.is_a?(Prism::ElseNode)

        node.statements&.location || node.location
      end

      # The empty width just past `location`.
      #: (Prism::Location location) -> Array[Integer]
      def after(location) = [location.end_line, location.end_column, location.end_line, location.end_column]

      # `body` with its branch counted first, or only `body`. A nil body
      # counts and returns nil, as an empty branch does in ruby.
      #: (Cover? cover, node? body, Integer line) -> node?
      def covered(cover, body, line)
        return body if cover.nil?

        Seq.new([cover, body || Literal.new(nil, line)], line)
      end
    end
  end
end
