# frozen_string_literal: true

require_relative "../../parse"

module Zr
  module Hir
    class Build
      # The paths that a build can tell from the source: a String literal,
      # or a path built from the file's own directory and literals. The
      # loader resolves requires with them, and `EmbeddedFiles` the files
      # that a library reads.
      module LiteralPaths
        extend self

        # The absolute path of a literal: a String (frozen or not), `File.expand_path(str,
        # __dir__)`, `File.expand_path(str, __FILE__)` or `File.join(__dir__,
        # str...)`, where `File.dirname(__FILE__)` can stand for `__dir__`.
        # nil for all others.
        #: (Prism::node node, String file) -> String?
        def literal_path(node, file)
          dir = File.dirname(file)
          case node
          when Prism::StringNode then File.expand_path(node.unescaped)
          when Prism::InterpolatedStringNode
            parts = node.parts #: untyped
            return nil unless parts.size == 2 && parts[0].is_a?(Prism::EmbeddedStatementsNode) && parts[0].statements&.body&.size == 1 &&
                              dir_call?(parts[0].statements.body[0]) && parts[1].is_a?(Prism::StringNode)

            File.expand_path(dir + parts[1].unescaped)
          when Prism::CallNode
            # `"lib".freeze`, as the prelude of `-I` writes each directory.
            receiver = node.receiver
            arguments = node.arguments
            return literal_path(receiver, file) if node.name == :freeze && receiver && arguments.nil? && node.block.nil?
            return nil unless receiver.is_a?(Prism::ConstantReadNode) && receiver.name == :File && arguments

            args = arguments.arguments #: untyped
            if node.name == :expand_path && args.size == 2 && args[0].is_a?(Prism::StringNode) && dir_call?(args[1])
              File.expand_path(args[0].unescaped, dir)
            elsif node.name == :expand_path && args.size == 2 && args[0].is_a?(Prism::StringNode) && args[1].is_a?(Prism::SourceFileNode)
              File.expand_path(args[0].unescaped, file)
            elsif node.name == :join && dir_call?(args[0]) && args[1..].all?(Prism::StringNode)
              File.join(dir, *args[1..].map(&:unescaped))
            end
          end
        end

        # `__dir__`, or `File.dirname(__FILE__)`: the directory of the file.
        #: (Prism::node? node) -> bool
        def dir_call?(node)
          return false unless node.is_a?(Prism::CallNode)
          return node.receiver.nil? && node.arguments.nil? if node.name == :__dir__

          args = node.arguments&.arguments || [] #: Array[Prism::node]
          node.name == :dirname && (receiver = node.receiver).is_a?(Prism::ConstantReadNode) && receiver.name == :File &&
            args.size == 1 && args[0].is_a?(Prism::SourceFileNode)
        end
      end
    end
  end
end
