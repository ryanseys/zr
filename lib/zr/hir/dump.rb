# frozen_string_literal: true

require_relative "node"

module Zr
  module Hir
    # One S-expression per node, one node per line, indented by depth. The
    # files in `test/hir/` contain this exact form.
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
        when Send then dump_send(n, depth, lines)
        when Block then dump_block(n, depth, lines)
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
        when Super then dump_super(n, depth, lines)
        when ZSuper
          lines << "#{pad}(zsuper"
          node(n.block, depth + 1, lines) if n.block
          lines[-1] += ")"
        when Yield then dump_yield(n, depth, lines)
        when Break, Next
          lines << "#{pad}(#{n.is_a?(Break) ? "break" : "next"}"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when Literal
          lines << "#{pad}(#{kind(n.value)} #{n.value.inspect})"
        when SelfRef
          lines << "#{pad}(self)"
        when Def then dump_def(n, depth, lines)
        when Local
          lines << "#{pad}(local #{n.name}#{n.depth.zero? ? "" : " ^#{n.depth}"})"
        when Assign
          lines << "#{pad}(assign #{n.name}#{n.depth.zero? ? "" : " ^#{n.depth}"}"
          node(n.value, depth + 1, lines) if n.value
          lines[-1] += ")"
        when MultiAssign then dump_multi_assign(n, depth, lines)
        when MultiTarget then dump_multi_target(n, depth, lines)
        when If then dump_if(n, depth, lines)
        when While then dump_while(n, depth, lines)
        when Begin then dump_begin(n, depth, lines)
        when Rescue then dump_rescue(n, depth, lines)
        when Undef
          lines << "#{pad}(undef #{n.names.join(" ")})"
        when UndefValue
          lines << "#{pad}(undef-value"
          n.names.each { |name| node(name, depth + 1, lines) }
          lines[-1] += ")"
        when Retry
          lines << "#{pad}(retry)"
        when Redo
          lines << "#{pad}(redo)"
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
        when ClassDef, ModuleDef then dump_class_def(n, depth, lines)
        when SingletonClassDef then dump_singleton_class_def(n, depth, lines)
        when ConstRead
          lines << "#{pad}(const #{scope(n.scope)}#{n.name}"
          node(n.scope, depth + 1, lines) if n.scope.is_a?(Node)
          lines[-1] += ")"
        when ConstWrite then dump_const_write(n, depth, lines)
        when RangeLit then dump_range(n, depth, lines)
        when HashLit
          lines << "#{pad}(hash#{" frozen" if n.frozen}"
          n.pairs.each { |e| node(e, depth + 1, lines) }
          lines[-1] += ")"
        when KwSplatElement
          lines << "#{pad}(kwsplat-element"
          node(n.pairs, depth + 1, lines)
          lines[-1] += ")"
        when RegexpLit then lines << "#{pad}(regexp #{n.source.inspect} #{n.options})"
        when RegexpOnce
          lines << "#{pad}(regexp-once"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when FrozenString then lines << "#{pad}(frozen#{" shared" if n.shared} #{n.value.inspect})"
        when Interp
          lines << "#{pad}(interp"
          n.parts.each { |e| node(e, depth + 1, lines) }
          lines[-1] += ")"
        when ArrayLit
          lines << "#{pad}(array#{" frozen" if n.frozen}"
          n.elements.each { |e| node(e, depth + 1, lines) }
          lines[-1] += ")"
        when IvarRead
          lines << "#{pad}(ivar #{n.name})"
        when GvarRead
          lines << "#{pad}(gvar #{n.name})"
        when BackRef
          lines << "#{pad}(backref #{n.kind}#{n.kind == :nth ? " #{n.number}" : ""})"
        when GvarWrite, CvarWrite
          lines << "#{pad}(#{n.is_a?(GvarWrite) ? "gvar" : "cvar"}-set #{n.name}"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when CvarRead
          lines << "#{pad}(cvar #{n.name})"
        when ConstOrWrite then dump_const_or_write(n, depth, lines)
        when Alias, GvarAlias
          lines << "#{pad}(alias #{n.new_name} #{n.old_name})"
        when AliasValue then dump_alias_value(n, depth, lines)
        when Defined then dump_defined(n, depth, lines)
        when Case then dump_case(n, depth, lines)
        when IndexOpAssign then dump_index_op_assign(n, depth, lines)
        when AttrOpAssign then dump_attr_op_assign(n, depth, lines)
        when Require
          lines << "#{pad}(#{n.kind} #{n.feature.inspect}#{n.unit ? " unit #{n.unit}" : " missing"})"
        when Autoload then dump_autoload(n, depth, lines)
        when IvarWrite
          lines << "#{pad}(ivar-set #{n.name}"
          node(n.value, depth + 1, lines) if n.value
          lines[-1] += ")"
        when Core
          lines << "#{pad}(core #{n.name})"
        when Slot
          lines << "#{pad}(slot #{n.index})"
        when Once
          lines << "#{pad}(once"
          node(n.body, depth + 1, lines)
          lines[-1] += ")"
        when Trace
          lines << "#{pad}(trace #{n.event})"
        when Cover
          lines << "#{pad}(cover #{n.id})"
        when Stop
          lines << "#{pad}(stop #{n.what.inspect})"
        when Using
          lines << "#{pad}(using #{n.id} from #{n.from}"
          node(n.value, depth + 1, lines)
          lines[-1] += ")"
        when UsingDefaults
          lines << "#{pad}(using-defaults #{n.rows.map { |id, from| "#{id}<-#{from}" }.join(" ")})"
        when Activations
          lines << "#{pad}(activations #{n.count})"
        else
          raise ArgumentError, "no dump for #{n.class}"
        end
      end

      def dump_send(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(#{n.vcall ? "vcall" : "send"}#{n.safe ? " safe" : ""} #{n.recv ? "" : "self "}#{n.name}"
        node(n.recv, depth + 1, lines) if n.recv
        n.args.each { |a| node(a, depth + 1, lines) }
        node(n.kwargs, depth + 1, lines) if n.kwargs
        node(n.block, depth + 1, lines) if n.block
        lines[-1] += ")"
      end

      def dump_block(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(block (#{params(n.params)}) locals (#{n.locals.join(" ")})"
        defaults(n.params, depth, lines)
        node(n.body, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_super(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(super"
        n.args.each { |a| node(a, depth + 1, lines) }
        node(n.kwargs, depth + 1, lines) if n.kwargs
        node(n.block, depth + 1, lines) if n.block
        lines[-1] += ")"
      end

      def dump_yield(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(yield"
        n.args.each { |a| node(a, depth + 1, lines) }
        node(n.kwargs, depth + 1, lines) if n.kwargs
        lines[-1] += ")"
      end

      def dump_def(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(#{n.receiver ? "sdef" : "def"} #{n.name} (#{params(n.params)}) locals (#{n.locals.join(" ")})"
        defaults(n.params, depth, lines)
        node(n.receiver, depth + 1, lines) if n.receiver
        node(n.body, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_multi_assign(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(masgn"
        node(n.target, depth + 1, lines)
        node(n.value, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_multi_target(n, depth, lines)
        pad = "  " * depth
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
      end

      def dump_if(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(if"
        node(n.cond, depth + 1, lines)
        [n.yes, n.no].each { |arm| arm ? node(arm, depth + 1, lines) : lines << "#{pad}  (none)" }
        lines[-1] += ")"
      end

      def dump_while(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(#{n.body_first ? "do-while" : "while"}"
        node(n.cond, depth + 1, lines)
        n.body ? node(n.body, depth + 1, lines) : lines << "#{pad}  (none)"
        lines[-1] += ")"
      end

      def dump_begin(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(begin"
        node(n.body, depth + 1, lines)
        n.rescues.each { |r| node(r, depth + 1, lines) }
        [n.else_body, n.ensure_body].each { |arm| arm ? node(arm, depth + 1, lines) : lines << "#{pad}  (none)" }
        lines[-1] += ")"
      end

      def dump_rescue(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(rescue"
        n.classes.each { |c| node(c, depth + 1, lines) }
        if n.target
          lines << "#{pad}  (into"
          node(n.target, depth + 2, lines)
          lines[-1] += ")"
        end
        node(n.body, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_class_def(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(#{n.is_a?(ClassDef) ? "class" : "module"} #{scope(n.scope)}#{n.name}"
        node(n.scope, depth + 1, lines) if n.scope.is_a?(Node)
        node(n.superclass, depth + 1, lines) if n.is_a?(ClassDef) && n.superclass
        node(n.body, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_singleton_class_def(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(sclass"
        node(n.target, depth + 1, lines)
        node(n.body, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_const_write(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(const-set #{scope(n.scope)}#{n.name}"
        node(n.scope, depth + 1, lines) if n.scope.is_a?(Node)
        node(n.value, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_range(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(range#{n.exclusive ? " exclusive" : ""}"
        node(n.low, depth + 1, lines)
        node(n.high, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_const_or_write(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(const-or-set #{scope(n.scope)}#{n.name}"
        node(n.scope, depth + 1, lines) if n.scope.is_a?(Node)
        node(n.value, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_alias_value(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(alias-value"
        node(n.new_name, depth + 1, lines)
        node(n.old_name, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_defined(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(defined? #{n.kind}#{n.target.is_a?(Symbol) ? " #{n.target}" : ""}"
        node(n.target, depth + 1, lines) if n.target.is_a?(Node)
        lines[-1] += ")"
      end

      def dump_case(n, depth, lines)
        pad = "  " * depth
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
      end

      def dump_index_op_assign(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(index-op-assign #{n.op}"
        node(n.recv, depth + 1, lines)
        n.args.each { |a| node(a, depth + 1, lines) }
        node(n.value, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_attr_op_assign(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(attr-op-assign #{n.name} #{n.op}"
        node(n.recv, depth + 1, lines)
        node(n.value, depth + 1, lines)
        lines[-1] += ")"
      end

      def dump_autoload(n, depth, lines)
        pad = "  " * depth
        lines << "#{pad}(autoload #{n.name} #{n.feature.inspect} #{n.declared ? "declared" : "unit #{n.unit}"}"
        node(n.recv, depth + 1, lines) if n.recv
        lines[-1] += ")"
      end

      # `a b= *r c k: k2:= **kw &blk`: each parameter as its syntax.
      def params(p)
        [*p.required.map { |r| param_name(r) }, *p.optional.map { |name, _| "#{name}=" }, p.rest && "*#{p.rest == :implicit ? "" : p.rest}", *p.post.map { |r| param_name(r) },
         *p.keywords.map { |name, default| "#{name}:#{default ? "=" : ""}" }, p.kwrest && "**#{p.kwrest}", p.block && "&#{p.block}"].compact.join(" ")
      end

      def param_name(r)
        return r.name if r.is_a?(Assign)
        return r unless r.is_a?(MultiTarget)

        rest = if r.rest == :implicit then ["*"]
               elsif r.rest then ["*#{param_name(r.rest)}"]
               else []
               end
        inner = (r.lefts + rest + r.rights).map { |t| t.is_a?(String) ? t : param_name(t) }
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
