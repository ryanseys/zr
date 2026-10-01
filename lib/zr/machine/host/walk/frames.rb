# frozen_string_literal: true

module Zr
  module Machine
    class Host
      class Walk
        # What the code of a scope knows when it is compiled: its HIR node,
        # its unit, the Hir::Def it is in (`def_node`), its kind (:main, :def,
        # :block, :class or :eval), the locals of each lexical scope out to
        # the def or toplevel (`scopes`, innermost first), and the HIR node
        # of each (`homes`: a block reads from them how often each outer
        # local is bound). Its FrameMeta, its parameters, whether its locals
        # are in an Env (`open`), and the first `line` word of its record.
        # Its record holds `values` Values: the Env, or each local, which
        # starts as `blank` gives it. `names` is the id table of its locals,
        # which its Env holds.
        # `loops` are the tags of the loops around the code being compiled,
        # innermost first: a `break`, `next` or `redo` throws one.
        Scope = Data.define(:node, :unit, :def_node, :kind, :scopes, :homes, :meta, :params, :open, :line, :values, :blank, :names,
                            :loops) do
          def locals = scopes.first
          def internal? = unit.internal

          # The scope inside a loop with `tags`: `[break, next, redo]`.
          def looping(tags) = with(loops: [tags, *loops])
        end

        # One run of a scope: its record in the slot area, its Env (nil
        # when its locals are in the record), self, cref, block, the Proc
        # of a block's run, the Env around a block (`outer`), and the host
        # Stack it runs on. `opened` and `ret_line` are for its TracePoint
        # events. A `return` throws to the Frame of its scope.
        Frame = Struct.new(:rec, :env, :self_, :cref, :blk, :proc, :outer, :stack, :opened, :ret_line)

        # The frames of the walker's code. Each run of a scope has a record
        # in the slot area, linked from the task, and a heap Env for its
        # locals when its scope keeps them there. So the collector, a
        # Binding and a backtrace see the frames as they see a binary's. A
        # Value that the code holds between kernel calls is pinned
        # (`Host#pin`) until the statement that made it ends.
        module Frames
          # The most frames that a ruby stack holds here: about 39,000 fit
          # in `zr-dev host`'s, a thread's or a fiber's. Past this a call
          # overflows as past the slots, and the margin keeps room for the
          # error's report, as STACK_MARGIN does.
          DEPTH = 20_000

          PARAM_KINDS = %i[req opt rest keyreq key keyrest block nokey].each_with_index.to_h.freeze

          private

          # The Scope of `node`, whose FrameMeta is `meta`.
          def scope(node, unit, kind, meta, scopes:, homes:, def_node: nil, params: nil, open: true)
            m = k::FrameMeta
            values = open ? 1 : scopes.first.size
            Scope.new(node: node, unit: unit, def_node: def_node, kind: kind, scopes: scopes, homes: homes, meta: meta,
                      params: params, open: open, line: m.line(meta) | (m.node(meta) << 32), values: values,
                      blank: Array.new([values, 1].max, @qnil).freeze, names: id_table(scopes.first), loops: [])
          end

          # The FrameMeta of the scope `node`.
          #
          # `ruby` is a core method that CRuby writes in Ruby: its signature
          # shows as ruby's. `cover` is the def-site entry of a method that
          # Coverage measures.
          def meta(node, unit, kind, name: 0, parent: 0, params: nil, locals: [], fn: 0, open: true, ruby: false, cover: nil)
            @metas[node] ||= begin
              m = k::FrameMeta
              addr = Memory.zeroed(m.layout_size, 8)
              file = unit.file.to_s
              m.set_name(addr, name.is_a?(Integer) ? name : id(name))
              m.set_file(addr, @host.bytes(file))
              m.set_file_len(addr, unit.internal ? 0 : file.bytesize)
              m.set_kind(addr, kind)
              m.set_line(addr, line_of(node))
              m.set_parent(addr, parent)
              m.set_arity(addr, params ? params.arity : 0)
              m.set_params(addr, params ? param_table(params) : 0)
              m.set_fn(addr, fn)
              m.set_locals(addr, id_table(locals))
              m.set_env(addr, open ? 1 : 0)
              m.set_node(addr, unit.node_ids&.[](node) || 0)
              m.set_hidden(addr, unit.hidden ? 1 : 0)
              m.set_ruby(addr, ruby ? 1 : 0)
              m.set_cover(addr, cover ? cover + 1 : 0)
              m.set_box(addr, m.box(unit.root)) if unit.root
              addr
            end
          end

          # `Method#parameters` as a table: the count, then a kind and a name
          # id (0 for none) for each (`Lower#param_table`).
          def param_table(params)
            rows = params.rows.flat_map { |kind, name| [PARAM_KINDS.fetch(kind), name.nil? ? 0 : id(name)] }
            table([params.rows.size, *rows])
          end

          # A scope's first line: its node's, or 1 for a file.
          def line_of(node) = node.respond_to?(:line) ? node.line || 1 : 1

          # Whether the scope `node` keeps its locals in an Env, as the
          # lowering decides (`Lower::Function`, `@has_env`): a main or eval
          # scope, or one that holds a block or opens its locals (`binding`,
          # `eval`, `local_variables`). In a traced program, a hook can read a
          # Binding of any def, block or file, and only an Env gives one.
          def open?(node, kind, unit, params = nil)
            return true if %i[main eval].include?(kind)
            return true if unit.traced && %i[def block top].include?(kind)

            defaults = params ? params.optional.map(&:last) + params.keywords.filter_map(&:last) : []
            [node.body, *defaults].any? { |b| Hir::Locals.holds_block?(b) || Hir::Locals.opens_locals?(b) }
          end

          # Runs the block in a new frame of the scope `s`: a record in the
          # slot area linked from the task, and an Env for the scope's
          # locals if it is open (an eval's frame gets its `env` from the
          # kernel). The block gets the Frame. Returns the block's Value, or
          # QUNDEF for a pending unwind that no handler took.
          def enter(s, self_, cref, blk, proc: nil, outer: @qnil, entry: 0, defined: @qnil, env: nil)
            t = task
            stack = @host.stack
            top = stack.top
            depth = stack.depth
            blank = s.blank
            rec = stack.take(@record + (8 * blank.size))
            begin
              return k.zr_stack_overflow if rec < @task_limit.call(t) || depth >= DEPTH

              stack.depth = depth + 1
              prev = @task_top.call(t)
              Memory.set_words(rec, [prev, s.meta, s.line, self_, cref, blk, entry, defined, 0, s.values, @qnil])
              Memory.set_words(rec + @record, blank)
              @task_refine.call(t, @qnil)
              @task_set_top.call(t, rec)
              begin
                if s.open
                  env ||= k.zr_env_new(outer, s.locals.size, s.names)
                  Memory.set_word(rec + @record, env)
                end
                f = Frame.new(rec, env, self_, cref, blk, proc, outer, stack)
                pins = stack.pins
                mark = pins.size
                result = yield f
                drop_pins(pins, mark)
                @host.pin(result)
              ensure
                @task_set_top.call(t, prev)
                stack.depth = depth
              end
            ensure
              stack.top = top
            end
          end

          # Runs a scope's body: a `return` in it (or a `break`, `next` or
          # `redo` that leaves the scope) throws to the Frame, which this
          # catches when the body has one (`jumps`). A pending unwind that
          # leaves the body makes the frame return QUNDEF, after a `return`
          # from a block is caught.
          #
          # A scope that fired its opening event fires its closing event as
          # it leaves, with its value, or QUNDEF while it unwinds.
          def run_body(s, f, jumps, node = nil)
            r = begin
              jumps ? catch(f) { yield } : yield
            rescue Unwind
              caught = k.zr_catch_return(f.rec)
              # A `return` in an eval string goes to the main scope or to the
              # def that runs the eval (`zr_return_here`).
              here = s.kind == :main || (s.kind == :def && s.def_node&.evals)
              caught == @qundef && here ? k.zr_catch_return_here : caught
            end
            f.opened ? closed(f, node, r) : r
          end

          # Whether the code of a scope's `body` throws to its Frame: a
          # `return`, or a `break`, `next` or `redo` outside the loops of
          # the scope. A nested scope's jumps are its own.
          def jumps?(body) = Jumps.new(body).any? { |node| !node.is_a?(Hir::Redo) }

          # Whether a `redo` in a block's body restarts the block.
          def redoes?(body) = Jumps.new(body).any?(Hir::Redo)

          # The jumps of a scope's body that leave it, as `jumps?` finds
          # them.
          class Jumps
            include Enumerable

            def initialize(body) = @body = body

            def each(&) = visit(@body, false, &)

            private

            def visit(node, looped, &)
              case node
              when Hir::Return then yield node
              when Hir::Break, Hir::Next, Hir::Redo then yield node unless looped
              when Hir::While
                visit(node.cond, true, &)
                visit(node.body, true, &)
                return
              when Hir::Def then return visit(node.receiver, looped, &)
              when Hir::Block, Hir::Lambda, Hir::ModuleDef then return
              when Hir::ClassDef then return [node.scope, node.superclass].each { |part| visit(part, looped, &) }
              when Hir::SingletonClassDef then return visit(node.target, looped, &)
              end
              Hir.each_child(node) { |child| visit(child, looped, &) if child.is_a?(Hir::Node) || child.is_a?(Array) }
            end
          end

          # --- TracePoint (Lower::Function::Tracing) ---

          EVENTS = { line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, b_call: 0x100, b_return: 0x200 }.freeze
          OPENING = { def: :call, block: :b_call, class: :class }.freeze
          CLOSING = { def: :return, block: :b_return, class: :end }.freeze

          # Whether an enabled TracePoint listens for `event`.
          def armed?(event) = Memory.word(@trace_events).anybits?(EVENTS.fetch(event))

          def fire(event)
            check(k.zr_trace_fire(EVENTS.fetch(event), @qnil)) if armed?(event)
          end

          # The scope's opening event, once its parameters are bound.
          def opened(s, f, kind)
            return unless s.unit.traced

            f.opened = kind
            fire(OPENING.fetch(kind))
          end

          # The closing event of a scope that leaves with `v`: at the line of
          # its `return`, else at its `end`; an unwind keeps the line where
          # it raised. Returns `v`, or QUNDEF if a hook raised.
          def closed(f, node, v)
            event = CLOSING.fetch(f.opened)
            return v unless armed?(event)

            line = f.ret_line || node.end_line
            line!(f, line) unless v == @qundef || line.nil?
            k.zr_trace_fire(EVENTS.fetch(event), v)
          end

          # Sets the frame's line word, as the lowering's `at_node` does
          # before a kernel call that can raise: the line, and the prism node
          # id above it, which error_highlight reads.
          def line!(f, word) = Memory.set_word(f.rec + @line_at, word)

          # The line word of `node` in the scope `s` (`line!`).
          def line_word(node, s) = (node.line || 0) | ((s.unit.node_ids&.[](node) || 0) << 32)
        end
      end
    end
  end
end
