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

        # `retry`: the begin body again, from its rescue clause.
        class RetryJump < StandardError; end

        # A form the walker does not run yet.
        class Unsupported < StandardError; end

        # A scope's state while it runs. `scopes` are the locals of this
        # scope, then of each lexical scope out to the def or toplevel.
        # `env` is nil for a scope whose locals are in its record's slots;
        # `outer` is the Env of the scope around a block.
        Ctx = Struct.new(:rec, :env, :self_, :cref, :blk, :meta, :proc, :scopes, :unit, :method, :loops, :kind, :params, :outer)

        # What a unit's code runs with: its file, as a backtrace shows it,
        # whether it is the core library, and the units of its program,
        # which its requires name by index, and the prism node id of each
        # of its HIR nodes (for error_highlight).
        Unit = Struct.new(:file, :internal, :units, :node_ids)

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
            r = toplevel(hir, Unit.new(path, true, hir.units, nil), @kern::KIND_MAIN)
            return r if r == @qundef
          end
          @qnil
        end

        # Runs the program `hir` (a Hir::Program) as `zr_toplevel`.
        def program(hir, file)
          spotted(hir)
          toplevel(hir, Unit.new(Paths.shown(file), false, hir.units, hir.node_ids), @kern::KIND_MAIN)
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
        # Returns the exit status.
        def run(path, args = [], target: Target.default)
          list = k.zr_global(k::G_ARGV)
          k::RArray.set_len(list, 0)
          args.each { |a| k.zr_ary_push(list, string(a)) }
          # As a build reads it: with error_highlight's spots, which a
          # build without eval support leaves out.
          hir = Hir.build(File.read(path), path, target: target, prebuilt: @eval_files)
          r = program(hir, path)
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

        private

        def k = @kern

        def check(v)
          raise Unwind if v == @qundef

          v
        end

        # The frame's line before a kernel call that can raise, as the
        # lowering's `at_node`: the line, and the prism node id above it,
        # which error_highlight reads.
        def at(node, c)
          id = c.unit.node_ids&.[](node) || 0
          k::Frame.set_line(c.rec, (node.line || 0) | (id << 32))
        end

        # Gives the load tables the program's error_highlight spots, which
        # a link writes into a binary (`Runtime#load_tables`).
        def spotted(hir)
          text = Hash(hir.spots).map { |file, rows| "#{Paths.shown(file)}\n#{rows}" }.join("\f").b
          words = Memory.fetch(TYPES["Ptr"], @host.extern("zr_load_tables"))
          at = k::LoadTable.layout_fields.fetch("spots").first
          Memory.write(words + at, [@host.bytes(text), text.bytesize].pack("Q<Q<"))
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
        def meta(node, unit, kind, name: 0, parent: 0, params: nil, locals: [], fn: 0, open: true)
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

        # Runs `body` in a new frame: a record in the slot area linked
        # from the task, and a heap Env for `locals`. Returns the body's
        # Value, or QUNDEF for a pending unwind that no handler took.
        # An eval's frame gets its Env (`env`) from the kernel.
        def frame(meta:, self_:, cref:, blk:, entry: 0, defined: @qnil, locals: [], parent_env: @qnil, scopes: [], unit:, method: nil, kind: :def,
                  proc: nil, params: nil, env: nil)
          f = k::Frame
          t = task
          open = env || k::FrameMeta.env(meta) == 1
          n = open ? 1 : locals.size
          slots do
            rec = @host.slot(f.layout_size + (8 * [n, 1].max))
            return k.zr_stack_overflow if rec < k::Task.stack_limit(t)

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
              ctx = Ctx.new(rec, env, self_, cref, blk, meta, proc, [locals, *scopes], unit, method, [], kind, params, parent_env)
              pinned { yield ctx }
            ensure
              k::Task.set_top(t, prev)
            end
          end
        end

        # A core file's or a program's toplevel.
        def toplevel(hir, unit, kind)
          m = meta(hir, unit, kind, locals: hir.locals, open: open?(hir, kind == k::KIND_MAIN ? :main : :top))
          frame(meta: m, self_: k.zr_global(k::G_MAIN), cref: k.zr_global(k::G_TOP_CREF), blk: @qnil, locals: hir.locals,
                unit: unit, kind: :main) do |c|
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
        def run_body(c, &)
          catch(c, &)
        rescue Unwind
          r = k.zr_catch_return(c.rec)
          # A `return` in an eval string goes to the main scope or to the
          # def that runs the eval (`zr_return_here`).
          here = c.kind == :main || (c.kind == :def && c.method&.evals)
          r == @qundef && here ? k.zr_catch_return_here : r
        end

        # --- eval ---

        # The compiler that a binary with eval links in, as the core's eval
        # forms call it (lib/zr/runtime/lib/zr/eval/forms.rb): here it
        # builds the HIR of the string and gives a function of the walker.
        EVAL_SUPPORT = <<~RUBY
          module Zr
            class Eval
              def self.current = @current ||= new
              def compile(source, file, line = 1, scopes = [], method = nil) = Primitive.zr_host_eval_compile(source, file, line, scopes, method)
              def compile_file(path) = Primitive.zr_host_eval_file(path)
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
            b.rubygems(@loader)
            b.rbconfig(@loader)
            b.normalizer(@loader)
            b.pretty_printer(@loader)
            b.irb_session(@loader)
            b.ast_translator(@loader)
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
          hir = Hir.build(text(source), text(file), eval_support: false, line: k.zr_fix2long(line), scopes: [*outer.reverse, []],
                                                    method: method == @qnil ? nil : ruby(method))
          unit = Unit.new(text(file), false, hir.units, hir.node_ids)
          m = meta(hir, unit, k::KIND_EVAL, locals: hir.locals)
          fn = @host.callable(lambda do |self_, cref, env, blk|
            frame(meta: m, self_: self_, cref: cref, blk: blk, locals: hir.locals, scopes: outer, unit: unit, kind: :eval, env: env) do |c|
              run_body(c) { ev(hir.body, c) }
            end
          end)
          words = [fn, m, hir.locals.size, id_table(hir.locals)].map { |w| (w << 1) | 1 }
          slots { k.zr_ary_of(words.size, argv(words)) }
        rescue Hir::Invalid, SyntaxError => e
          message = e.message.b
          k.zr_raise_msg(k.zr_core_class(id(:SyntaxError)), @host.bytes(message), message.bytesize)
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
            m = meta(node, unit, kind, name: node.name, params: node.params, locals: node.locals, open: open?(node, :def, node.params))
            @host.callable(lambda do |recv, argc, argv, entry, blk, found|
              cref = entry.zero? ? @qnil : k::MEntry.cref(entry)
              frame(meta: m, self_: recv, cref: cref, blk: blk, entry: entry, defined: found, locals: node.locals,
                    scopes: parent_scopes, unit: unit, method: node, params: node.params) do |c|
                run_body(c) do
                  bind_method(node.params, argc, argv, c)
                  preempt(c)
                  node.body ? ev(node.body, c) : @qnil
                end
              end
            end)
          end
        end

        # The leading `Primitive.attr!(:name)` statements of a def.
        def attributes(node)
          body = node.body.is_a?(Hir::Begin) ? node.body.body : node.body
          stmts = body.is_a?(Hir::Seq) ? body.stmts : [body]
          stmts.take_while { |s| s.is_a?(Hir::Send) && s.name == :attr! && s.recv.is_a?(Hir::ConstRead) && s.recv.name == :Primitive }
               .flat_map { |s| s.args.map(&:value) }
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
          m = meta(node, c.unit, kind, name: name, locals: node.locals, open: open?(node, :class))
          check(frame(meta: m, self_: klass, cref: cref, blk: @qnil, locals: node.locals, unit: c.unit, kind: :class) do |inner|
            run_body(inner) { node.body ? ev(node.body, inner) : @qnil }
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

        def bind_method(p, argc, argv, c)
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
            argc = k.zr_kw_undeclared(kw, argc, argv, 0)
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
          p.optional.each_with_index do |(name, default), i|
            v = i < given_opt ? args[front + i] : ev(default, c)
            set_local(name, v, c) if owns?(p, name, [:opt, i])
          end
          if p.rest && p.rest != :implicit
            start = front + given_opt
            rest = args[start...[post_at, start].max] || []
            set_local(p.rest, k.zr_ary_of(rest.size, argv(rest)), c) if owns?(p, p.rest, [:rest, 0])
          end
          p.post.each_with_index { |target, i| bind_target(target, post_at + i < n ? args[post_at + i] : @qnil, c) if first?(p, target, front + i) }
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
        # `eval`, `local_variables`).
        def open?(node, kind, params = nil)
          return true if %i[main eval].include?(kind)

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
          when Hir::Not then bool(!truthy?(ev(node.value, c)))
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
          when Hir::RangeLit then check(k.zr_range_new(ev(node.low, c), ev(node.high, c), node.exclusive ? 1 : 0))
          when Hir::Interp then interp(node, c)
          when Hir::IvarRead then check(k.zr_ivar_get_cached(c.self_, id(ivar(node.name, c)), cell(node, :ic, k::IvarCache.layout_size)))
          when Hir::IvarWrite
            v = ev(node.value, c)
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
            v = ev(node.value, c)
            multi(node.target, v, c)
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
          when Hir::KwSplatElement then check(k.zr_ary_kw_element(hash(Hir::HashLit.new(node.pairs, node.line, false), c)))
          when Hir::Once
            return @once[node] if @once.key?(node)

            @once[node] = ev(node.body, c)
          when Hir::Stop then check(k.zr_unloadable(string(node.what.to_s)))
          when Hir::Trace, Hir::Cover, Hir::Activations, Hir::UsingDefaults then @qnil
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
          stmts.each_with_index do |s, i|
            mark = list.size
            last = ev(s, c)
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
          when String
            bytes = v.b
            ptr = @host.bytes(bytes)
            node.chilled && !c.unit.internal ? k.zr_str_new_chilled(ptr, bytes.bytesize) : k.zr_str_new(ptr, bytes.bytesize)
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

        def frozen_string(node, _c)
          bytes = node.value.b
          ptr = @host.bytes(bytes)
          case node.shared
          when true then k.zr_str_literal_cell(cell(node, :str, 8), ptr, bytes.bytesize)
          when false then k.zr_str_frozen(ptr, bytes.bytesize)
          else check(k.zr_str_literal_freeze(ptr, bytes.bytesize))
          end
        end

        def ivar(name, c)
          return name unless c.unit.internal
          return name if Hir::VISIBLE_IVARS.include?(c.unit.file)
          return name if c.method && attributes(c.method).include?(:ivars)

          name.to_s.delete_prefix("@").to_sym
        end

        def const_read(node, c)
          if node.scope.nil? && c.unit.internal && (slot = @boot_classes[node.name])
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
            if part.is_a?(Hir::Literal) && part.value.is_a?(String)
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
            ev(node.body, c) if node.body_first
            while truthy?(ev(node.cond, c))
              redoable(tags[2]) { catch(tags[1]) { ev(node.body, c) } }
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
          when :def then throw c, v
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
            toplevel(unit, Unit.new(Paths.shown(unit.file), unit.internal ? true : false, units, unit.node_ids), k::KIND_TOP)
          end)
        end

        # The toplevel of a required file: a unit of the program (an index),
        # a unit of eval support (`EvalSupport#units`), or the compiler,
        # which is the host's eval support.
        def entry(c, unit)
          case unit
          when Integer then unit_fn(c.unit.units, unit)
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

          recv = node.recv ? ev(node.recv, c) : c.self_
          return @qnil if node.safe && recv == @qnil

          args, splat = arguments(node.args, c)
          if c.unit.internal && !splat && args.size == 1 && node.block.nil? && node.kwargs.nil? && FIXNUM_OPS.key?(node.name)
            v = fixnum_op(node.name, recv, args.first)
            return v if v
          end
          kwargs = node.kwargs && hash(node.kwargs, c)
          mode = if node.vcall then 1
                 elsif node.recv && !node.recv.is_a?(Hir::SelfRef) then 2
                 else 0
                 end
          mode |= SEND_CORE if c.unit.internal && !PROTOCOL.include?(node.name)
          written = args.last if node.write
          result = slots do
            blk = block_arg(node.block, c)
            values = splat ? elements(splat) : args
            values += [kwargs] if kwargs
            av = argv(values)
            argc = values.size
            argc = k.zr_kw_argc(argc, av) if kwargs
            argc = k.zr_kw_ruby2_out(argc, av) if splat && !kwargs
            at(node, c)
            sent(node.block.is_a?(Hir::Block) ? node.block : nil, c) do
              if node.name == :new && node.block.nil?
                # `new` with no block runs with no frame of its own, as in
                # a binary.
                k.zr_new_cached(cell(node, :new, 8 * k::CallCache.layout_size), recv, argc, av, blk, mode)
              else
                cached_send(cell(node, :cc, 4 * k::CallCache.layout_size), recv, id(node.name), argc, av, blk, mode)
              end
            end
          end
          node.write ? written : result
        end

        # The Integer operators that the core computes inline on two
        # fixnums, whatever a program redefines (Lower::Function::Arith):
        # each gives its result, or nil when the result is no fixnum (a
        # bignum, a division by zero), and the send runs instead.
        FIXNUM = (-(1 << 62))...(1 << 62)
        FIXNUM_OPS = {
          :+ => ->(a, b) { a + b }, :- => ->(a, b) { a - b }, :* => ->(a, b) { a * b },
          :/ => ->(a, b) { b.zero? ? nil : a / b }, :% => ->(a, b) { b.zero? ? nil : a % b },
          :& => ->(a, b) { a & b }, :| => ->(a, b) { a | b }, :^ => ->(a, b) { a ^ b },
          :<< => ->(a, b) { b.between?(0, 62) ? a << b : nil }, :>> => ->(a, b) { b.between?(0, 62) ? a >> b : nil },
          :< => ->(a, b) { a < b }, :<= => ->(a, b) { a <= b }, :> => ->(a, b) { a > b }, :>= => ->(a, b) { a >= b },
          :== => ->(a, b) { a == b }, :!= => ->(a, b) { a != b }, :<=> => ->(a, b) { a <=> b }
        }.freeze

        def fixnum_op(name, recv, arg)
          return nil unless (recv & arg & 1) == 1

          r = FIXNUM_OPS.fetch(name).call(recv >> 1, arg >> 1)
          case r
          when true then @qtrue
          when false then @qfalse
          when FIXNUM then (r << 1) | 1
          end
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
          raise Unwind unless block

          check(k.zr_catch_break(c.rec, @sites[block]))
        end

        def block_arg(block, c)
          case block
          when nil then @qnil
          when Hir::BlockPass then check(k.zr_block_pass(ev(block.value, c)))
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
          @fns[node] ||= begin
            m = meta(node, unit, k::KIND_BLOCK, parent: parent, params: node.params, locals: node.locals, open: open?(node, :block, node.params))
            fn = @host.callable(lambda do |pr, argc, argv, blk|
              frame(meta: m, self_: k::RProc.self(pr), cref: k::RProc.cref(pr), blk: k::RProc.blk(pr), defined: blk,
                    locals: node.locals, parent_env: k::RProc.env(pr), scopes: scopes, unit: unit, method: method,
                    kind: :block, proc: pr, params: node.params) do |inner|
                run_body(inner) do
                  bind_block(node.params, argc, argv, blk, inner)
                  # A `redo` in the block throws its meta (`Hir::Redo`).
                  redoable(inner.meta) { node.body ? ev(node.body, inner) : @qnil }
                end
              end
            end)
            k::FrameMeta.set_fn(m, fn)
            [fn, m]
          end
        end

        def bind_block(p, argc, argv, blk, c)
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
            argc = k.zr_kw_undeclared(kw, argc, argv, 0)
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
          p.optional.each_with_index do |(name, default), i|
            v = i < given_opt ? args[front + i] : ev(default, c)
            set_local(name, v, c) if owns?(p, name, [:opt, i])
          end
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

        def super_node(node, c)
          args, splat = arguments(node.args, c)
          kwargs = node.kwargs && hash(node.kwargs, c)
          slots do
            blk = node.block ? block_arg(node.block, c) : c.blk
            values = splat ? elements(splat) : args
            values += [kwargs] if kwargs
            av = argv(values)
            argc = values.size
            argc = k.zr_kw_argc(argc, av) if kwargs
            at(node, c)
            sent(node.block.is_a?(Hir::Block) ? node.block : nil, c) do
              k.zr_super(cell(node, :sc, k::SuperCache.layout_size), c.rec, argc, av, blk)
            end
          end
        end

        # `super` with no arguments: the method's parameters as they are now.
        def zsuper(node, c)
          at(node, c)
          return check(k.zr_zsuper_in_block(c.rec)) if c.kind == :block
          return check(k.zr_zsuper_outside(c.rec)) unless c.method

          p = c.params
          values = p.required.map { |n| get_local(n, 0, c) } + p.optional.map { |n, _| get_local(n, 0, c) }
          values += elements(get_local(p.rest, 0, c)) if p.rest && p.rest != :implicit
          values += p.post.map { |n| get_local(n, 0, c) }
          unless p.keywords.empty? && p.kwrest.nil?
            h = @host.pin(k.zr_hash_new)
            p.keywords.each { |n, _| k.zr_hash_store(h, sym(n), get_local(n, 0, c)) }
            k.zr_hash_update(h, get_local(p.kwrest, 0, c)) if p.kwrest && p.kwrest != :nokey
            values << h
          end
          slots do
            blk = node.block ? block_arg(node.block, c) : c.blk
            av = argv(values)
            argc = values.size
            argc = k.zr_kw_argc(argc, av) unless p.keywords.empty? && p.kwrest.nil?
            at(node, c)
            sent(node.block.is_a?(Hir::Block) ? node.block : nil, c) do
              k.zr_super(cell(node, :sc, k::SuperCache.layout_size), c.rec, argc, av, blk)
            end
          end
        end

        # A send that the walker makes: `recv.name(*values)`, mode 0.
        def call(recv, name, values, node, kind = :op)
          slots do
            check(k.zr_send_cached(cell(node, kind, 4 * k::CallCache.layout_size), recv, id(name), values.size, argv(values), @qnil, 0))
          end
        end

        def index_op_assign(node, c)
          recv = ev(node.recv, c)
          args = node.args.map { |a| ev(a, c) }
          old = call(recv, :[], args, node, :get)
          v = op_value(node, old, c) { return old }
          call(recv, :[]=, args + [v], node, :set)
          v
        end

        def attr_op_assign(node, c)
          recv = ev(node.recv, c)
          return @qnil if node.safe && recv == @qnil

          old = call(recv, node.name, [], node, :get)
          v = op_value(node, old, c) { return old }
          call(recv, :"#{node.name}=", [v], node, :set)
          v
        end

        # The new value of an op-assign, or the block's for `||=` and `&&=`
        # that leave the old one.
        def op_value(node, old, c)
          case node.op
          when :or then truthy?(old) ? yield : ev(node.value, c)
          when :and then truthy?(old) ? ev(node.value, c) : yield
          else call(old, node.op, [ev(node.value, c)], node, :op)
          end
        end

        # --- assignment ---

        def multi(target, v, c)
          ary = @host.pin(check(k.zr_masgn_ary(v)))
          nl = target.lefts.size
          nr = target.rights.size
          target.lefts.each_with_index { |t, i| assign_target(t, k.zr_ary_at(ary, i), c) }
          if target.rest && target.rest != :implicit
            assign_target(target.rest, check(k.zr_masgn_rest(ary, nl, nr)), c)
          end
          target.rights.each_with_index { |t, i| assign_target(t, k.zr_masgn_right(ary, nl, nr, i), c) }
          v
        end

        def assign_target(t, v, c)
          case t
          when Hir::Assign then set_local(t.name, v, c, t.depth)
          when Hir::IvarWrite then check(k.zr_ivar_set_cached(c.self_, id(ivar(t.name, c)), v, cell(t, :ic, k::IvarCache.layout_size)))
          when Hir::GvarWrite then gvar_write(t.name, v, c, t.shown)
          when Hir::CvarWrite then check(k.zr_cvar_set(c.cref, id(t.name), v))
          when Hir::ConstWrite then check(k.zr_const_set(scope_class(t.scope, c), id(t.name), v))
          when Hir::MultiTarget then multi(t, v, c)
          when Hir::Splat then assign_target(t.value, v, c)
          when Hir::Send
            recv = t.recv ? ev(t.recv, c) : c.self_
            args = t.args.map { |a| ev(a, c) }
            mode = t.recv && !t.recv.is_a?(Hir::SelfRef) ? 2 : 0
            at(t, c)
            slots do
              values = args + [v]
              check(k.zr_send_cached(cell(t, :cc, 4 * k::CallCache.layout_size), recv, id(t.name), values.size, argv(values), @qnil, mode))
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
            ensured(node, c)
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
            begin
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
        def ensured(node, c)
          prev = k.zr_errinfo
          slots do
            out = @host.slot(24)
            v = k.zr_signal_take(out)
            ev(node.ensure_body, c)
            k.zr_errinfo_set(prev)
            k.zr_signal_restore(v, out)
          end
        end

        def defined(node, c)
          at(node, c)
          r = case node.kind
              when :nil then "nil"
              when :true then "true"
              when :false then "false"
              when :self then "self"
              when :assignment then "assignment"
              when :expression then "expression"
              when :local then "local-variable"
              when :yield then c.blk == @qnil ? nil : "yield"
              when :ivar then truthy?(k.zr_ivar_defined(c.self_, id(ivar(node.target, c)))) ? "instance-variable" : nil
              when :gvar then truthy?(k.zr_gvar_defined(id(node.target))) ? "global-variable" : nil
              when :cvar then truthy?(k.zr_cvar_defined(c.cref, id(node.target))) ? "class variable" : nil
              when :const then const_defined?(node.target, c) ? "constant" : nil
              when :method then method_defined?(node.target, c) ? "method" : nil
              when :super then truthy?(k.zr_super_defined(c.rec)) ? "super" : nil
              else raise Unsupported, "defined?(#{node.kind})"
              end
          r ? k.zr_str_frozen(@host.bytes(r), r.bytesize) : @qnil
        end

        def const_defined?(target, c)
          if target.scope.nil?
            truthy?(k.zr_const_defined(c.cref, id(target.name)))
          else
            scope = guarded { scope_class(target.scope, c) }
            !scope.nil? && truthy?(k.zr_const_defined_at(scope, id(target.name)))
          end
        end

        def method_defined?(target, c)
          recv = target.recv ? guarded { ev(target.recv, c) } : c.self_
          !recv.nil? && truthy?(k.zr_method_defined(recv, id(target.name), !target.recv.nil? && !target.recv.is_a?(Hir::SelfRef)))
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
