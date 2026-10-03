# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # The code of definitions, as `Lower` emits them: a def is a
        # function of the kernel (`(recv, argc, argv, entry, blk, found) =>
        # Value`) at an address that `Host#callable` gives, a class body
        # runs in a frame of its own, and a require runs a unit's toplevel.
        module Definitions
          # @type instance: Walk
          # The ivars of Walk that this module reads (walk.rb):
          # @rbs @host: Host
          # @rbs @kern: untyped
          # @rbs @qnil: Integer
          # @rbs @qundef: Integer
          # @rbs @fns: Hash[untyped, untyped]
          # @rbs @metas: Hash[untyped, Integer]
          # @rbs @attributes: Hash[Hir::Def, Array[Symbol]]
          # @rbs @traced: bool
          # @rbs @eval_files: EvalSupport
          # @rbs @eval_entry: Integer?

          # zr_require's kinds (Lower::Function::Control::REQUIRE_KINDS).
          REQUIRE_KINDS = { require: 0, require_relative: 1, load: 2, hidden: 3, computed: 4, declared: 5 }.freeze

          private

          def define(node, s)
            owner = if node.receiver
                      recv = code(node.receiver, s)
                      word = line_word(node, s)
                      lambda do |f|
                        target = recv.call(f)
                        line!(f, word)
                        check(@kern.zr_singleton_class(target))
                      end
                    else
                      ->(f) { @kern.zr_cref_klass(f.cref) }
                    end
            fn = def_fn(node, s.unit)
            word = line_word(node, s)
            arity = node.params.plain? ? node.params.required.size : -1
            entry = node.receiver || s.def_node ? :zr_define_method_public : :zr_define_method
            name = id(node.name)
            m = @metas.fetch(node)
            symbol = sym(node.name)
            lambda do |f|
              klass = owner.call(f)
              line!(f, word)
              check(@kern.public_send(entry, klass, name, fn, arity, @kern::KIND_DEF, m, f.cref))
              symbol
            end
          end

          # The function of the def `node`. Its body compiles when it first
          # runs.
          def def_fn(node, unit)
            @fns[node] ||= begin
              hidden = attributes(node).include?(:hidden)
              kind = if unit.internal then hidden ? k::KIND_HIDDEN : k::KIND_BUILTIN
                     else k::KIND_DEF
                     end
              open = open?(node, :def, unit, node.params)
              m = meta(node, unit, kind, name: node.name, params: node.params, locals: node.locals, open: open,
                                         ruby: unit.internal && attributes(node).include?(:ruby), cover: node.cover)
              s = scope(node, unit, :def, m, scopes: [node.locals], homes: [node], def_node: node, params: node.params, open: open)
              # The body compiles at its first run.
              run = nil #: untyped
              @host.callable(lambda do |recv, argc, argv, entry, blk, found|
                run ||= def_body(node, s)
                cref = entry.zero? ? @qnil : k::MEntry[entry].cref
                enter(s, recv, cref, blk, entry: entry, defined: found) { |f| run.call(f, argc, argv, entry) }
              end)
            end
          end

          # The code of a def's run: its arguments bound, a safe point, its
          # events, then its body.
          def def_body(node, s)
            bind = method_binder(node.params, s, @fns[node])
            body = code(node.body, s)
            jumps = jumps?([node.body, node.params])
            internal = s.internal?
            cover = node.cover
            lambda do |f, argc, argv, entry|
              run_body(s, f, jumps, node) do
                bind.call(f, argc, argv)
                preempt unless internal
                opened(s, f, :def)
                @kern.zr_coverage_method(entry) if cover
                body.call(f)
              end
            end
          end

          # The leading `Primitive.attr!(:name)` statements of a def.
          def attributes(node)
            @attributes[node] ||= begin
              body = node.body.is_a?(Hir::Begin) ? node.body.body : node.body
              stmts = body.is_a?(Hir::Seq) ? body.stmts : [body]
              stmts.take_while { |s| s.is_a?(Hir::Send) && s.name == :attr! && s.recv.is_a?(Hir::ConstRead) && s.recv.name == :Primitive }
                   .flat_map { |s| s.args.map(&:value) }
            end
          end

          def class_body(node, s)
            scope = scope_class(node.scope, s)
            sup = node.is_a?(Hir::ClassDef) && node.superclass && code(node.superclass, s)
            word = line_word(node, s)
            name = id(node.name)
            nested = node.scope ? 1 : 0
            kind = node.is_a?(Hir::ClassDef) ? k::KIND_CLASS : k::KIND_MODULE
            body = body_in(node, s, kind, node.name)
            if node.is_a?(Hir::ClassDef)
              lambda do |f|
                outer = scope.call(f)
                superclass = sup ? sup.call(f) : @qundef
                line!(f, word)
                body.call(f, check(@kern.zr_class_define(outer, name, superclass, nested)))
              end
            else
              lambda do |f|
                outer = scope.call(f)
                line!(f, word)
                body.call(f, check(@kern.zr_module_define(outer, name, nested)))
              end
            end
          end

          def singleton_class_body(node, s)
            target = code(node.target, s)
            word = line_word(node, s)
            body = body_in(node, s, k::KIND_SCLASS, 0)
            lambda do |f|
              v = target.call(f)
              line!(f, word)
              body.call(f, check(@kern.zr_singleton_class(v)))
            end
          end

          # The code that runs a class body in `klass` (its second argument),
          # in a frame of its own. Its body compiles when it first runs.
          def body_in(node, s, kind, name)
            kind = k::KIND_HIDDEN if s.internal?
            # A `class << self` body is inside its scope (`Lower#body`): a
            # `return` there leaves the method around it.
            parent = kind == k::KIND_SCLASS ? s.meta : 0
            open = open?(node, :class, s.unit)
            m = meta(node, s.unit, kind, name: name, parent: parent, locals: node.locals, open: open)
            inner = scope(node, s.unit, :class, m, scopes: [node.locals], homes: [], open: open)
            # The body compiles at its first run.
            run = nil #: untyped
            lambda do |f, klass|
              run ||= class_code(node, inner)
              check(enter(inner, klass, @kern.zr_cref_push(klass, f.cref), @qnil) { |c| run.call(c) })
            end
          end

          def class_code(node, s)
            body = code(node.body, s)
            jumps = jumps?(node.body)
            lambda do |f|
              run_body(s, f, jumps, node) do
                opened(s, f, :class)
                body.call(f)
              end
            end
          end

          # --- files ---

          # The toplevel function of unit `index` of the program `units`.
          def unit_fn(units, index)
            unit = units.fetch(index)
            @fns[unit] ||= @host.callable(lambda do
              internal = unit.internal ? true : false
              traced = @traced && !internal && !units.equal?(@eval_files.loader.units)
              toplevel(unit, Unit.new(Paths.shown(unit.file), internal, units, unit.node_ids, false, unit.hidden ? true : false, nil, traced),
                       k::KIND_TOP)
            end)
          end

          # The toplevel of a required file: a unit of the program (an index),
          # a unit of eval support (`EvalSupport#units`), or the compiler,
          # which is the host's eval support.
          def entry_in(units, unit)
            case unit
            when Integer then unit_fn(units, unit)
            when [:eval]
              @eval_entry ||= @host.callable(lambda do
                eval_support!
                @qnil
              end)
            else unit_fn(@eval_files.loader.units, unit.last)
            end
          end

          def require_unit(node, s)
            shown = Paths.shown(node.path || node.feature.to_s)
            bytes = @host.bytes(shown.b)
            word = line_word(node, s)
            unless node.unit
              return lambda do |f|
                line!(f, word)
                check(@kern.zr_load_error(bytes, shown.bytesize))
              end
            end

            units = s.unit.units
            kind = REQUIRE_KINDS.fetch(node.kind)
            lambda do |f|
              line!(f, word)
              fn = entry_in(units, node.unit)
              check(@kern.zr_require(@kern.zr_str_new(bytes, shown.bytesize), fn, kind))
            end
          end

          def autoload_unit(node, s)
            word = line_word(node, s)
            recv = receiver(node.recv, s)
            shown = Paths.shown(node.path.to_s)
            name = id(node.name)
            key = if node.declared then :declared
                  elsif node.unit then :require
                  else :computed
                  end
            kind = REQUIRE_KINDS.fetch(key)
            units = s.unit.units
            lambda do |f|
              line!(f, word)
              target = @host.pin(recv.call(f))
              feature = @host.pin(string(node.feature))
              path = string(shown)
              fn = node.unit ? entry_in(units, node.unit) : 0
              check(@kern.zr_autoload(target, name, feature, fn, f.cref, kind, path))
            end
          end
        end
      end
    end
  end
end
