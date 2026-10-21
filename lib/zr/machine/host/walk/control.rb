# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # The code of control flow, as `Lower::Function::Control` and
        # `Regions` emit it. A local jump is a `throw`: to its loop's tags
        # for a `break`, `next` or `redo`, and to the scope's Frame for a
        # def's `return` or a block's `next` (`Frames#run_body` catches it).
        # A throw runs no handler, so it costs no backtrace. A loop or a
        # scope catches only the jumps that its code has.
        module Control
          # @type instance: Walk
          # The ivars of Walk that this module reads (walk.rb):
          # @rbs @host: Host
          # @rbs @kern: untyped
          # @rbs @qnil: Integer
          # @rbs @qundef: Integer
          # @rbs @poll: Integer
          # @rbs @ensure_path: Symbol
          # @rbs @jump_line: Integer?

          private

          def if_node(node, s)
            cond = code(node.cond, s)
            yes = code(node.yes, s)
            no = code(node.no, s)
            ->(f) { truthy?(cond.call(f)) ? yes.call(f) : no.call(f) }
          end

          def and_node(node, s)
            left = code(node.left, s)
            right = code(node.right, s)
            lambda do |f|
              v = left.call(f)
              truthy?(v) ? right.call(f) : v
            end
          end

          def or_node(node, s)
            left = code(node.left, s)
            right = code(node.right, s)
            lambda do |f|
              v = left.call(f)
              truthy?(v) ? v : right.call(f)
            end
          end

          # A `while`: its tags are `[break, next, redo]`, one set for the
          # loop's code, which the innermost run of the loop catches.
          def while_loop(node, s)
            tags = [Object.new, Object.new, Object.new].freeze
            inner = s.looping(tags)
            cond = code(node.cond, inner)
            body = code(node.body, inner)
            jumps = LoopJumps.new(node)
            breaks = jumps.any?(Hir::Break)
            nexts = jumps.any?(Hir::Next)
            redoes = jumps.any?(Hir::Redo)
            pass = body
            pass = ->(f) { catch(tags[1]) { body.call(f) } } if nexts
            pass = redo_pass(tags[2], pass) if redoes
            first = node.body_first
            internal = s.internal?
            run = lambda do |f|
              pass.call(f) if first
              loop do
                taken = holds?(f, cond, nexts && tags[1])
                break if taken == false

                pass.call(f) if taken
                preempt unless internal
              end
              @qnil
            end
            breaks ? ->(f) { catch(tags[0]) { run.call(f) } } : run
          end

          # Whether a loop's condition holds. A `next` in the condition
          # (thrown to `tag`) starts the next pass, as one in the body does:
          # the test is then nil, and the pass does not run.
          def holds?(f, cond, tag)
            return truthy?(cond.call(f)) unless tag

            taken = nil
            catch(tag) { taken = truthy?(cond.call(f)) }
            taken
          end

          # A loop's pass that runs again for each `redo` thrown to `tag`.
          def redo_pass(tag, pass) = ->(f) { redoable(tag) { pass.call(f) } }

          # Runs the block again for each `redo` thrown to `tag`, and returns
          # its value.
          def redoable(tag)
            loop do
              again = true
              value = catch(tag) do
                v = yield
                again = false
                v
              end
              return value unless again
            end
          end

          # The jumps of a loop's own code: the `break`, `next` and `redo`
          # that a nested loop or scope does not take.
          class LoopJumps
            # @rbs @loop: Hir::While

            include Enumerable #[Hir::Node]

            #: (Hir::While loop) -> void
            def initialize(loop)
              @loop = loop
            end

            #: () { (Hir::Node) -> void } -> void
            def each(&)
              visit(@loop.cond, &)
              visit(@loop.body, &)
            end

            private

            def visit(node, &)
              case node
              when Hir::Break, Hir::Next, Hir::Redo then yield node
              when Hir::While, Hir::Def, Hir::Block, Hir::Lambda, Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef then return
              end
              Hir.each_child(node) { |child| visit(child, &) }
            end
          end

          # A safe point of program code, at a def's entry and a loop's back
          # edge (Lower::Function::Control#preempt): when the timer or a
          # signal set the poll word, the kernel runs the scheduler and the
          # traps. The core has none.
          def preempt
            check(@kern.zr_preempt_expired) if Memory.word(@poll) != 0
          end

          # `redo`: a back edge, so a safe point, as the lowering's
          # `redo_body` has.
          def redo_node(s)
            if s.loops.empty?
              return ->(_) { raise Unsupported, "a redo outside a loop or block" } unless s.kind == :block

              tag = s.meta
            else
              tag = s.loops.first[2]
            end
            return ->(_) { jump(nil) { throw tag } } if s.internal?

            lambda do |_|
              preempt
              jump(nil) { throw tag }
            end
          end

          def do_return(node, s)
            value = code(node.value, s)
            word = line_word(node, s)
            line = node.line
            case s.kind
            when :def
              lambda do |f|
                v = value.call(f)
                line!(f, word)
                f.ret_line = line
                jump(line) { throw f, v }
              end
            when :block
              lambda do |f|
                v = value.call(f)
                line!(f, word)
                jump(nil) { throw f, v } if lambda_proc?(f.block_proc)

                check(@kern.zr_return(f.block_proc, v))
              end
            else
              lambda do |f|
                v = value.call(f)
                line!(f, word)
                check(@kern.zr_return_here(v))
              end
            end
          end

          def do_break(node, s)
            value = code(node.value, s)
            unless s.loops.empty?
              tag = s.loops.first[0]
              line = node.line
              return lambda do |f|
                v = value.call(f)
                jump(line) { throw tag, v }
              end
            end
            return ->(_) { raise Unsupported, "a break outside a loop or block" } unless s.kind == :block

            lambda do |f|
              v = value.call(f)
              jump(nil) { throw f, v } if lambda_proc?(f.block_proc)

              check(@kern.zr_break(f.block_proc, v))
            end
          end

          def do_next(node, s)
            value = code(node.value, s)
            if s.loops.empty?
              return lambda do |f|
                v = value.call(f)
                jump(nil) { throw f, v }
              end
            end

            tag = s.loops.first[1]
            line = node.line
            lambda do |f|
              v = value.call(f)
              jump(line) { throw tag, v }
            end
          end

          # Leaves through `throw`, from the jump's instruction on `line`
          # (nil for one with no line of its own, as a block's `next`): an
          # ensure body that the jump runs gives its silent :line event to
          # that line (`Hir::Trace#line_on`), as the lowering's `unwind`
          # does.
          #: (Integer? line) { () -> void } -> void
          def jump(line)
            @jump_line = line
            yield
          end

          def case_node(node, s)
            subject = node.subject && code(node.subject, s)
            clauses = node.clauses.map do |values, body|
              [values.map { |value| when_test(value, node, s, subject) }, code(body, s)]
            end
            otherwise = code(node.else_body, s)
            lambda do |f|
              v = subject&.call(f)
              clauses.each do |tests, body|
                return body.call(f) if tests.any? { |test| test.call(f, v) }
              end
              otherwise.call(f)
            end
          end

          # The code of one `when` value: whether it matches the subject (the
          # second argument), or, with no subject, whether it is true. A
          # `when`'s `===` sees the refinements of its `case`.
          def when_test(value, node, s, subject)
            if value.is_a?(Hir::Splat)
              list = code(value.value, s)
              return ->(f, v) { truthy?(check(@kern.zr_case_any(v, list.call(f), 0))) } if subject

              return ->(f, _) { truthy?(check(@kern.zr_any_truthy(list.call(f)))) }
            end

            pattern = code(value, s)
            return ->(f, _) { truthy?(pattern.call(f)) } unless subject

            eqq = sender(value, s, :===, :eqq, using: node.using)
            return symbol_when(value, s, eqq) if value.is_a?(Hir::Literal) && value.value.is_a?(Symbol)

            ->(f, v) { truthy?(eqq.call(f, pattern.call(f), [v])) }
          end

          # A Symbol `when` value: while Symbol#=== is the runtime's own
          # (GATE_SYM_EQQ, which the core ignores), `:sym === subject` is
          # identity, as `Control#symbol_case` compiles it. Else it sends.
          def symbol_when(value, s, eqq)
            symbol = sym(value.value)
            internal = s.internal?
            gate = @kern::GATE_SYM_EQQ
            lambda do |f, v|
              next v == symbol if internal || (@host.gates & gate).zero?

              truthy?(eqq.call(f, symbol, [v]))
            end
          end

          # `begin`/`rescue`/`else`/`ensure`, as Lower::Function::Regions.
          #
          # An ensure body runs on every exit: inline after the body, with
          # the pending unwind set aside for a raise (`ensured`), and as it is
          # for a local jump (a `throw` out of the region).
          def begin_node(node, s)
            body = rescued(node, s)
            return ->(f) { body.call(f, @kern.zr_errinfo) } unless node.ensure_body

            ensure_body = code(node.ensure_body, s)
            lambda do |f|
              saved = @kern.zr_errinfo
              left = true
              value = begin
                v = body.call(f, saved)
                left = false
                v
              rescue Unwind
                left = false
                on_path(:raise) { ensured(f, ensure_body, saved) }
                raise
              ensure
                on_path(:jump) { ensure_body.call(f) } if left
              end
              on_path(:exit) { ensure_body.call(f) }
              value
            end
          end

          # Runs an ensure body on `path`, as Lower::Function::Regions#run_ensure.
          #: [T] (Symbol path) { () -> T } -> T
          def on_path(path)
            was = @ensure_path
            @ensure_path = path
            begin
              yield
            ensure
              @ensure_path = was
            end
          end

          # The code of a region's body and its rescue clauses, a lambda of
          # the Frame and the `$!` of the region's start.
          def rescued(node, s)
            if node.rescues.empty?
              plain = code(node.else_body ? Hir::Seq.new([node.body, node.else_body].compact, node.line) : node.body, s)
              return ->(f, _) { plain.call(f) }
            end

            body = code(node.body, s)
            other = node.else_body && code(node.else_body, s)
            clauses = node.rescues.map { |clause| rescue_clause(clause, s, node.line) }
            # @type var run: ^(Frame, Integer) -> untyped
            run = lambda do |f, saved|
              begin
                v = body.call(f)
              rescue Unwind
                next rescue_unwind(f, saved, clauses, run)
              end
              other ? other.call(f) : v
            end
          end

          # An unwind out of a region's body: the first clause that matches
          # the exception takes it, else the unwind goes on. A `retry` in
          # the clause runs the region (`run`) again.
          def rescue_unwind(f, saved, clauses, run)
            exc = @kern.zr_rescuable
            raise UNWIND, cause: nil if exc == @qundef

            # As the lowering's: the classes are read with the raise as `$!`,
            # and the code that reads them can raise and rescue, so a miss
            # sets the raise again, and a match takes the exception it saw.
            @kern.zr_errinfo_set(exc)
            _, handler = clauses.find { |matches, _| matches.call(f, exc) }
            unless handler
              @kern.zr_errinfo_set(saved)
              @kern.zr_rescue_miss(exc)
              raise UNWIND, cause: nil
            end

            @kern.zr_rescue_take(exc)
            begin
              handler.call(f, exc)
            rescue RetryJump
              @kern.zr_errinfo_set(saved)
              run.call(f, saved)
            ensure
              @kern.zr_errinfo_set(saved)
            end
          end

          # A rescue clause as `[matches, handler]`: whether it takes the
          # exception, and the code that binds it and runs the clause's body.
          # `:rescue` fires at the clause's first statement (`Regions`). The
          # clause runs in a frame of its own in CRuby, whose caller is the
          # scope at the region's `begin` line (`begun`).
          def rescue_clause(clause, s, begun)
            classes = clause.classes.map do |klass|
              if klass.is_a?(Hir::Splat)
                list = code(klass.value, s)
                ->(f, exc) { truthy?(check(@kern.zr_exc_match_any(exc, list.call(f)))) }
              else
                value = code(klass, s)
                ->(f, exc) { truthy?(check(@kern.zr_exc_match(exc, value.call(f)))) }
              end
            end
            matches = if classes.empty?
                        ->(_, exc) { truthy?(check(@kern.zr_exc_match(exc, @kern.zr_global(@kern::G_STANDARD_ERROR)))) }
                      else
                        ->(f, exc) { classes.any? { |test| test.call(f, exc) } }
                      end
            line = (clause.body || clause).line
            bind = clause.target && target_store(clause.target, s)
            body = code(clause.body, s.rescuing(begun))
            handler = lambda do |f, exc|
              check(@kern.zr_trace_rescue(line))
              bind&.call(f, exc)
              body.call(f)
            end
            [matches, handler]
          end

          # The ensure body on an unwind: the pending unwind is set aside
          # while it runs, and restored after.
          #
          # If the ensure body itself leaves (a raise or a jump), `$!` goes
          # back to `saved`, its value when the region began.
          def ensured(f, ensure_body, saved)
            prev = @kern.zr_errinfo
            slots(f) do
              out = f.stack.take(24)
              v = @kern.zr_ensure_take(out)
              done = false
              begin
                ensure_body.call(f)
                done = true
              ensure
                @kern.zr_errinfo_set(saved) unless done
              end
              @kern.zr_errinfo_set(prev)
              @kern.zr_signal_restore(v, out)
            end
          end

          # `defined?`, as Lower::Function::Defined: the description, or nil.
          # A form whose test can raise runs in a guard, so a raise is nil.
          DEFINED_NAMES = {
            local: "local-variable", ivar: "instance-variable", gvar: "global-variable", global: "global-variable",
            backref: "global-variable", attrasgn: "method", cvar: "class variable",
            const: "constant", method: "method", yield: "yield", super: "super", self: "self", nil: "nil",
            true: "true", false: "false", assignment: "assignment", expression: "expression", list: "expression"
          }.freeze
          TESTED = %i[ivar gvar backref cvar const method attrasgn yield super list].freeze
          UNGUARDED = %i[ivar gvar backref yield].freeze

          def defined(node, s)
            name = DEFINED_NAMES.fetch(node.kind)
            ptr = @host.bytes(name)
            answer = ->(_) { @kern.zr_str_frozen(ptr, name.bytesize) }
            return answer unless TESTED.include?(node.kind)

            test = defined_test(node, s)
            guarded = !UNGUARDED.include?(node.kind)
            lambda do |f|
              ok = guarded ? guarded { test.call(f) } : test.call(f)
              ok ? answer.call(f) : @qnil
            end
          end

          # The code of whether the target of a `defined?` is defined.
          def defined_test(node, s)
            target = node.target
            case node.kind
            when :ivar
              name = id(ivar(target, s))
              ->(f) { truthy?(check(@kern.zr_ivar_defined(f.self_, name))) }
            when :gvar
              name = id(target)
              ->(_) { truthy?(@kern.zr_gvar_defined(name)) }
            when :backref
              value = code(target, s)
              ->(f) { value.call(f) != @qnil }
            when :cvar
              name = id(target)
              word = line_word(node, s)
              lambda do |f|
                line!(f, word)
                truthy?(check(@kern.zr_cvar_defined(f.cref, name)))
              end
            when :const then const_defined(target, s)
            when :method, :attrasgn then method_defined(target, s)
            when :list
              parts = target.map { |part| part_defined(part, s) }
              ->(f) { parts.all? { |part| part.call(f) } }
            when :yield then ->(f) { f.blk != @qnil }
            when :super then ->(f) { truthy?(@kern.zr_super_defined(f.rec)) }
            else ->(_) { true }
            end
          end

          # Whether an expression used as a receiver or argument is itself
          # defined: a name by its form, anything else is.
          def part_defined(node, s)
            case node
            when Hir::Send then method_defined(node, s)
            when Hir::Splat then part_defined(node.value, s)
            when Hir::ArrayLit
              parts = node.elements.map { |e| part_defined(e, s) }
              ->(f) { parts.all? { |part| part.call(f) } }
            when Hir::HashLit
              parts = node.pairs.compact.map { |p| part_defined(p.is_a?(Hir::HashSplat) ? p.value : p, s) }
              ->(f) { parts.all? { |part| part.call(f) } }
            when Hir::ConstRead then const_defined(node, s)
            when Hir::IvarRead then defined_test(Hir::Defined.new(:ivar, node.name, node.line), s)
            when Hir::GvarRead then defined_test(Hir::Defined.new(:gvar, node.name, node.line), s)
            when Hir::CvarRead then defined_test(Hir::Defined.new(:cvar, node.name, node.line), s)
            else ->(_) { true }
            end
          end

          # A constant, as the lowering's: the scope of `A::B` is tested
          # first (compile.c's defined_expr), so an undefined `A` is nil and
          # never reaches const_missing.
          def const_defined(read, s)
            name = id(read.name)
            return ->(f) { truthy?(@kern.zr_const_defined(f.cref, name)) } if read.scope.nil?
            return ->(_) { truthy?(@kern.zr_const_defined_at(@kern.zr_global(@kern::G_OBJECT), name)) } if read.scope == :top

            outer = part_defined(read.scope, s)
            scope = code(read.scope, s)
            ->(f) { outer.call(f) && truthy?(@kern.zr_const_defined_at(scope.call(f), name)) }
          end

          # A method: its arguments must be defined, then its receiver,
          # then the receiver's class answers. As in the lowering
          # (`Lower::Function::Defined#method_defined`), a receiver is
          # evaluated once. Any receiver, `self` too, makes the call
          # explicit.
          def method_defined(send, s)
            test = method_test(send, s)
            ->(f) { !test.call(f).nil? }
          end

          # The test of `send`: a lambda that gives nil when it is not
          # defined, else the value of its receiver (self when it has none).
          def method_test(send, s)
            parts = send.args.compact.map { |part| part_defined(part, s) }
            name = id(send.name)
            value = send.recv && defined_receiver(send.recv, s)
            lambda do |f|
              next unless parts.all? { |part| part.call(f) }
              next (f.self_ if truthy?(@kern.zr_method_defined(f.self_, name, false))) unless value

              r = value.call(f)
              r if r && truthy?(@kern.zr_method_defined(r, name, true))
            end
          end

          # The value of the receiver `node` when it is defined, else nil.
          # A call on a receiver of its own runs once, on the receiver that
          # its own test evaluated.
          def defined_receiver(node, s)
            kept = node.is_a?(Hir::Send) && node.recv && !node.recv.is_a?(Hir::SelfRef) && !node.safe
            unless kept
              test = part_defined(node, s)
              value = code(node, s)
              return ->(f) { value.call(f) if test.call(f) }
            end

            test = method_test(node, s)
            # The send reads its receiver first, before an argument can
            # come back here, so the newest entry is its own.
            held = [] #: Array[Integer]
            call = send_node(node, s, ->(_) { held.last })
            lambda do |f|
              r = test.call(f) or next

              held.push(r)
              begin
                call.call(f)
              ensure
                held.pop
              end
            end
          end

          # The block's value, or nil if it raised (the raise is dropped).
          def guarded
            saved = @kern.zr_errinfo
            yield
          rescue Unwind
            @kern.zr_rescuable
            @kern.zr_rescue_enter
            @kern.zr_errinfo_set(saved)
            nil
          end
        end
      end
    end
  end
end
