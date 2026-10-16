# frozen_string_literal: true

require_relative "../parse"
# ruby makes ErrorHighlight an autoload, and so does a zr program. The
# compiler that a program carries (eval support) must not load the
# library itself: that would end the program's autoload.
require "error_highlight" unless defined?(ErrorHighlight)
require "zlib"

module Zr
  module Hir
    # The spots that error_highlight shows for a file, found when the file
    # is compiled. When CRuby reports an error, it parses the file again
    # with prism and finds a backtrace entry's node by its id. A zr
    # program contains no parser. So while the compiler has the tree, it
    # calls error_highlight's own Spotter for each node that a backtrace
    # entry can refer to, and the program keeps the results.
    #
    # One record per line: `id point name first_line first_column
    # last_line last_column`. `point` is `n` for `point_type: :name` and
    # `a` for `:args`, or `r` for the range of a node that calls (CALLS).
    # The first record, `0 h - crc length`, is the digest of the code that
    # was compiled (`digest`).
    # `name` is the constant in the NameError, or `-` if the spot does not
    # depend on it.
    module Spots
      # Spotter reads the file's lines once per spot, and prism splits the
      # source again each time. A compiled file's source never changes, so
      # keep the lines. `ErrorHighlight.spot` takes only the node and reads
      # the lines through the node's `Prism::Source`, so the lines can be
      # kept only there.
      module Lines
        # @rbs @lines: Array[String]

        # Steep cannot see the `super` of a module that a class prepends.
        #: () -> Array[String]
        def lines = @lines ||= super # steep:ignore UnexpectedSuper
      end
      Prism::Source.prepend(Lines)

      module_function

      # The spots of a file's tree, cached next to its parse when the
      # parse cache is on (`Cache::Parse.derived`). Finding them is a third of
      # a warm build's HIR time, and the spots are the same for the same
      # tree and the same Spotter.
      #: (Prism::ParseResult result, String source, Hash[Symbol, untyped] options) -> String
      def for(result, source, options)
        cache = Zr.parse_cache or return digest(result) + of(result.value)
        spotter = ErrorHighlight.method(:spot).source_location&.first or return digest(result) + of(result.value)
        digest(result) + cache.derived("spots", source, options, [__FILE__, spotter]) { of(result.value) }
      end

      # The record of the code that prism parsed, up to the end of an
      # `__END__` line: its CRC-32 and length. #syntax_tree parses the file
      # again only while it has the same code, as iseq_syntax_tree checks
      # the source hash.
      #: (Prism::ParseResult result) -> String
      def digest(result)
        code = result.source.source
        if (data = result.data_loc) && (eol = code.byteindex("\n", data.start_offset))
          code = code.byteslice(0, eol + 1) #: String
        end
        "0 h - #{Zlib.crc32(code)} #{code.bytesize}\n"
      end

      # The node types that Spotter handles, each with its point types.
      POINTS = {
        call_node: %i[name args],
        local_variable_operator_write_node: %i[name args],
        call_operator_write_node: %i[name args],
        index_operator_write_node: %i[name args],
        constant_read_node: %i[name],
        constant_path_node: %i[name],
        constant_path_operator_write_node: %i[name],
        def_node: %i[name],
        lambda_node: %i[name],
        block_node: %i[name]
      }.freeze

      # The node types where a frame can stand, so a frame can report one:
      # Thread::Backtrace::Location#source_range gives its range, as CRuby
      # finds the node again by its id. These are the nodes whose code calls a
      # method, reads or writes a constant or a class variable, converts a
      # value, matches a pattern, or opens a class body.
      RANGES = %i[call_node super_node forwarding_super_node yield_node call_operator_write_node call_and_write_node
                  call_or_write_node index_operator_write_node index_and_write_node index_or_write_node
                  local_variable_operator_write_node instance_variable_operator_write_node
                  class_variable_operator_write_node class_variable_and_write_node class_variable_or_write_node
                  global_variable_operator_write_node constant_read_node constant_path_node constant_write_node
                  constant_path_write_node constant_operator_write_node constant_and_write_node constant_or_write_node
                  constant_path_operator_write_node constant_path_and_write_node constant_path_or_write_node
                  constant_target_node constant_path_target_node call_target_node index_target_node multi_write_node
                  multi_target_node array_node hash_node keyword_hash_node splat_node hash_pattern_node array_pattern_node
                  find_pattern_node class_node module_node singleton_class_node def_node block_node lambda_node
                  interpolated_string_node interpolated_symbol_node interpolated_x_string_node
                  interpolated_regular_expression_node x_string_node match_write_node].to_h { [_1, true] }.freeze

      # Bit 30 of a node id: a frame that stands at the entry of a def, block
      # or lambda, before its first statement (a TracePoint :call). Its row is
      # that statement, and the id without the bit is the whole node. The
      # id sits in a word from bit 32 up, so bit 30 keeps that word positive.
      ENTRY = 1 << 30

      # `spotted: false` leaves out error_highlight's spots: a compile at run
      # time must not load error_highlight, which is the program's autoload.
      #: (Prism::node tree, ?spotted: bool) -> String
      def of(tree, spotted: true)
        rows = +""
        queue = [tree]
        # The ids of the parts of a constant path that its outermost node
        # already spotted.
        parts = {} #: Hash[Integer, true]
        while (node = queue.shift)
          queue.concat(node.compact_child_nodes)
          range(rows, node.node_id, node.location) if RANGES[node.type]
          range(rows, node.node_id | ENTRY, entry(node))
          # A value that `when` or `in` tests with ===.
          node.conditions.each { |test| range(rows, test.node_id, test.location) unless RANGES[test.type] } if node.is_a?(Prism::WhenNode)
          range(rows, pinned(node.pattern).node_id, pinned(node.pattern).location) if node.is_a?(Prism::InNode) && !RANGES[pinned(node.pattern).type]
          next unless spotted && !parts.key?(node.node_id)

          points = POINTS[node.type] or next

          # `Foo::Bar::Baz` is one instruction (opt_getconstant_path), and
          # the frame of a NameError in any of its parts names the whole
          # path's node, so each part takes the whole path's spots: the
          # Spotter picks the part by the name, or none when two parts
          # have it.
          ids = [node.node_id]
          path_parts(node)&.each do |part|
            ids << part.node_id
            parts[part.node_id] = true
          end
          names(node).each do |name|
            points.each do |point|
              spot = spot(node, point, name) or next

              ids.each do |id|
                rows << [id, point == :name ? "n" : "a", name || "-",
                         spot[:first_lineno], spot[:first_column], spot[:last_lineno], spot[:last_column]].join(" ") << "\n"
              end
            end
          end
        end
        rows
      end

      # The inner parts of a constant path whose base is a constant or
      # `::` (the paths opt_getconstant_path reads at once), or nil.
      #: (untyped node) -> Array[untyped]?
      def path_parts(node)
        return unless node.type == :constant_path_node

        found = [] #: Array[untyped]
        part = node.parent
        while part.is_a?(Prism::ConstantPathNode)
          found << part
          part = part.parent
        end
        return unless part.nil? || part.is_a?(Prism::ConstantReadNode)

        part ? found << part : found
      end

      # The value that a pinned pattern tests, or the pattern itself.
      #: (untyped node) -> untyped
      def pinned(node)
        case node.type
        when :pinned_variable_node then node.variable
        when :pinned_expression_node then node.expression
        else node
        end
      end

      # Adds the range row of the node `id` at `at`, if there is one.
      #: (String rows, Integer id, Prism::Location? at) -> void
      def range(rows, id, at)
        rows << [id, "r", "-", at.start_line, at.start_column, at.end_line, at.end_column].join(" ") << "\n" if at
      end

      # Where a frame of a def, block or lambda stands before its first call
      # (a TracePoint's :call): its frame keeps the def's id with ENTRY, as
      # CRuby's stands at the body's first statement. Nil for any other node, or
      # for an empty body.
      #: (untyped node) -> Prism::Location?
      def entry(node)
        return unless node.type == :def_node || node.type == :block_node || node.type == :lambda_node

        body = node.body
        body = body.statements if body.is_a?(Prism::BeginNode)
        first_run(body.body.first)&.location if body.is_a?(Prism::StatementsNode)
      end

      # The node of the first instruction of a statement, where CRuby's
      # frame stands before it runs: a write's value, a call's receiver.
      #: (untyped node) -> untyped
      def first_run(node)
        node = node.value while WRITES[node&.type] && node.value
        node = node.receiver while node&.type == :call_node && node.receiver
        node
      end

      WRITES = %i[local_variable_write_node instance_variable_write_node global_variable_write_node
                  class_variable_write_node constant_write_node].to_h { [_1, true] }.freeze

      # The constant names that a NameError at `node` can contain, if the
      # spot depends on the name. `[nil]` if it does not.
      #: (untyped node) -> Array[Symbol?]
      def names(node)
        case node.type
        when :constant_path_node
          chain = [] #: Array[Symbol?]
          # @type var part: Prism::node?
          part = node
          while part.is_a?(Prism::ConstantPathNode)
            chain << part.name
            part = part.parent
          end
          chain << part.name if part.is_a?(Prism::ConstantReadNode)
          chain.uniq
        when :constant_path_operator_write_node then [node.target.name, nil]
        # The read, the write and the operator each have a different spot.
        # The operator's spot is used for any other name.
        when :call_operator_write_node then [node.read_name, node.write_name, nil]
        when :index_operator_write_node then [:[], :[]=, nil]
        else [nil]
        end
      end

      # Spotter raises for a form that it does not know. A spot only
      # adds a highlight to an error message, so a failed spot is no spot,
      # and it must not stop the build. The Spotter is called directly:
      # `ErrorHighlight.spot` takes only a node of the host's own parser
      # (Ruby::Prism), not of the prism gem that zr parses with.
      #: (untyped node, Symbol point, Symbol? name) -> Hash[Symbol, Integer]?
      def spot(node, point, name)
        name ||= node.binary_operator if node.type == :call_operator_write_node
        ErrorHighlight.const_get(:Spotter).new(node, point_type: point, name: name).spot
      rescue StandardError, NotImplementedError
        nil
      end
    end
  end
end
