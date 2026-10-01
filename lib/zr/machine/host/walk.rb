# frozen_string_literal: true

require_relative "boot"
require_relative "../../hir"
require_relative "../../paths"

module Zr
  module Machine
    class Host
      # Runs HIR (the core library, then a program) on CRuby over the
      # kernel's heap (A7). A value is a kernel Value; a send, a constant,
      # a block and a raise go through the same kernel calls as the code
      # that `Lower` emits (lib/zr/lower/function/*.rb), so a binary and
      # the walker agree. A def and a block are functions of the kernel:
      # Ruby procs at addresses that `Host#callable` gives.
      #
      # Each scope has a heap Env for its locals and a frame record in the
      # slot area, linked from the task. So the collector, a Binding and a
      # backtrace see the frames as they see a binary's. A Value that the
      # walker holds between kernel calls is pinned (`Host#pin`) until the
      # statement that made it ends.
      #
      # A pending unwind in the task (a raise, a break to a call site, a
      # return from a block) is the Ruby exception `Unwind` in the walker,
      # until a rescue, a call site or a frame takes it; a frame then
      # returns QUNDEF to the kernel.
      class Walk
        # The task has a pending unwind.
        class Unwind < StandardError; end

        # The one Unwind that the walker raises. Its backtrace is set, so a
        # raise records none: an unwind out of 30,000 frames raises again in
        # each, and a backtrace of the ruby stack at each would cost the
        # square of the depth. With no cause, it never refers to itself.
        UNWIND = Unwind.new.tap { |e| e.set_backtrace([]) }

        # `retry`: the begin body again, from its rescue clause.
        class RetryJump < StandardError; end

        # A form the walker does not run yet.
        class Unsupported < StandardError; end

        # A scope's state while it runs. `scopes` are the locals of this
        # scope, then of each lexical scope out to the def or toplevel.
        # `env` is nil for a scope whose locals are in its record's slots;
        # `outer` is the Env of the scope around a block.
        # `homes` is the HIR node of each scope in `scopes`, innermost first:
        # a block reads from them how often each outer local is bound.
        # `opened` is the scope's kind once it fired its opening TracePoint
        # event, and `ret_line` the line of the `return` that leaves it.
        Ctx = Struct.new(:rec, :env, :self_, :cref, :blk, :meta, :proc, :scopes, :unit, :method, :loops, :kind, :params, :outer, :homes,
                         :opened, :ret_line)

        # What a unit's code runs with: its file, as a backtrace shows it,
        # whether it is the core library, and the units of its program,
        # which its requires name by index, and the prism node id of each
        # of its HIR nodes (for error_highlight). `core` is the core library
        # itself, where a bare boot class name reads its global slot; an
        # extension's Ruby part is internal but not core (`Lower#boot_class_slot`).
        # `hidden` is a unit that loads only for the runtime's own use: its
        # code reads the constants that such units set (`zr_const_sees_concealed`).
        # `root` is the FrameMeta of an eval's toplevel: the walker makes the
        # metas of its scopes when it first runs them, so each takes the box
        # that `zr_box_stamp` gave the root. `traced` is a unit of a program
        # that uses TracePoint, whose code fires events (`Lower#traced?`).
        # `spelling` is the order of its program's local names (`Spelling`).
        Unit = Struct.new(:file, :internal, :units, :node_ids, :core, :hidden, :root, :traced, :spelling)

        # The order in which a lowering first meets each local name of its
        # program (`Lower#spell`): the toplevels in order, each scope's
        # locals before the scopes in it. A captures table is in this order.
        class Spelling
          def initialize(roots)
            @roots = roots
            @order = nil
          end

          def index(name) = order.fetch(name, order.size)

          private

          def order
            @order ||= {}.tap do |seen|
              spell = ->(names) { names.each { |n| seen[n] ||= seen.size } }
              visit = lambda do |n|
                case n
                when Hir::Def, Hir::Block, Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef then spell.call(n.locals)
                end
                Hir.each_child(n) { |child| visit.call(child) } if n.is_a?(Hir::Node) || n.is_a?(Array)
              end
              @roots.each do |root|
                spell.call(root.locals)
                visit.call(root.body)
              end
            end
          end
        end

        # zr_require's kinds (Lower::Function::Control::REQUIRE_KINDS).
        REQUIRE_KINDS = { require: 0, require_relative: 1, load: 2, hidden: 3, computed: 4, declared: 5 }.freeze

        # The names that the core's sends dispatch normally
        # (Lower::Function::Sends::PROTOCOL); any other core send finds the
        # core's own method (SEND_CORE).
        PROTOCOL = %i[
          initialize initialize_copy initialize_dup initialize_clone
          to_s inspect to_str to_sym to_proc to_ary to_a to_hash to_h to_int to_i to_f to_r to_c to_path to_io to_regexp
          == != eql? hash <=> === =~ ! coerce
          call write warn default
          respond_to? respond_to_missing? method_missing
          method_added singleton_method_added method_removed singleton_method_removed method_undefined
          singleton_method_undefined inherited included extended prepended const_added const_missing
          marshal_dump marshal_load _dump _load pp
          exception message backtrace full_message detailed_message
        ].to_set.freeze
        SEND_CORE = 8
        SEND_USING = 16
        PARAM_KINDS = %i[req opt rest keyreq key keyrest block nokey].each_with_index.to_h.freeze

        attr_reader :boot, :kern, :host

        def initialize(boot = Boot.new)
          @boot = boot
          @kern = boot.kern
          @host = boot.host
          k = @kern
          @qnil = k::QNIL
          @qtrue = k::QTRUE
          @qfalse = k::QFALSE
          @qundef = k::QUNDEF
          @ids = {}
          @sites = Hash.new { |h, node| h[node] = h.size + 1 }.compare_by_identity
          @cells = {}.compare_by_identity
          @metas = {}.compare_by_identity
          @fns = {}.compare_by_identity
          @tables = {}
          @boot_classes = File.read(File.join(Paths::RUNTIME, "kernel/main.rb"))
                              .scan(/zr_boot_name\((G_\w+), Machine\.id\(:(\w+)\)\)/).to_h { |slot, name| [name.to_sym, k.const_get(slot)] }
          @once = {}.compare_by_identity
        end

        # Runs each core file's toplevel in the order a binary's
        # `zr_prelude` runs them. Returns the Value of the last, or QUNDEF
        # when one left a pending unwind.
        def core(target = Target.default)
          RuntimeSources.for(target).core_files.each do |path|
            hir = Hir.build(File.read(path), path, eval_support: false, target: target)
            r = toplevel(hir, Unit.new(path, true, hir.units, nil, true), @kern::KIND_MAIN)
            return r if r == @qundef
          end
          @qnil
        end

        # Runs the program `hir` (a Hir::Program) as `zr_toplevel`.
        def program(hir, file, target = Target.default)
          spotted(hir, target)
          interned([hir])
          @traced = hir.traced ? true : false
          toplevel(hir, Unit.new(Paths.shown(file), false, hir.units, hir.node_ids, false, false, nil, @traced), @kern::KIND_MAIN)
        end

        # CRuby's gem prelude, as `zr_gem_prelude`.
        def gem_prelude(target = Target.default)
          hir = Zr.gem_prelude(target)
          toplevel(hir, Unit.new(Paths.shown(hir.file), false, hir.units, hir.node_ids), @kern::KIND_TOP)
        end

        # Runs `path` as a binary built from it runs: the boot, the core,
        # the gem prelude, then the program, with `args` as ARGV. Returns
        # the exit status.
        def main(path, args = [], target: Target.default)
          prepare(target)
          run(path, args, target: target)
        end

        # All a program needs before its first line: the core and the gem
        # prelude. A test worker does this once, and forks for each program.
        def prepare(target = Target.default)
          finish = lambda do |r|
            k.zr_report(k::Task.pending(task)) if r == @qundef
          end
          k.zr_args_init(1, argv([@host.bytes("zr"), 0]))
          @eval_files = EvalSupport.new(target)
          finish.call(core(target))
          k.zr_box_snapshot
          k.zr_runtime_written
          finish.call(gem_prelude(target))
          k.zr_gates_snapshot
        end

        # Runs the program at `path` with `args` in ARGV, after `prepare`.
        # Returns the exit status. `source` is the program's text in place
        # of the file's.
        def run(path, args = [], target: Target.default, source: File.read(path))
          # A test worker forks after `prepare`: this process has its own
          # pid, and only the thread that forked.
          @boot.restart
          k.zr_gvar_assign(id(:$$), k.zr_process_id)
          list = k.zr_global(k::G_ARGV)
          k::RArray.set_len(list, 0)
          args.each { |a| k.zr_ary_push(list, string(a)) }
          # As a build reads it: with error_highlight's spots, which a
          # build without eval support leaves out.
          hir = Hir.build(source, path, target: target, prebuilt: @eval_files)
          r = program(hir, path, target)
          exc = @qundef
          if r == @qundef
            exc = k::Task.pending(task)
            k::Task.set_pending(task, @qnil)
          end
          k.zr_program_end(exc)
        end

        # The symbol id of `name`, interned in the kernel's table if the
        # kernel has not seen it.
        def id(name)
          @ids[name] ||= begin
            text = name.to_s
            @host.symbols.ids[text] || @kern.zr_intern(@host.bytes(text), text.bytesize)
          end
        end

        def sym(name) = (id(name) << 8) | 12

        # Interns each Symbol in the trees `roots`, as a binary's symbol
        # table has every name its program uses before the first line:
        # Symbol.all_symbols lists one that has not run yet.
        def interned(roots)
          stack = roots.dup
          until stack.empty?
            node = stack.pop
            case node
            when Symbol then id(node)
            when Hir::Node, Array then stack.concat(Hir.each_child(node))
            end
          end
        end

        private

        def k = @kern

        def check(v)
          raise UNWIND, cause: nil if v == @qundef

          v
        end

        # The frame's line before a kernel call that can raise, as the
        # lowering's `at_node`: the line, and the prism node id above it,
        # which error_highlight reads.
        def at(node, c)
          id = c.unit.node_ids&.[](node) || 0
          k::Frame.set_line(c.rec, (node.line || 0) | (id << 32))
        end

        # Gives the load tables what a link writes into a binary
        # (`Zr.load_tables`): the texts (`Zr.load_texts`: for a program with
        # eval, what a require of a computed name searches; error_highlight's
        # spots; Coverage's tables), and the files the program was built
        # with, by path, each with its toplevel, where a require of a
        # computed name finds its file (`zr_unit_for`).
        TEXTS = %w[roots missing preloaded ext spots coverable branches defs sources manifest].freeze

        def spotted(hir, target)
          words = Memory.fetch(TYPES["Ptr"], @host.extern("zr_load_tables"))
          table = k::LoadTable
          texts = Zr.load_texts(evals: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {}, branches: hir.branches || {},
                                defs: hir.defs || {}, target: target, manifest: Manifest.bytes(Manifest.of_program(hir, @eval_files), target))
          TEXTS.zip(texts) do |field, lines|
            text = lines.join("\n").b
            Memory.write(words + table.layout_fields.fetch(field).first, [@host.bytes(text), text.bytesize].pack("Q<Q<"))
          end
          units = Hash(hir.entries).select { |path, _| path.start_with?("/") }.map { |path, unit| [Paths.shown(path), unit] }.sort_by(&:first)
          rows = units.flat_map do |path, unit|
            bytes = path.b
            [@host.bytes(bytes), bytes.bytesize, entry_in(hir.units, unit)]
          end
          at = Memory.zeroed([rows.size * 8, 8].max, 8)
          Memory.write(at, rows.pack("Q<*")) unless rows.empty?
          table.set_units(words, units.size)
          table.set_rows(words, at)
        end

        def truthy?(v) = (v & ~8) != 0
        def bool(b) = b ? @qtrue : @qfalse
        def task = k.zr_task

        # A zeroed cell of `bytes` for one site and kind.
        def cell(node, kind, bytes)
          (@cells[node] ||= {})[kind] ||= Memory.zeroed(bytes, 8)
        end

        # A static table of words: `[count, ids...]` and the like.
        def table(words)
          @tables[words] ||= begin
            addr = Memory.zeroed([words.size * 8, 8].max, 8)
            Memory.write(addr, words.pack("q<*")) unless words.empty?
            addr
          end
        end

        def id_table(names) = table([names.size, *names.map { |n| id(n) }])

        # `values` as an argument vector in the slot area, which the caller
        # gives back when the call returns.
        def argv(values)
          return 0 if values.empty?

          p = @host.slot(values.size * 8)
          Memory.write(p, values.map { |v| v & MASK }.pack("Q<*"))
          p
        end

        # Runs the block with the slots it takes given back after.
        def slots
          top = @host.slot_top
          yield
        ensure
          @host.slot_top = top
        end

        # Runs the block with the pins it makes dropped after, except its
        # result.
        def pinned
          list = @host.pins
          mark = list.size
          result = yield
          list.slice!(mark..)
          @host.pin(result)
        end

        # --- frames ---

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

        # Whether the Proc `pr` is a lambda: its `lambda` field, which the
        # kernel's layout names as Kernel#lambda is named.
        def lambda_proc?(pr) = k::RProc.public_send(:lambda, pr) != 0

        # The elements of an Array as Values.
        def elements(ary) = Memory.read(k::RArray.ptr(ary), k::RArray.len(ary) * 8).unpack("q<*")

        # A scope's first line: its node's, or 1 for a file.
        def line_of(node) = node.respond_to?(:line) ? node.line || 1 : 1

        # The most frames that a ruby stack holds here: about 39,000 fit in
        # `zr-dev host`'s, a thread's or a fiber's. Past this a call
        # overflows as past the slots, and the margin keeps room for the
        # error's report, as STACK_MARGIN does.
        DEPTH = 20_000

        # Runs `body` in a new frame: a record in the slot area linked
        # from the task, and a heap Env for `locals`. Returns the body's
        # Value, or QUNDEF for a pending unwind that no handler took.
        # An eval's frame gets its Env (`env`) from the kernel.
        def frame(meta:, self_:, cref:, blk:, entry: 0, defined: @qnil, locals: [], parent_env: @qnil, scopes: [], unit:, method: nil, kind: :def,
                  proc: nil, params: nil, env: nil, homes: [])
          f = k::Frame
          t = task
          open = env || k::FrameMeta.env(meta) == 1
          n = open ? 1 : locals.size
          depth = @host.depth
          slots do
            rec = @host.slot(f.layout_size + (8 * [n, 1].max))
            return k.zr_stack_overflow if rec < k::Task.stack_limit(t) || depth >= DEPTH

            @host.depth = depth + 1
            prev = k::Task.top(t)
            line = k::FrameMeta.line(meta) | (k::FrameMeta.node(meta) << 32)
            Memory.write(rec, [prev, meta, line, self_ & MASK, cref & MASK, blk & MASK, entry, defined & MASK, 0, n, @qnil].pack("Q<*"))
            Memory.write(rec + f.layout_size, ([@qnil] * [n, 1].max).pack("Q<*"))
            k::Task.set_refine(t, @qnil)
            k::Task.set_top(t, rec)
            begin
              if open
                env ||= k.zr_env_new(parent_env, locals.size, id_table(locals))
                Memory.write(rec + f.layout_size, [env].pack("Q<"))
              end
              ctx = Ctx.new(rec, env, self_, cref, blk, meta, proc, [locals, *scopes], unit, method, [], kind, params, parent_env, homes)
              pinned { yield ctx }
            ensure
              k::Task.set_top(t, prev)
              @host.depth = depth
            end
          end
        end

        # A core file's or a program's toplevel.
        def toplevel(hir, unit, kind)
          # One lowering takes a program and its units, or the units of eval
          # support, so they share one spelling.
          unit.spelling ||= (@spellings ||= {}.compare_by_identity)[unit.units || hir] ||=
            Spelling.new(hir.is_a?(Hir::Program) ? [hir, *unit.units] : Array(unit.units))
          shown = unit.internal ? k::KIND_HIDDEN : kind
          m = meta(hir, unit, shown, locals: hir.locals, open: open?(hir, kind == k::KIND_MAIN ? :main : :top, unit))
          frame(meta: m, self_: k.zr_global(k::G_MAIN), cref: k.zr_global(k::G_TOP_CREF), blk: @qnil, locals: hir.locals,
                unit: unit, kind: :main, homes: [hir]) do |c|
            unless unit.internal
              if kind == k::KIND_MAIN
                file = unit.file.to_s.b
                k.zr_program_start(@host.bytes(file), file.bytesize)
                k.zr_toplevel_binding(c.env, c.self_, c.cref, m)
              end
              Array(hir.warnings).each do |line|
                text = "#{line}\n".b
                k.zr_write_err(@host.bytes(text), text.bytesize)
              end
            end
            run_body(c) { ev(hir.body, c) }
          end
        end

        # The body of a scope; a pending unwind that leaves it makes the
        # frame return QUNDEF, after a `return` from a block is caught.
        #
        # A scope that fired its opening event fires its closing event as
        # it leaves, with its value, or QUNDEF while it unwinds.
        def run_body(c, node = nil, &)
          r = begin
            catch(c, &)
          rescue Unwind
            caught = k.zr_catch_return(c.rec)
            # A `return` in an eval string goes to the main scope or to the
            # def that runs the eval (`zr_return_here`).
            here = c.kind == :main || (c.kind == :def && c.method&.evals)
            caught == @qundef && here ? k.zr_catch_return_here : caught
          end
          c.opened ? closed(c, node, r) : r
        end

        # --- TracePoint (Lower::Function::Tracing) ---

        EVENTS = { line: 0x1, class: 0x2, end: 0x4, call: 0x8, return: 0x10, b_call: 0x100, b_return: 0x200 }.freeze
        OPENING = { def: :call, block: :b_call, class: :class }.freeze
        CLOSING = { def: :return, block: :b_return, class: :end }.freeze

        # Whether an enabled TracePoint listens for `event`.
        def armed?(event)
          @trace_events ||= @host.static("trace_events", 8)
          Memory.fetch(TYPES["Word"], @trace_events).anybits?(EVENTS.fetch(event))
        end

        def fire(event)
          check(k.zr_trace_fire(EVENTS.fetch(event), @qnil)) if armed?(event)
        end

        # The scope's opening event, once its parameters are bound.
        def opened(c, kind)
          return unless c.unit.traced

          c.opened = kind
          fire(OPENING.fetch(kind))
        end

        # The closing event of a scope that leaves with `v`: at the line of
        # its `return`, else at its `end`; an unwind keeps the line where
        # it raised. Returns `v`, or QUNDEF if a hook raised.
        def closed(c, node, v)
          event = CLOSING.fetch(c.opened)
          return v unless armed?(event)

          line = c.ret_line || node.end_line
          k::Frame.set_line(c.rec, line) unless v == @qundef || line.nil?
          k.zr_trace_fire(EVENTS.fetch(event), v)
        end

        # --- eval ---

        # The compiler that a binary with eval links in, as the core's eval
        # forms call it (lib/zr/runtime/lib/zr/eval/forms.rb): here it
        # builds the HIR of the string and gives a function of the walker.
        EVAL_SUPPORT = <<~RUBY
          module Zr
            class Eval
              def self.current = @current ||= new

              def compile(source, file, line = 1, scopes = [], method = nil)
                Primitive.attr! :hidden
                # String#+ converts as prism does: `eval(123)` is a TypeError.
                Primitive.zr_host_eval_compile(+"" + source, file, line, scopes, method)
              end

              def compile_file(path)
                Primitive.attr! :hidden
                Primitive.zr_host_eval_file(path)
              end

              # prism loads at the first parse: walking it takes seconds here.
              def parse(source, line)
                Primitive.attr! :hidden
                Primitive.zr_host_prism
                ::Prism.parse(source, line: line).value
              end
            end
          end
        RUBY

        # Eval support for a program's build (`Hir.build(prebuilt:)`), as a
        # binary links it in: the libraries a program with eval gets
        # (rubygems, rbconfig, pp, irb, ...), built once, which the program
        # refers to and does not build again. Its compiler file stands for
        # the host's own `Zr::Eval` (EVAL_SUPPORT), not for zr's compiler.
        class EvalSupport
          attr_reader :loader

          def initialize(target)
            b = Hir::Build
            @loader = b::Loader.new(b.stdlib(target), description: b.description(target))
            # A binary's eval support adds the compiler first, hidden, and
            # with it prism. Here the translator adds prism first, so prism
            # stays hidden from the program, as there, when irb requires it.
            b.ast_translator(@loader)
            b.rubygems(@loader)
            b.rbconfig(@loader)
            b.normalizer(@loader)
            b.pretty_printer(@loader)
            b.irb_session(@loader)
            @compiler = b.eval_file(target)
          end

          # Each file by path, and its entry: `[:eval, index]` into the
          # loader's units, or `[:eval]` for the compiler.
          def units
            @units ||= @loader.entries.transform_values { |i| [:eval, i] }.merge(@compiler => [:eval])
          end

          def configures? = @loader.configures?
          def normalizes? = @loader.normalizes?
          def pretty_prints? = @loader.pretty_prints?
          def irbs? = @loader.irbs?
          def gems? = @loader.gems?
          def activations = @loader.activations
        end

        # Loads the eval forms, at the first program that evals.
        def eval_support!
          return if @eval_support

          @eval_support = true
          walk = self
          k.singleton_class.define_method(:zr_host_eval_compile) { |*args| walk.send(:eval_compile, *args) }
          k.singleton_class.define_method(:zr_host_eval_file) { |path| walk.send(:eval_file, path) }
          k.singleton_class.define_method(:zr_host_prism) { walk.send(:prism!) }
          unit = Unit.new("<internal:zr_eval>", true, [], nil)
          check(toplevel(Hir.build(EVAL_SUPPORT, "<internal:zr_eval>", eval_support: false), unit, k::KIND_MAIN))
          forms = File.join(Paths::RUNTIME, "lib/zr/eval/forms.rb")
          check(toplevel(Hir.build(File.read(forms), forms, eval_support: false), Unit.new(forms, true, [], nil), k::KIND_MAIN))
        end

        # `Zr::Eval#compile`: the code record of the string `source`, as the
        # kernel reads it (`zr_code_word`): the toplevel, its FrameMeta,
        # and the slot count and names of the Env for its own locals.
        def eval_compile(source, file, line, scopes, method)
          outer = ruby(scopes).map { |names| names.map(&:to_sym) }
          # Its `using` entries take the next free slots of the program's
          # table, now (`Zr::Eval#compiled`); a traced program's eval is
          # traced too.
          hir = Hir.build(text(source), text(file), eval_support: false, line: k.zr_fix2long(line), scopes: [*outer.reverse, []],
                                                    method: method == @qnil ? nil : ruby(method),
                                                    activations: k.zr_fix2long(k.zr_activations_count), trace: @traced)
          k.zr_activations_reserve(hir.activations)
          unit = Unit.new(text(file), false, hir.units, hir.node_ids)
          unit.spelling = Spelling.new([hir])
          # A traced program's eval'd code fires its events too.
          unit.traced = @traced
          m = meta(hir, unit, k::KIND_EVAL, locals: hir.locals)
          unit.root = m
          fn = @host.callable(lambda do |self_, cref, env, blk|
            frame(meta: m, self_: self_, cref: cref, blk: blk, locals: hir.locals, scopes: outer, unit: unit, kind: :eval, env: env,
                  parent_env: k::REnv.parent(env)) do |c|
              run_body(c) { ev(hir.body, c) }
            end
          end)
          words = [fn, m, hir.locals.size, id_table(hir.locals)].map { |w| (w << 1) | 1 }
          # The fifth word: the metas that a box stamps (`Ruby::Box#run`).
          slots do
            metas = @host.pin(k.zr_ary_of(1, argv([(m << 1) | 1])))
            k.zr_ary_of(words.size + 1, argv(words + [metas]))
          end
        rescue Hir::Invalid, SyntaxError => e
          message = e.message.b
          klass = k.zr_core_class(id(:SyntaxError))
          return k.zr_raise_msg(klass, @host.bytes(message), message.bytesize) unless e.is_a?(SyntaxError) && e.backtrace == [e.path]

          # An error in the string alone (a stray `yield`) keeps the
          # string's path as its backtrace (`Zr::Eval#compile`).
          slots do
            exc = @host.pin(check(k.zr_send(klass, id(:new), 1, argv([string(e.message)]))))
            path = @host.pin(k.zr_ary_of(1, argv([string(e.path)])))
            check(k.zr_send(exc, id(:set_backtrace), 1, argv([path])))
            k.zr_raise(exc)
          end
        end

        # prism's files of eval support, required hidden as a binary's
        # compiler requires them, the first time the host's `Zr::Eval#parse`
        # runs.
        def prism!
          unless @prism
            @prism = true
            path, unit = @eval_files.units.find { |p, _| p.end_with?("/prism.rb") }
            check(k.zr_require(string(Paths.shown(path)), entry_in(nil, unit), REQUIRE_KINDS.fetch(:hidden)))
          end
          @qnil
        end

        # `Zr::Eval#compile_file`: the toplevel of a file that the program
        # was not built with, as a fixnum address.
        def eval_file(path)
          name = text(path)
          hir = Hir.build(File.read(name), name, eval_support: false)
          unit = Unit.new(Paths.shown(name), Hir::Build.internal_library?(name), hir.units, hir.node_ids)
          fn = @host.callable(-> { toplevel(hir, unit, k::KIND_TOP) })
          (fn << 1) | 1
        end

        # A String's bytes as a Ruby String.
        def text(s)
          Memory.read(k::RString.ptr(s), k::RString.len(s)).force_encoding(::Encoding::UTF_8)
        end

        # A Value as a plain Ruby value: Integers, Symbols, Strings, Arrays,
        # nil, true and false.
        def ruby(v)
          return nil if v == @qnil
          return true if v == @qtrue
          return false if v == @qfalse
          return v >> 1 if v & 1 == 1
          return Memory.read(k.zr_symbol_name_ptr(v >> 8), k.zr_symbol_name_len(v >> 8)).force_encoding(::Encoding::UTF_8).to_sym if v & 0xFF == 12

          case k.zr_type(v)
          when k::T_STRING then text(v)
          when k::T_ARRAY then elements(v).map { |e| ruby(e) }
          else raise Unsupported, "a #{k.zr_type(v)} value given to the host"
          end
        end

        # --- definitions ---

        # The function of the def `node`: `(recv, argc, argv, entry, blk,
        # found) => Value`.
        def def_fn(node, unit, parent_scopes)
          @fns[node] ||= begin
            hidden = attributes(node).include?(:hidden)
            kind = if unit.internal then hidden ? k::KIND_HIDDEN : k::KIND_BUILTIN
                   else k::KIND_DEF
                   end
            m = meta(node, unit, kind, name: node.name, params: node.params, locals: node.locals, open: open?(node, :def, unit, node.params),
                                       ruby: unit.internal && attributes(node).include?(:ruby), cover: node.cover)
            @host.callable(lambda do |recv, argc, argv, entry, blk, found|
              cref = entry.zero? ? @qnil : k::MEntry.cref(entry)
              frame(meta: m, self_: recv, cref: cref, blk: blk, entry: entry, defined: found, locals: node.locals,
                    scopes: parent_scopes, unit: unit, method: node, params: node.params, homes: [node]) do |c|
                run_body(c, node) do
                  bind_method(node.params, argc, argv, c, @fns[node])
                  preempt(c)
                  opened(c, :def)
                  k.zr_coverage_method(entry) if node.cover
                  node.body ? ev(node.body, c) : @qnil
                end
              end
            end)
          end
        end

        # The leading `Primitive.attr!(:name)` statements of a def.
        def attributes(node)
          (@attributes ||= {}.compare_by_identity)[node] ||= begin
            body = node.body.is_a?(Hir::Begin) ? node.body.body : node.body
            stmts = body.is_a?(Hir::Seq) ? body.stmts : [body]
            stmts.take_while { |s| s.is_a?(Hir::Send) && s.name == :attr! && s.recv.is_a?(Hir::ConstRead) && s.recv.name == :Primitive }
                 .flat_map { |s| s.args.map(&:value) }
          end
        end

        def define(node, c)
          owner = if node.receiver
                    recv = ev(node.receiver, c)
                    at(node, c)
                    check(k.zr_singleton_class(recv))
                  else
                    k.zr_cref_klass(c.cref)
                  end
          fn = def_fn(node, c.unit, [])
          at(node, c)
          arity = node.params.plain? ? node.params.required.size : -1
          entry = node.receiver || inside_method?(c) ? :zr_define_method_public : :zr_define_method
          check(k.public_send(entry, owner, id(node.name), fn, arity, k::KIND_DEF, @metas.fetch(node), c.cref))
          sym(node.name)
        end

        def inside_method?(c) = !c.method.nil?

        def class_body(node, c)
          scope = scope_class(node.scope, c)
          klass = if node.is_a?(Hir::ClassDef)
                    sup = node.superclass ? ev(node.superclass, c) : @qundef
                    at(node, c)
                    check(k.zr_class_define(scope, id(node.name), sup, node.scope ? 1 : 0))
                  else
                    at(node, c)
                    check(k.zr_module_define(scope, id(node.name), node.scope ? 1 : 0))
                  end
          body_in(node, klass, c, node.is_a?(Hir::ClassDef) ? k::KIND_CLASS : k::KIND_MODULE, node.name)
        end

        def body_in(node, klass, c, kind, name)
          cref = k.zr_cref_push(klass, c.cref)
          kind = k::KIND_HIDDEN if c.unit.internal
          # A `class << self` body is inside its scope (`Lower#body`): a
          # `return` there leaves the method around it.
          parent = kind == k::KIND_SCLASS ? c.meta : 0
          m = meta(node, c.unit, kind, name: name, parent: parent, locals: node.locals, open: open?(node, :class, c.unit))
          check(frame(meta: m, self_: klass, cref: cref, blk: @qnil, locals: node.locals, unit: c.unit, kind: :class) do |inner|
            run_body(inner, node) do
              opened(inner, :class)
              node.body ? ev(node.body, inner) : @qnil
            end
          end)
        end

        def scope_class(scope, c)
          case scope
          when nil then k.zr_cref_lexical_class(c.cref)
          when :top then k.zr_global(k::G_OBJECT)
          else ev(scope, c)
          end
        end

        # --- arguments ---

        # `fn` is the def's function: a `ruby2_keywords` method is known by
        # it (`zr_kw_undeclared`).
        def bind_method(p, argc, argv, c, fn)
          t = task
          kw = k::Task.kw(t)
          k::Task.set_kw(t, 0)
          kwhash = nil
          if keywords?(p)
            if kw > 1
              argc = k.zr_kw_tab_in(kw, argc, argv)
              kw = 1
            end
            if kw == 1
              argc -= 1
              kwhash = Memory.fetch(TYPES["Value"], argv + (argc * 8))
            end
          elsif kw != 0
            argc = k.zr_kw_undeclared(kw, argc, argv, p.rest && p.rest != :implicit ? fn : 0)
          end
          args = argc.zero? ? [] : Memory.read(argv, argc * 8).unpack("q<*")
          check_arity(p, args.size)
          bind_positional(p, args, c)
          bind_keywords(p, kwhash, c) if keywords?(p)
          set_local(p.block, k.zr_block_proc(c.blk), c) if p.block && owns?(p, p.block, [:block, 0])
        end

        def keywords?(p) = p.keywords.any? || !p.kwrest.nil?

        def check_arity(p, given)
          min = p.required.size + p.post.size
          max = p.rest && p.rest != :implicit ? -1 : min + p.optional.size
          return if given >= min && (max.negative? || given <= max)

          required = p.keywords.select { |_, d| d.nil? }.map(&:first)
          check(k.zr_wrong_arity_kw(given, min, max, required.empty? ? 0 : id_table(required) + 8, required.size))
        end

        # Required parameters from the front, post parameters from the
        # back, then the optional ones in order, then the rest.
        def bind_positional(p, args, c)
          n = args.size
          front = p.required.size
          back = p.post.size
          p.required.each_with_index { |target, i| bind_target(target, i < n ? args[i] : @qnil, c) if first?(p, target, i) }
          post_at = [n - back, front].max
          optional = p.optional.size
          given_opt = [[n - front - back, 0].max, optional].min
          bind_optional(p, args, front, given_opt, c)
          if p.rest && p.rest != :implicit
            start = front + given_opt
            rest = args[start...[post_at, start].max] || []
            set_local(p.rest, k.zr_ary_of(rest.size, argv(rest)), c) if owns?(p, p.rest, [:rest, 0])
          end
          p.post.each_with_index { |target, i| bind_target(target, post_at + i < n ? args[post_at + i] : @qnil, c) if first?(p, target, front + i) }
        end

        # The optional parameters: a given argument binds its slot, if the
        # slot owns the name; a default is an assignment to the name, as
        # CRuby compiles it, so a repeated `_`'s default reaches the first.
        def bind_optional(p, args, front, given, c)
          p.optional.each_with_index do |(name, default), i|
            if i < given
              set_local(name, args[front + i], c) if owns?(p, name, [:opt, i])
            else
              set_local(name, ev(default, c), c)
            end
          end
        end

        # Whether the parameter `target` at position `i` of the required
        # and post parameters is the first of its name: a repeated `_`
        # binds its first argument, as in ruby.
        def first?(p, target, i) = owns?(p, target, i < p.required.size ? [:req, i] : [:post, i - p.required.size])

        # Whether the parameter at `slot` (`[kind, index]`) owns the name
        # `name`: it is the first parameter of that name, in ruby's order.
        def owns?(p, name, slot)
          return true unless name.is_a?(Symbol)

          owners = (@owners ||= {}.compare_by_identity)[p] ||= begin
            slots = [*p.required.each_index.map { |i| [[:req, i], p.required[i]] }, *p.optional.each_index.map { |i| [[:opt, i], p.optional[i][0]] },
                     [[:rest, 0], p.rest], *p.post.each_index.map { |i| [[:post, i], p.post[i]] },
                     *p.keywords.each_index.map { |i| [[:key, i], p.keywords[i][0]] }, [[:kwrest, 0], p.kwrest], [[:block, 0], p.block]]
            slots.reverse.to_h { |at, owner| [owner, at] }
          end
          owners[name] == slot
        end

        def bind_target(target, v, c)
          target.is_a?(Hir::MultiTarget) ? multi(target, v, c) : set_local(target, v, c)
        end

        def bind_keywords(p, kwhash, c)
          hash = kwhash || @qnil
          ids = p.keywords.map(&:first)
          required = p.keywords.select { |_, d| d.nil? }.map(&:first)
          check(k.zr_kw_missing(hash == @qnil ? k.zr_hash_new : hash, id_table(required) + 8, required.size)) unless required.empty?
          check(k.zr_kw_unknown(hash, id_table(ids) + 8, ids.size)) if p.kwrest.nil? && hash != @qnil
          p.keywords.each_with_index do |(name, default), i|
            v = hash == @qnil ? @qundef : k.zr_kw_get(hash, id(name))
            v = default ? ev(default, c) : @qnil if v == @qundef
            set_local(name, v, c) if owns?(p, name, [:key, i])
          end
          return if p.kwrest.nil?

          if p.kwrest == :nokey
            check(k.zr_kw_none(hash))
          else
            rest = hash == @qnil ? k.zr_hash_new : check(k.zr_kw_rest(hash, id_table(ids) + 8, ids.size))
            set_local(p.kwrest, rest, c) if owns?(p, p.kwrest, [:kwrest, 0])
          end
        end

        # --- locals ---

        # The Env `depth` scopes out; at depth 0, nil when the locals are in
        # the record.
        def env_at(c, depth)
          return c.env if depth.zero?

          env = c.outer
          (depth - 1).times { env = k::REnv.parent(env) }
          env
        end

        def local_index(c, name, depth)
          c.scopes.fetch(depth).index(name) or raise Unsupported, "no local #{name} at depth #{depth}"
        end

        def local_at(c, name, depth)
          env = env_at(c, depth)
          i = local_index(c, name, depth) * 8
          env ? [env, k::REnv.slots(env) + i] : [nil, c.rec + k::Frame.layout_size + i]
        end

        def get_local(name, depth, c)
          _, at = local_at(c, name, depth)
          Memory.fetch(TYPES["Value"], at)
        end

        def set_local(name, v, c, depth = 0)
          env, at = local_at(c, name, depth)
          Memory.put(TYPES["Value"], at, v)
          k.zr_env_barrier(env, v) if env
          v
        end

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

        # --- the walk ---

        def ev(node, c)
          case node
          when nil then @qnil
          when Hir::Seq then seq(node, c)
          when Hir::Literal then literal(node, c)
          when Hir::Send then send_node(node, c)
          when Hir::Local then get_local(node.name, node.depth, c)
          when Hir::Assign then set_local(node.name, ev(node.value, c), c, node.depth)
          when Hir::SelfRef then c.self_
          when Hir::ConstRead then const_read(node, c)
          when Hir::ConstWrite
            scope = scope_class(node.scope, c)
            v = ev(node.value, c)
            at(node, c)
            check(k.zr_const_set(scope, id(node.name), v))
            v
          when Hir::ConstOrWrite
            scope = scope_class(node.scope, c)
            at(node, c)
            v = node.scope ? k.zr_const_lookup_at(scope, id(node.name)) : k.zr_const_lookup(c.cref, id(node.name))
            return v if v != @qundef && truthy?(v)

            v = ev(node.value, c)
            check(k.zr_const_set(scope, id(node.name), v))
            v
          when Hir::FrozenString then frozen_string(node, c)
          when Hir::If then truthy?(ev(node.cond, c)) ? ev(node.yes, c) : ev(node.no, c)
          when Hir::And
            v = ev(node.left, c)
            truthy?(v) ? ev(node.right, c) : v
          when Hir::Or
            v = ev(node.left, c)
            truthy?(v) ? v : ev(node.right, c)
          when Hir::Not then negate(node, c)
          when Hir::While then while_loop(node, c)
          when Hir::Def then define(node, c)
          when Hir::ClassDef, Hir::ModuleDef then class_body(node, c)
          when Hir::SingletonClassDef
            target = ev(node.target, c)
            at(node, c)
            klass = check(k.zr_singleton_class(target))
            body_in(node, klass, c, k::KIND_SCLASS, 0)
          when Hir::Return then do_return(node, c)
          when Hir::Break then do_break(node, c)
          when Hir::Next then do_next(node, c)
          when Hir::ArrayLit then array(node, c)
          when Hir::HashLit then hash(node, c)
          when Hir::RangeLit
            low = ev(node.low, c)
            high = ev(node.high, c)
            excl = node.exclusive ? 1 : 0
            check(node.static ? k.zr_range_literal(@sites[node], low, high, excl) : k.zr_range_new(low, high, excl))
          when Hir::Interp then interp(node, c)
          when Hir::IvarRead then check(k.zr_ivar_get_cached(c.self_, id(ivar(node.name, c)), cell(node, :ic, k::IvarCache.layout_size)))
          when Hir::IvarWrite
            v = ev(node.value, c)
            at(node, c)
            check(k.zr_ivar_set_cached(c.self_, id(ivar(node.name, c)), v, cell(node, :ic, k::IvarCache.layout_size)))
            v
          when Hir::GvarRead then gvar_read(node, c)
          when Hir::GvarWrite then gvar_write(node.name, ev(node.value, c), c, node.shown, node)
          when Hir::CvarRead
            at(node, c)
            check(k.zr_cvar_get(c.cref, id(node.name)))
          when Hir::CvarWrite
            v = ev(node.value, c)
            at(node, c)
            check(k.zr_cvar_set(c.cref, id(node.name), v))
            v
          when Hir::Yield then yield_node(node, c)
          when Hir::Begin then begin_node(node, c)
          when Hir::MultiAssign
            prepared = stage_targets(node.target, c)
            return spread_assign(node, c, prepared) if spread_assign?(node)

            v = ev(node.value, c)
            multi(node.target, v, c, prepared)
            v
          when Hir::Case then case_node(node, c)
          when Hir::Alias
            at(node, c)
            check(k.zr_alias(k.zr_cref_klass(c.cref), id(node.new_name), id(node.old_name)))
          when Hir::AliasValue
            new_name = ev(node.new_name, c)
            old_name = ev(node.old_name, c)
            at(node, c)
            check(k.zr_alias_value(k.zr_cref_klass(c.cref), new_name, old_name))
          when Hir::Undef
            at(node, c)
            node.names.each { |n| check(k.zr_undef(k.zr_cref_klass(c.cref), id(n))) }
            @qnil
          when Hir::UndefValue
            node.names.each do |n|
              name = ev(n, c)
              at(node, c)
              check(k.zr_undef_value(k.zr_cref_klass(c.cref), name))
            end
            @qnil
          when Hir::GvarAlias
            at(node, c)
            k.zr_gvar_alias(id(node.new_name), id(node.old_name))
            @qnil
          when Hir::Super then super_node(node, c)
          when Hir::ZSuper then zsuper(node, c)
          when Hir::Lambda then lambda_node(node, c)
          when Hir::Core then check(k.zr_core_class(id(node.name)))
          when Hir::Defined then defined(node, c)
          when Hir::RegexpLit
            src = node.source.b
            check(k.zr_regexp_literal(@sites[node], @host.bytes(src), src.bytesize, node.options,
                                      node.pinned ? ::Encoding.list.index(node.pinned) : -1))
          when Hir::RegexpOnce
            v = k.zr_regexp_once(@sites[node])
            v == @qnil ? k.zr_regexp_once_set(@sites[node], ev(node.value, c)) : v
          when Hir::BackRef then back_ref(node)
          when Hir::IndexOpAssign then index_op_assign(node, c)
          when Hir::AttrOpAssign then attr_op_assign(node, c)
          when Hir::KwSplatElement then check(k.zr_ary_kw_element(ev(node.pairs, c)))
          when Hir::Once
            return @once[node] if @once.key?(node)

            @once[node] = ev(node.body, c)
          when Hir::Stop then check(k.zr_unloadable(string(node.what.to_s)))
          when Hir::Trace
            at(node, c)
            fire(:line) if c.unit.traced
            @qnil
          when Hir::Cover
            at(node, c)
            k.zr_coverage_branch(node.id)
            @qnil
          when Hir::Using
            at(node, c)
            check(k.zr_using_activate(node.id, ev(node.value, c), node.from))
            c.self_
          when Hir::UsingDefaults
            node.rows.each { |id, from| k.zr_using_default(id, from) }
            @qnil
          when Hir::Activations
            k.zr_activations_reserve(node.count)
            @qnil
          when Hir::Retry then raise RetryJump
          when Hir::Redo
            throw c.loops.last[2] unless c.loops.empty?
            raise Unsupported, "a redo outside a loop or block" unless c.kind == :block

            throw c.meta
          when Hir::Require then require_unit(node, c)
          when Hir::Autoload then autoload_unit(node, c)
          else raise Unsupported, "#{c.unit.file}:#{line_of(node)}: the walker does not run a #{node.class.name.split("::").last}"
          end
        end

        def seq(node, c)
          last = @qnil
          list = @host.pins
          stmts = node.stmts
          # A continuation (`callcc`) restores the machine stack, not the
          # locals of Ruby frames, so this loop keeps its place in a C
          # iterator: under YJIT, Array#each is Ruby.
          stmts.each_index do |i|
            mark = list.size
            last = ev(stmts[i], c)
            list.slice!(mark..) if i < stmts.size - 1
          end
          last
        end

        def literal(node, c)
          v = node.value
          case v
          when Integer
            return (v << 1) | 1 if v.bit_length < 63

            text = v.to_s
            check(k.zr_big_literal(@sites[node], @host.bytes(text), text.bytesize))
          when Float then k.zr_float_from_bits([v].pack("E").unpack1("q<"))
          when String then string_literal(v, node.chilled && !c.unit.internal ? :zr_str_new_chilled : :zr_str_new)
          when Symbol then sym(v)
          when nil then @qnil
          when true then @qtrue
          when false then @qfalse
          else raise Unsupported, "a literal #{v.class}"
          end
        end

        def string(text)
          bytes = text.b
          k.zr_str_new(@host.bytes(bytes), bytes.bytesize)
        end

        # A String literal, made by the kernel's `fn` with the file's script
        # encoding (`Expressions#string_literal`).
        def string_literal(text, fn)
          bytes = text.b
          ptr = @host.bytes(bytes)
          return k.public_send(fn, ptr, bytes.bytesize) if text.encoding == ::Encoding::UTF_8

          k.public_send(:"#{fn}_at", ptr, bytes.bytesize, ENCODING_INDEX.fetch(text.encoding))
        end

        # ruby's own index for an encoding, which a String holds.
        ENCODING_INDEX = ::Encoding.list.each_with_index.to_h.freeze

        def frozen_string(node, _c)
          bytes = node.value.b
          case node.shared
          when true then k.zr_str_literal_cell(cell(node, :str, 8), @host.bytes(bytes), bytes.bytesize)
          when false then string_literal(node.value, :zr_str_frozen)
          else check(string_literal(node.value, :zr_str_literal_freeze))
          end
        end

        def ivar(name, c)
          return name unless c.unit.internal
          return name if Hir::VISIBLE_IVARS.include?(c.unit.file)
          return name if c.method && attributes(c.method).include?(:ivars)

          name.to_s.delete_prefix("@").to_sym
        end

        def const_read(node, c)
          if node.scope.nil? && c.unit.core && (slot = @boot_classes[node.name])
            return k.zr_global(slot)
          end

          size = k::ConstCache.layout_size
          if node.scope.nil?
            at(node, c)
            check(k.public_send(c.unit.internal ? :zr_const_get_cached : :zr_const_read_cached, cell(node, :cc, size), c.cref, id(node.name)))
          else
            scope = scope_class(node.scope, c)
            at(node, c)
            check(k.public_send(c.unit.internal ? :zr_const_get_at_cached : :zr_const_read_at_cached, cell(node, :cc, size), scope, id(node.name)))
          end
        end

        def gvar_read(node, c)
          case node.name
          when :$! then k.zr_errinfo
          when :$~ then k.zr_backref_get
          when :$_ then k.zr_lastline_get
          when :$< then k.zr_core_class(id(:ARGF))
          else c.unit.internal ? k.zr_gvar_get(id(node.name)) : check(k.zr_gvar_read(id(node.name)))
          end
        end

        HOOKED_GVARS = %i[
          $! $@ $& $` $' $+ $$ $? $* $< $FILENAME $LOAD_PATH $LOADED_FEATURES $-a $-l $-p $-W
          $; $, $/ $\\ $stdout $stderr $0 $VERBOSE $.
        ].to_set.freeze

        def gvar_write(name, v, c, shown = nil, node = nil)
          return k.zr_backref_set(v) if name == :$~ && c.unit.internal
          return check(k.zr_backref_assign(v)) if name == :$~
          return k.zr_lastline_set(v) if name == :$_

          at(node, c) if node
          check(k.zr_ractor_gvar_check(id(name))) unless c.unit.internal
          return check(k.zr_gvar_assign(id(name), v)) if c.unit.internal || !HOOKED_GVARS.include?(name)

          check(k.zr_gvar_hooked(id(shown || name), id(name), v))
        end

        def back_ref(node)
          m = k.zr_backref_get
          return @qnil if m == @qnil

          case node.kind
          when :nth then k.zr_match_nth(m, (node.number << 1) | 1)
          when :pre then k.zr_match_pre(m)
          when :post then k.zr_match_post(m)
          when :last then k.zr_match_last(m)
          end
        end

        def array(node, c)
          v = if node.elements.any?(Hir::Splat)
                gather(node.elements, c)
              else
                values = node.elements.map { |e| ev(e, c) }
                slots { k.zr_ary_of(values.size, argv(values)) }
              end
          node.frozen ? k.zr_literal_freeze(v) : v
        end

        # An Array of `parts`; a Splat spreads its value.
        def gather(parts, c)
          ary = @host.pin(k.zr_ary_new(parts.size))
          parts.each do |part|
            if part.is_a?(Hir::Splat)
              check(k.zr_ary_splat(ary, ev(part.value, c)))
            else
              k.zr_ary_push(ary, ev(part, c))
            end
          end
          ary
        end

        def hash(node, c)
          h = @host.pin(k.zr_hash_new)
          node.pairs.each_slice(2) do |key, value|
            if key.is_a?(Hir::HashSplat)
              check(k.zr_hash_update(h, ev(key.value, c)))
            else
              kv = ev(key, c)
              check(k.zr_hash_store(h, kv, ev(value, c)))
            end
          end
          node.frozen ? k.zr_literal_freeze(h) : h
        end

        def interp(node, c)
          values = node.parts.map do |part|
            # A part in another script encoding is a plain literal.
            if part.is_a?(Hir::Literal) && part.value.is_a?(String) && part.value.encoding == ::Encoding::UTF_8
              bytes = part.value.b
              k.zr_str_literal_shared(@host.bytes(bytes), bytes.bytesize)
            else
              ev(part, c)
            end
          end
          slots { check(k.zr_str_interp(values.size, argv(values))) }
        end

        # A local jump is a `throw`: to the loop's tags for its `break` and
        # `next`, and to the scope's Ctx for a def's `return` or a block's
        # `next` (`run_body` catches it). A throw runs no handler, so it
        # costs no backtrace.
        def while_loop(node, c)
          tags = [Object.new, Object.new, Object.new]
          c.loops.push(tags)
          catch(tags[0]) do
            redoable(tags[2]) { catch(tags[1]) { ev(node.body, c) } } if node.body_first
            # A `next` in the condition starts the next pass, as one in the
            # body does.
            loop do
              cond = nil
              catch(tags[1]) { cond = truthy?(ev(node.cond, c)) }
              break if cond == false

              redoable(tags[2]) { catch(tags[1]) { ev(node.body, c) } } if cond
              preempt(c)
            end
            @qnil
          end
        ensure
          c.loops.pop
        end

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

        # A safe point of program code, at a def's entry and a loop's back
        # edge (Lower::Function::Control#preempt): when the timer or a
        # signal set the poll word, the kernel runs the scheduler and the
        # traps. The core has none.
        def preempt(c)
          return if c.unit.internal

          @poll ||= @host.static("current_task", 16) + 8
          check(k.zr_preempt_expired) if Memory.fetch(TYPES["Word"], @poll) != 0
        end

        def do_return(node, c)
          v = ev(node.value, c)
          at(node, c)
          case c.kind
          when :def
            c.ret_line = node.line
            throw c, v
          when :block
            throw c, v if lambda_proc?(c.proc)

            check(k.zr_return(c.proc, v))
          else check(k.zr_return_here(v))
          end
        end

        def do_break(node, c)
          v = ev(node.value, c)
          throw c.loops.last[0], v unless c.loops.empty?
          raise Unsupported, "a break outside a loop or block" unless c.kind == :block
          throw c, v if lambda_proc?(c.proc)

          check(k.zr_break(c.proc, v))
        end

        def do_next(node, c)
          v = ev(node.value, c)
          throw c.loops.last[1], v unless c.loops.empty?

          throw c, v
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
        def entry(c, unit) = entry_in(c.unit.units, unit)

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

        def require_unit(node, c)
          shown = Paths.shown(node.path || node.feature.to_s)
          bytes = @host.bytes(shown.b)
          at(node, c)
          return check(k.zr_load_error(bytes, shown.bytesize)) unless node.unit

          fn = entry(c, node.unit)
          check(k.zr_require(k.zr_str_new(bytes, shown.bytesize), fn, REQUIRE_KINDS.fetch(node.kind)))
        end

        def autoload_unit(node, c)
          at(node, c)
          recv = @host.pin(node.recv ? ev(node.recv, c) : c.self_)
          feature = @host.pin(string(node.feature))
          shown = Paths.shown(node.path.to_s)
          path = string(shown)
          fn = node.unit ? entry(c, node.unit) : 0
          key = if node.declared then :declared
                elsif node.unit then :require
                else :computed
                end
          check(k.zr_autoload(recv, id(node.name), feature, fn, c.cref, REQUIRE_KINDS.fetch(key), path))
        end

        # --- sends ---

        def send_node(node, c)
          return primitive(node, c) if c.unit.internal && node.recv.is_a?(Hir::ConstRead) && node.recv.name == :Primitive && node.recv.scope.nil?
          return send_node(funcall(node), c) if kernel_send?(node, c)

          recv = node.recv ? ev(node.recv, c) : c.self_
          if node.safe
            # Coverage counts the call's branch or the nil branch (`Sends#safe_call`).
            k.zr_coverage_branch((recv == @qnil ? node.covers.last : node.covers.first).id) if node.covers
            return @qnil if recv == @qnil
          end
          return recv if node.interp && k.zr_interp_plain_p(recv)

          args, splat = arguments(node.args, c)
          if !splat && node.block.nil? && node.kwargs.nil? && !node.vcall && node.using != :owner && !c.unit.traced
            v = case args.size
                when 1 then operator(node.name, recv, args.first, c, [node.recv, node.args.first])
                when 2
                  # The core's range checks of its own integers.
                  if node.name == :between? && node.recv && !node.recv.is_a?(Hir::SelfRef) && native_operators?(c)
                    slots { check(k.zr_native_between(recv, argv(args))) }
                  end
                end
            return v if v
          end
          kwargs = node.kwargs && hash(node.kwargs, c)
          mode = if node.vcall then 1
                 elsif node.recv && !node.recv.is_a?(Hir::SelfRef) && !@funcalls&.key?(node) then 2
                 else 0
                 end
          mode |= SEND_CORE if core_send?(node.name, c)
          mode |= SEND_USING if node.using
          written = nil
          result = slots do
            blk = block_arg(node.block, c, node)
            values = splat ? elements(splat) : args
            written = values.last
            values += [kwargs] if kwargs
            av = argv(values)
            argc = values.size
            argc = k.zr_kw_argc(argc, av) if kwargs
            argc = k.zr_kw_ruby2_out(argc, av) if splat && !kwargs
            at(node, c)
            sent(node.block.is_a?(Hir::Block) ? node.block : nil, c) do
              activate(node, c)
              if node.name == :new && node.block.nil?
                # `new` with no block runs with no frame of its own, as in
                # a binary.
                k.zr_new_cached(cell(node, :new, 8 * k::CallCache.layout_size), recv, argc, av, blk, mode)
              elsif node.using == :owner
                k.zr_send_cached(cell(node, :cc, 4 * k::CallCache.layout_size), recv, id(node.name), argc, av, blk, mode)
              elsif (entry = opt_entry(node, c, recv))
                k.public_send(entry, recv, id(node.name), argc, av, mode)
              else
                cached_send(cell(node, :cc, 4 * k::CallCache.layout_size), recv, id(node.name), argc, av, blk, mode)
              end.tap { k::Task.set_refine(task, @qnil) if node.using }
            end
          end
          node.write ? written : result
        end

        # In the core, `recv.send(:name, ...)` is rb_funcall in CRuby's C: a
        # direct call of `name`, private permitted, and never a class's own
        # `send` (`Sends#kernel_send?`).
        def kernel_send?(node, c)
          return false unless c.unit.internal && %i[send __send__].include?(node.name)

          first = node.args.first
          first.is_a?(Hir::Literal) && first.value.is_a?(Symbol) && !%i[send __send__ public_send].include?(first.value)
        end

        # The call that a kernel send makes, one per site (`Sends#funcall`).
        def funcall(node)
          (@funcall_of ||= {}.compare_by_identity)[node] ||= node.dup.tap do |n|
            n.name = node.args.first.value
            n.args = node.args.drop(1)
            (@funcalls ||= {}.compare_by_identity)[n] = true
          end
        end

        # The kernel entry of each send with a core fast path, and the
        # classes it takes (Lower::Function::Sends::OPT_ENTRIES). The
        # entry calls the core's method with no frame of its own, as
        # CRuby's specialized instructions do.
        OPT_ENTRIES = {
          :[] => [:zr_opt_aref, %i[G_ARRAY G_HASH]], :[]= => [:zr_opt_aset, %i[G_ARRAY G_HASH]], :<< => [:zr_opt_ltlt, %i[G_ARRAY G_STRING]],
          getbyte: [:zr_opt_getbyte, %i[G_STRING]], setbyte: [:zr_opt_setbyte, %i[G_STRING]],
          push: [:zr_opt_push, %i[G_ARRAY]], pop: [:zr_opt_pop, %i[G_ARRAY]], shift: [:zr_opt_shift, %i[G_ARRAY]],
          empty?: [:zr_opt_empty_p, %i[G_ARRAY]]
        }.freeze

        # The kernel entry for the send `node` (`Sends#opt_send`), when the
        # site has a fast path and `recv` is of one of its classes. A
        # traced program sends each, so its events fire.
        def opt_entry(node, c, recv)
          return unless node.opt && node.using != :owner && !c.unit.traced && recv & 7 == 0 && recv > @qnil

          entry, classes = OPT_ENTRIES.fetch(node.name)
          klass = k::RBasic.klass(recv)
          entry if classes.any? { |g| klass == k.zr_global(k.const_get(g)) }
        end

        # Gives the task the refinements that are active at the send
        # (`Sends#activate`): those of the `using` entry, or in a `refine`
        # block those of the owner.
        def activate(node, c)
          case node.using
          when nil then nil
          when :owner then k.zr_activate_owner(c.rec)
          else k.zr_activate(node.using)
          end
        end

        # The Integer operators with an inline path on two fixnums while
        # the operator's gate is clear (Lower::Function::Sends::OPS), each
        # with its gate and its result: nil when the result is no fixnum (a
        # bignum, a division by zero), and the send runs instead.
        FIXNUM = (-(1 << 62))...(1 << 62)
        FIXNUM_OPS = {
          :+ => [:GATE_PLUS, ->(a, b) { a + b }], :- => [:GATE_MINUS, ->(a, b) { a - b }], :* => [:GATE_MUL, ->(a, b) { a * b }],
          :/ => [:GATE_DIV, ->(a, b) { b.zero? ? nil : a / b }], :% => [:GATE_MOD, ->(a, b) { b.zero? ? nil : a % b }],
          :< => [:GATE_LT, ->(a, b) { a < b }], :<= => [:GATE_LE, ->(a, b) { a <= b }], :> => [:GATE_GT, ->(a, b) { a > b }],
          :>= => [:GATE_GE, ->(a, b) { a >= b }], :== => [:GATE_EQ, ->(a, b) { a == b }], :!= => [:GATE_NE, ->(a, b) { a != b }],
          :& => [:GATE_AND, ->(a, b) { a & b }], :| => [:GATE_OR, ->(a, b) { a | b }], :^ => [:GATE_XOR, ->(a, b) { a ^ b }],
          :>> => [:GATE_SHR, ->(a, b) { b.between?(0, 62) ? a >> b : nil }]
        }.freeze

        # `recv name arg` without a send, as a binary's site answers it
        # (`Arith#operator`): two fixnums under a clear gate (the core
        # ignores the gates, as ruby's C does); in the core, `==` and `!=`
        # of the values that CRuby's C compares natively, and `<=>` of two
        # fixnums while Integer#<=> is ruby's own. Else nil, and the send
        # runs.
        def operator(name, recv, arg, c, operands = [])
          native = native_operators?(c)
          if (op = FIXNUM_OPS[name]) && (recv & arg & 1) == 1 && (native || (@host.gates & k.const_get(op.first)).zero?)
            case (r = op.last.call(recv >> 1, arg >> 1))
            when true then return @qtrue
            when false then return @qfalse
            when FIXNUM then return (r << 1) | 1
            end
          end
          v = float_op(name, recv, arg, native, operands)
          return v if v
          return unless native

          case name
          when :==, :!=
            kind = k.zr_native_eq_kind(recv, arg)
            bool(name == :== ? kind == 1 : kind != 1) unless kind.zero?
          when :<=>
            ((((recv >> 1) <=> (arg >> 1)) << 1) | 1) if (recv & arg & 1) == 1 && (@host.gates & k::GATE_CMP).zero?
          end
        end

        # The operators with a flonum path, and Float's gate of each
        # (Lower::Function::Sends::FLOAT_OPS).
        FLOAT_OPS = {
          :+ => :GATE_FLO_PLUS, :- => :GATE_FLO_MINUS, :* => :GATE_FLO_MUL, :/ => :GATE_FLO_DIV,
          :< => :GATE_FLO_LT, :<= => :GATE_FLO_LE, :> => :GATE_FLO_GT, :>= => :GATE_FLO_GE, :== => :GATE_FLO_EQ
        }.freeze
        FLOAT_COMPARES = %i[< <= > >= ==].freeze

        # `recv name arg` on doubles (`Arith#float_path`): both operands
        # are flonums, or one is a flonum and the other a fixnum (within
        # 2**53 for a comparison), and the gates are clear. A site whose
        # `operands` has an Integer literal in a sum, a difference or a
        # comparison has no flonum path (`Arith#float_path?`). Else nil.
        def float_op(name, recv, arg, native, operands)
          return unless (gate = FLOAT_OPS[name])
          return if %i[* /].none?(name) && operands.any? { |n| n.is_a?(Hir::Literal) && n.value.is_a?(Integer) }

          compare = FLOAT_COMPARES.include?(name)
          return unless [recv, arg].any? { |v| v & 3 == 2 } && [recv, arg].all? { |v| float_number?(v, compare) }
          return unless native || (@host.gates & (k.const_get(FIXNUM_OPS.fetch(name).first) | k.const_get(gate))).zero?

          x, y = [recv, arg].map { |v| v & 3 == 2 ? k.zr_float_value(v) : (v >> 1).to_f }
          r = x.public_send(name, y)
          compare ? bool(r) : k.zr_float_new(r)
        end

        def float_number?(v, exact)
          return true if v & 3 == 2
          return false unless v & 1 == 1

          !exact || ((v >> 1) + (1 << 53)).between?(0, (1 << 54) - 1)
        end

        # Whether a core send of `name` finds the core's own method
        # (`Sends#core_send?`): any name but PROTOCOL, and `each` except in
        # a method marked `:sends_each`, where ruby's C sends it by name.
        def core_send?(name, c)
          return false unless c.unit.internal

          name == :each ? !(c.method && attributes(c.method).include?(:sends_each)) : !PROTOCOL.include?(name)
        end

        # Whether the scope answers the core's operators natively
        # (`Arith#native_operators?`): core code outside a method that
        # CRuby writes in Ruby (`Primitive.attr! :ruby`).
        def native_operators?(c)
          c.unit.internal && !(c.method && attributes(c.method).include?(:ruby))
        end

        # A send through the site's cell, tested here first as a binary's
        # site tests it (`Sends#cached_send`): if the receiver's class and
        # the site stamp are the cell's, call the cell's function; else the
        # kernel's send, which fills a cell.
        def cached_send(cc, recv, mid, argc, av, blk, mode)
          cell = k::CallCache
          klass = if recv & 1 == 1 then (@integer ||= k.zr_global(k::G_INTEGER))
                  elsif recv & 7 == 0 && recv > @qnil then k::RBasic.klass(recv)
                  else k.zr_class_of(recv)
                  end
          if cell.klass(cc) == klass && cell.stamp(cc) == Memory.fetch(TYPES["Word"], @site_stamp ||= @host.static("site_stamp", 8))
            return k::Method.call(cell.fn(cc), recv, argc, av, cell.entry(cc), blk, cell.found(cc))
          end

          k.zr_send_cached(cc, recv, mid, argc, av, blk, mode)
        end

        # Positional arguments as Values, or, with a Splat, one Array.
        def arguments(nodes, c)
          return [nodes.map { |a| ev(a, c) }, nil] unless nodes.any?(Hir::Splat)

          [[], gather(nodes, c)]
        end

        # The result of a send that a literal block goes with: a `break`
        # out of the block ends here.
        def sent(block, c)
          r = yield
          return r if r != @qundef
          raise UNWIND, cause: nil unless block

          check(k.zr_catch_break(c.rec, @sites[block]))
        end

        # The site's refinements are active when `&value` becomes a Proc,
        # so `&:name` and a refined `to_proc` use them.
        def block_arg(block, c, site = nil)
          case block
          when nil then @qnil
          when Hir::BlockPass
            v = ev(block.value, c)
            activate(site, c) if site
            check(k.zr_block_pass(v))
          when Hir::Block then block_image(block, c)
          end
        end

        # A block literal: an RProc image in the slot area, as the lowering
        # makes in the caller's record (FL_STACK). A callee that keeps it
        # copies it to the heap (`zr_block_proc`).
        def block_image(node, c)
          r = k::RProc
          p = @host.slot(r.layout_size)
          fields = r.layout_fields
          put = ->(name, v) { Memory.write(p + fields.fetch(name).first, [v & MASK].pack("Q<")) }
          put.call("basic", k::T_PROC | k::FL_ALLOCATED | k::FL_STACK)
          Memory.write(p + 8, [k.zr_global(k::G_PROC) & MASK].pack("Q<"))
          fn, m = block_fn(node, c)
          serial = k.zr_frame_serial(c.rec)
          ret_home, ret_serial = if c.kind == :block && !lambda_proc?(c.proc)
                                   [k::RProc.ret_home(c.proc), k::RProc.ret_serial(c.proc)]
                                 else
                                   [c.rec, serial]
                                 end
          { "fn" => fn, "meta" => m, "env" => c.env, "self" => c.self_, "cref" => c.cref, "blk" => c.blk, "home" => c.rec,
            "serial" => serial, "site" => @sites[node], "ret_home" => ret_home, "ret_serial" => ret_serial,
            "spread" => node.params.spread? ? 1 : 0, "lambda" => 0, "passed" => 0 }.each { |name, v| put.call(name, v) }
          p
        end

        # The function of the block `node`: `(proc, argc, argv, blk) =>
        # Value`, and its FrameMeta.
        def block_fn(node, c)
          scopes = c.scopes
          unit = c.unit
          method = c.method
          parent = c.meta
          homes = [node, *c.homes]
          @fns[node] ||= begin
            kind = unit.internal ? k::KIND_HIDDEN : k::KIND_BLOCK
            m = meta(node, unit, kind, parent: parent, params: node.params, locals: node.locals, open: open?(node, :block, unit, node.params),
                                       cover: node.cover)
            k::FrameMeta.set_captures(m, captures_table(node, homes, unit.spelling))
            fn = @host.callable(lambda do |pr, argc, argv, blk|
              frame(meta: m, self_: k::RProc.self(pr), cref: k::RProc.cref(pr), blk: k::RProc.blk(pr), defined: blk,
                    locals: node.locals, parent_env: k::RProc.env(pr), scopes: scopes, unit: unit, method: method,
                    kind: :block, proc: pr, params: node.params, homes: homes) do |inner|
                run_body(inner, node) do
                  bind_block(node.params, argc, argv, blk, inner, @fns[node].first)
                  opened(inner, :block)
                  # A `redo` in the block throws its meta (`Hir::Redo`).
                  redoable(inner.meta) { node.body ? ev(node.body, inner) : @qnil }
                end
              end
            end)
            k::FrameMeta.set_fn(m, fn)
            [fn, m]
          end
        end

        # The captures table of the block `node` (`Lower#captures_table`):
        # each outer local with its flags (1: the block writes it, 2: its
        # scope binds it more than once), in the order of the program's
        # `spelling`. A Ractor reads it.
        def captures_table(node, homes, spelling)
          rows = Hir::Locals.captures(node).sort_by { |name, _, _| spelling.index(name) }
          words = rows.flat_map do |name, depth, written|
            home = homes[depth]
            counts = home.respond_to?(:body) ? Hir::Locals.assignments(home.body) : Hash.new(0)
            home.params.names.each { |n| counts[n] += 1 } if home.respond_to?(:params) && home.params
            [id(name), (written ? 1 : 0) | (counts[name] > 1 ? 2 : 0)]
          end
          table([rows.size, *words])
        end

        def bind_block(p, argc, argv, blk, c, fn)
          lambda = lambda_proc?(c.proc)
          t = task
          kw = k::Task.kw(t)
          k::Task.set_kw(t, 0)
          kwhash = nil
          if keywords?(p)
            argc = k.zr_kw_tab_in(kw, argc, argv) if kw > 1
            if kw != 0
              argc -= 1
              kwhash = Memory.fetch(TYPES["Value"], argv + (argc * 8))
            end
          elsif kw != 0
            argc = k.zr_kw_undeclared(kw, argc, argv, p.rest && p.rest != :implicit ? fn : 0)
          end
          return check_arity(p, argc) if p.names.empty? && p.plain? && lambda

          check_arity(p, argc) if lambda
          if p.spread? && !lambda
            out = @host.slot(16)
            n = check(k.zr_block_args(argc, argv, p.optional.empty? ? 1 : 2, out, out + 8))
            argc = n >> 1
            argv = Memory.fetch(TYPES["Ptr"], out)
          end
          args = argc.zero? ? [] : Memory.read(argv, argc * 8).unpack("q<*")
          if lambda
            bind_positional(p, args, c)
          else
            loose(p, args, c)
          end
          bind_keywords(p, kwhash, c) if keywords?(p)
          set_local(p.block, k.zr_block_proc(blk), c) if p.block && owns?(p, p.block, [:block, 0])
        end

        # A proc's parameters: missing ones are nil, extra ones are dropped.
        def loose(p, args, c)
          front = p.required.size
          back = p.post.size
          optional = p.optional.size
          has_rest = p.rest && p.rest != :implicit
          given_opt = [[args.size - front - back, 0].max, optional].min
          p.required.each_with_index { |t, i| bind_target(t, args.fetch(i, @qnil), c) if first?(p, t, i) }
          bind_optional(p, args, front, given_opt, c)
          start = front + given_opt
          post_at = has_rest ? [args.size - back, start].max : start
          if has_rest
            rest = args[start...post_at] || []
            set_local(p.rest, k.zr_ary_of(rest.size, argv(rest)), c) if owns?(p, p.rest, [:rest, 0])
          end
          p.post.each_with_index { |t, i| bind_target(t, args.fetch(post_at + i, @qnil), c) if first?(p, t, front + i) }
        end

        def lambda_node(node, c)
          slots { check(k.zr_proc_lambda(block_image(node.block, c))) }
        end

        def yield_node(node, c)
          args, splat = arguments(node.args, c)
          kwargs = node.kwargs && hash(node.kwargs, c)
          slots do
            values = splat ? elements(splat) : args
            values += [kwargs] if kwargs
            av = argv(values)
            argc = values.size
            argc = k.zr_kw_argc(argc, av) if kwargs
            at(node, c)
            # The core yields through the kernel, which polls the scheduler;
            # a program calls the block's function (`Control#block_call`).
            if c.unit.internal || c.blk == @qnil
              check(k.zr_yield(c.blk, argc, av))
            else
              check(k::Block.call(k::RProc.fn(c.blk), c.blk, argc, av, @qnil))
            end
          end
        end

        def primitive(node, c)
          return @qnil if node.name == :attr!
          return get_local(node.args.first.value, 0, c) if node.name == :arg!

          args = node.args.map { |a| ev(a, c) }
          slots do
            if node.block
              sent(node.block, c) { k.public_send(node.name, *args, block_image(node.block, c)) }
            else
              check(k.public_send(node.name, *args))
            end
          end
        end

        # `super(args)`. A bare `super` in a block, which the builder
        # expanded, first asks whether `define_method` made the block a
        # method: ruby refuses that.
        def super_node(node, c)
          if node.in_block
            at(node, c)
            check(k.zr_zsuper_in_block(c.rec))
          end
          args, splat = arguments(node.args, c)
          kwargs = node.kwargs && hash(node.kwargs, c)
          slots do
            blk = node.block ? block_arg(node.block, c) : c.blk
            values = splat ? elements(splat) : args
            values += [kwargs] if kwargs
            av = argv(values)
            argc = values.size
            argc = k.zr_kw_argc(argc, av) if kwargs
            argc = k.zr_kw_ruby2_out(argc, av) if splat && !kwargs
            at(node, c)
            sent(node.block.is_a?(Hir::Block) ? node.block : nil, c) do
              activate(node, c)
              k.zr_super(cell(node, :sc, k::SuperCache.layout_size), c.rec, argc, av, blk).tap do
                k::Task.set_refine(task, @qnil) if node.using
              end
            end
          end
        end

        # A bare `super` that the builder could not expand into a Super with
        # the method's parameters: no def encloses it. The kernel raises.
        def zsuper(node, c)
          at(node, c)
          check(k.zr_zsuper_outside(c.rec))
        end

        # A send that the walker makes: `recv.name(*values)`.
        # An op-assign's sends (`c` given) see the refinements of its
        # `using` entry.
        def call(recv, name, values, node, kind = :op, mode: 0, c: nil)
          using = c && node.using
          mode |= SEND_CORE if c && core_send?(name, c)
          slots do
            activate(node, c) if using
            r = k.zr_send_cached(cell(node, kind, 4 * k::CallCache.layout_size), recv, id(name), values.size, argv(values), @qnil,
                                 using ? mode | SEND_USING : mode)
            k::Task.set_refine(task, @qnil) if using
            check(r)
          end
        end

        # `!x`: nil, false and true answer here while no class redefines
        # `!` (the gate GATE_NOT; the core ignores the gates); any other
        # value gets the send (Lower::Function::Arith#negate).
        def negate(node, c)
          v = ev(node.value, c)
          return bool(!truthy?(v)) if (v | 28) == 28 && (c.unit.internal || (@host.gates & k::GATE_NOT).zero?)

          at(node, c)
          call(v, :!, [], node, :not, mode: 2)
        end

        # An op-assign's read and write are sends as written: through
        # `self` they may call a private method, else they are explicit.
        def op_mode(node) = node.recv.is_a?(Hir::SelfRef) ? 0 : 2

        def index_op_assign(node, c)
          recv = ev(node.recv, c)
          args, splat = arguments(node.args, c)
          args = elements(splat) if splat
          at(node, c)
          old = call(recv, :[], args, node, :get, mode: op_mode(node), c: c)
          v = op_value(node, old, c) { return old }
          at(node, c)
          call(recv, :[]=, args + [v], node, :set, mode: op_mode(node), c: c)
          v
        end

        def attr_op_assign(node, c)
          recv = ev(node.recv, c)
          return @qnil if node.safe && recv == @qnil

          at(node, c)
          old = call(recv, node.name, [], node, :get, mode: op_mode(node), c: c)
          v = op_value(node, old, c) { return old }
          at(node, c)
          call(recv, :"#{node.name}=", [v], node, :set, mode: op_mode(node), c: c)
          v
        end

        # The new value of an op-assign, or the block's for `||=` and `&&=`
        # that leave the old one.
        def op_value(node, old, c)
          case node.op
          when :or then truthy?(old) ? yield : ev(node.value, c)
          when :and then truthy?(old) ? ev(node.value, c) : yield
          else
            # The operator is a send of its own (`Targets#op_assign`), with
            # an operator's paths.
            arg = ev(node.value, c)
            fast = operator(node.op, old, arg, c, [node.value]) unless node.using == :owner || c.unit.traced
            fast || call(old, node.op, [arg], node, :op, c: c)
          end
        end

        # --- assignment ---

        # A multiple assignment's send targets' receivers and arguments, and
        # its constant targets' scopes, evaluated before the right-hand
        # side, in ruby's order (`Targets#prepare`).
        def stage_targets(target, c, prepared = {}.compare_by_identity)
          (target.lefts + [target.rest] + target.rights).each do |t|
            case t
            when Hir::Send
              recv = @host.pin(t.recv ? ev(t.recv, c) : c.self_)
              args, splat = arguments(t.args, c)
              prepared[t] = [recv, (splat ? elements(splat) : args).each { |a| @host.pin(a) }]
            when Hir::ConstWrite
              prepared[t] = @host.pin(ev(t.scope, c)) unless t.scope.nil? || t.scope == :top
            when Hir::MultiTarget then stage_targets(t, c, prepared)
            end
          end
          prepared
        end

        # `a, b = b, a` as a statement makes no Array (`Targets#spread_assign`).
        def spread_assign?(node)
          value = node.value
          !node.taken && value.is_a?(Hir::ArrayLit) && value.elements.none?(Hir::Splat) && node.target.rights.empty?
        end

        def spread_assign(node, c, prepared)
          target = node.target
          values = node.value.elements.map { |e| @host.pin(ev(e, c)) }
          target.lefts.each_with_index { |t, i| assign_target(t, values.fetch(i, @qnil), c, prepared) }
          rest = target.rest
          unless rest.nil? || rest == :implicit
            tail = values.drop(target.lefts.size)
            slots { assign_target(rest, k.zr_ary_of(tail.size, argv(tail)), c, prepared) }
          end
          @qnil
        end

        def multi(target, v, c, prepared = {})
          ary = @host.pin(check(k.zr_masgn_ary(v)))
          nl = target.lefts.size
          nr = target.rights.size
          target.lefts.each_with_index { |t, i| assign_target(t, k.zr_ary_at(ary, i), c, prepared) }
          if target.rest && target.rest != :implicit
            assign_target(target.rest, check(k.zr_masgn_rest(ary, nl, nr)), c, prepared)
          end
          target.rights.each_with_index { |t, i| assign_target(t, k.zr_masgn_right(ary, nl, nr, i), c, prepared) }
          v
        end

        def assign_target(t, v, c, prepared = {})
          case t
          when Hir::Assign then set_local(t.name, v, c, t.depth)
          when Hir::IvarWrite
            at(t, c)
            check(k.zr_ivar_set_cached(c.self_, id(ivar(t.name, c)), v, cell(t, :ic, k::IvarCache.layout_size)))
          when Hir::GvarWrite then gvar_write(t.name, v, c, t.shown)
          when Hir::CvarWrite then check(k.zr_cvar_set(c.cref, id(t.name), v))
          when Hir::ConstWrite
            scope = prepared.fetch(t) { scope_class(t.scope, c) }
            check(k.zr_const_set(scope, id(t.name), v))
          when Hir::MultiTarget then multi(t, v, c, prepared)
          when Hir::Splat then assign_target(t.value, v, c, prepared)
          when Hir::Send
            recv, args = prepared.fetch(t) do
              r = t.recv ? ev(t.recv, c) : c.self_
              a, splat = arguments(t.args, c)
              [r, splat ? elements(splat) : a]
            end
            return @qnil if t.safe && recv == @qnil

            mode = t.recv && !t.recv.is_a?(Hir::SelfRef) ? 2 : 0
            mode |= SEND_CORE if core_send?(t.name, c)
            at(t, c)
            slots do
              values = args + [v]
              check(if (entry = opt_entry(t, c, recv))
                      k.public_send(entry, recv, id(t.name), values.size, argv(values), mode)
                    else
                      k.zr_send_cached(cell(t, :cc, 4 * k::CallCache.layout_size), recv, id(t.name), values.size, argv(values), @qnil, mode)
                    end)
            end
          else raise Unsupported, "an assignment to a #{t.class}"
          end
        end

        # --- control ---

        def case_node(node, c)
          subject = node.subject && ev(node.subject, c)
          node.clauses.each do |values, body|
            hit = values.any? do |value|
              if value.is_a?(Hir::Splat)
                list = ev(value.value, c)
                truthy?(subject ? check(k.zr_case_any(subject, list)) : check(k.zr_any_truthy(list)))
              else
                v = ev(value, c)
                truthy?(subject ? call(v, :===, [subject], value, :eqq) : v)
              end
            end
            return ev(body, c) if hit
          end
          ev(node.else_body, c)
        end

        # `begin`/`rescue`/`else`/`ensure`, as Lower::Function::Regions.
        #
        # An ensure body runs on every exit: inline after the body, with
        # the pending unwind set aside for a raise (`ensured`), and as it is
        # for a local jump (a `throw` out of the region).
        def begin_node(node, c)
          saved = k.zr_errinfo
          return rescued(node, saved, c) unless node.ensure_body

          left = true
          begin
            value = rescued(node, saved, c)
            left = false
          rescue Unwind
            left = false
            ensured(node, c, saved)
            raise
          ensure
            ev(node.ensure_body, c) if left
          end
          ev(node.ensure_body, c)
          value
        end

        def rescued(node, saved, c)
          return ev(node.else_body ? Hir::Seq.new([node.body, node.else_body].compact, node.line) : node.body, c) if node.rescues.empty?

          begin
            v = ev(node.body, c)
          rescue Unwind
            exc = k.zr_rescuable
            raise if exc == @qundef

            clause = node.rescues.find { |r| matches?(r, exc, c) } or raise
            k.zr_rescue_enter
            # `:rescue` fires at the clause's first statement (`Regions`).
            begin
              check(k.zr_trace_rescue((clause.body || clause).line))
              assign_target(clause.target, exc, c) if clause.target
              return ev(clause.body, c)
            rescue RetryJump
              k.zr_errinfo_set(saved)
              return rescued(node, saved, c)
            ensure
              k.zr_errinfo_set(saved)
            end
          end
          node.else_body ? ev(node.else_body, c) : v
        end

        def matches?(clause, exc, c)
          return truthy?(check(k.zr_exc_match(exc, k.zr_global(k::G_STANDARD_ERROR)))) if clause.classes.empty?

          clause.classes.any? do |klass|
            if klass.is_a?(Hir::Splat)
              truthy?(check(k.zr_exc_match_any(exc, ev(klass.value, c))))
            else
              truthy?(check(k.zr_exc_match(exc, ev(klass, c))))
            end
          end
        end

        # The ensure body on an unwind: the pending unwind is set aside
        # while it runs, and restored after.
        #
        # If the ensure body itself leaves (a raise or a jump), `$!` goes
        # back to `saved`, its value when the region began.
        def ensured(node, c, saved)
          prev = k.zr_errinfo
          slots do
            out = @host.slot(24)
            v = k.zr_signal_take(out)
            done = false
            begin
              ev(node.ensure_body, c)
              done = true
            ensure
              k.zr_errinfo_set(saved) unless done
            end
            k.zr_errinfo_set(prev)
            k.zr_signal_restore(v, out)
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

        def defined(node, c)
          name = DEFINED_NAMES.fetch(node.kind)
          if TESTED.include?(node.kind)
            ok = UNGUARDED.include?(node.kind) ? defined_test(node, c) : guarded { defined_test(node, c) }
            return @qnil unless ok
          end
          k.zr_str_frozen(@host.bytes(name), name.bytesize)
        end

        def defined_test(node, c)
          case node.kind
          when :ivar then truthy?(check(k.zr_ivar_defined(c.self_, id(ivar(node.target, c)))))
          when :gvar then truthy?(k.zr_gvar_defined(id(node.target)))
          when :backref then ev(node.target, c) != @qnil
          when :cvar
            at(node, c)
            truthy?(check(k.zr_cvar_defined(c.cref, id(node.target))))
          when :const then const_defined?(node.target, c)
          when :method, :attrasgn then method_defined?(node.target, c)
          when :list then node.target.all? { |part| part_defined?(part, c) }
          when :yield then c.blk != @qnil
          when :super then truthy?(k.zr_super_defined(c.rec))
          else true
          end
        end

        # Whether an expression used as a receiver or argument is itself
        # defined: a name by its form, anything else is.
        def part_defined?(node, c)
          case node
          when Hir::Send then method_defined?(node, c)
          when Hir::ArrayLit then node.elements.all? { |e| part_defined?(e, c) }
          when Hir::HashLit then node.pairs.compact.all? { |p| part_defined?(p.is_a?(Hir::HashSplat) ? p.value : p, c) }
          when Hir::ConstRead then const_defined?(node, c)
          when Hir::IvarRead then defined_test(Hir::Defined.new(:ivar, node.name, node.line), c)
          when Hir::GvarRead then defined_test(Hir::Defined.new(:gvar, node.name, node.line), c)
          when Hir::CvarRead then defined_test(Hir::Defined.new(:cvar, node.name, node.line), c)
          else true
          end
        end

        def const_defined?(read, c)
          return truthy?(k.zr_const_defined(c.cref, id(read.name))) if read.scope.nil?

          scope = read.scope == :top ? k.zr_global(k::G_OBJECT) : ev(read.scope, c)
          truthy?(k.zr_const_defined_at(scope, id(read.name)))
        end

        # A method: its receiver and arguments must be defined, then the
        # receiver's class answers. Any receiver, `self` too, makes the
        # call explicit.
        def method_defined?(send, c)
          return false unless [send.recv, *send.args].compact.all? { |part| part_defined?(part, c) }

          recv = send.recv ? ev(send.recv, c) : c.self_
          truthy?(k.zr_method_defined(recv, id(send.name), !send.recv.nil?))
        end

        # The block's value, or nil if it raised (the raise is dropped).
        def guarded
          saved = k.zr_errinfo
          yield
        rescue Unwind
          k.zr_rescuable
          k.zr_rescue_enter
          k.zr_errinfo_set(saved)
          nil
        end
      end
    end
  end
end
