# frozen_string_literal: true

require "prism"

module Zr
  module Dev
    module Fuzz
      # Changes a program that runs (a seed) into a new one, a few edits
      # at a time, as Fuzzilli's mutators do, on the tree that prism
      # parses. Each edit replaces the bytes of one node, so the rest of
      # the seed keeps its form. A result that does not parse is thrown
      # away.
      #
      #   literal    a number, a string or a symbol becomes an edge value
      #   operator   a binary operator becomes another of its group
      #   input      a read of a local becomes a read of another local
      #   splice     a statement of another seed goes in after a statement
      #   duplicate  a statement runs twice
      #   delete     a statement goes away
      #   insert     a unit that the generator writes goes in (when given)
      class Mutator
        # Values at the edges of what each kind of literal can hold. Each one
        # is parenthesized where an operator could bind to it.
        INTEGERS = %w[0 1 (-1) 2 7 255 256 (2**31-1) (2**31) (2**62-1) (2**62) (2**63) (2**64) (2**64+1) (-(2**63)) (-(2**64))
                      (10**20) 0x7f 0b1010 0o17 1_000_000].freeze
        FLOATS = %w[0.0 (-0.0) 0.1 0.5 1.5 2.5 (-2.5) 1e-10 1e308 (1.0/3) Float::NAN Float::INFINITY (-Float::INFINITY)
                    Float::EPSILON Float::MAX Float::MIN 100.0 1.0e15 1.0e16].freeze
        STRINGS = ['""', '"a"', '" "', '"é"', '"日本語"', '"\\x00"', '"a\\nb"', '"\\xff".b', '"%s %d"', '"abc" * 3',
                   '"Ab_c-D"', '"\\u{1F600}"', '"0x1f"', '"12abc"', '"  pad  "', "'\#{x}'",'"é".encode("UTF-16LE")',
                   '"\\xff"', '"z" * 40'].freeze
        SYMBOLS = %w[:a :+ :[] :"" :"with\ space" :_x :A :== :<=> :foo?].freeze

        OPERATORS = [%i[+ - * / %], %i[< <= > >= == != <=>], %i[& | ^ << >>], %i[=== =~ eql? equal?]].freeze
        GROUP = OPERATORS.flat_map { |group| group.map { |op| [op, group] } }.to_h.freeze

        KINDS = %i[literal literal operator input splice duplicate delete insert].freeze

        # `seeds` gives the source of another seed for a splice:
        # `seeds.call(rng)`. `generator` writes one unit for an insert:
        # `generator.call(rng)`, or nil.
        def initialize(seeds: nil, generator: nil)
          @seeds = seeds
          @generator = generator
        end

        # `source` after `count` edits, and the names of the edits; nil when
        # no edit worked.
        def mutate(source, rng, count: rng.rand(1..4))
          done = []
          (count * 4).times do
            break if done.size >= count

            kind = KINDS.sample(random: rng)
            changed = edit(kind, source, rng)
            next unless changed && changed != source && Prism.parse(changed).errors.empty?

            source = changed
            done << kind
          end
          done.empty? ? nil : [source, done]
        end

        private

        def edit(kind, source, rng)
          tree = Prism.parse(source)
          return nil unless tree.errors.empty?

          send(kind, source, tree.value, rng)
        end

        def nodes(tree, &)
          out = []
          Reducer.walk(tree) { |node| out << node if yield(node) }
          out
        end

        def replace(source, node, text)
          bytes = source.b.dup
          bytes[node.location.start_offset...node.location.end_offset] = text.b
          bytes.force_encoding(source.encoding)
        end

        def insert_after(source, node, text)
          bytes = source.b.dup
          indent = source.b[0...node.location.start_offset][/[ \t]*\z/]
          bytes.insert(node.location.end_offset, "\n#{text.b.gsub("\n", "\n#{indent}")}".b)
          bytes.force_encoding(source.encoding)
        end

        def literal(source, tree, rng)
          node = nodes(tree) { |n| literal?(n) }.sample(random: rng) or return nil
          text = case node
                 when Prism::IntegerNode then INTEGERS.sample(random: rng)
                 when Prism::FloatNode then FLOATS.sample(random: rng)
                 when Prism::StringNode then "(#{STRINGS.sample(random: rng)})"
                 when Prism::SymbolNode then SYMBOLS.sample(random: rng)
                 when Prism::TrueNode then "false"
                 when Prism::FalseNode then "true"
                 when Prism::NilNode then "false"
                 end
          replace(source, node, text)
        end

        # A literal that stands alone: not a part of a bigger literal (a
        # string in an interpolation, a symbol key of `a: 1`), and not a
        # heredoc.
        def literal?(node)
          case node
          when Prism::IntegerNode, Prism::FloatNode, Prism::TrueNode, Prism::FalseNode, Prism::NilNode then true
          when Prism::StringNode then node.opening_loc && %w[" '].include?(node.opening)
          when Prism::SymbolNode then node.opening == ":"
          else false
          end
        end

        def operator(source, tree, rng)
          node = nodes(tree) do |n|
            n.is_a?(Prism::CallNode) && GROUP.key?(n.name) && n.receiver && n.arguments&.arguments&.size == 1 &&
              n.message_loc && !n.block && n.call_operator_loc.nil?
          end.sample(random: rng) or return nil
          op = (GROUP[node.name] - [node.name]).sample(random: rng)
          return nil if op.to_s.match?(/\A\w/) # eql? and equal? need a dot

          bytes = source.b.dup
          bytes[node.message_loc.start_offset...node.message_loc.end_offset] = op.to_s.b
          bytes.force_encoding(source.encoding)
        end

        def input(source, tree, rng)
          scopes = nodes(tree) { |n| n.respond_to?(:locals) && n.locals.size > 1 }
          scope = scopes.sample(random: rng) or return nil
          reads = nodes(scope) { |n| n.is_a?(Prism::LocalVariableReadNode) && n.depth.zero? && scope.locals.include?(n.name) }
          read = reads.sample(random: rng) or return nil
          other = (scope.locals - [read.name]).reject { |name| name.to_s.start_with?("_") || name.to_s.include?("*") }
          name = other.sample(random: rng) or return nil
          replace(source, read, name.to_s)
        end

        def statements(tree)
          nodes(tree) { |n| n.is_a?(Prism::StatementsNode) }.flat_map(&:body)
        end

        def splice(source, tree, rng)
          return nil unless @seeds

          other = @seeds.call(rng) or return nil
          parsed = Prism.parse(other)
          return nil unless parsed.errors.empty?

          piece = statements(parsed.value).select { |n| n.location.length < 400 }.sample(random: rng) or return nil
          at = statements(tree).sample(random: rng) or return nil
          insert_after(source, at, piece.slice)
        end

        def duplicate(source, tree, rng)
          at = statements(tree).select { |n| n.location.length < 400 }.sample(random: rng) or return nil
          insert_after(source, at, at.slice)
        end

        def delete(source, tree, rng)
          lists = nodes(tree) { |n| n.is_a?(Prism::StatementsNode) && n.body.size > 1 }
          list = lists.sample(random: rng) or return nil
          index = rng.rand(list.body.size)
          ranges = Reducer.removal_ranges(source, list.body)
          bytes = source.b.dup
          bytes[ranges[index]] = ""
          bytes.force_encoding(source.encoding)
        end

        def insert(source, tree, rng)
          return nil unless @generator

          unit = @generator.call(rng) or return nil
          at = statements(tree).sample(random: rng) or return nil
          insert_after(source, at, unit)
        end
      end

      # Programs from mutations of seeds: a seed from `files` (or from the
      # store's corpus, which comes up three times as often), changed by
      # the Mutator.
      class MutateSource
        def initialize(files, mutator:, kept: [])
          @files = files
          @kept = kept
          @mutator = mutator
        end

        def pick(rng)
          pool = !@kept.empty? && rng.rand < 0.75 ? @kept : @files
          pool.sample(random: rng)
        end

        def next_candidate(rng)
          50.times do
            file = pick(rng) or return nil
            source = File.binread(file)
            changed, edits = @mutator.mutate(source, rng)
            next unless changed

            return Candidate.new(source: changed, origin: "mutate", meta: { file: Dev.rel(file), edits: edits })
          end
          nil
        end
      end
    end
  end
end
