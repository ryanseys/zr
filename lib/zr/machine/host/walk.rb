# frozen_string_literal: true

require_relative "boot"
require_relative "../../hir"
require_relative "../../paths"
require_relative "walk/frames"
require_relative "walk/code"
require_relative "walk/sends"
require_relative "walk/control"
require_relative "walk/assign"
require_relative "walk/arguments"
require_relative "walk/definitions"
require_relative "walk/regexps"

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
      # The walker compiles each scope's HIR to Ruby lambdas once (`Code`),
      # and runs those: the work that depends only on the tree is done
      # once, not at each run. The modules below follow the lowering's
      # (`Lower::Function`): `Frames`, `Code`, `Sends`, `Control`,
      # `Assign`, `Arguments` and `Definitions`.
      #
      # A pending unwind in the task (a raise, a break to a call site, a
      # return from a block) is the Ruby exception `Unwind` in the walker,
      # until a rescue, a call site or a frame takes it; a frame then
      # returns QUNDEF to the kernel.
      class Walk
        include Frames
        include Code
        include Sends
        include Control
        include Assign
        include Arguments
        include Definitions
        include Regexps

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
        # @rbs skip -- typed in sig/zr/machine/host/walk.rbs
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
          @once = {}.compare_by_identity
          # The bytes of a String that `value` makes, before the kernel
          # copies them.
          @scratch = 0
          @scratch_size = 0
          @task_slot = k.zr_current_task_slot
          boot.walk = self
          @boot_classes = File.read(File.join(Paths::RUNTIME, "kernel/main.rb"))
                              .scan(/zr_boot_name\((G_\w+), Machine\.id\(:(\w+)\)\)/).to_h { |slot, name| [name.to_sym, k.const_get(slot)] }
          layouts!
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
          hir = Runtime.gem_prelude(target)
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
          name = Memory.zeroed(16)
          Memory.set_words(name, [@host.bytes("zr"), 0])
          k.zr_args_init(1, name)
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
        # The running task (`zr_task`), read from its static slot.
        def task = Memory.word(@task_slot)

        # The offsets of the kernel's fields that the code reads and writes
        # itself, and the statics it reads.
        def layouts!
          k = @kern
          @record = k::Frame.layout_size
          @line_at = offset(k::Frame, "line")
          @env_slots = offset(k::REnv, "slots")
          @env_parent = offset(k::REnv, "parent")
          @ary_ptr = offset(k::RArray, "ptr")
          @ary_len = offset(k::RArray, "len")
          @basic_klass = offset(k::RBasic, "klass")
          @proc_fn = offset(k::RProc, "fn")
          @proc_env = offset(k::RProc, "env")
          @proc_self = offset(k::RProc, "self")
          @proc_cref = offset(k::RProc, "cref")
          @proc_blk = offset(k::RProc, "blk")
          @proc_ret_home = offset(k::RProc, "ret_home")
          @proc_ret_serial = offset(k::RProc, "ret_serial")
          @proc_lambda = offset(k::RProc, "lambda")
          @cc_klass = offset(k::CallCache, "klass")
          @cc_stamp = offset(k::CallCache, "stamp")
          @cc_entry = offset(k::CallCache, "entry")
          @cc_found = offset(k::CallCache, "found")
          @cc_fn = offset(k::CallCache, "fn")
          task = k::Task.layout_fields
          @task_top = Memory.reader(TYPES["Ptr"], task.fetch("top").first)
          @task_set_top = Memory.writer(TYPES["Ptr"], task.fetch("top").first)
          @task_limit = Memory.reader(TYPES["Ptr"], task.fetch("stack_limit").first)
          @task_refine = Memory.writer(TYPES["Value"], task.fetch("refine").first)
          @task_kw = Memory.reader(TYPES["Word"], task.fetch("kw").first)
          @task_set_kw = Memory.writer(TYPES["Word"], task.fetch("kw").first)
          @site_stamp = @host.static("site_stamp", 8)
          @poll = @host.static("current_task", 16) + 8
          @trace_events = @host.static("trace_events", 8)
          @integer = k.zr_global(k::G_INTEGER)
        end

        def offset(layout, field) = layout.layout_fields.fetch(field).first

        # A core file's or a program's toplevel.
        def toplevel(hir, unit, kind)
          # One lowering takes a program and its units, or the units of eval
          # support, so they share one spelling.
          unit.spelling ||= (@spellings ||= {}.compare_by_identity)[unit.units || hir] ||=
            Spelling.new(hir.is_a?(Hir::Program) ? [hir, *unit.units] : Array(unit.units))
          shown = unit.internal ? k::KIND_HIDDEN : kind
          main = kind == k::KIND_MAIN
          open = open?(hir, main ? :main : :top, unit)
          m = meta(hir, unit, shown, locals: hir.locals, open: open)
          s = scope(hir, unit, :main, m, scopes: [hir.locals], homes: [hir], open: open)
          body = code(hir.body, s)
          jumps = jumps?(hir.body)
          enter(s, k.zr_global(k::G_MAIN), k.zr_global(k::G_TOP_CREF), @qnil) do |f|
            unless unit.internal
              if main
                file = unit.file.to_s.b
                k.zr_program_start(@host.bytes(file), file.bytesize)
                k.zr_toplevel_binding(f.env, f.self_, f.cref, m)
              end
              Array(hir.warnings).each do |line|
                text = "#{line}\n".b
                k.zr_write_err(@host.bytes(text), text.bytesize)
              end
            end
            run_body(s, f, jumps) { body.call(f) }
          end
        end

        # Gives the load tables what a link writes into a binary
        # (`LoadTables#data`): the texts (`LoadTables#texts`: for a program with
        # eval, what a require of a computed name searches; error_highlight's
        # spots; Coverage's tables), and the files the program was built
        # with, by path, each with its toplevel, where a require of a
        # computed name finds its file (`zr_unit_for`).
        TEXTS = %w[roots missing preloaded ext spots coverable branches defs sources manifest].freeze

        def spotted(hir, target)
          words = Memory.word(@host.extern("zr_load_tables"))
          table = k::LoadTable
          texts = LoadTables.new(evals: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {}, branches: hir.branches || {},
                                 defs: hir.defs || {}, target: target, manifest: Manifest.bytes(Manifest.of_program(hir, @eval_files), target)).texts
          TEXTS.zip(texts) do |field, lines|
            text = lines.join("\n").b
            Memory.set_words(words + table.layout_fields.fetch(field).first, [@host.bytes(text), text.bytesize])
          end
          units = Hash(hir.entries).select { |path, _| path.start_with?("/") }.map { |path, unit| [Paths.shown(path), unit] }.sort_by(&:first)
          rows = units.flat_map do |path, unit|
            bytes = path.b
            [@host.bytes(bytes), bytes.bytesize, entry_in(hir.units, unit)]
          end
          at = Memory.zeroed([rows.size * 8, 8].max, 8)
          Memory.set_words(at, rows) unless rows.empty?
          table.set_units(words, units.size)
          table.set_rows(words, at)
        end

        # `values` as an argument vector in the slot area for a call that no
        # frame makes; the slots are given back after the block.
        def outside(values)
          stack = @host.stack
          top = stack.top
          p = stack.take(values.size * 8)
          Memory.set_words(p, values)
          yield p
        ensure
          stack.top = top
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
            @loader = b::Loader.new(Library::Roots.stdlib(target), description: Library::Roots.description(target))
            # A binary's eval support adds the compiler first, hidden, and
            # with it prism. Here the translator adds prism first, so prism
            # stays hidden from the program, as there, when irb requires it.
            b.ast_translator(@loader)
            b.rubygems(@loader)
            b.rbconfig(@loader)
            b.normalizer(@loader)
            b.pretty_printer(@loader)
            b.irb_session(@loader)
            @compiler = Library::Roots.eval_file(target)
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
          s = scope(hir, unit, :eval, m, scopes: [hir.locals, *outer], homes: [])
          run = nil
          fn = @host.callable(lambda do |self_, cref, env, blk|
            run ||= [code(hir.body, s), jumps?(hir.body)]
            body, jumps = run
            enter(s, self_, cref, blk, env: env, outer: k::REnv.parent(env)) do |f|
              run_body(s, f, jumps) { body.call(f) }
            end
          end)
          words = [fn, m, hir.locals.size, id_table(hir.locals)].map { |w| (w << 1) | 1 }
          # The fifth word: the metas that a box stamps (`Ruby::Box#run`).
          metas = outside([(m << 1) | 1]) { |av| @host.pin(k.zr_ary_of(1, av)) }
          outside(words + [metas]) { |av| k.zr_ary_of(words.size + 1, av) }
        rescue Hir::Invalid, SyntaxError => e
          message = e.message.b
          klass = k.zr_core_class(id(:SyntaxError))
          return k.zr_raise_msg(klass, @host.bytes(message), message.bytesize) unless e.is_a?(SyntaxError) && e.backtrace == [e.path]

          # An error in the string alone (a stray `yield`) keeps the
          # string's path as its backtrace (`Zr::Eval#compile`).
          exc = @host.pin(check(outside([string(e.message)]) { |av| k.zr_send(klass, id(:new), 1, av) }))
          path = @host.pin(outside([string(e.path)]) { |av| k.zr_ary_of(1, av) })
          check(outside([path]) { |av| k.zr_send(exc, id(:set_backtrace), 1, av) })
          k.zr_raise(exc)
        end

        # prism's files of eval support, required hidden as a binary's
        # compiler requires them, the first time the host's `Zr::Eval#parse`
        # runs.
        def prism!
          unless @prism
            @prism = true
            path, unit = @eval_files.units.find { |p, _| p.end_with?("/prism.rb") }
            check(k.zr_require(string(Paths.shown(path)), entry_in(nil, unit), Definitions::REQUIRE_KINDS.fetch(:hidden)))
          end
          @qnil
        end

        # `Zr::Eval#compile_file`: the toplevel of a file that the program
        # was not built with, as a fixnum address.
        def eval_file(path)
          name = text(path)
          hir = Hir.build(File.read(name), name, eval_support: false)
          unit = Unit.new(Paths.shown(name), Library::Roots.internal_library?(name), hir.units, hir.node_ids)
          fn = @host.callable(-> { toplevel(hir, unit, k::KIND_TOP) })
          (fn << 1) | 1
        end

        # A String's bytes as a Ruby String.
        def text(s)
          Memory.read(k::RString.ptr(s), k::RString.len(s)).force_encoding(::Encoding::UTF_8)
        end

        # A plain Ruby value as a Value: nil, true, false, Integers of the
        # fixnum range, Strings (their bytes) and Arrays of these. Each
        # String and Array is pinned (`Host#pin`), so a collection while the
        # rest is made keeps it.
        def value(x)
          case x
          when nil then @qnil
          when true then @qtrue
          when false then @qfalse
          when Integer then (x << 1) | 1
          when String
            bytes = x.b
            if @scratch_size < bytes.bytesize
              @scratch_size = [bytes.bytesize, 2 * @scratch_size].max
              @scratch = Memory.zeroed(@scratch_size)
            end
            Memory.write(@scratch, bytes)
            @host.pin(k.zr_str_new(@scratch, bytes.bytesize))
          when Array
            a = @host.pin(k.zr_ary_new(x.size))
            x.each { |e| k.zr_ary_push(a, value(e)) }
            a
          else raise ArgumentError, "a #{x.class} has no Value here"
          end
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
      end
    end
  end
end
