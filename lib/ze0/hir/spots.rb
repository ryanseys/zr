# frozen_string_literal: true

require "prism"
require "error_highlight"

module Ze0
  module Hir
    # The spots error_highlight shows for a file, found when the file is
    # compiled. CRuby parses the file again with prism when it reports an
    # error and finds the node a backtrace row names by its id; a program
    # here carries no parser, so the compiler asks error_highlight's own
    # Spotter about each node a row can name while it still holds the
    # tree, and the program keeps the answers.
    #
    # One row a line: `id point name first_line first_column last_line
    # last_column`, where `point` is `n` for `point_type: :name` and `a`
    # for `:args`, and `name` is the constant a NameError names, or `-`
    # where the spot does not depend on it.
    module Spots
      # Spotter reads the file's lines once per spot, and prism splits the
      # source again each time; a compiled file's source never changes.
      module Lines
        def lines = @lines ||= super
      end
      Prism::Source.prepend(Lines)

      module_function

      # The node types Spotter spots, each with the point types it
      # answers for.
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

      # The constant names a NameError at `node` can carry, where the spot
      # depends on which one it is; `[nil]` where it does not.
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
        # The read, the write and the operator each spot apart; the
        # operator's spot is any other name's.
        when :call_operator_write_node then [node.read_name, node.write_name, nil]
        when :index_operator_write_node then [:[], :[]=, nil]
        else [nil]
        end
      end

      def spot(node, point, name)
        name ||= node.binary_operator if node.type == :call_operator_write_node
        ErrorHighlight.spot(node, point_type: point, name: name)
      rescue StandardError, NotImplementedError
        nil
      end
    end
  end
end
