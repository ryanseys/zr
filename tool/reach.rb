# frozen_string_literal: true

require_relative "lib/zr/dev"
require_relative "../lib/zr/runtime"

module Zr
  module Dev
    # The reachability spike (plan A4). It lowers the kernel, the core
    # library, the gem prelude and each program, and finds how much of the
    # runtime each program can reach. It changes no source file and builds
    # no binary.
    #
    #   zr-dev reach                        the benchmarks and test/programs/*.rb
    #   zr-dev reach prog.rb ...            only these programs
    #   zr-dev reach --why 'Integer#times'  the path from a root to a def
    #   zr-dev reach --rates                also measure lowering, assembly
    #                                       and the cost of relocatable ids
    #
    # The graph:
    #
    # - A function reaches each function that it calls or takes the
    #   address of, and each datum that it reads. A datum reaches what its
    #   relocations name.
    # - A `def` registers its body under its name. The body is reached only
    #   when a reached function uses that name as a selector. So is a
    #   kernel builtin, which `zr_builtin(klass, Machine.id(:x),
    #   Machine.addr(:fn), ...)` registers.
    # - A function's selectors come from its HIR: each send's name, each
    #   Symbol literal, and the names that the lowering implies (`to_s`
    #   for an interpolation, `===` for a `case`, and so on). A kernel
    #   function's selectors are its `Machine.id` names.
    # - `alias new old` reaches `old` when `new` is reached.
    #
    # The roots are the kernel's `main`, the core's `zr_prelude` (the boot
    # runs every core toplevel), the gem prelude and the program's toplevel.
    #
    # A call by a name computed at run time can reach any body. The rules
    # say when a program must fall back to a full build:
    #
    # - R0: any reached function (core, prelude or program) makes a
    #   computed call.
    # - R0p: a reached function of the program makes a computed call.
    # - R1: a reached function of the program makes a computed call, and
    #   one makes names (`to_sym`, a dynamic symbol, the `methods` family,
    #   `Symbol.all_symbols`, `Marshal.load`, `symbolize_names`).
    #
    # A program that evals always falls back.
    class Reach < Command
      summary "How much of the runtime each program reaches (the A4 spike)"
      usage "[--why NAME] [--rates] [program.rb...]"

      def defaults
        @why = nil
        @rates = false
        @tsv = nil
      end

      def options(o)
        o.on("--why NAME", "the path from a root to a def (Owner#name) or function") { |v| @why = v }
        o.on("--rates", "measure lowering, assembly and the cost of relocatable ids") { @rates = true }
        o.on("--tsv FILE", "write one row for each program") { |v| @tsv = v }
      end

      RULES = %i[R0 R0p R1].freeze

      # Sends that call the method their first argument names.
      BY_NAME = %i[send __send__ public_send method public_method instance_method public_instance_method].freeze
      # Sends whose Symbol arguments name methods and do not call them.
      DECLARES = %i[private public protected module_function private_class_method public_class_method private_constant
                    public_constant attr_reader attr_writer attr_accessor attr undef_method remove_method
                    method_added respond_to? instance_variable_get instance_variable_set const_get const_set
                    const_defined? define_method alias_method].freeze
      # Sends that make a Symbol from data.
      SOURCES = %i[to_sym intern methods public_methods private_methods protected_methods singleton_methods
                   instance_methods public_instance_methods private_instance_methods protected_instance_methods
                   all_symbols].freeze
      # What the lowering sends for each node kind, beyond the node's own name.
      IMPLIED = { Hir::Interp => %i[to_s], Hir::Splat => %i[to_a], Hir::HashSplat => %i[to_hash],
                  Hir::BlockPass => %i[to_proc], Hir::MultiAssign => %i[to_ary], Hir::Case => %i[===],
                  Hir::Rescue => %i[===], Hir::Not => %i[!], Hir::IndexOpAssign => %i[[] []=] }.freeze

      # What the hooks record while zr lowers.
      class Record
        attr_reader :selectors, :defs, :aliases, :computed, :sources, :labels, :builtins, :owners, :consts, :relations, :self_new

        def initialize
          @selectors = Hash.new { |h, k| h[k] = Set.new }
          @defs = []
          @aliases = Hash.new { |h, k| h[k] = Set.new }
          @computed = {}
          @sources = {}
          @labels = {}
          @builtins = {}
          @owners = {}
          @self_new = Set.new
          @consts = Hash.new { |h, k| h[k] = Set.new }
          @relations = Hash.new { |h, k| h[k] = Set.new }
        end

        # The selectors of one function, from its HIR.
        def scan(fn, body, node, kind, file)
          found = @selectors[fn]
          @class = %i[class module].include?(kind) ? node.name : nil
          walk(body, found, fn, file)
          walk(node.params, found, fn, file) if node.is_a?(Hir::Def) || node.is_a?(Hir::Block)
          @class = nil
          return unless kind == :def && node

          # `super` in a def looks up the def's own name.
          found << node.name if contains?(body, Hir::Super) || contains?(body, Hir::ZSuper)
        end

        def contains?(node, type)
          return true if node.is_a?(type)
          return false if node.is_a?(Hir::Def) || node.is_a?(Hir::Block)

          Hir.each_child(node) { |c| return true if (c.is_a?(Hir::Node) || c.is_a?(Array)) && contains?(c, type) }
          false
        end

        # `owner` is a class or module name; `singleton` for a method of
        # the class itself, not of its instances.
        def defined(holder, fn, name, owner, singleton, label)
          @defs << [holder, fn, name.to_sym]
          @owners[fn] = [owner.to_sym, singleton]
          @labels[fn] = label
        end

        def machine_id(fn, name) = @selectors[fn] << name.to_sym

        # What a program adds, so that `restore` can take it away. Programs
        # use the same function names (`zr_toplevel_blk_3`), and one must
        # not see what another recorded.
        def checkpoint
          { defs: @defs.size, aliases: deep(@aliases), relations: deep(@relations) }
        end

        def restore(point, functions)
          @defs.slice!(point[:defs]..)
          @aliases = point[:aliases]
          @relations = point[:relations]
          [@selectors, @computed, @sources, @owners, @labels, @consts].each { |h| functions.each { |fn| h.delete(fn) } }
          functions.each { |fn| @self_new.delete(fn) }
        end

        def deep(table)
          copy = Hash.new { |h, k| h[k] = Set.new }
          table.each { |k, v| copy[k] = v.dup }
          copy
        end

        private

        def walk(node, found, fn, file)
          case node
          when Array then return node.each { |c| walk(c, found, fn, file) }
          when Hir::Def, Hir::Block, Hir::Lambda then return
          when Hir::ClassDef
            # A class is live when its subclass is. The key of a class's
            # instances is its name with `#`.
            if node.superclass.is_a?(Hir::ConstRead)
              @relations[node.name] << node.superclass.name
              @relations[:"#{node.name}#"] << :"#{node.superclass.name}#"
            end
            return walk(node.scope, found, fn, file)
          when Hir::ConstRead then @consts[fn] << node.name
          when Hir::ModuleDef then return walk(node.scope, found, fn, file)
          when Hir::SingletonClassDef then return walk(node.target, found, fn, file)
          when Hir::Literal
            found << node.value if node.value.is_a?(Symbol)
            note(@sources, fn, file, node, "symbolize_names") if node.value == :symbolize_names
          when Hir::Alias then @aliases[node.new_name.to_sym] << node.old_name.to_sym
          when Hir::AliasValue then note(@computed, fn, file, node, "alias with computed names")
          when Hir::AttrOpAssign then found.merge([node.name, :"#{node.name}=", node.op])
          when Hir::IndexOpAssign then found << node.op
          when Hir::BlockPass
            note(@computed, fn, file, node, "&expr") unless literal_name(node.value) || node.value.nil?
          when Hir::Send then return send_node(node, found, fn, file)
          end
          IMPLIED[node.class]&.each { |s| found << s }
          Hir.each_child(node) { |c| walk(c, found, fn, file) if c.is_a?(Hir::Node) || c.is_a?(Array) }
        end

        def send_node(node, found, fn, file)
          name = node.name
          found << name
          found << :== if name == :!=
          args = node.args || []
          if node.recv.nil? && @class && %i[include extend prepend].include?(name) && args.all?(Hir::ConstRead)
            # A module is live when a class that includes it is.
            args.each { |a| @relations[name == :extend ? @class : :"#{@class}#"] << :"#{a.name}#" }
            args = []
          elsif node.recv.nil? && @class && (name == :module_function && args.empty? ||
                                             name == :extend && args.all?(Hir::SelfRef))
            # The module's instance methods are its own methods too.
            @relations[@class] << :"#{@class}#"
            args = []
          elsif %i[new allocate].include?(name) && node.recv.is_a?(Hir::ConstRead)
            @consts[fn] << :"#{node.recv.name}#"
          elsif %i[new allocate].include?(name) && (node.recv.nil? || node.recv.is_a?(Hir::SelfRef))
            @self_new << fn
          elsif node.recv.nil? && DECLARES.include?(name)
            if name == :alias_method && args.size == 2 && args.all? { |a| literal_name(a) }
              @aliases[literal_name(args[0])] << literal_name(args[1])
            end
            if name == :define_method && !literal_name(args[0])
              # A computed name only makes a method; the block is reached anyway.
            end
            args = args.reject { |a| literal_name(a) }
          elsif BY_NAME.include?(name)
            first = args.first
            if (literal = literal_name(first))
              found << literal
            else
              note(@computed, fn, file, node, "#{name}(computed)")
            end
          elsif %i[inject reduce].include?(name) && args.size == 1 && node.block.nil? && !literal_name(args[0]) &&
                !args[0].is_a?(Hir::Literal)
            note(@computed, fn, file, node, "#{name}(computed)")
          end
          note(@sources, fn, file, node, name.to_s) if SOURCES.include?(name)
          note(@sources, fn, file, node, "Marshal.load") if name == :load && const?(node.recv, :Marshal)
          [node.recv, args, node.kwargs, node.block].each { |c| walk(c, found, fn, file) }
        end

        def const?(node, name) = node.is_a?(Hir::ConstRead) && node.name == name

        # The method name that a Symbol or String literal gives, or nil.
        def literal_name(node)
          case node
          when Hir::Literal then node.value.is_a?(Symbol) || node.value.is_a?(String) ? node.value.to_sym : nil
          when Hir::FrozenString then node.value.to_s.to_sym
          end
        end

        def note(table, fn, file, node, what)
          (table[fn] ||= []) << "#{what} at #{Paths.shown(file.to_s)}:#{node.line}"
        end
      end

      class << self
        attr_accessor :record
      end

      # Records each function's selectors and each def's registration.
      module LowerHook
        def lower
          Reach.record&.scan(@name, @body, @def, @kind, @l.file)
          super
        end

        private

        def define_method(node)
          value = super
          if (record = Reach.record)
            owner = case @kind
                    when :class, :module then @def.name
                    when :sclass then %i[class module].include?(@outer&.kind) ? @outer.def_node.name : :Object
                    else :Object
                    end
            record.defined(@f.name, @l.def_name(node), node.name, owner, node.receiver || @kind == :sclass ? true : false,
                           node.receiver || @kind == :sclass ? "#{owner}.#{node.name}" : "#{owner}##{node.name}")
          end
          value
        end
      end

      # Records a kernel function's `Machine.id` names.
      module MachineHook
        def intrinsic(node, args, want)
          if node.name == :id && (record = Reach.record) && args.first.is_a?(Prism::SymbolNode)
            record.machine_id(@f.name, args.first.unescaped)
          end
          super
        end
      end

      # One lowered piece (the kernel, the core, the prelude, a program):
      # its edges, its sizes and what the hooks recorded.
      class Piece
        attr_reader :name, :edges, :insts, :bytes, :functions

        # `registered`: the functions that are reached only through a name.
        def initialize(name, functions, data, registered)
          @name = name
          @edges = {}
          @insts = {}
          @bytes = {}
          @functions = Set.new
          functions.each do |f|
            @functions << f.name
            @insts[f.name] = f.blocks.sum { |b| b.insts.size }
            @edges[f.name] = edges_of(f, registered)
          end
          data.each do |d|
            @bytes[d.name] = d.size
            @edges[d.name] = d.relocs.filter_map { |r| r.symbol if r.kind == :abs64 }.uniq
          end
        end

        def total_insts = @insts.values.sum
        def total_bytes = @bytes.values.sum

        private

        def edges_of(f, registered)
          symbol = f.callees.to_h { |c| [c.fn, c.symbol] }
          out = Set.new
          f.blocks.each do |b|
            b.insts.each do |i|
              case i.op
              when :call then out << symbol.fetch(i.callee)
              when :func_addr
                target = symbol.fetch(i.args.first)
                out << target unless registered.include?([f.name, target]) || registered.include?([nil, target])
              end
            end
          end
          f.globals.each { |g| out << g.symbol }
          out.to_a
        end
      end

      # The fixed point over some pieces, from `roots`.
      class Walk
        attr_reader :seen, :unlocked, :live

        # With `classes`, a def body also needs its owner to be live: a
        # class or module whose constant a reached function reads, or one
        # that a live class inherits or includes (rapid type analysis).
        # With `split` too, an instance method needs a live instance (`C#`):
        # a reached `C.new`, a kernel class, or a live subclass or includer.
        def initialize(pieces, record, classes: false, split: false, live: [])
          @pieces = pieces
          @record = record
          @classes = classes
          @split = split
          @always = live.flat_map { |c| [c, :"#{c}#"] }
          @cond = Hash.new { |h, k| h[k] = [] }
          record.defs.each { |_, fn, name| @cond[name] << fn }
          record.builtins.each { |fn, names| names.each { |name| @cond[name] << fn } }
        end

        def run(roots)
          @seen = {}
          @unlocked = {}
          @live = {}
          @parked = Hash.new { |h, k| h[k] = [] }
          @queue = []
          @always.each { |c| enliven(c) }
          roots.each { |r| @queue << r if first_visit?(r, [:root]) }
          until @queue.empty?
            n = @queue.pop
            @pieces.each { |p| p.edges[n]&.each { |m| @queue << m if first_visit?(m, [:edge, n]) } }
            @record.selectors[n]&.each { |s| unlock(s, n) } if @record.selectors.key?(n)
            next unless @classes

            @record.consts[n]&.each { |c| enliven(c) } if @record.consts.key?(n)
            # `new` on self in a class method makes an instance of its class.
            owner, singleton = @record.owners[n]
            enliven(:"#{owner}#") if singleton && @record.self_new.include?(n)
          end
          self
        end

        def reached?(name) = @seen.key?(name)

        private

        # Records why `name` is reached. False when it already was.
        def first_visit?(name, why)
          return false if @seen.key?(name)

          @seen[name] = why
          true
        end

        def unlock(selector, from)
          return if @unlocked.key?(selector)

          @unlocked[selector] = from
          @cond[selector].each { |fn| offer(fn, [:selector, selector, from]) }
          @record.aliases[selector]&.each { |old| unlock(old, from) } if @record.aliases.key?(selector)
        end

        # A body whose selector is reached: taken now, or when its owner
        # becomes live.
        def offer(fn, why)
          owner, singleton = @record.owners[fn]
          if @classes && owner
            key = key(singleton ? owner : :"#{owner}#")
            return @parked[key] << [fn, why] unless @live.key?(key)
          end

          @queue << fn if first_visit?(fn, why)
        end

        # Without `split`, a class and its instances are one key.
        def key(name) = @split ? name : name.to_s.delete_suffix("#").to_sym

        def enliven(name)
          name = key(name)
          return if @live.key?(name)

          @live[name] = true
          @parked.delete(name)&.each { |fn, why| @queue << fn if first_visit?(fn, why) }
          @record.relations[name]&.each { |c| enliven(c) } if @record.relations.key?(name)
        end
      end

      def run(argv)
        require_relative "../lib/zr/ir/passes"
        require_relative "../lib/zr/backend/aarch64/codegen"
        require_relative "../lib/zr/native/build"
        Lower::Function.prepend(LowerHook)
        Machine::Function.prepend(MachineHook)
        @target = Target.default
        Reach.record = @record = Record.new

        base = timed("lowered the kernel, the core and the gem prelude") { runtime_pieces }
        programs = argv.empty? ? default_programs : argv.map { |a| File.expand_path(a) }
        rows = [row("(empty)", "", "<empty>"), row("(hello)", "puts \"hello\"\n", "<hello>")]
        timed("lowered #{programs.size} programs") do
          programs.each { |path| rows << row(Dev.rel(path), File.read(path), path) }
        end
        return why(rows) if @why

        report(base, rows)
        rates(base) if @rates
        write_tsv(rows) if @tsv
      end

      def default_programs
        (Dir[Dev.path("benchmark/bm_*.rb")] + Dir[Dev.path("test/programs/*.rb")]).sort
      end

      def timed(what)
        began = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        warn format("%s in %.1fs", what, Process.clock_gettime(Process::CLOCK_MONOTONIC) - began)
        result
      end

      # The kernel, core and gem prelude pieces, lowered with the hooks on.
      def runtime_pieces
        sources = RuntimeSources.for(@target)
        kernel_files = sources.kernel_files
        @kernel_texts = kernel_files.map { |path| [File.read(path), path] }
        @symbols = Machine::Symbols.new
        began = clock
        @kernel = Machine::Lower.new(@kernel_texts, @symbols).tap(&:run)
        @kernel_names = @symbols.names.dup
        @kernel_seconds = clock - began
        builtins!
        registered = @record.builtins.keys.to_set { |fn| [nil, fn] }
        kernel = Piece.new(:kernel, @kernel.functions, @kernel.data, registered)
        fixed = @kernel_fixed = @symbols.ids.dup.freeze
        began = clock
        core_functions = []
        core_data = []
        entries = sources.core_files.map do |path|
          f, d = Runtime.lower_core_file(path, File.read(path), @kernel, fixed, @target)
          core_functions.concat(f)
          core_data.concat(d)
          Runtime.core_entry(path)
        end
        @core_seconds = clock - began
        core_functions << Runtime.prelude(entries, @kernel)
        began = clock
        f, d = Runtime.lower_gem_prelude(Runtime.gem_prelude(@target), @kernel, fixed, @target)
        @prelude_seconds = clock - began
        @core_ir = core_functions
        @prelude_ir = f
        @pieces = [kernel, Piece.new(:core, core_functions, core_data, def_registrations),
                   Piece.new(:prelude, f, d, def_registrations)]
      end

      def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      # The kernel's builtins, which the kernel registers by name.
      BUILTIN = /zr_builtin(?:_private|_hidden)?\(\s*[^,()]+(?:\([^()]*\))?,\s*Machine\.id\(:"?([^")]+)"?\),\s*Machine\.addr\(:(\w+)\)/

      def builtins!
        @kernel_texts.each do |text, _|
          text.scan(BUILTIN) { |name, fn| (@record.builtins[fn] ||= []) << name.to_sym }
        end
      end

      def def_registrations = @record.defs.to_set { |holder, fn, _| [holder, fn] }

      MODES = %i[names classes instances].freeze

      # One program: whether it evals, its own size, and a Measure for
      # each mode.
      Row = Struct.new(:name, :evals, :program_insts, :modes)
      # What one walk reached: the share of the runtime's IR instructions,
      # the first trigger under each rule, the kernel functions and the
      # def bodies of the runtime.
      Measure = Struct.new(:walk, :share, :fallback, :kernel, :bodies)

      ROOTS = %w[main zr_prelude zr_gem_prelude zr_toplevel].freeze

      def row(name, source, path)
        hir = Hir.build(source, path, target: @target)
        return Row.new(name, true, 0, {}) if hir.evals

        point = @record.checkpoint
        symbols = Machine::Symbols.new(@symbols.names.dup, sites: @symbols.sites)
        functions, data = Lower.new(hir, @kernel, symbols, target: @target, fixed: @kernel_fixed).run
        registered = @record.defs.drop(point[:defs]).to_set { |holder, fn, _| [holder, fn] }
        program = Piece.new(:program, functions, data, registered)
        modes = MODES.to_h do |mode|
          walk = Walk.new(@pieces + [program], @record, classes: mode != :names, split: mode == :instances,
                                                        live: live_classes).run(ROOTS)
          [mode, measure(walk, program)]
        end
        Row.new(name, false, program.total_insts, modes)
      ensure
        @record.restore(point, program.functions) if point && program
      end

      # The classes that are live before any constant read: those the
      # kernel makes (`Lower.boot_classes`), and the roots of the tree.
      def live_classes = @live_classes ||= [*Lower.boot_classes.keys, :Object, :BasicObject, :Kernel]

      def measure(walk, program)
        own = program.functions
        reached_own = own.select { |fn| walk.reached?(fn) }
        computed_own = reached_own.flat_map { |fn| @record.computed[fn] || [] }
        sources_own = reached_own.flat_map { |fn| @record.sources[fn] || [] }
        computed_all = walk.seen.keys.flat_map { |fn| @record.computed[fn] || [] }
        fallback = {
          R0: computed_all.first,
          R0p: computed_own.first,
          R1: computed_own.first && sources_own.first ? "#{computed_own.first}; names from #{sources_own.first}" : nil
        }
        reached = @pieces.sum { |p| p.insts.sum { |fn, n| walk.reached?(fn) ? n : 0 } }
        Measure.new(walk, 100.0 * reached / runtime_insts, fallback, @pieces[0].functions.count { |fn| walk.reached?(fn) },
                    @record.defs.count { |_, fn, _| walk.reached?(fn) && !own.include?(fn) })
      end

      def runtime_insts = @runtime_insts ||= @pieces.sum(&:total_insts)

      # The share of the runtime under `rule`: 100 when the program falls back.
      def share(row, mode, rule)
        return 100.0 if row.evals

        m = row.modes[mode]
        m.fallback[rule] ? 100.0 : m.share
      end

      def report(_base, rows)
        kernel, core, prelude = @pieces
        puts "runtime: kernel #{kernel.functions.size} functions, #{kernel.total_insts} IR instructions; " \
             "core #{core.functions.size} functions, #{core.total_insts}; prelude #{prelude.functions.size}, #{prelude.total_insts}"
        runtime = ->(fn) { core.functions.include?(fn) || prelude.functions.include?(fn) }
        puts "#{@record.defs.count { |_, fn, _| runtime[fn] }} def bodies in the core and prelude and " \
             "#{@record.builtins.size} kernel builtins are registered by name"
        puts "core and prelude functions that make a computed call: #{@record.computed.count { |fn, _| runtime[fn] }}"
        puts "(names: a body is reached through its selector; classes: its owner must also be live; " \
             "instances: an instance method needs a live instance)"
        puts
        puts format("%-40s %7s %7s %7s %7s %7s  %s", "program", "names", "classes", "insts", "R0p", "R1", "R1 fallback (instances)")
        rows.each do |r|
          next puts(format("%-40s %7s %7s %7s %7s %7s  eval", r.name[0, 40], *["100%"] * 5)) if r.evals

          c = r.modes[:instances]
          puts format("%-40s %6.1f%% %6.1f%% %6.1f%% %6.1f%% %6.1f%%  %s", r.name[0, 40], r.modes[:names].share,
                      r.modes[:classes].share, c.share, share(r, :instances, :R0p), share(r, :instances, :R1),
                      c.fallback[:R1].to_s[0, 100])
        end
        summary(rows)
      end

      def summary(rows)
        floor, hello = rows.first(2)
        programs = rows.drop(2)
        plain = programs.reject(&:evals)
        puts
        MODES.each do |mode|
          puts format("%s: floor (empty program) %.1f%%, hello %.1f%% of the runtime's IR instructions",
                      mode, floor.modes[mode].share, hello.modes[mode].share)
          RULES.each do |rule|
            shares = programs.map { |r| share(r, mode, rule) }.sort
            back = plain.count { |r| r.modes[mode].fallback[rule] }
            puts format("  %-3s  median %.1f%%, mean %.1f%%, max %.1f%%; %d of %d programs without eval fall back (%.0f%%); %d eval",
                        rule, shares[shares.size / 2], shares.sum / shares.size, shares.max, back, plain.size,
                        100.0 * back / plain.size, programs.count(&:evals))
          end
        end
        triggers = plain.filter_map { |r| r.modes[:instances].fallback[:R0p] }.map { |t| t.split(" at ").first }.tally.sort_by { -_2 }
        puts "R0p triggers (instances): #{triggers.map { |t, n| "#{t} #{n}" }.join(", ")}"
        MODES.each { |mode| top_selectors(floor.modes[mode].walk, "floor, #{mode}") }
      end

      # The selectors whose def bodies add the most instructions to a row.
      def top_selectors(walk, label)
        weight = Hash.new(0)
        @record.defs.each do |_, fn, name|
          next unless walk.reached?(fn)

          weight[name] += @pieces.sum { |p| p.insts[fn] || 0 }
        end
        puts "#{label}: the selectors whose def bodies are largest"
        weight.sort_by { -_2 }.first(20).each { |name, n| puts format("  %7d  %s", n, name) }
      end

      def why(rows)
        target = @record.labels.key(@why) || @why
        rows.each do |r|
          walk = r.modes[:instances]&.walk or next

          chain = []
          at = target
          while (why = walk.seen[at])
            chain << [at, why]
            break if why.first == :root

            at = why.first == :edge ? why[1] : why[2]
          end
          puts "#{r.name}: #{chain.empty? ? "not reached" : chain.reverse.map { |n, w| describe(n, w) }.join(" -> ")}"
        end
      end

      def describe(name, why)
        label = @record.labels[name] ? "#{name} (#{@record.labels[name]})" : name
        why.first == :selector ? "[:#{why[1]}] #{label}" : label
      end

      # The rates that turn instruction counts into times.
      def rates(_base)
        kernel, core, prelude = @pieces
        runtime = kernel.total_insts + core.total_insts + prelude.total_insts
        puts
        puts format("lowering: kernel %.2fs for %d, core %.2fs for %d, prelude %.2fs for %d IR instructions (%.1f us each)",
                    @kernel_seconds, kernel.total_insts, @core_seconds, core.total_insts, @prelude_seconds,
                    prelude.total_insts, 1e6 * (@core_seconds + @prelude_seconds) / (core.total_insts + prelude.total_insts))
        sample = (@kernel.functions + @core_ir + @prelude_ir).each_slice(10).map(&:first)
        insts = sample.sum { |f| f.blocks.sum { |b| b.insts.size } }
        defined = (@kernel.functions + @core_ir + @prelude_ir).to_set(&:name)
        began = clock
        bytes = sample.sum do |f|
          IR::Passes.prepare(f)
          Backend::Aarch64::Codegen.new(f, defined: defined).compile.bytes.bytesize
        end
        took = clock - began
        per = took / insts
        puts format("assembly (passes and codegen): %.1f us per IR instruction, %.2f bytes of code each (a sample of %d functions)",
                    1e6 * per, bytes.to_f / insts, sample.size)
        puts format("the whole runtime: %.1fs to assemble serially, %.1fs on %d jobs", per * runtime, per * runtime / Native::Build.jobs,
                    Native::Build.jobs)
        ids
      end

      # The cost of relocatable symbol ids: the core as a build lowers it
      # (only the kernel's ids fixed, each other name a pool word), and
      # lowered again with a table that fixes every id.
      def ids
        symbols = Machine::Symbols.new(@kernel_names, sites: @symbols.sites)
        Reach.record = nil
        fixed = RuntimeSources.for(@target).core_files.sum do |path|
          hir = Hir.build(File.read(path), path, eval_support: false, target: @target)
          functions, = Lower.new(hir, @kernel, symbols, entry: Runtime.core_entry(path), internal: true, target: @target).run
          functions.sum { |f| f.blocks.sum { |b| b.insts.size } }
        end
        pooled = @pieces[1].total_insts
        puts format("relocatable ids: the core has %d IR instructions with fixed ids and %d with pooled ids (%+.2f%%)",
                    fixed, pooled, 100.0 * (pooled - fixed) / fixed)
      end

      def write_tsv(rows)
        head = ["program", "evals", "program insts", *MODES.flat_map { |m| RULES.map { |rule| "#{m} #{rule}" } }, "R1 trigger"]
        lines = [head.join("\t")] + rows.map do |r|
          shares = MODES.flat_map { |m| RULES.map { |rule| format("%.2f", share(r, m, rule)) } }
          [r.name, r.evals, r.program_insts, *shares, r.modes[:instances]&.fallback&.[](:R1)].join("\t")
        end
        File.write(@tsv, "#{lines.join("\n")}\n")
      end
    end
  end
end
