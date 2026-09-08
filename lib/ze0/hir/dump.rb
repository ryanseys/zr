# frozen_string_literal: true

require_relative "node"

module Ze0
  module Hir
    # One S-expression per node, one node per line, indented by depth: the
    # form `test/hir/` holds byte for byte.
    module Dump
      module_function

      def program(p)
        lines = []
        node(p.body, 0, lines)
        lines.join("\n") + "\n"
      end

      def node(n, depth, lines)
        pad = "  " * depth
        case n
        when Seq
          lines << "#{pad}(seq"
          n.stmts.each { |s| node(s, depth + 1, lines) }
          lines[-1] += ")"
        when Send
          lines << "#{pad}(#{n.vcall ? "vcall" : "send"} #{n.recv ? "" : "self "}#{n.name}"
          node(n.recv, depth + 1, lines) if n.recv
          n.args.each { |a| node(a, depth + 1, lines) }
          lines[-1] += ")"
        when Literal
          lines << "#{pad}(#{kind(n.value)} #{n.value.inspect})"
        when SelfRef
          lines << "#{pad}(self)"
        else
          raise ArgumentError, "no dump for #{n.class}"
        end
      end

      def kind(value)
        case value
        when Integer then "int"
        when String then "str"
        when Symbol then "sym"
        else "const"
        end
      end
    end
  end
end
