# frozen_string_literal: true

require_relative "../prism"
require "error_highlight"

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
    # `a` for `:args`. `name` is the constant in the NameError, or `-` if
    # the spot does not depend on it.
    module Spots
      # Spotter reads the file's lines once per spot, and prism splits the
      # source again each time. A compiled file's source never changes, so
      # keep the lines. `ErrorHighlight.spot` takes only the node and reads
      # the lines through the node's `Prism::Source`, so the lines can be
      # kept only there.
      module Lines
        def lines = @lines ||= super
      end
      Prism::Source.prepend(Lines)

      module_function

      # The spots of a file's tree, cached next to its parse when the
      # parse cache is on (ParseCache.derived). Finding them is a third of
      # a warm build's HIR time, and the spots are the same for the same
      # tree and the same Spotter.
      def for(result, source, options)
        return of(result.value) unless defined?(ParseCache)

        spotter = ErrorHighlight.method(:spot).source_location&.first or return of(result.value)
        ParseCache.derived("spots", source, options, [__FILE__, spotter]) { of(result.value) }
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

      def of(tree)
        rows = +""
        queue = [tree]
        while (node = queue.shift)
          queue.concat(node.compact_child_nodes)
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

      # The constant names that a NameError at `node` can contain, if the
      # spot depends on the name. `[nil]` if it does not.
      def names(node)
        case node.type
        when :constant_path_node
          chain = []
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
      # and it must not stop the build.
      def spot(node, point, name)
        name ||= node.binary_operator if node.type == :call_operator_write_node
        ErrorHighlight.spot(node, point_type: point, name: name)
      rescue StandardError, NotImplementedError
        nil
      end
    end
  end
end
