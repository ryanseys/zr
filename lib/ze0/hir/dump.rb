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
          lines << "#{pad}(#{n.vcall ? "vcall" : "send"}#{n.safe ? " safe" : ""} #{n.recv ? "" : "self "}#{n.name}"
          node(n.recv, depth + 1, lines) if n.recv
          n.args.each { |a| node(a, depth + 1, lines) }
          node(n.kwargs, depth + 1, lines) if n.kwargs
          node(n.block, depth + 1, lines) if n.block
          lines[-1] += ")"
        when Block
          lines << "#{pad}(block (#{params(n.params)}) locals (#{n.locals.join(" ")})"
          defaults(n.params, depth, lines)
          node(n.body, depth + 1, lines)
          lines[-1] += ")"
        when Splat
          lines << "#{pad}(splat"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when HashSplat
          lines << "#{pad}(double-splat"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when BlockPass
          lines << "#{pad}(block-pass"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when nil
          lines << "#{pad}(none)"
        when Lambda
          lines << "#{pad}(lambda"
          node(n.block, depth + 1, lines)
          lines[-1] += ")"
        when Super
          lines << "#{pad}(super"
          n.args.each { |a| node(a, depth + 1, lines) }
          node(n.kwargs, depth + 1, lines) if n.kwargs
          node(n.block, depth + 1, lines) if n.block
          lines[-1] += ")"
        when ZSuper
          lines << "#{pad}(zsuper"
          node(n.block, depth + 1, lines) if n.block
          lines[-1] += ")"
        when Yield
          lines << "#{pad}(yield"
          n.args.each { |a| node(a, depth + 1, lines) }
          node(n.kwargs, depth + 1, lines) if n.kwargs
          lines[-1] += ")"
        when Break, Next
          lines << "#{pad}(#{n.is_a?(Break) ? "break" : "next"}"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when Literal
          lines << "#{pad}(#{kind(n.value)} #{n.value.inspect})"
        when SelfRef
          lines << "#{pad}(self)"
        when Def
          lines << "#{pad}(#{n.receiver ? "sdef" : "def"} #{n.name} (#{params(n.params)}) locals (#{n.locals.join(" ")})"
          defaults(n.params, depth, lines)
          node(n.receiver, depth + 1, lines) if n.receiver
          node(n.body, depth + 1, lines)
          lines[-1] += ")"
        when Local
          lines << "#{pad}(local #{n.name}#{n.depth.zero? ? "" : " ^#{n.depth}"})"
        when Assign
          lines << "#{pad}(assign #{n.name}#{n.depth.zero? ? "" : " ^#{n.depth}"}"
          node(n.value, depth + 1, lines) if n.value
          lines[-1] += ")"
        when MultiAssign
          lines << "#{pad}(masgn"
          node(n.target, depth + 1, lines)
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when MultiTarget
          lines << "#{pad}(targets"
          n.lefts.each { |t| node(t, depth + 1, lines) }
          case n.rest
          when nil then nil
          when :implicit then lines << "#{pad}  (rest)"
          else
            lines << "#{pad}  (rest"
            node(n.rest, depth + 2, lines)
            lines[-1] += ")"
          end
          n.rights.each { |t| node(t, depth + 1, lines) }
          lines[-1] += ")"
        when If
          lines << "#{pad}(if"
          node(n.cond, depth + 1, lines)
          [n.yes, n.no].each { |arm| arm ? node(arm, depth + 1, lines) : lines << "#{pad}  (none)" }
          lines[-1] += ")"
        when While
          lines << "#{pad}(while"
          node(n.cond, depth + 1, lines)
          n.body ? node(n.body, depth + 1, lines) : lines << "#{pad}  (none)"
          lines[-1] += ")"
        when Begin
          lines << "#{pad}(begin"
          node(n.body, depth + 1, lines)
          n.rescues.each { |r| node(r, depth + 1, lines) }
          [n.else_body, n.ensure_body].each { |arm| arm ? node(arm, depth + 1, lines) : lines << "#{pad}  (none)" }
          lines[-1] += ")"
        when Rescue
          lines << "#{pad}(rescue"
          n.classes.each { |c| node(c, depth + 1, lines) }
          if n.target
            lines << "#{pad}  (into"
            node(n.target, depth + 2, lines)
            lines[-1] += ")"
          end
          node(n.body, depth + 1, lines)
          lines[-1] += ")"
        when Undef
          lines << "#{pad}(undef #{n.names.join(" ")})"
        when Retry
          lines << "#{pad}(retry)"
        when Return
          lines << "#{pad}(return"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when And, Or
          lines << "#{pad}(#{n.is_a?(And) ? "and" : "or"}"
          node(n.left, depth + 1, lines)
          node(n.right, depth + 1, lines)
          lines[-1] += ")"
        when Not
          lines << "#{pad}(not"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when ClassDef, ModuleDef
          lines << "#{pad}(#{n.is_a?(ClassDef) ? "class" : "module"} #{scope(n.scope)}#{n.name}"
          node(n.scope, depth + 1, lines) if n.scope.is_a?(Struct)
          node(n.superclass, depth + 1, lines) if n.is_a?(ClassDef) && n.superclass
          node(n.body, depth + 1, lines)
          lines[-1] += ")"
        when SingletonClassDef
          lines << "#{pad}(sclass"
          node(n.target, depth + 1, lines)
          node(n.body, depth + 1, lines)
          lines[-1] += ")"
        when ConstRead
          lines << "#{pad}(const #{scope(n.scope)}#{n.name}"
          node(n.scope, depth + 1, lines) if n.scope.is_a?(Struct)
          lines[-1] += ")"
        when ConstWrite
          lines << "#{pad}(const-set #{scope(n.scope)}#{n.name}"
          node(n.scope, depth + 1, lines) if n.scope.is_a?(Struct)
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when RangeLit
          lines << "#{pad}(range#{n.exclusive ? " exclusive" : ""}"
          node(n.low, depth + 1, lines)
          node(n.high, depth + 1, lines)
          lines[-1] += ")"
        when HashLit
          lines << "#{pad}(hash"
          n.pairs.each { |e| node(e, depth + 1, lines) }
          lines[-1] += ")"
        when Interp
          lines << "#{pad}(interp"
          n.parts.each { |e| node(e, depth + 1, lines) }
          lines[-1] += ")"
        when ArrayLit
          lines << "#{pad}(array"
          n.elements.each { |e| node(e, depth + 1, lines) }
          lines[-1] += ")"
        when IvarRead
          lines << "#{pad}(ivar #{n.name})"
        when GvarRead
          lines << "#{pad}(gvar #{n.name})"
        when GvarWrite, CvarWrite
          lines << "#{pad}(#{n.is_a?(GvarWrite) ? "gvar" : "cvar"}-set #{n.name}"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when CvarRead
          lines << "#{pad}(cvar #{n.name})"
        when ConstOrWrite
          lines << "#{pad}(const-or-set #{scope(n.scope)}#{n.name}"
          node(n.scope, depth + 1, lines) if n.scope.is_a?(Struct)
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when Alias
          lines << "#{pad}(alias #{n.new_name} #{n.old_name})"
        when Defined
          lines << "#{pad}(defined? #{n.kind}#{n.target.is_a?(Symbol) ? " #{n.target}" : ""}"
          node(n.target, depth + 1, lines) if n.target.is_a?(Struct)
          lines[-1] += ")"
        when Case
          lines << "#{pad}(case"
          n.subject ? node(n.subject, depth + 1, lines) : lines << "#{pad}  (none)"
          n.clauses.each do |values, body|
            lines << "#{pad}  (when"
            values.each { |v| node(v, depth + 2, lines) }
            node(body, depth + 2, lines)
            lines[-1] += ")"
          end
          n.else_body ? node(n.else_body, depth + 1, lines) : lines << "#{pad}  (none)"
          lines[-1] += ")"
        when IndexOpAssign
          lines << "#{pad}(index-op-assign #{n.op}"
          node(n.recv, depth + 1, lines)
          n.args.each { |a| node(a, depth + 1, lines) }
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when AttrOpAssign
          lines << "#{pad}(attr-op-assign #{n.name} #{n.op}"
          node(n.recv, depth + 1, lines)
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when Require
          lines << "#{pad}(#{n.kind} #{n.feature.inspect}#{n.unit ? " unit #{n.unit}" : " missing"})"
        when Autoload
          lines << "#{pad}(autoload #{n.name} #{n.feature.inspect} unit #{n.unit}"
          node(n.recv, depth + 1, lines) if n.recv
          lines[-1] += ")"
        when IvarWrite
          lines << "#{pad}(ivar-set #{n.name}"
          node(n.value, depth + 1, lines) if n.value
          lines[-1] += ")"
        else
          raise ArgumentError, "no dump for #{n.class}"
        end
      end

      # `a b= *r c k: k2:= **kw &blk`: each parameter as its syntax.
      def params(p)
        [*p.required.map { |r| param_name(r) }, *p.optional.map { |name, _| "#{name}=" }, p.rest && "*#{p.rest == :implicit ? "" : p.rest}", *p.post.map { |r| param_name(r) },
         *p.keywords.map { |name, default| "#{name}:#{default ? "=" : ""}" }, p.kwrest && "**#{p.kwrest}", p.block && "&#{p.block}"].compact.join(" ")
      end

      def param_name(r)
        return r.name if r.is_a?(Assign)
        return r unless r.is_a?(MultiTarget)

        inner = (r.lefts + (r.rest ? [r.rest == :implicit ? "*" : "*#{param_name(r.rest)}"] : []) + r.rights).map { |t| t.is_a?(String) ? t : param_name(t) }
        "(#{inner.join(" ")})"
      end

      # The default expressions, optional then keyword, as child nodes.
      def defaults(p, depth, lines)
        (p.optional + p.keywords).each { |_, default| node(default, depth + 1, lines) if default }
      end

      def scope(s)
        case s
        when nil then ""
        when :top then "::"
        else "(scope)::"
        end
      end

      def kind(value)
        case value
        when Integer then "int"
        when Float then "float"
        when String then "str"
        when Symbol then "sym"
        else "const"
        end
      end
    end
  end
end
