# frozen_string_literal: true

# `Hir::Build`'s line events and coverage counters.

module Zr
  module Hir
    class Build
      # The `:line` event that ruby's compiler puts before a statement that
      # starts a line of its scope, or nil. This is pm_compile_node's rule,
      # which reads prism's newline flag. A `begin` with no statements
      # before its rescue is on the rescue's line.
      def line_event(node)
        return nil unless @loader&.tracing? && node.newline? && !Build.runtime_file?(@file)
        # A `begin` or parentheses start with the statement inside. Ruby
        # merges their event into that statement's event.
        return nil if node.is_a?(Prism::BeginNode) && node.statements
        return nil if node.is_a?(Prism::ParenthesesNode) && node.body

        line = node.location.start_line
        line = node.rescue_clause.location.start_line if node.is_a?(Prism::BeginNode) && node.statements.nil? && node.rescue_clause
        return nil if @last_lines.last == line

        @last_lines[-1] = line
        @loader.line_event!(@file, line)
        Trace.new(:line, line)
      end

      # The id of the def-site entry that a `def` or a block uses when it
      # makes a method, or nil if coverage is not measured.
      def method_cover(node)
        return nil unless @loader&.covers? && !Build.runtime_file?(@file)

        @loader.def_site!(@file, method_span(node))
      end

      # The location that ruby gives a method made from this scope. A
      # lambda's span starts after its `->`, where CRuby's iseq for it
      # starts: `define_method(:a, ->(x) { x })` is located at `(x) { x }`.
      # All other scopes use their own location.
      def method_span(node)
        return span(node.location) unless node.is_a?(Prism::LambdaNode)

        [node.operator_loc.end_line, node.operator_loc.end_column, node.location.end_line, node.location.end_column]
      end

      # A `Cover` for each branch of a construct that Coverage measures, or
      # nils if it measures nothing. `sides` are `[kind, span]` in ruby's
      # order, which is the source order, except that an `unless` puts its
      # else first. The root gets its number before its branches, as in
      # CRuby.
      def branch_covers(kind, span, sides)
        return [nil] * sides.size unless @loader&.covers? && !Build.runtime_file?(@file)

        _, root = @loader.branch!(@file, kind, span)
        sides.map do |side, where|
          id, = @loader.branch!(@file, side, where, under: root)
          Cover.new(id, where[0])
        end
      end

      # The four numbers that Coverage uses for a branch: its start and
      # end, with 0-based columns as in ruby.
      def span(location) = [location.start_line, location.start_column, location.end_line, location.end_column]

      # The branches of an `if`, a ternary or an `elsif`. A then with no
      # statements is at the empty width after the predicate. A missing
      # else covers the whole `if`. CRuby records the same.
      def if_sides(node)
        [[:then, node.statements ? span(node.statements.location) : after(node.predicate.location)],
         [:else, node.subsequent ? span(else_location(node.subsequent)) : span(node.location)]]
      end

      # An `unless` has its then first in the source, but ruby numbers its
      # else first, so the two are in reverse order.
      def unless_sides(node)
        [[:else, node.else_clause ? span(else_location(node.else_clause)) : span(node.location)],
         [:then, node.statements ? span(node.statements.location) : after(node.predicate.location)]]
      end

      # Each `when` or `in` clause, then the else. A `case` always has an
      # else: if the source has none, it covers the whole `case`, so a
      # subject that matched nothing is also counted.
      def case_sides(node, kind)
        sides = node.conditions.map { |c| [kind, span(c.statements&.location || c.location)] }
        sides << [:else, span(node.else_clause ? else_location(node.else_clause) : node.location)]
      end

      # A loop has one branch: its body, or the whole loop if it has no
      # body.
      def loop_sides(node) = [[:body, span(node.statements&.location || node.location)]]

      # An `else` has the location of its statements, or of the whole
      # clause if it has none. An `elsif` is its own branch, with its own
      # location.
      def else_location(node)
        return node.location unless node.is_a?(Prism::ElseNode)

        node.statements&.location || node.location
      end

      # The empty width just past `location`.
      def after(location) = [location.end_line, location.end_column, location.end_line, location.end_column]

      # `body` with its branch counted first, or only `body`. A nil body
      # counts and returns nil, as an empty branch does in ruby.
      def covered(cover, body, line)
        return body if cover.nil?

        Seq.new([cover, body || Literal.new(nil, line)], line)
      end
    end
  end
end
