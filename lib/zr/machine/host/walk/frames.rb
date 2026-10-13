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
        # `rescues` are the `begin` lines of the rescue clauses around it,
        # outermost first (`Lower#rescues_table`).
        #
        # The fields of Scope and Frame are typed in
        # sig/zr/machine/host/walk/frames.rbs, the methods here.
        # @rbs skip
        Scope = Data.define(:node, :unit, :def_node, :kind, :scopes, :homes, :meta, :params, :open, :line, :values, :blank, :names,
                            :loops, :rescues)

        class Scope
          #: () -> Array[Symbol]
          def locals = scopes.first

          #: () -> bool
          def internal? = unit.internal

          # The scope inside a loop with `tags`: `[break, next, redo]`.
          #: (untyped tags) -> Scope
          def looping(tags) = with(loops: [tags, *loops])

          # The scope inside a rescue clause of the region at `line`.
          #: (Integer line) -> Scope
          def rescuing(line) = with(rescues: [*rescues, line])
        end

        # One run of a scope: its record in the slot area, its Env (nil
        # when its locals are in the record), self, cref, block, the Proc
        # of a block's run, the Env around a block (`outer`), and the host
        # Stack it runs on. `opened` and `ret_line` are for its TracePoint
        # events. A `return` throws to the Frame of its scope.
        # @rbs skip
        Frame = Struct.new(:rec, :env, :self_, :cref, :blk, :proc, :outer, :stack, :opened, :ret_line)

        # The frames of the walker's code. Each run of a scope has a record
        # in the slot area, linked from the task, and a heap Env for its
        # locals when its scope keeps them there. So the collector, a
        # Binding and a backtrace see the frames as they see a binary's. A
        # Value that the code holds between kernel calls is pinned
        # (`Host#pin`) until the statement that made it ends.
        module Frames
          # @type instance: Walk
          # The ivars of Walk that this module reads (walk.rb):
          # @rbs @host: Host
          # @rbs @kern: untyped
          # @rbs @qnil: Integer
          # @rbs @qundef: Integer
          # @rbs @metas: Hash[untyped, Integer]
          # @rbs @rescues: Hash[Integer, Hash[Integer, Array[Integer]]]
          # @rbs @record: Integer
          # @rbs @line_at: Integer
          # @rbs @trace_events: Integer
          # @rbs @task_top: ^(Integer) -> untyped
          # @rbs @task_set_top: ^(Integer, untyped) -> untyped
          # @rbs @task_limit: ^(Integer) -> untyped
          # @rbs @task_refine: ^(Integer, untyped) -> untyped

          # The most frames that a ruby stack holds here: about 39,000 fit
          # in `zr-dev host`'s, a thread's or a fiber's. Past this a call
          # overflows as past the slots, and the margin keeps room for the
          # error's report, as STACK_MARGIN does.
          DEPTH = 20_000

          PARAM_KINDS = %i[req opt rest keyreq key keyrest block nokey noblock].each_with_index.to_h.freeze

          private

          # The Scope of `node`, whose FrameMeta is `meta`.
          # @rbs node: untyped
          # @rbs unit: Unit
          # @rbs kind: Symbol
          # @rbs meta: Integer
          # @rbs scopes: Array[Array[Symbol]]
          # @rbs homes: Array[untyped]
          # @rbs def_node: Hir::Def?
          # @rbs params: Hir::Params?
          # @rbs open: bool
          # @rbs return: Scope
          def scope(node, unit, kind, meta, scopes:, homes:, def_node: nil, params: nil, open: true)
            m = k::FrameMeta
            values = open ? 1 : scopes.first.size
            loops = [] #: Array[untyped]
            rescues = [] #: Array[Integer]
            Scope.new(node: node, unit: unit, def_node: def_node, kind: kind, scopes: scopes, homes: homes, meta: meta,
                      params: params, open: open, line: m[meta].line | (m[meta].node << 32), values: values,
                      blank: Array.new([values, 1].max, @qnil).freeze, names: id_table(scopes.first), loops: loops, rescues: rescues)
          end

          # The FrameMeta of the scope `node`.
          #
          # `ruby` is a core method that CRuby writes in Ruby: its signature
          # shows as ruby's. `cover` is the def-site entry of a method that
          # Coverage measures.
          # @rbs node: untyped
          # @rbs unit: Unit
          # @rbs kind: Integer
          # @rbs name: Integer | Symbol
          # @rbs parent: Integer
          # @rbs params: Hir::Params?
          # @rbs locals: Array[Symbol]
          # @rbs fn: Integer
          # @rbs open: bool
          # @rbs ruby: bool
          # @rbs cover: Integer?
          # @rbs owns_backref: bool
          # @rbs reads_backref: bool
          # @rbs frameless: bool
          # @rbs return: Integer
          def meta(node, unit, kind, name: 0, parent: 0, params: nil, locals: [], fn: 0, open: true, ruby: false, cover: nil,
                   owns_backref: false, reads_backref: false, frameless: false)
            @metas[node] ||= begin
              m = k::FrameMeta
              addr = Memory.zeroed(m.size, 8)
              file = unit.file.to_s
              row = m[addr]
              row.name = name.is_a?(Integer) ? name : id(name)
              row.file = @host.bytes(file)
              row.file_len = unit.internal ? 0 : file.bytesize
              row.kind = kind
              row.line = line_of(node)
              row.end_line = node.respond_to?(:end_line) ? node.end_line.to_i : 0
              row.parent = parent
              row.arity = params ? params.arity : 0
              row.params = params ? param_table(params) : 0
              row.fn = fn
              row.locals = id_table(locals)
              row.env = open ? 1 : 0
              row.node = unit.node_ids&.[](node) || 0
              row.hidden = unit.hidden ? 1 : 0
              row.ruby = ruby ? 1 : 0
              row.cover = cover ? cover + 1 : 0
              row.owns_backref = owns_backref ? 1 : 0
              row.reads_backref = reads_backref ? 1 : 0
              # Where a def's or block's code starts and ends (`Lower#meta`'s
              # span), which #source_range and #syntax_tree read.
              own = node if node.is_a?(Hir::Def) || node.is_a?(Hir::Block)
              span = own&.span
              if span
                row.span_line = span[0]
                row.column = span[1]
                row.end_column = span[3]
              end
              row.frameless = frameless ? 1 : 0
              row.evaled = unit.evaled ? 1 : 0
              # The `using` entry of a def or block, plus one, which
              # super_method searches with (`Lower#meta`'s `using`).
              using = own&.using
              row.using = using ? using + 1 : 0
              row.box = m[unit.root].box if unit.root
              addr
            end
          end

          # `Method#parameters` as a table: the count, then a kind and a name
          # id (0 for none) for each (`Lower#param_table`).
          #: (Hir::Params params) -> Integer
          def param_table(params)
            rows = params.rows.flat_map { |kind, name| [PARAM_KINDS.fetch(kind), name.nil? ? 0 : id(name)] }
            table([params.rows.size, *rows])
          end

          # A scope's first line: its node's, or 1 for a file.
          #: (untyped node) -> Integer
          def line_of(node) = node.respond_to?(:line) ? node.line || 1 : 1

          # Whether the scope `node` keeps its locals in an Env, as the
          # lowering decides (`Lower::Function`, `@has_env`): a main or eval
          # scope, or one that holds a block or opens its locals (`binding`,
          # `eval`, `local_variables`). In a traced program, a hook can read a
          # Binding of any def, block or file, and only an Env gives one.
          #: (untyped node, Symbol kind, Unit unit, ?Hir::Params? params) -> bool
          def open?(node, kind, unit, params = nil)
            return true if %i[main eval].include?(kind)
            # A traced program's hooks read a Binding of any frame, as the
            # lowering's `@has_env` gives one.
            return true if unit.traced && %i[def block top class].include?(kind)

            defaults = [] #: Array[Hir::node?]
            defaults = params.optional.map(&:last) + params.keywords.filter_map(&:last) if params
            [node.body, *defaults].any? { |b| Hir::Locals.holds_block?(b) || Hir::Locals.opens_locals?(b, computed: !unit.internal) }
          end

          # Runs the block in a new frame of the scope `s`: a record in the
          # slot area linked from the task, and an Env for the scope's
          # locals if it is open (an eval's frame gets its `env` from the
          # kernel). The block gets the Frame. Returns the block's Value, or
          # QUNDEF for a pending unwind that no handler took.
          # @rbs s: Scope
          # @rbs self_: Integer
          # @rbs cref: Integer
          # @rbs blk: Integer
          # @rbs proc: Integer?
          # @rbs outer: Integer
          # @rbs entry: Integer
          # @rbs defined: Integer
          # @rbs env: Integer?
          # @rbs &: (Frame) -> Integer
          # @rbs return: Integer
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
          #: (Scope s, Frame f, bool jumps, ?untyped node) { () -> Integer } -> Integer
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
          #: (untyped body) -> bool
          def jumps?(body) = Jumps.new(body).any? { |node| !node.is_a?(Hir::Redo) }

          # Whether a `redo` in a block's body restarts the block.
          #: (untyped body) -> bool
          def redoes?(body) = Jumps.new(body).any?(Hir::Redo)

          # The jumps of a scope's body that leave it, as `jumps?` finds
          # them.
          class Jumps
            # @rbs @body: untyped

            include Enumerable #[Hir::Node]

            #: (untyped body) -> void
            def initialize(body)
              @body = body
            end

            #: () { (Hir::Node) -> void } -> void
            def each(&) = visit(@body, false, &)

            private

            #: (untyped node, bool looped) { (Hir::Node) -> void } -> void
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

          EVENTS = { line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, b_call: 0x100, b_return: 0x200 }.freeze #: Hash[Symbol, Integer]
          OPENING = { def: :call, block: :b_call, class: :class }.freeze #: Hash[Symbol, Symbol]
          CLOSING = { def: :return, block: :b_return, class: :end }.freeze #: Hash[Symbol, Symbol]
          LAMBDA = 1 << 32

          # Whether an enabled TracePoint listens for `event`.
          #: (Symbol event) -> bool
          def armed?(event) = Memory.word(@trace_events).anybits?(EVENTS.fetch(event))

          #: (Symbol event) -> void
          def fire(event)
            check(k.zr_trace_fire(EVENTS.fetch(event), @qnil)) if armed?(event)
          end

          # The scope's opening event, once its parameters are bound, with
          # the frame on the line of its body's first statement.
          #: (Scope s, Frame f, Symbol kind) -> void
          def opened(s, f, kind)
            return unless s.unit.traced

            f.opened = kind
            event = OPENING.fetch(kind)
            check(k.zr_trace_open(event_word(f, event), Hir::Trace.first_line(s.node.body) || 0)) if armed?(event)
          end

          # The bit of `event` of frame `f`: a block's :b_call and :b_return
          # also carry whether the block runs as a lambda, as the lowering's
          # `event_word` gives them (the kernel's TRACE_LAMBDA).
          #: (Frame f, Symbol event) -> Integer
          def event_word(f, event)
            bit = EVENTS.fetch(event)
            f.opened == :block && f.proc && lambda_proc?(f.proc) ? bit | LAMBDA : bit
          end

          # The closing event of a scope that leaves with `v`: at the line of
          # its `return`, else at its `end`; an unwind keeps the line where
          # it raised. Returns `v`, or QUNDEF if a hook raised.
          #: (Frame f, untyped node, Integer v) -> Integer
          def closed(f, node, v)
            event = CLOSING.fetch(f.opened)
            return v unless armed?(event)

            line = f.ret_line || node.end_line
            line!(f, line) unless v == @qundef || line.nil?
            k.zr_trace_fire(event_word(f, event), v)
          end

          # Sets the frame's line word, as the lowering's `at_node` does
          # before a kernel call that can raise: the line, and the prism node
          # id above it, which error_highlight reads.
          #: (Frame f, Integer word) -> void
          def line!(f, word) = Memory.set_word(f.rec + @line_at, word)

          # The line word of `node` in the scope `s` (`line!`). A node in a
          # rescue clause goes in its scope's rescues table as well.
          #: (untyped node, Scope s) -> Integer
          def line_word(node, s)
            id = s.unit.node_ids&.[](node) || 0
            add_rescue_row(s, id) unless id.zero? || s.rescues.empty? || s.internal? || s.unit.hidden
            (node.line || 0) | (id << 32)
          end

          # Adds the node `id` to the rescues table of the scope `s`, with
          # the `begin` lines of the clauses around it, innermost first, and
          # writes the table again (`Lower#rescues_table`).
          #: (Scope s, Integer id) -> void
          def add_rescue_row(s, id)
            rows = (@rescues[s.meta] ||= {})
            return if rows.key?(id)

            rows[id] = s.rescues.reverse
            words = rows.sort.flat_map { |node, lines| lines.map { |line| (node << 32) | (line & 0xffffffff) } }
            k::FrameMeta[s.meta].rescues = table([words.size, *words])
          end
        end
      end
    end
  end
end
