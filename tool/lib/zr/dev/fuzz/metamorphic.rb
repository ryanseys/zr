# frozen_string_literal: true

require "prism"

module Zr
  module Dev
    module Fuzz
      # Rewrites of a program that keep what it prints, but change the
      # code that the compiler sees (metamorphic testing, and EMI's dead
      # code). Ruby runs the rewritten program too, so a rewrite that
      # changes the output by accident costs nothing: the oracle still
      # compares ruby with zr. What a rewrite buys is code that a person
      # does not write and the compiler must still get right:
      #
      #   opaque  a literal becomes `__opaque(lit)`, a value that the compiler
      #           cannot fold or know the type of
      #   dead    `if __opaque(false) ... end` with new code in it (EMI)
      #   wrap    a statement goes into `begin`, a block, a lambda, a method
      #           that is called at once, a Fiber, a thread, or an eval
      module Metamorphic
        KINDS = %i[opaque opaque dead wrap wrap].freeze

        OPAQUE = "def __opaque(x) = x\n"

        module_function

        # `source` after one to three rewrites, and their names; nil when
        # none worked.
        def transform(source, rng, generator: nil)
          done = []
          6.times do
            break if done.size >= rng.rand(1..3)

            kind = KINDS.sample(random: rng)
            changed = rewrite(kind, source, rng, generator)
            next unless changed && changed != source && Prism.parse(changed).errors.empty?

            source = changed
            done << kind
          end
          return nil if done.empty?

          source = OPAQUE + source unless source.include?("def __opaque")
          [source, done]
        end

        def rewrite(kind, source, rng, generator)
          tree = Prism.parse(source)
          return nil unless tree.errors.empty?

          case kind
          when :opaque then opaque(source, tree.value, rng)
          when :dead then dead(source, tree.value, rng, generator)
          when :wrap then wrap(source, tree.value, rng)
          end
        end

        # Each literal outside a pattern, a `defined?`, and a string's parts
        # becomes `__opaque(lit)` with a chance of a third.
        def opaque(source, tree, rng)
          skip = []
          literals = []
          Reducer.walk(tree) do |node|
            case node
            when Prism::InNode, Prism::MatchPredicateNode, Prism::MatchRequiredNode
              skip << range(node.pattern)
            when Prism::DefinedNode, Prism::InterpolatedStringNode, Prism::InterpolatedSymbolNode, Prism::XStringNode,
                 Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode, Prism::ArrayNode
              skip << range(node) if !node.is_a?(Prism::ArrayNode) || node.opening&.start_with?("%")
            when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode, Prism::ImaginaryNode, Prism::NilNode,
                 Prism::TrueNode, Prism::FalseNode
              literals << node
            when Prism::StringNode
              literals << node if node.opening == '"' || node.opening == "'"
            end
          end
          chosen = literals.reject { |n| skip.any? { |r| r.cover?(n.location.start_offset) } }.select { rng.rand < 0.33 }
          return nil if chosen.empty?

          splice(source, chosen.map { |n| [range(n), "__opaque(#{n.slice})"] })
        end

        # Inserts code that never runs after a statement.
        def dead(source, tree, rng, generator)
          at = statements(tree).sample(random: rng) or return nil
          code = generator ? generator.call(rng) : "p :never"
          insert_after(source, at, "if __opaque(false)\n#{code.gsub(/^/, "  ")}\nend")
        end

        # Each wrap takes the code and a number for a name of its own.
        WRAPS = [
          ->(code, _) { "begin\n#{code}\nend" },
          ->(code, _) { "1.times do\n#{code}\nend" },
          ->(code, _) { "-> do\n#{code}\nend.call" },
          ->(code, n) { "def __moved_#{n}\n#{code}\nend\n__moved_#{n}" },
          ->(code, _) { "Fiber.new do\n#{code}\nend.resume" },
          ->(code, _) { "Thread.new do\n#{code}\nend.join" },
          ->(code, _) { "[0].each do |_|\n#{code}\nend" },
          ->(code, _) { "proc do\n#{code}\nend.call" },
          ->(code, _) { "eval(#{code.dump})" }
        ].freeze

        # Moves one statement that prints into another place. The statement
        # must not end a method or a block (`return`, `break`, `next`,
        # `redo`, `retry`, `yield`) and must not define a local that a
        # later statement reads.
        def wrap(source, tree, rng)
          movable = statements(tree).select { |node| movable?(node) }
          node = movable.sample(random: rng) or return nil
          code = node.slice.gsub(/^/, "  ")
          splice(source, [[range(node), WRAPS.sample(random: rng).call(code, rng.rand(10**6))]])
        end

        STOPPERS = [Prism::ReturnNode, Prism::BreakNode, Prism::NextNode, Prism::RedoNode, Prism::RetryNode, Prism::YieldNode,
                    Prism::LocalVariableWriteNode, Prism::LocalVariableOperatorWriteNode, Prism::LocalVariableOrWriteNode,
                    Prism::LocalVariableAndWriteNode, Prism::MultiWriteNode, Prism::DefNode, Prism::ClassNode,
                    Prism::ModuleNode, Prism::ConstantWriteNode, Prism::ConstantPathWriteNode, Prism::AliasMethodNode,
                    Prism::ForNode, Prism::SingletonClassNode, Prism::MatchWriteNode, Prism::MatchRequiredNode,
                    Prism::MatchPredicateNode, Prism::CaseMatchNode, Prism::SourceLineNode, Prism::SourceFileNode,
                    Prism::BackReferenceReadNode, Prism::NumberedReferenceReadNode, Prism::ForwardingSuperNode,
                    Prism::SuperNode].freeze

        def movable?(node)
          return false unless node.is_a?(Prism::CallNode) && node.location.length < 2000

          Reducer.walk(node) { |n| return false if STOPPERS.any? { |k| n.is_a?(k) } }
          Reducer.walk(node) { |n| return false if n.is_a?(Prism::CallNode) && %i[binding block_given? __method__ local_variables using].include?(n.name) }
          true
        end

        def statements(tree)
          out = []
          Reducer.walk(tree) { |n| out.concat(n.body) if n.is_a?(Prism::StatementsNode) }
          out
        end

        def range(node) = node.location.start_offset...node.location.end_offset

        # `source` with each byte range replaced, last first.
        def splice(source, edits)
          bytes = source.b.dup
          edits.sort_by { |r, _| -r.begin }.each { |r, text| bytes[r] = text.b }
          bytes.force_encoding(source.encoding)
        end

        def insert_after(source, node, text)
          indent = source.b[0...node.location.start_offset][/[ \t]*\z/]
          bytes = source.b.dup
          bytes.insert(node.location.end_offset, "\n#{text.b.gsub("\n", "\n#{indent}")}".b)
          bytes.force_encoding(source.encoding)
        end
      end

      # Programs from rewrites of other programs: of generated ones, and of
      # seeds.
      class MetaSource
        def initialize(base:, generator: nil)
          @base = base
          @generator = generator
        end

        def next_candidate(rng)
          10.times do
            parent = @base.next_candidate(rng) or return nil
            changed, kinds = Metamorphic.transform(parent.source, rng, generator: @generator)
            next unless changed

            return Candidate.new(source: changed, origin: "meta", meta: parent.meta.merge(parent: parent.origin, rewrites: kinds))
          end
          nil
        end
      end
    end
  end
end
