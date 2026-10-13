# frozen_string_literal: true

require_relative "../prism"
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
        return digest(result) + of(result.value) unless defined?(Cache::Parse)

        spotter = ErrorHighlight.method(:spot).source_location&.first or return digest(result) + of(result.value)
        digest(result) + Cache::Parse.derived("spots", source, options, [__FILE__, spotter]) { of(result.value) }
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

      # The node types whose code calls a method, so a frame can stand at
      # one: Thread::Backtrace::Location#source_range gives its range, as
      # CRuby finds the node again by its id.
      CALLS = %i[call_node super_node forwarding_super_node yield_node call_operator_write_node call_and_write_node
                 call_or_write_node index_operator_write_node index_and_write_node index_or_write_node
                 local_variable_operator_write_node instance_variable_operator_write_node
                 class_variable_operator_write_node global_variable_operator_write_node
                 constant_operator_write_node constant_path_operator_write_node interpolated_string_node
                 interpolated_symbol_node interpolated_x_string_node interpolated_regular_expression_node
                 x_string_node match_write_node].to_h { [_1, true] }.freeze

      # `spotted: false` leaves out error_highlight's spots: a compile at run
      # time must not load error_highlight, which is the program's autoload.
      #: (Prism::node tree, ?spotted: bool) -> String
      def of(tree, spotted: true)
        rows = +""
        queue = [tree]
        while (node = queue.shift)
          queue.concat(node.compact_child_nodes)
          at = CALLS[node.type] ? node.location : entry(node)
          rows << [node.node_id, "r", "-", at.start_line, at.start_column, at.end_line, at.end_column].join(" ") << "\n" if at
          next unless spotted

          points = POINTS[node.type] or next

          names(node).each do |name|
            points.each do |point|
              spot = spot(node, point, name) or next

              rows << [node.node_id, point == :name ? "n" : "a", name || "-",
                       spot[:first_lineno], spot[:first_column], spot[:last_lineno], spot[:last_column]].join(" ") << "\n"
            end
          end
        end
        rows
      end

      # Where a frame of a def, block or lambda stands before its first call
      # (a TracePoint's :call): its frame keeps the def's id, and CRuby's
      # stands at the body's first statement. Nil for any other node, or
      # for an empty body.
      #: (untyped node) -> Prism::Location?
      def entry(node)
        return unless node.type == :def_node || node.type == :block_node || node.type == :lambda_node

        body = node.body
        body = body.statements if body.is_a?(Prism::BeginNode)
        body.body.first&.location if body.is_a?(Prism::StatementsNode)
      end

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
