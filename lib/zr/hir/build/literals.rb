# frozen_string_literal: true

# `Hir::Build`'s literals: shareable constants, frozen strings and
# regexps.

module Zr
  module Hir
    class Build
      # `# shareable_constant_value:` on a constant write. A value that the
      # compiler knows is a literal is deep-frozen. Any other value must
      # already be shareable, as in ruby.
      def shareable_constant(node, line)
        write = expr(node.write)
        ractor = ConstRead.new(nil, :Ractor, line)
        write.value =
          if node.literal?
            literally_shareable(node.write.value, write.value, constant_written(node.write), line)
          elsif node.experimental_copy?
            Send.of(ractor, :make_shareable, [write.value], line, kwargs: HashLit.new([Literal.new(:copy, line), Literal.new(true, line)], line))
          else
            Send.new(ractor, :make_shareable, [write.value], line, false)
          end
        write
      end

      # `literal`'s value, as prism_compile.c's
      # pm_compile_shareable_constant_value builds it. An Array or Hash
      # literal builds each element the same way, then is made shareable
      # as a whole. A value of only literals is made shareable. Any other
      # value must already be shareable (an interpolated String after
      # deduplication). `top` is the constant's own value, not an element.
      def literally_shareable(node, value, name, line, top: true)
        node, value = unparenthesized(node, value)
        return frozen_literal(node, value, line) if shareable_literal?(node)

        ractor = ConstRead.new(nil, :Ractor, line)
        whole = ->(built) { top ? Send.new(ractor, :make_shareable, [built], line, false) : built }
        if node.is_a?(Prism::ArrayNode) && node.elements.none? { |e| e.is_a?(Prism::SplatNode) || e.is_a?(Prism::KeywordHashNode) }
          value.elements = node.elements.zip(value.elements).map { |e, v| literally_shareable(e, v, name, line, top: false) }
          whole.(value)
        elsif node.is_a?(Prism::HashNode) && node.elements.all?(Prism::AssocNode)
          value.pairs = value.pairs.each_slice(2).zip(node.elements).flat_map do |(key, v), e|
            [key, literally_shareable(e.value.is_a?(Prism::ImplicitNode) ? e.value.value : e.value, v, name, line, top: false)]
          end
          whole.(value)
        else
          value = Send.new(value, :-@, [], line, false) if node.is_a?(Prism::InterpolatedStringNode)
          Send.new(ractor, :ensure_shareable, [value, Literal.new(name, line)], line, false)
        end
      end

      # `(value)`: the one statement inside, and its built value, as
      # compile.c reads through the parentheses of `X = (1..2)`.
      def unparenthesized(node, value)
        while node.is_a?(Prism::ParenthesesNode) && node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1 &&
              value.is_a?(Seq) && value.stmts.size == 1
          node = node.body.body[0]
          value = value.stmts[0]
        end
        [node, value]
      end

      # Whether CRuby makes a new Range of two String literals at each run.
      # Its peephole optimizer folds the two strings and the newrange into
      # one static Range only if no label is before the first string. A
      # label starts a block's body, a loop's body, the else branch of an
      # `if`, the then branch of an `unless` (a `case` has none), and a
      # body that a rescue covers.
      def after_label?(node)
        @after_label ||= {}.compare_by_identity.tap { |found| labeled(@root, found) if @root }
        @after_label.key?(node)
      end

      def labeled(node, found)
        return if node.nil?

        start = case node
                when Prism::BlockNode, Prism::LambdaNode then node.body
                when Prism::WhileNode, Prism::UntilNode then node.statements
                when Prism::IfNode then node.subsequent
                when Prism::UnlessNode then node.statements
                when Prism::BeginNode then node.rescue_clause && node.statements
                end
        first = leading(start)
        found[first] = true if first
        node.compact_child_nodes.each { |child| labeled(child, found) }
      end

      # The Range whose code comes first in `node`'s code, if any: a
      # receiver comes before its call, a value before the variable that
      # it sets, a condition before its branches.
      def leading(node)
        case node
        when Prism::RangeNode then node
        when Prism::StatementsNode then leading(node.body.first)
        when Prism::ParenthesesNode then leading(node.body)
        when Prism::ElseNode then leading(node.statements)
        when Prism::BeginNode then node.rescue_clause ? nil : leading(node.statements)
        when Prism::IfNode, Prism::UnlessNode then leading(node.predicate)
        when Prism::CallNode then leading(node.receiver)
        when Prism::AndNode, Prism::OrNode then leading(node.left)
        when Prism::ArrayNode then leading(node.elements.first)
        when Prism::LocalVariableWriteNode, Prism::InstanceVariableWriteNode, Prism::GlobalVariableWriteNode,
             Prism::ClassVariableWriteNode then leading(node.value)
        end
      end

      # A value built only of literals (`shareable_literal?`), frozen when
      # it is built and with no send, as compile.c freezes the object that
      # it makes at compile time. An Array or Hash literal is marked frozen
      # and its elements are built the same way. A String is the shared
      # frozen String of its text. A Range's ends are frozen. All other
      # literals are always frozen.
      def frozen_literal(node, value, line)
        case node
        when Prism::ArrayNode
          value.elements = node.elements.zip(value.elements).map { |e, v| frozen_literal(e, v, line) }
          value.frozen = true
        when Prism::HashNode
          value.pairs = value.pairs.each_slice(2).zip(node.elements).flat_map do |(key, v), e|
            [frozen_literal(e.key, key, line), frozen_literal(e.value, v, line)]
          end
          value.frozen = true
        when Prism::RangeNode
          value.low = frozen_literal(node.left, value.low, line) if node.left
          value.high = frozen_literal(node.right, value.high, line) if node.right
        when Prism::StringNode, Prism::SourceFileNode
          text = value.value
          return FrozenString.new(text, line, text.encoding == ::Encoding::UTF_8)
        end
        value
      end

      # The constant name of a shareable constant write, for the error.
      def constant_written(write)
        write.respond_to?(:name) ? write.name.to_s : write.target.name.to_s
      end

      # Whether a value is built only of literals, so a freeze cannot
      # affect an object that the program still uses. A Range with literal
      # ends counts as the constant's own value, but not as an element:
      # compile.c's static_literal_node_p, which reads an Array's or a
      # Hash's elements, has no case for it, so `[(1..2)]` uses
      # make_shareable.
      def shareable_literal?(node, top: true)
        case node
        when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode,
             Prism::SymbolNode, Prism::StringNode, Prism::NilNode, Prism::TrueNode, Prism::FalseNode,
             Prism::RegularExpressionNode, Prism::SourceFileNode, Prism::SourceLineNode, Prism::SourceEncodingNode
          true
        when Prism::ArrayNode then node.elements.all? { |e| shareable_literal?(e, top: false) }
        when Prism::HashNode
          node.elements.all? { |e| e.is_a?(Prism::AssocNode) && shareable_literal?(e.key, top: false) && shareable_literal?(e.value, top: false) }
        when Prism::RangeNode
          top && (node.left.nil? || shareable_literal?(node.left, top: false)) && (node.right.nil? || shareable_literal?(node.right, top: false))
        else false
        end
      end

      # A regexp literal's option bits, as Regexp.new takes them.
      # `i`, `x` and `m`, then the two encoding bits: `n` declares the
      # pattern encoding-agnostic, and `e`, `s` and `u` pin it to one.
      def regexp_options(node)
        (node.ignore_case? ? 1 : 0) | (node.extended? ? 2 : 0) | (node.multi_line? ? 4 : 0) |
          (regexp_encoding(node) ? 16 : 0) | (node.ascii_8bit? ? 32 : 0)
      end

      # The encoding that a flag letter sets for the pattern, or nil.
      def regexp_encoding(node)
        if node.euc_jp? then ::Encoding::EUC_JP
        elsif node.windows_31j? then ::Encoding::Windows_31J
        elsif node.utf_8? then ::Encoding::UTF_8
        end
      end

      # Ruby checks the pattern. A pattern that ruby refuses is also a
      # syntax error here.
      def interpolated_regexp(node, line)
        pinned = regexp_encoding(node)
        # Each fragment is a separate String: ruby reads each one in its
        # own encoding before it joins them.
        fragments = ArrayLit.new(interpolation(node, line).parts.map { |part| Interp.new([part], line) }, line)
        args = [fragments, Literal.new(regexp_options(node), line), Literal.new(pinned && ::Encoding.list.index(pinned), line)]
        made = Send.new(ConstRead.new(nil, :Regexp, line), :interpolated, args, line, false)
        node.once? ? RegexpOnce.new(made, line) : made
      end

      # Used in place of $stderr while a check compiles a pattern. It keeps
      # what the engine writes.
      class Written < String
        def write(*parts) = parts.sum { |part| concat(part.to_s) && part.to_s.bytesize }
      end

      # Whether this build keeps the engine's warnings, and does not let
      # the engine print them.
      def keeps_warnings? = !@loader&.eval?

      # What the engine wrote to $stderr while it read `held`. The read is
      # also the check: an invalid pattern raises.
      #
      # The only way to keep those warnings is to replace $stderr and
      # $VERBOSE. A build can do this, because it forks and nothing else
      # in that process writes. An eval compile runs inside the program,
      # where all threads share the two, and where ruby lets the engine
      # warn on the program's stderr (as `eval("/(?:a?)*b/")` does). So
      # there, the pattern is read with no redirection.
      def read_pattern(held, options)
        unless keeps_warnings?
          Regexp.new(held, options)
          return ""
        end

        written = Written.new
        begin
          stderr, $stderr = $stderr, written
          verbose, $VERBOSE = $VERBOSE, false
          Regexp.new(held, options)
          written
        ensure
          $stderr = stderr
          $VERBOSE = verbose
        end
      end

      # The branch that a literal condition always selects, or nil if the
      # program decides. Ruby's compiler writes no code for the other
      # branch and does not read it: `if false then /[q-a]/ end` runs, and
      # `if 1 == 2 then /[q-a]/ end` does not.
      def chooses?(node)
        case node
        when Prism::TrueNode then true
        when Prism::FalseNode, Prism::NilNode then false
        end
      end

      def regexp_literal(node, line, taken = true)
        # This literal's value is not used, so ruby never reads the
        # pattern, and zr does not either. An invalid one here is a
        # program that runs. An interpolated regexp is a Send, not this,
        # and it still runs its parts.
        return Seq.new([], line) unless taken

        pinned = regexp_encoding(node)
        # `n` reads the pattern as bytes, so a non-ASCII escape is valid
        # only there. The check must read it the same way.
        held = node.unescaped.dup.force_encoding(node.ascii_8bit? ? ::Encoding::BINARY : (pinned || node.unescaped.encoding))
        written = read_pattern(held, regexp_options(node) & 7)
        written.scan(/warning: (.*)$/) { |(message)| @warnings << "#{Paths.shown(@file)}:#{line}: warning: #{message}" }
        RegexpLit.new(node.unescaped, regexp_options(node), pinned, line)
      rescue RegexpError => e
        invalid(node, "#{e.message.sub(/: \/.*\z/m, "")}: /#{node.unescaped}/")
      end

      # The parts of an interpolated string, each a String or the value
      # of an embedded expression.
      def interpolation(node, line)
        parts = node.parts.map do |part|
          case part
          when Prism::StringNode then Literal.new(unescaped(part), part.location.start_line)
          when Prism::EmbeddedStatementsNode then part.statements ? seq(part.statements) : Literal.new(nil, line)
          when Prism::EmbeddedVariableNode then expr(part.variable)
          when Prism::InterpolatedStringNode then interpolation(part, line)
          else unsupported(part, "#{Refused.form_of(part)} in a string")
          end
        end
        # A single embedded part is joined to an empty literal, which gives
        # the result's start encoding, as ruby's compiler does.
        parts.unshift(Literal.new(+"", line)) if node.parts.size == 1 && !node.parts[0].is_a?(Prism::StringNode)
        # If refinements are active, each part gets `to_s` at its own site,
        # which does the lookup with them. Ruby folds a String or Symbol
        # part into the text first.
        parts = parts.map { |part| folded?(part) ? part : Send.new(part, :to_s, [], line, false) } if @using
        Interp.new(parts, line)
      end

      def folded?(part)
        part = part.stmts.first if part.is_a?(Seq) && part.stmts.size == 1
        part.is_a?(Interp) || (part.is_a?(Literal) && [String, Symbol, NilClass].include?(part.value.class))
      end
    end
  end
end
