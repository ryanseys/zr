# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # The code of assignments to more than a local, as
        # `Lower::Function::Targets` emits it: a multiple assignment, whose
        # targets' receivers and arguments are staged first, and the
        # op-assigns of an index and an attribute.
        module Assign
          # @type instance: Walk
          # The ivars of Walk that this module reads (walk.rb):
          # @rbs @host: Host
          # @rbs @kern: untyped
          # @rbs @qnil: Integer
          # @rbs @basic_klass: Integer

          # The staged parts of a multiple assignment with none.
          UNSTAGED = begin
            none = {} #: Hash[untyped, untyped]
            none.compare_by_identity.freeze
          end

          private

          def multi_assign(node, s)
            stage = stager(node.target, s)
            return spread_assign(node, s, stage) if spread_assign?(node)

            value = code(node.value, s)
            assign = multi(node.target, s)
            lambda do |f|
              prepared = stage&.call(f)
              v = value.call(f)
              assign.call(f, v, prepared || UNSTAGED)
              v
            end
          end

          # The code that stages a multiple assignment's send targets'
          # receivers and arguments, and its constant targets' scopes, before
          # the right-hand side, in ruby's order (`Targets#prepare`). It
          # returns them by target, or it is nil when no target has any.
          def stager(target, s)
            steps = staging(target, s)
            return if steps.empty?

            lambda do |f|
              prepared = {} #: Hash[untyped, untyped]
              prepared.compare_by_identity
              steps.each { |step| step.call(f, prepared) }
              prepared
            end
          end

          #: (Hir::MultiTarget target, Scope s) -> Array[^(Frame, Hash[untyped, untyped]) -> untyped]
          def staging(target, s)
            none = [] #: Array[^(Frame, Hash[untyped, untyped]) -> untyped]
            (target.lefts + [target.rest] + target.rights).flat_map do |t|
              case t
              when Hir::Send
                recv = receiver(t.recv, s)
                args, splat = arguments(t.args, s)
                step = lambda do |f, prepared|
                  r = @host.pin(recv.call(f))
                  values = splat ? elements(splat.call(f)) : args.map { |a| a.call(f) }
                  prepared[t] = [r, values.each { |v| @host.pin(v) }]
                end
                [step]
              when Hir::ConstWrite
                next none if t.scope.nil? || t.scope == :top

                scope = code(t.scope, s)
                [->(f, prepared) { prepared[t] = @host.pin(scope.call(f)) }]
              when Hir::MultiTarget then staging(t, s)
              else none
              end
            end
          end

          # `a, b = b, a` as a statement makes no Array (`Targets#spread_assign`).
          def spread_assign?(node)
            value = node.value
            !node.taken && value.is_a?(Hir::ArrayLit) && value.elements.none?(Hir::Splat) && node.target.rights.empty?
          end

          def spread_assign(node, s, stage)
            target = node.target
            values = node.value.elements.map { |e| code(e, s) }
            lefts = target.lefts.map { |t| target_store(t, s) }
            rest = target.rest
            rest = nil if rest == :implicit
            rest &&= target_store(rest, s)
            count = lefts.size
            lambda do |f|
              prepared = stage&.call(f) || UNSTAGED
              list = values.map { |v| @host.pin(v.call(f)) }
              count.times { |i| lefts[i].call(f, list.fetch(i, @qnil), prepared) }
              if rest
                tail = list.drop(count)
                slots(f) { rest.call(f, @kern.zr_ary_of(tail.size, argv(f, tail)), prepared) }
              end
              @qnil
            end
          end

          # The code that spreads a Value (an Array, or one made of it) over
          # the targets, and returns the Value.
          #: (Hir::MultiTarget target, Scope s) -> ^(Frame, Integer, Hash[untyped, untyped]) -> Integer
          def multi(target, s)
            lefts = target.lefts.map { |t| target_store(t, s) }
            rest = target.rest && target.rest != :implicit ? target_store(target.rest, s) : nil
            rights = target.rights.map { |t| target_store(t, s) }
            nl = lefts.size
            nr = rights.size
            lambda do |f, v, prepared|
              ary = @host.pin(check(@kern.zr_masgn_ary(v)))
              nl.times { |i| lefts[i].call(f, @kern.zr_ary_at(ary, i), prepared) }
              rest&.call(f, check(@kern.zr_masgn_rest(ary, nl, nr)), prepared)
              nr.times { |i| rights[i].call(f, @kern.zr_masgn_right(ary, nl, nr, i), prepared) }
              v
            end
          end

          # The code that assigns a Value to the target `t`, with the staged
          # parts of its assignment (`stager`).
          #: (untyped t, Scope s) -> ^(Frame, Integer, ?Hash[untyped, untyped]) -> untyped
          def target_store(t, s)
            case t
            when Hir::Assign
              store = local_store(t.name, t.depth, s)
              ->(f, v, _ = nil) { store.call(f, v) }
            when Hir::IvarWrite
              store = ivar_store(t, s)
              ->(f, v, _ = nil) { store.call(f, v) }
            when Hir::GvarWrite
              store = gvar_store(t.name, s, t.shown)
              ->(f, v, _ = nil) { store.call(f, v) }
            when Hir::CvarWrite
              name = id(t.name)
              ->(f, v, _ = nil) { check(@kern.zr_cvar_set(f.cref, name, v)) }
            when Hir::ConstWrite
              scope = scope_class(t.scope, s)
              name = id(t.name)
              lambda do |f, v, prepared = UNSTAGED|
                klass = prepared.fetch(t) { scope.call(f) }
                check(@kern.zr_const_set(klass, name, v))
              end
            when Hir::MultiTarget
              spread = multi(t, s)
              ->(f, v, prepared = UNSTAGED) { spread.call(f, v, prepared) }
            when Hir::Splat then target_store(t.value, s)
            when Hir::Send then send_store(t, s)
            else ->(_, _, _ = nil) { raise Unsupported, "an assignment to a #{t.class}" }
            end
          end

          # The code that assigns a Value through the send `t` (`a.b = v`,
          # `a[i] = v`): with its staged receiver and arguments, or ones it
          # evaluates now.
          def send_store(t, s)
            recv = receiver(t.recv, s)
            args, splat = arguments(t.args, s)
            mode = t.recv && !t.recv.is_a?(Hir::SelfRef) ? 2 : 0
            mode |= Sends::SEND_CORE if core_send?(t.name, s)
            word = line_word(t, s)
            name = id(t.name)
            at = cell(t, :cc, k::CallCache.size * 4)
            entry, globals = Sends::OPT_ENTRIES[t.name] if t.opt && t.using != :owner && !s.unit.traced
            classes = globals&.map { |g| @kern.zr_global(@kern.const_get(g)) }
            safe = t.safe
            lambda do |f, v, prepared = UNSTAGED|
              r, values = prepared.fetch(t) do
                [recv.call(f), splat ? elements(splat.call(f)) : args.map { |a| a.call(f) }]
              end
              next @qnil if safe && r == @qnil

              line!(f, word)
              slots(f) do
                list = values + [v]
                av = argv(f, list)
                if classes && r.nobits?(7) && r > @qnil && classes.include?(Memory.word(r + @basic_klass))
                  check(@kern.public_send(entry, r, name, list.size, av, mode))
                else
                  check(@kern.zr_send_cached(at, r, name, list.size, av, @qnil, mode))
                end
              end
            end
          end

          # An op-assign's read and write are sends as written: through
          # `self` they may call a private method, else they are explicit.
          def op_mode(node) = node.recv.is_a?(Hir::SelfRef) ? 0 : 2

          def index_op_assign(node, s)
            recv = code(node.recv, s)
            args, splat = arguments(node.args, s)
            word = line_word(node, s)
            get = sender(node, s, :[], :get, mode: op_mode(node), using: node.using)
            set = sender(node, s, :[]=, :set, mode: op_mode(node), using: node.using)
            change = op_value(node, s)
            lambda do |f|
              r = recv.call(f)
              values = splat ? elements(splat.call(f)) : args.map { |a| a.call(f) }
              line!(f, word)
              old = get.call(f, r, values)
              v = change.call(f, old) or next old

              line!(f, word)
              set.call(f, r, values + [v])
              v
            end
          end

          def attr_op_assign(node, s)
            recv = code(node.recv, s)
            word = line_word(node, s)
            get = sender(node, s, node.name, :get, mode: op_mode(node), using: node.using)
            set = sender(node, s, :"#{node.name}=", :set, mode: op_mode(node), using: node.using)
            change = op_value(node, s)
            safe = node.safe
            lambda do |f|
              r = recv.call(f)
              next @qnil if safe && r == @qnil

              line!(f, word)
              args = [] #: Array[Integer]
              old = get.call(f, r, args)
              v = change.call(f, old) or next old

              line!(f, word)
              set.call(f, r, [v])
              v
            end
          end

          # The code of an op-assign's new value from the old one, or nil for
          # `||=` and `&&=` that keep the old one.
          def op_value(node, s)
            value = code(node.value, s)
            case node.op
            when :or then ->(f, old) { truthy?(old) ? nil : value.call(f) }
            when :and then ->(f, old) { truthy?(old) ? value.call(f) : nil }
            else
              # The operator is a send of its own (`Targets#op_assign`), with
              # an operator's paths.
              fast = operator(node.op, s, [node.value]) unless node.using == :owner || s.unit.traced
              send = sender(node, s, node.op, :op, using: node.using)
              lambda do |f, old|
                arg = value.call(f)
                fast&.call(old, arg) || send.call(f, old, [arg])
              end
            end
          end
        end
      end
    end
  end
end
