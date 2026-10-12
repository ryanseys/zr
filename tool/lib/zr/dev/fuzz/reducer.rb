# frozen_string_literal: true

require "digest"
require "prism"

module Zr
  module Dev
    module Fuzz
      # Makes a failing program small, while it still fails the same way:
      # the same kind and key of verdict. It works on the tree that prism
      # parses (hierarchical delta debugging, as Perses does): it tries
      # only candidates that parse, so no run is spent on a program that
      # ruby would reject.
      #
      # Each pass edits the source by byte ranges of the tree's nodes, so
      # no printer of Ruby is needed:
      #
      # 1. lists: for each list of nodes (statements, arguments, array
      #    elements, hash pairs, parameters), outermost first, remove as
      #    many elements as it can (ddmin);
      # 2. nodes: replace a node with one of its children, or with `nil`,
      #    when that is shorter;
      # 3. lines: when the program does not parse (junk), remove lines.
      #
      # The passes repeat until none makes the program smaller, or the
      # budget of checks is used. Each check is cached by the digest of
      # the candidate. The candidates of one step are checked `jobs` at a
      # time.
      class Reducer
        BUDGET = 400

        # The kinds that a reduction does not pay for: each check waits for
        # a limit, or the failure does not come back on each run.
        SKIP = %w[timeout memory flaky build-timeout].freeze

        attr_reader :checks

        # `check` takes a source and returns an Oracle::Result.
        def initialize(check:, jobs: 4, budget: BUDGET)
          @check = check
          @jobs = jobs
          @budget = budget
          @cache = {}
          @lock = Mutex.new
          @checks = 0
        end

        # Returns the reduced source, its result, and its shape (the node
        # kinds and method names that it has, for its bucket).
        def reduce(source, result)
          return [source, result, Reducer.shape(source)] if SKIP.include?(result.verdict.kind)

          @want = result.verdict
                    @cache[digest(source)] = result
          current = source
          loop do
            before = current.bytesize
            current = parses?(current) ? tree_passes(current) : lines(current)
            break if current.bytesize >= before || spent?
          end
          [current, @cache.fetch(digest(current)), Reducer.shape(current)]
        end

        # The sorted node kinds and called method names of `source`, or nil
        # when it does not parse.
        def self.shape(source)
          tree = Prism.parse(source)
          return nil unless tree.errors.empty?

          names = Set.new
          walk(tree.value) do |node|
            names << node.class.name.split("::").last.delete_suffix("Node")
            names << ".#{node.name}" if node.is_a?(Prism::CallNode)
          end
          names.to_a.sort.join(" ")
        end

        def self.walk(node, &)
          return unless node

          yield node
          node.compact_child_nodes.each { |child| walk(child, &) }
        end

        private

        def spent? = @lock.synchronize { @checks >= @budget }

        def digest(source) = Digest::SHA1.hexdigest(source)

        def parses?(source) = Prism.parse(source).errors.empty?

        # True when `candidate` fails as the original did. A candidate that
        # does not parse is false with no run.
        def interesting?(candidate)
          key = digest(candidate)
          cached = @lock.synchronize { @cache[key] }
          return keeps?(cached) if cached
          return false if spent?

          @lock.synchronize { @checks += 1 }
          got = @check.call(candidate)
          @lock.synchronize { @cache[key] = got }
          keeps?(got)
        end

        def keeps?(got)
          got.failure? && got.verdict.kind == @want.kind && got.verdict.key == @want.key
        end

        # The first candidate (in order) that is interesting, or nil. The
        # candidates are checked `jobs` at a time.
        def first_interesting(candidates)
          candidates = candidates.uniq.select { |c| parses?(c) }
          candidates.each_slice(@jobs) do |slice|
            hits = Dev.parallel_map(slice, jobs: @jobs) { |c| interesting?(c) }
            index = hits.index(true)
            return slice[index] if index
            return nil if spent?
          end
          nil
        end

        # The comments go first: one check, which a spent budget would
        # never reach at the end.
        def tree_passes(source)
          bare = Reducer.uncommented(source)
          source = bare if bare != source && interesting?(bare)
          source = list_pass(source)
          node_pass(source)
        end

        # ddmin over each list of the tree. After each removal the source
        # is parsed again, and the walk goes on at the same list.
        def list_pass(source)
          index = 0
          loop do
            lists = Reducer.lists(Prism.parse(source).value)
            return source if index >= lists.size || spent?

            reduced = ddmin(source, lists[index])
            if reduced
              source = reduced
            else
              index += 1
            end
          end
        end

        # Removes elements of `list` (byte ranges) from `source`. Returns the
        # smaller source, or nil when no removal keeps the failure.
        def ddmin(source, list)
          ranges = Reducer.removal_ranges(source, list)
          return nil if ranges.empty?

          keep = (0...ranges.size).to_a
          granularity = 2
          changed = false
          while keep.size.positive? && !spent?
            chunks = keep.each_slice((keep.size.to_f / granularity).ceil).to_a
            candidates = chunks.map { |chunk| [chunk, without(source, ranges, ranges.each_index.to_a - keep + chunk)] }
            hit = first_interesting(candidates.map(&:last))
            if hit
              chunk = candidates.find { |_, c| c == hit }.first
              keep -= chunk
              changed = true
              granularity = [granularity - 1, 2].max
            else
              break if granularity >= keep.size

              granularity = [granularity * 2, keep.size].min
            end
          end
          changed ? without(source, ranges, ranges.each_index.to_a - keep) : nil
        end

        # `source` without the ranges at `indexes`.
        def without(source, ranges, indexes)
          out = source.b.dup
          indexes.map { |i| ranges[i] }.sort_by { |r| -r.begin }.each { |r| out[r] = "" }
          out.force_encoding(source.encoding)
        end

        # Replaces one node at a time with a shorter text: a child, or nil.
        # The biggest nodes go first.
        def node_pass(source)
          loop do
            return source if spent?

            tree = Prism.parse(source).value
            nodes = []
            Reducer.walk(tree) { |n| nodes << n unless n.is_a?(Prism::ProgramNode) || n.is_a?(Prism::StatementsNode) }
            nodes.sort_by! { |n| -n.location.length }
            hit = nil
            nodes.each do |node|
              candidates = Reducer.replacements(node).map do |text|
                bytes = source.b.dup
                bytes[node.location.start_offset...node.location.end_offset] = text.b
                bytes.force_encoding(source.encoding)
              end
              hit = first_interesting(candidates.select { |c| c.bytesize < source.bytesize })
              break if hit || spent?
            end
            return source unless hit

            source = hit
          end
        end

        # Line ddmin, for a program that does not parse.
        def lines(source)
          all = source.lines
          keep = (0...all.size).to_a
          granularity = 2
          while keep.size > 1 && !spent?
            chunks = keep.each_slice((keep.size.to_f / granularity).ceil).to_a
            candidates = chunks.map { |chunk| (keep - chunk).map { |i| all[i] }.join }
            hits = Dev.parallel_map(candidates, jobs: @jobs) { |c| interesting?(c) }
            index = hits.index(true)
            if index
              keep -= chunks[index]
              granularity = [granularity - 1, 2].max
            else
              break if granularity >= keep.size

              granularity = [granularity * 2, keep.size].min
            end
          end
          keep.map { |i| all[i] }.join
        end

        class << self
          # `source` without its comments and its blank lines. A magic
          # comment goes too: the check tells whether it mattered.
          def uncommented(source)
            out = source.b.dup
            Prism.parse(source).comments.sort_by { |c| -c.location.start_offset }.each do |comment|
              loc = comment.location
              out[loc.start_offset...loc.end_offset] = ""
            end
            out.force_encoding(source.encoding).lines.map(&:rstrip).reject(&:empty?).map { "#{_1}\n" }.join
          end

          # The lists of a tree, outermost first: each one an Array of nodes
          # whose removal one by one keeps the rest well formed.
          def lists(tree)
            out = []
            queue = [tree]
            until queue.empty?
              node = queue.shift
              list = case node
                     when Prism::StatementsNode then node.body
                     when Prism::ArgumentsNode then node.arguments
                     when Prism::ArrayNode then node.elements
                     when Prism::HashNode, Prism::KeywordHashNode then node.elements
                     when Prism::ParametersNode then [*node.requireds, *node.optionals, *node.posts, *node.keywords]
                     when Prism::CaseNode then node.conditions
                     end
              out << list if list && !list.empty?
              queue.concat(node.compact_child_nodes)
            end
            out
          end

          # The byte range to cut for each element of `list`: from its
          # start to the start of the next one, and the last one from the
          # end of the one before it, so that separators go with it.
          def removal_ranges(_source, list)
            list.each_with_index.map do |node, i|
              loc = node.location
              if i < list.size - 1
                loc.start_offset...list[i + 1].location.start_offset
              elsif i.positive?
                list[i - 1].location.end_offset...loc.end_offset
              else
                loc.start_offset...loc.end_offset
              end
            end
          end

          # Shorter texts that can stand for `node`: its children that are
          # expressions or bodies, `nil`, and small literals.
          def replacements(node)
            texts = node.compact_child_nodes.filter_map do |child|
              next if child.is_a?(Prism::ArgumentsNode) && child.arguments.size != 1
              next child.arguments.first.slice if child.is_a?(Prism::ArgumentsNode)
              next if child.is_a?(Prism::ParametersNode) || child.is_a?(Prism::BlockParametersNode)

              child.slice
            end
            texts << "nil"
            texts << "0" if node.is_a?(Prism::IntegerNode) || node.is_a?(Prism::FloatNode)
            texts << '""' if node.is_a?(Prism::StringNode) || node.is_a?(Prism::InterpolatedStringNode)
            len = node.location.length
            texts.uniq.select { |t| t.bytesize < len }.sort_by(&:bytesize)
          end
        end
      end
    end
  end
end
