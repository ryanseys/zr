# frozen_string_literal: true

require_relative "boot"
require_relative "../../hir"
require_relative "../../ext"
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
      # kernel's heap. A value is a kernel Value; a send, a constant,
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
        # The kernel's Values, addresses and offsets are Integers. A code is
        # a lambda of the running Frame (`Code`).
        # @rbs @boot: Boot
        # @rbs @kern: untyped
        # @rbs @host: Host
        # @rbs @qnil: Integer
        # @rbs @qtrue: Integer
        # @rbs @qfalse: Integer
        # @rbs @qundef: Integer
        # @rbs @ids: Hash[Symbol, Integer]
        # @rbs @sites: Hash[Hir::node, Integer]
        # @rbs @cells: Hash[Hir::node, Hash[Symbol, Integer]]
        # @rbs @metas: Hash[Hir::node | Hir::Program | Hir::Unit, Integer]
        # @rbs @fns: Hash[untyped, untyped]
        # @rbs @tables: Hash[Array[Integer], Integer]
        # @rbs @rescues: Hash[Integer, Hash[Integer, Array[Integer]]]
        # @rbs @ensure_path: Symbol
        # @rbs @once: Hash[Hir::node, Integer]
        # @rbs @scratch: Integer
        # @rbs @scratch_size: Integer
        # @rbs @task_slot: Integer
        # @rbs @boot_classes: Hash[Symbol, Integer]
        # @rbs @traced: bool
        # @rbs @eval_files: EvalSupport
        # @rbs @eval_support: bool
        # @rbs @eval_entry: Integer?
        # @rbs @prism: bool
        # @rbs @file_spots: Hash[String, String]
        # @rbs @spellings: Hash[untyped, Spelling]
        # @rbs @owners: Hash[Hir::Params, Hash[Symbol?, [Symbol, Integer]]]
        # @rbs @attributes: Hash[Hir::Def, Array[Symbol]]
        # @rbs @funcall_of: Hash[Hir::Send, Hir::Send]
        # @rbs @funcalls: Hash[Hir::Send, bool]
        # @rbs @record: Integer
        # @rbs @line_at: Integer
        # @rbs @env_slots: Integer
        # @rbs @env_parent: Integer
        # @rbs @ary_ptr: Integer
        # @rbs @ary_len: Integer
        # @rbs @basic_klass: Integer
        # @rbs @proc_fn: Integer
        # @rbs @proc_env: Integer
        # @rbs @proc_self: Integer
        # @rbs @proc_cref: Integer
        # @rbs @proc_blk: Integer
        # @rbs @proc_ret_home: Integer
        # @rbs @proc_ret_serial: Integer
        # @rbs @proc_lambda: Integer
        # @rbs @cc_klass: Integer
        # @rbs @cc_stamp: Integer
        # @rbs @cc_entry: Integer
        # @rbs @cc_found: Integer
        # @rbs @cc_fn: Integer
        # @rbs @task_top: ^(Integer) -> untyped
        # @rbs @task_set_top: ^(Integer, untyped) -> untyped
        # @rbs @task_limit: ^(Integer) -> untyped
        # @rbs @task_refine: ^(Integer, untyped) -> untyped
        # @rbs @task_kw: ^(Integer) -> untyped
        # @rbs @task_set_kw: ^(Integer, untyped) -> untyped
        # @rbs @task_eval_using: ^(Integer, untyped) -> untyped
        # @rbs @site_stamp: Integer
        # @rbs @poll: Integer
        # @rbs @trace_events: Integer
        # @rbs @integer: Integer

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
        # `evaled` is a unit that an eval compiled, whose code has no
        # absolute path (`Lower#meta`'s `evaled`).
        # @rbs skip -- typed in sig/zr/machine/host/walk.rbs
        Unit = Struct.new(:file, :internal, :units, :node_ids, :core, :hidden, :root, :traced, :spelling, :evaled)

        # The order in which a lowering first meets each local name of its
        # program (`Lower#spell`): the toplevels in order, each scope's
        # locals before the scopes in it. A captures table is in this order.
        class Spelling
          # @rbs @roots: Array[Hir::Program | Hir::Unit]
          # @rbs @order: Hash[Symbol, Integer]?

          #: (Array[Hir::Program | Hir::Unit] roots) -> void
          def initialize(roots)
            @roots = roots
            @order = nil
          end

          #: (Symbol name) -> Integer
          def index(name) = order.fetch(name, order.size)

          private

          #: () -> Hash[Symbol, Integer]
          def order
            @order ||= begin
              seen = {} #: Hash[Symbol, Integer]
              @roots.each do |root|
                # The lowering releases a unit's locals only after it lowers it.
                spell(root.locals || raise(ArgumentError, "#{root.file}: its locals are gone"), seen)
                visit(root.body, seen)
              end
              seen
            end
          end

          #: (Array[Symbol] names, Hash[Symbol, Integer] seen) -> void
          def spell(names, seen) = names.each { |n| seen[n] ||= seen.size }

          #: (untyped n, Hash[Symbol, Integer] seen) -> void
          def visit(n, seen)
            case n
            when Hir::Def, Hir::Block, Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef then spell(n.locals, seen)
            end
            Hir.each_child(n) { |child| visit(child, seen) }
          end
        end

        attr_reader :boot #: Boot
        attr_reader :kern #: untyped
        attr_reader :host #: Host

        #: (?Boot boot) -> void
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
          @file_spots = {}
          @sites = Hash.new { |h, node| h[node] = h.size + 1 }.compare_by_identity
          @cells = {} #: Hash[Hir::node, Hash[Symbol, Integer]]
          @cells.compare_by_identity
          @metas = {} #: Hash[Hir::node | Hir::Program | Hir::Unit, Integer]
          @metas.compare_by_identity
          @fns = {} #: Hash[untyped, untyped]
          @fns.compare_by_identity
          @tables = {}
          @rescues = {}
          @ensure_path = :none
          @once = {} #: Hash[Hir::node, Integer]
          @once.compare_by_identity
          @spellings = {} #: Hash[untyped, Spelling]
          @spellings.compare_by_identity
          @owners = {} #: Hash[Hir::Params, Hash[Symbol?, [Symbol, Integer]]]
          @owners.compare_by_identity
          @attributes = {} #: Hash[Hir::Def, Array[Symbol]]
          @attributes.compare_by_identity
          @funcall_of = {} #: Hash[Hir::Send, Hir::Send]
          @funcall_of.compare_by_identity
          @funcalls = {} #: Hash[Hir::Send, bool]
          @funcalls.compare_by_identity
          # The bytes of a String that `value` makes, before the kernel
          # copies them.
          @scratch = 0
          @scratch_size = 0
          @task_slot = k.zr_current_task_slot
          boot.walk = self
          main = File.read(File.join(Paths::RUNTIME, "kernel/main.rb"))
          pairs = main.scan(/zr_boot_name\((G_\w+), Machine\.id\(:(\w+)\)\)/) #: Array[[String, String]]
          @boot_classes = pairs.to_h { |slot, name| [name.to_sym, k.const_get(slot)] }
          layouts!
        end

        # Runs each core file's toplevel in the order a binary's
        # `zr_prelude` runs them. Returns the Value of the last, or QUNDEF
        # when one left a pending unwind.
        #: (?Target target) -> Integer
        def core(target = Target.default)
          RuntimeSources.for(target).core_files.each do |path|
            hir = Hir.build(File.read(path), path, BuildOptions.new(target: target), program: false)
            r = toplevel(hir, Unit.new(path, true, hir.units, nil, true), @kern::KIND_MAIN)
            return r if r == @qundef
          end
          @qnil
        end

        # Runs the program `hir` (a Hir::Program) as `zr_toplevel`.
        #: (Hir::Program hir, String file, ?Target target) -> Integer
        def program(hir, file, target = Target.default)
          spotted(hir, target)
          interned([hir])
          @traced = hir.traced ? true : false
          toplevel(hir, Unit.new(Paths.shown(file), false, hir.units, hir.node_ids, false, false, nil, @traced), @kern::KIND_MAIN)
        end

        # CRuby's gem prelude, as `zr_gem_prelude`.
        #: (?Target target) -> Integer
        def gem_prelude(target = Target.default)
          hir = Runtime.gem_prelude(target)
          toplevel(hir, Unit.new(Paths.shown(hir.file), false, hir.units, hir.node_ids), @kern::KIND_TOP)
        end

        # Runs `path` as a binary built from it runs: the boot, the core,
        # the gem prelude, then the program, with `args` as ARGV. Returns
        # the exit status.
        #: (String path, ?Array[String] args, ?target: Target) -> Integer
        def main(path, args = [], target: Target.default)
          prepare(target)
          run(path, args, target: target)
        end

        # All a program needs before its first line: the core and the gem
        # prelude. A test worker does this once, and forks for each program.
        #: (?Target target) -> void
        def prepare(target = Target.default)
          name = Memory.zeroed(16)
          Memory.set_words(name, [@host.bytes("zr"), 0])
          k.zr_args_init(1, name)
          @eval_files = EvalSupport.new(target)
          report_unwind(core(target))
          k.zr_box_snapshot
          k.zr_runtime_written
          report_unwind(gem_prelude(target))
          k.zr_gates_snapshot
        end

        # Runs the program at `path` with `args` in ARGV, after `prepare`.
        # Returns the exit status. `source` is the program's text in place
        # of the file's.
        #: (String path, ?Array[String] args, ?target: Target, ?source: String) -> Integer
        def run(path, args = [], target: Target.default, source: File.read(path))
          # A test worker forks after `prepare`: this process has its own
          # pid, and only the thread that forked.
          @boot.restart
          k.zr_gvar_assign(id(:$$), k.zr_process_id)
          list = k.zr_global(k::G_ARGV)
          k::RArray[list].len = 0
          args.each { |a| k.zr_ary_push(list, string(a)) }
          # As a build reads it: with error_highlight's spots, which a
          # build without eval support leaves out.
          hir = Hir.build(source, path, BuildOptions.new(target: target), prebuilt: @eval_files, extensions: Ext)
          r = program(hir, path, target)
          exc = @qundef
          if r == @qundef
            exc = k::Task[task].pending
            k::Task[task].pending = @qnil
          end
          k.zr_program_end(exc)
        end

        # The symbol id of `name`, interned in the kernel's table if the
        # kernel has not seen it. A name that is not ASCII keeps its
        # encoding as the tag of the entry (`zr_symbol_tag`).
        #: (Symbol name) -> Integer
        def id(name)
          @ids[name] ||= begin
            text = name.to_s
            @host.symbols.ids[text] || begin
              index = text.ascii_only? ? 1 : Code::ENCODING_INDEX.fetch(text.encoding)
              @kern.zr_intern_tagged(@host.bytes(text), text.bytesize, index < 2 ? 1 - index : index)
            end
          end
        end

        #: (Symbol name) -> Integer
        def sym(name) = (id(name) << 8) | 12

        # Interns each Symbol in the trees `roots`, as a binary's symbol
        # table has every name its program uses before the first line:
        # Symbol.all_symbols lists one that has not run yet.
        #: (Array[untyped] roots) -> void
        def interned(roots)
          stack = roots.dup
          until stack.empty?
            node = stack.pop
            case node
            when Symbol then id(node)
            when Hir::Node, Array then node.each { |child| stack << child }
            end
          end
        end

        private

        #: () -> untyped
        def k = @kern
        # The running task (`zr_task`), read from its static slot.
        #: () -> Integer
        def task = Memory.word(@task_slot)

        # Reports the pending unwind of a toplevel that returned QUNDEF.
        #: (Integer r) -> void
        def report_unwind(r)
          k.zr_report(k::Task[task].pending) if r == @qundef
        end

        # The offsets of the kernel's fields that the code reads and writes
        # itself, and the statics it reads.
        #: () -> void
        def layouts!
          k = @kern
          @record = k::Frame.size
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
          task = @host.layout_of(k::Task).fields
          @task_top = Memory.reader(TYPES["Ptr"], task.fetch("top").first)
          @task_set_top = Memory.writer(TYPES["Ptr"], task.fetch("top").first)
          @task_limit = Memory.reader(TYPES["Ptr"], task.fetch("stack_limit").first)
          @task_refine = Memory.writer(TYPES["Value"], task.fetch("refine").first)
          @task_kw = Memory.reader(TYPES["Word"], task.fetch("kw").first)
          @task_set_kw = Memory.writer(TYPES["Word"], task.fetch("kw").first)
          @task_eval_using = Memory.writer(TYPES["Word"], task.fetch("eval_using").first)
          @site_stamp = @host.static("site_stamp", 8)
          @poll = @host.static("current_task", 16) + 8
          @trace_events = @host.static("trace_events", 8)
          @integer = k.zr_global(k::G_INTEGER)
        end

        #: (singleton(View) layout, String field) -> Integer
        def offset(layout, field) = @host.layout_of(layout).fields.fetch(field).first

        # A core file's or a program's toplevel.
        #: (Hir::Program | Hir::Unit hir, Unit unit, Integer kind) -> Integer
        def toplevel(hir, unit, kind)
          # One lowering takes a program and its units, or the units of eval
          # support, so they share one spelling.
          unit.spelling ||= @spellings[unit.units || hir] ||=
            Spelling.new(hir.is_a?(Hir::Program) ? [hir, *unit.units.to_a] : unit.units.to_a)
          shown = unit.internal ? k::KIND_HIDDEN : kind
          main = kind == k::KIND_MAIN
          open = open?(hir, main ? :main : :top, unit)
          locals = hir.locals or raise ArgumentError, "#{hir.file}: its locals are gone"
          m = meta(hir, unit, shown, locals: locals, open: open)
          s = scope(hir, unit, :main, m, scopes: [locals], homes: [hir], open: open)
          body = code(hir.body, s)
          jumps = jumps?(hir.body)
          enter(s, k.zr_global(k::G_MAIN), k.zr_global(k::G_TOP_CREF), @qnil) do |f|
            unless unit.internal
              if main
                file = unit.file.to_s.b
                k.zr_program_start(@host.bytes(file), file.bytesize, @traced ? 1 : 0)
                k.zr_toplevel_binding(f.env, f.self_, f.cref, m)
              end
              parse_warnings(Array(hir.warnings))
            end
            run_body(s, f, jumps) { body.call(f) }
          end
        end

        # The parser's warnings `lines`, through Warning.warn and under
        # $VERBOSE, as the lowering's `parse_warnings` gives them.
        #: (Array[String] lines) -> void
        def parse_warnings(lines)
          lines.each do |line|
            verbose = line.start_with?(Hir::Build::Loader::VERBOSE_WARNING)
            text = "#{verbose ? line[1..] : line}\n".b
            k.zr_parse_warning(@host.bytes(text), text.bytesize, verbose ? 1 : 0)
          end
        end

        # Gives the load tables what a link writes into a binary
        # (`LoadTables#data`): the texts (`LoadTables#texts`: for a program with
        # eval, what a require of a computed name searches; error_highlight's
        # spots; Coverage's tables), and the files the program was built
        # with, by path, each with its toplevel, where a require of a
        # computed name finds its file (`zr_unit_for`).
        TEXTS = %w[roots missing preloaded ext spots coverable branches defs sources manifest redirects].freeze

        #: (Hir::Program hir, Target target) -> void
        def spotted(hir, target)
          words = Memory.word(@host.extern("zr_load_tables"))
          table = k::LoadTable
          # `Walk::EvalSupport` has the `units` that `Manifest` reads of a `Zr::EvalSupport`.
          manifest = Manifest.of_program(hir, @eval_files) # steep:ignore ArgumentTypeMismatch
          files = Manifest.files_of(hir, @eval_files) # steep:ignore ArgumentTypeMismatch
          texts = LoadTables.new(computed: hir.evals, spots: hir.spots || {}, coverable: hir.coverable || {}, branches: hir.branches || {},
                                 defs: hir.defs || {}, target: target, manifest: Manifest.bytes(manifest, target, files)).texts
          TEXTS.zip(texts) do |field, lines|
            text = lines.join("\n").b
            Memory.set_words(words + offset(table, field), [@host.bytes(text), text.bytesize])
          end
          units = [] #: Array[[String, Hir::entry]]
          Hash(hir.entries).each { |path, unit| units << [Paths.shown(path), unit] if path.start_with?("/") }
          units.sort_by!(&:first)
          rows = units.flat_map do |path, unit|
            bytes = path.b
            [@host.bytes(bytes), bytes.bytesize, entry_in(hir.units, unit), 0]
          end
          at = Memory.zeroed([rows.size * 8, 8].max, 8)
          Memory.set_words(at, rows) unless rows.empty?
          table[words].units = units.size
          table[words].rows = at
        end

        # `values` as an argument vector in the slot area for a call that no
        # frame makes; the slots are given back after the block.
        #: [T] (Array[Integer] values) { (Integer) -> T } -> T
        def outside(values)
          stack = @host.stack
          top = stack.top
          begin
            p = stack.take(values.size * 8)
            Memory.set_words(p, values)
            yield p
          ensure
            stack.top = top
          end
        end

        # --- eval ---

        # The compiler that a binary with eval links in, as the core's eval
        # forms call it (lib/zr/runtime/lib/zr/eval/forms.rb): here it
        # builds the HIR of the string and gives a function of the walker.
        EVAL_SUPPORT = <<~RUBY
          module Zr
            class Eval
              def self.current = @current ||= new

              # The keywords are Zr::Eval#compile's.
              def compile(source, file, line = 1, scopes = [], method = nil, using: nil, warn_now: false, debug_frozen: false)
                Primitive.attr! :hidden
                # String#+ converts as prism does: `eval(123)` is a TypeError.
                # A String keeps its encoding, which String#+ would not.
                source = +"" + source unless source.is_a?(String)
                # eval_make_iseq: a source that is not ASCII compatible cannot be read.
                raise ArgumentError, +"invalid source encoding" unless source.encoding.ascii_compatible?

                Primitive.zr_host_eval_compile(source, file, line, scopes, method, using, source.encoding.name, warn_now)
              end

              def compile_file(path)
                Primitive.attr! :hidden
                Primitive.zr_host_eval_file(path)
              end

              def file_spots(path)
                Primitive.attr! :hidden
                Primitive.zr_host_file_spots(path)
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
          # @rbs @compiler: String
          # @rbs @units: Hash[String, Array[Symbol | Hir::entry]]?

          attr_reader :loader #: Hir::Build::Loader

          #: (Target target) -> void
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
          #: () -> Hash[String, Array[Symbol | Hir::entry]]
          def units
            @units ||= begin
              compiler = [:eval] #: Array[Symbol | Hir::entry]
              @loader.entries.transform_values { |i| [:eval, i] }.merge(@compiler => compiler)
            end
          end

          #: () -> bool
          def configures? = @loader.configures?
          #: () -> bool
          def normalizes? = @loader.normalizes?
          #: () -> bool
          def pretty_prints? = @loader.pretty_prints?
          #: () -> bool
          def irbs? = @loader.irbs?
          #: () -> bool
          def gems? = @loader.gems?
          #: () -> Integer
          def activations = @loader.activations
        end

        # Loads the eval forms, at the first program that evals.
        #: () -> void
        def eval_support!
          return if @eval_support

          @eval_support = true
          # In the methods below, self is the kernel, so they read `walk`.
          walk = self #: Walk
          k.singleton_class.define_method(:zr_host_eval_compile) { |*args| walk.send(:eval_compile, *args) }
          k.singleton_class.define_method(:zr_host_eval_file) { |path| walk.send(:eval_file, path) }
          k.singleton_class.define_method(:zr_host_prism) { walk.send(:prism!) }
          k.singleton_class.define_method(:zr_host_file_spots) { |path| walk.send(:file_spots, path) }
          unit = Unit.new("<internal:zr_eval>", true, [], nil)
          check(toplevel(Hir.build(EVAL_SUPPORT, "<internal:zr_eval>", program: false), unit, k::KIND_MAIN))
          # The forms check their arguments with Eval::Arguments.
          %w[arguments.rb forms.rb].each do |name|
            path = File.join(Paths::RUNTIME, "lib/zr/eval", name)
            check(toplevel(Hir.build(File.read(path), path, program: false), Unit.new(path, true, [], nil), k::KIND_MAIN))
          end
        end

        # `Zr::Eval#compile`: the code record of the string `source`, as the
        # kernel reads it (`zr_code_word`): the toplevel, its FrameMeta,
        # the slot count and names of the Env for its own locals, the metas
        # that a box stamps, and the `using` entry that its toplevel leaves.
        # The code starts under the `using` entry `using` (nil for none). The
        # source is in the encoding named `encoding`. The parser's warnings
        # print as the code runs, or now under `warn_now`.
        #: (Integer source, Integer file, Integer line, Integer scopes, Integer method, Integer using, Integer encoding, Integer warn_now) -> Integer
        def eval_compile(source, file, line, scopes, method, using, encoding, warn_now) # rubocop:disable Metrics/ParameterLists -- the kernel's call passes eight words
          outer = ruby(scopes).map { |names| names.map(&:to_sym) } #: Array[Array[Symbol]]
          own = [] #: Array[Symbol]
          # Its `using` entries take the next free slots of the program's
          # table, now (`Zr::Eval#compiled`); a traced program's eval is
          # traced too.
          hir = Hir.build(text(source).force_encoding(text(encoding)), text(file), BuildOptions.new(trace: @traced), program: false,
                          line: k.zr_fix2long(line), scopes: [*outer.reverse, own], method: method == @qnil ? nil : ruby(method),
                          activations: k.zr_fix2long(k.zr_activations_count), using: using == @qnil ? nil : k.zr_fix2long(using))
          k.zr_activations_reserve(hir.activations)
          warnings = Array(hir.warnings)
          if warn_now == @qtrue
            parse_warnings(warnings)
            warnings = [] #: Array[String]
          end
          unit = Unit.new(text(file), false, hir.units, hir.node_ids)
          unit.spelling = Spelling.new([hir])
          unit.evaled = true
          # A traced program's eval'd code fires its events too.
          unit.traced = @traced
          m = meta(hir, unit, k::KIND_EVAL, locals: hir.locals)
          unit.root = m
          s = scope(hir, unit, :eval, m, scopes: [hir.locals, *outer], homes: [])
          # The body compiles at its first run.
          run = nil #: [untyped, bool]?
          fn = @host.callable(lambda do |self_, cref, env, blk|
            body, jumps = run ||= [code(hir.body, s), jumps?(hir.body)]
            enter(s, self_, cref, blk, env: env, outer: k::REnv[env].parent) do |f|
              parse_warnings(warnings)
              run_body(s, f, jumps) { body.call(f) }
            end
          end)
          words = [fn, m, hir.locals.size, id_table(hir.locals)].map { |w| (w << 1) | 1 }
          # The fifth word: the metas that a box stamps (`Ruby::Box#run`).
          metas = outside([(m << 1) | 1]) { |av| @host.pin(k.zr_ary_of(1, av)) }
          left = hir.using ? (hir.using << 1) | 1 : @qnil
          outside(words + [metas, left]) { |av| k.zr_ary_of(words.size + 2, av) }
        rescue Hir::Invalid, SyntaxError => e
          # The parser's warnings print before its error (`Zr::Eval#warned`).
          parse_warnings(Array(e.instance_variable_get(:@zr_warnings))) if e.instance_variable_defined?(:@zr_warnings)
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
        #: () -> Integer
        def prism!
          unless @prism
            @prism = true
            path, unit = @eval_files.units.find { |p, _| p.end_with?("/prism.rb") } || raise(ArgumentError, "eval support has no prism")
            check(k.zr_require(string(Paths.shown(path)), entry_in(nil, unit), Definitions::REQUIRE_KINDS.fetch(:hidden)))
          end
          @qnil
        end

        # `Zr::Eval#compile_file`: the toplevel of a file that the program
        # was not built with, as a fixnum address. As a binary compiles it,
        # it fires TracePoint's events while a TracePoint is on or the
        # program fires them, and a Coverage that measures learns its lines
        # and its def sites.
        #: (Integer path) -> Integer
        def eval_file(path)
          name = text(path)
          coverage = measuring_coverage
          base = coverage && ruby(check(k.zr_send(coverage, id(:next_def_site), 0, 0)))
          branch_base = coverage && ruby(check(k.zr_send(coverage, id(:next_branch_id), 0, 0)))
          traced = @traced || ruby(k.zr_trace_armed_m)
          hir = Hir.build(File.read(name), name, BuildOptions.new(trace: traced), program: false, def_base: base, branch_base: branch_base)
          @file_spots[name] = (hir.spots || {}).fetch(name, "")
          if coverage
            check(outside([value(hir.coverable), value(hir.defs), value(false), value(hir.branches)]) do |av|
              k.zr_send(coverage, id(:compiled_lines!), 4, av)
            end)
          end
          unit = Unit.new(Paths.shown(name), Library::Roots.internal_library?(name), hir.units, hir.node_ids, false, false, nil, hir.traced)
          fn = @host.callable(-> { toplevel(hir, unit, k::KIND_TOP) })
          (fn << 1) | 1
        end

        # `Zr::Eval#file_spots`: the spots (Hir::Spots) of the file at `path`
        # that a load or require compiled at run time, or nil.
        #: (Integer path) -> Integer
        def file_spots(path)
          spots = @file_spots[text(path)]
          spots ? value(spots) : @qnil
        end

        # The program's Coverage, when the program loaded it
        # (`Zr::Eval#covering`); else nil.
        #: () -> Integer?
        def measuring_coverage
          e = k.zr_const_row_in(k.zr_global(k::G_OBJECT), id(:Coverage), false)
          e.zero? ? nil : k::CEntry[e].value
        end

        # A String's bytes as a Ruby String.
        #: (Integer s) -> String
        def text(s)
          Memory.read(k::RString[s].ptr, k::RString[s].len).force_encoding(::Encoding::UTF_8)
        end

        # A plain Ruby value as a Value: nil, true, false, Integers of the
        # fixnum range, Strings (their bytes), and Arrays (a Set as one) and
        # Hashes of these. Each String, Array and Hash is pinned
        # (`Host#pin`), so a collection while the rest is made keeps it.
        #: (untyped x) -> Integer
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
          when Array, Set
            a = @host.pin(k.zr_ary_new(x.size))
            x.each { |e| k.zr_ary_push(a, value(e)) }
            a
          when Hash
            h = @host.pin(k.zr_hash_new)
            x.each { |key, v| check(k.zr_hash_store(h, value(key), value(v))) }
            h
          else raise ArgumentError, "a #{x.class} has no Value here"
          end
        end

        # A Value as a plain Ruby value: Integers, Symbols, Strings, Arrays,
        # nil, true and false.
        #: (Integer v) -> untyped
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
