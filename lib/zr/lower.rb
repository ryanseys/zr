# frozen_string_literal: true

require "digest/sha2"
require_relative "hir"
require_relative "ir"
require_relative "obj/model"
require_relative "refused"
require_relative "lower/function"

module Zr
  # Lowers the HIR to the IR, over the zr runtime: one Function per scope
  # (the toplevel, each def, class body and block), the data that they
  # refer to, and the FrameMeta records that backtraces read.
  class Lower
    # A scope that an eval runs inside: the names of its locals in Env
    # order, and the enclosing scope. It is used in place of a block's
    # Function, so a name that the string did not declare resolves to its
    # slot in the calling scope.
    class Outer
      attr_reader :outer

      def initialize(names, outer = nil)
        @slot_of = names.each_with_index.to_h
        @outer = outer
      end

      def meta = nil

      # A scope that an eval runs inside is already compiled, and its
      # captures are already recorded. The eval keeps its own table, and
      # the walk stops here.
      def capture(_name, _depth, write:) = nil

      # Its body is not available, so no local counts as bound twice.
      def bindings = Hash.new(0)

      def slot_index(node)
        @slot_of.fetch(node.name) { raise ArgumentError, "#{node.name} is not a local of the scope this eval runs in" }
      end
    end

    class Refused < Zr::Refused; end

    # The Symbol Value for `id`: the id shifted above the tag that the
    # kernel reads (lib/zr/runtime/kernel/object.rb).
    def self.symbol_value(id, tag) = (id << 8) | tag

    # The bit in an ivar table's `names` for the name `id`
    # (lib/zr/runtime/kernel/object.rb, zr_ivtab_name_bit), as a signed word.
    def self.ivar_name_bit(id)
      bit = 1 << (id & 63)
      bit < 1 << 63 ? bit : bit - (1 << 64)
    end

    # `fixed`: the ids that this lowering's code has as immediates (the
    # kernel's), or nil when the lowering owns the table.
    attr_reader :program, :unit, :symbols, :data, :functions, :file, :warnings, :fixed

    # The id of the prism node that `node` came from, or 0. The ids are
    # those of the file that is lowering now (`@ids`): the program's main
    # file, or a unit. A unit's ids go with its tree (`spent`).
    def node_id(node)
      @ids&.[](node) || 0
    end

    # Gives `made` (a node that the lowering builds for `node`) the same
    # node id as `node`.
    def noted(made, node)
      @ids[made] ||= @ids[node] if @ids&.key?(node)
      made
    end

    # Whether the program uses TracePoint, so its own code fires events.
    def traced?
      @program.traced ? true : false
    end

    # True in the core library and in an extension's Ruby part. Both are
    # runtime code, so `Primitive` resolves there.
    def internal?
      @internal || @unit_internal
    end

    # True in a unit of eval support (a hidden unit): the compiler that a
    # program carries. ruby's compiler is C, so what the program redefines
    # or traces must not reach this code either.
    def support?
      @unit_hidden
    end

    # The builtin classes that the kernel sets at boot, each with its
    # global slot. The core library reads them directly from the slot, as
    # CRuby's C reads rb_cInteger. So a constant that a program defines
    # never replaces one, and no read walks the constant tables.
    def self.boot_classes
      Session.current.memo(:boot_classes) do
        File.read(File.join(Paths::RUNTIME, "kernel/main.rb")).scan(/zr_boot_name\((G_\w+), Machine\.id\(:(\w+)\)\)/).to_h { |slot, name| [name.to_sym, slot] }
      end
    end

    # The slot for a bare constant `name` in the core library, or nil.
    def boot_class_slot(name) = @internal ? Lower.boot_classes[name] : nil

    # `internal` marks the core library: a backtrace shows its methods as
    # builtins, and its blocks and bodies have no backtrace entry. `ext`
    # marks a program that is one extension file, compiled alone; it is
    # internal as a one-unit program. `kind` is `:top` for a loaded file
    # (its toplevel is a file's, not a program's): it starts no program
    # and prints no parse warning.
    def initialize(program, kernel, symbols, entry: "zr_toplevel", internal: false, ext: false, kind: :main, outer: nil,
                   target: Target.default, fixed: nil, units: nil)
      @program = program
      @ids = program.node_ids
      @kernel = kernel
      @target = target
      @symbols = symbols
      @fixed = fixed
      @units = units
      @entry = entry
      @internal = internal
      @ext = ext
      @unit_internal = ext
      @kind = kind
      @outer = outer
      @file = program.file
      @warnings = program.warnings || []
      @data = []
      @functions = []
      open_unit
    end

    # Each unit is independent. Every name in it starts with its own
    # prefix and uses its own counters, so a file gets the same names
    # whatever was compiled before it. The program's main file keeps the
    # entry that it was given.
    def open_unit(prefix = @entry, body = nil)
      close_pool
      @prefix = prefix
      @next = 0
      @lits = 0
      @sites = 0
      @pool = []
      @pool_at = {}
      @spelled = {}
      @file_bytes = {}
      @keyword_tables = {}
      # The unit's own tree (a site can inline a def from it,
      # `Function::Inline`), the function name of each def, and the cells
      # that a site and its inlined copies share.
      @unit_body = body
      @inline_defs = nil
      @def_names = {}.compare_by_identity
      @block_names = {}.compare_by_identity
      @site_cells = {}.compare_by_identity
    end

    # The def in this unit that a send of `name` can inline, or nil. It
    # must be the only def of that name in the unit, with a shape that
    # `Function::Inline` accepts. The name is only a guess at the callee;
    # the site's cell decides at run time.
    def inline_def(name)
      @inline_defs ||= Function::Inline.candidates(@unit_body)
      @inline_defs[name]
    end

    # The function name of the def `node`. It is made once, whether the
    # def or a site that inlines it needs it first.
    def def_name(node)
      @def_names[node] ||= "#{@prefix}_def_#{number}_#{node.name.to_s.gsub(/[^A-Za-z0-9_]/, "")}"
    end

    # The cell of the site `node`, shared by every lowering of the node.
    # The def's own function and each inlined copy read one cell, which
    # the def's run fills.
    def site_cell(node, prefix, bytes)
      @site_cells[node] ||= cache_cell(prefix, bytes)
    end

    # The fixed id of `name`, or nil. An id is fixed for a name of the
    # kernel, or for any name in a lowering that owns the table (an eval in
    # a running program). For nil, the link numbers the name, and the
    # caller emits a word and a relocation.
    def fixed_id(name)
      return @symbols.id(name) unless @fixed

      @fixed[name.to_s]
    end

    # The word in this unit's pool for `name` under `kind`, as `[the
    # pool's name, its offset]`. A unit's code loads it, so the code does
    # not contain a number that depends on the compile order.
    def pool_word(kind, name)
      row = [kind, name.to_s]
      at = @pool_at[row] ||= (@pool << row).size - 1
      ["#{@prefix}_pool", at * 8]
    end

    # The pool as data: one zero word per entry, each with the relocation
    # that tells the link what to write there.
    def close_pool
      return if @pool.nil? || @pool.empty?

      relocs = @pool.each_with_index.map { |(kind, name), i| Obj::Reloc.new(i * 8, kind, name) }
      @data << Obj::Datum.new("#{@prefix}_pool", :data_const, "\0".b * (@pool.size * 8), relocs: relocs, align: 8)
      @pool = []
      @pool_at = {}
    end

    # The unit's code from an earlier build's cache, with its data added
    # to this build's data.
    def taken(unit)
      kept = @units&.take(unit, @prefix) or return nil

      @data.concat(kept[1])
      kept[0]
    end

    # A read-only table of words. A word given as a name becomes the
    # program's id for it, or the Symbol Value of that id when `tagged`.
    # A fixed id is written directly; other ids are words that the link
    # fills.
    def id_table(name, words, section: :text_const, tagged: false)
      relocs = []
      filled = words.each_with_index.map do |word, i|
        next word if word.is_a?(Integer)
        next 0 if word.nil?

        id = fixed_id(word)
        next(tagged ? Lower.symbol_value(id, const("SYMBOL_TAG")) : id) if id

        relocs << Obj::Reloc.new(i * 8, tagged ? :symval : :symid, word.to_s)
        0
      end
      @data << Obj::Datum.new(name, section, filled.pack("q<*"), relocs: relocs, align: 8)
      name
    end

    # The words of an Array or Hash literal that contains only
    # immediates, as data that zr_ary_of and zr_hash_of copy into the
    # object's slots. Each word is an Integer, or a name whose Symbol the
    # link writes.
    def word_table(words)
      name = "#{@prefix}_lit_#{@lits}"
      @lits += 1
      id_table(name, words, tagged: true)
    end

    # `[functions, data]`: the program's toplevel, then one function
    # per required file, each with its own file name for backtraces.
    #
    # With a block, each function goes to the block after its file is
    # lowered, and the result is the block's return values. So a program
    # of a thousand files never has all of their IR in memory at once.
    def run(&finish)
      finished = []
      open_unit(@entry, @program.body)
      Function.new(self, @entry, @program.locals, @program.body, nil, @kind, outer: @outer).lower
      finished.concat(finished_functions(&finish)) if finish
      (@program.units || []).each_with_index do |u, i|
        @file = u.file
        @warnings = u.warnings || []
        @unit_internal = u.internal
        @unit_hidden = u.hidden
        @ids = u.node_ids
        open_unit(unit_entry(i), u.body)
        kept = finish && taken(u)
        if kept
          spent(u)
          next finished.concat(kept)
        end

        from = @data.size
        Function.new(self, @prefix, u.locals, u.body, nil, :top).lower
        next unless finish

        close_pool
        made = finished_functions(&finish)
        @units&.keep(u, @prefix, made, @data[from..])
        spent(u)
        finished.concat(made)
      end
      open_unit
      close_pool
      @ids = @program.node_ids
      @unit_internal = @ext
      @unit_hidden = false
      @file = @program.file
      @warnings = @program.warnings || []
      [finish ? finished : @functions, @data]
    end

    # The program's toplevel alone, as `run` lowers it first: its
    # `[functions, data]`. With `lower_unit`, a caller can lower the units
    # one at a time, in any order (`Cache::Lowering::EvalSupport`): each unit uses its own
    # names and counters, so its code is the same as in `run`. The pool
    # closes at the end of each, where `run` puts it.
    def lower_entry
      sliced do
        open_unit(@entry, @program.body)
        Function.new(self, @entry, @program.locals, @program.body, nil, @kind, outer: @outer).lower
        close_pool
      end
    end

    # The unit at `index` of the program, as `run` lowers it: its
    # `[functions, data]`.
    def lower_unit(index)
      u = @program.units[index]
      sliced do
        @file = u.file
        @warnings = u.warnings || []
        @unit_internal = u.internal
        @unit_hidden = u.hidden
        @ids = u.node_ids
        open_unit(unit_entry(index), u.body)
        Function.new(self, @prefix, u.locals, u.body, nil, :top).lower
        close_pool
      ensure
        @ids = @program.node_ids
      end
    end

    # The functions and data that the block adds. Each is a copy: a slice
    # (`@data[data..]`) shares the whole buffer of the array, and eval
    # support's 411 slices kept 0.9 GB for the collector to mark.
    def sliced
      functions = @functions.size
      data = @data.size
      yield
      [@functions.values_at(functions...@functions.size), @data.values_at(data...@data.size)]
    end
    private :sliced

    # Releases a unit after its code is made and cached. Only the
    # lowering reads its tree, locals and source, and the cache already
    # has the source for its key. A self-compile lowers about 4,000
    # units, and keeping every tree to the end of the build is most of
    # what the collector marks on each pass.
    #
    # Only the streaming path releases. Without a block, `run` returns
    # all functions at once, and the caller can be a test that lowers a
    # program and then dumps it.
    def spent(unit)
      unit.body = nil
      unit.node_ids = nil
      unit.locals = nil
      unit.source = nil
    end

    # The prefix of each function name in the current unit.
    def entry = @prefix

    # A unit's toplevel entry. For a file in eval support, it is the
    # entry that eval support already built. Otherwise it is a name made
    # from this lowering's entry and the file. The name uses the file,
    # not the position in the program, so a unit's names and code do not
    # change when a file is added before it. The name includes the entry
    # because the core library is lowered one file at a time, and each
    # lowering contains its own copy of what it requires. Two copies of
    # one file must be two symbols.
    def unit_entry(index)
      return index if index.is_a?(String)

      self.class.entry_of(@entry, index, @program.units[index]&.file)
    end

    # The entry of the unit at `index` and `file`, in a program lowered
    # from `entry`.
    def self.entry_of(entry, index, file)
      return "#{entry}_unit_#{index}" unless file&.start_with?("/")

      "zr_u#{Digest::SHA256.hexdigest("#{entry}\0#{Paths.shown(file)}")[0, 16]}"
    end

    # Every unit's entry, in order. A require or an autoload refers to
    # its target by this entry, so the entries are an input of each
    # unit's bytes (`Cache::Unit`).
    def self.entries_of(entry, units) = (units || []).each_with_index.map { |u, i| entry_of(entry, i, u.file) }

    # Whether the code goes to the wasm backend, where the preemption
    # count is the clock (lib/zr/runtime/kernel/send.rb).
    def wasm? = @target.arch == :wasm32

    # The FrameMeta kind of a function of `kind` in this lowering.
    def frame_kind(kind)
      return Function::KINDS.fetch(kind) unless internal?

      kind == :def ? "KIND_BUILTIN" : "KIND_HIDDEN"
    end

    def const(name)
      @kernel.const_for(name) or raise ArgumentError, "the kernel declares no #{name}"
    end

    def layout(name)
      @kernel.struct_for(name) or raise ArgumentError, "the kernel declares no #{name}"
    end

    # Whether `word` is an immediate and not a cell, as the kernel
    # defines it (lib/zr/runtime/kernel/value.rb).
    def immediate?(word) = @kernel.immediate?(word)

    # The kernel def named `name`, with the signature a call needs.
    def kernel_def(name)
      @kernel.def_for(name) or raise ArgumentError, "the kernel declares no #{name}"
    end

    def refuse(node, message)
      raise Refused, "#{@file}:#{node.line}: #{message}"
    end

    # A form of Ruby that zr does not support yet, at the node's line.
    def unsupported(node, form = Refused.form_of(node))
      raise Refused.unsupported(form, file: @file, line: node.line)
    end

    # A read-only string literal, as data in this unit.
    def literal(bytes)
      name = "#{@prefix}_lit_#{@lits}"
      @lits += 1
      @data << Obj::Datum.new(name, :text_const, bytes.b, align: 1)
      name
    end

    # The slot of a regexp or range literal site in the runtime's table,
    # when this lowering owns the counter.
    def literal_index = @symbols.site

    # The pool word for this unit's next literal site, or nil when the
    # lowering owns the counter and can take a slot now. A site is a
    # location, not a name, so each call takes its own pool entry.
    def pool_site
      return nil unless @fixed

      at = @pool.size
      @pool << [:site, "#{@prefix}##{@sites}"]
      @sites += 1
      ["#{@prefix}_pool", at * 8]
    end

    # A zeroed cell of `bytes` for one site's cache (lib/zr/runtime/kernel/cache.rb).
    # Its name includes the site count, so two lowerings that share a
    # symbol table never make the same cell name.
    def cache_cell(prefix, bytes)
      name = "#{@prefix}_cell_#{prefix}_#{number}"
      @data << Obj::Datum.new(name, :bss, bytes, align: 8)
      name
    end

    # The current unit's file name as a build writes it (`Paths.shown`),
    # and as bytes in the object.
    def shown_file = Paths.shown(@file)
    def file_bytes = @file_bytes[@file] ||= literal(shown_file)

    # The FrameMeta of function `fn`. It is writable, because the runtime
    # fills in the owner and name at definition. A class body's name is
    # the class's, set here. A def or block contains its arity and its
    # parameter entries, and a block contains its function, so a Proc
    # finds both.
    def meta(fn, kind, line, name = 0, parent = nil, params = nil, locals = [], env = false, ruby = false,
             captures: false, node: 0, cover: nil)
      layout = layout("FrameMeta")
      file = file_bytes
      bytes = ("\0" * layout.size).b
      word = ->(field, value) { bytes[layout.fields.fetch(field).first, 8] = [value].pack("q<") }
      word.call("name", name.is_a?(Integer) ? name : (fixed_id(name) || 0))
      word.call("file_len", internal? ? 0 : shown_file.bytesize)
      word.call("kind", const(kind))
      word.call("line", line)
      word.call("node", node)
      # The def-site entry that this scope uses when it makes a method,
      # plus one, so 0 means that the program does not measure coverage.
      word.call("cover", cover ? cover + 1 : 0)
      word.call("arity", params ? params.arity : 0)
      word.call("env", env ? 1 : 0)
      word.call("ruby", ruby ? 1 : 0)
      word.call("hidden", @unit_hidden ? 1 : 0)
      relocs = [Obj::Reloc.new(layout.fields.fetch("file").first, :abs64, file)]
      relocs << Obj::Reloc.new(layout.fields.fetch("name").first, :symid, name.to_s) if !name.is_a?(Integer) && !fixed_id(name)
      relocs << Obj::Reloc.new(layout.fields.fetch("parent").first, :abs64, parent) if parent
      relocs << Obj::Reloc.new(layout.fields.fetch("params").first, :abs64, param_table(fn, params)) if params
      relocs << Obj::Reloc.new(layout.fields.fetch("locals").first, :abs64, local_table(fn, locals))
      # A scope's captures are known only after its body is lowered, so
      # the caller writes that table later and sets `captures` here. The
      # table name is the same in both cases.
      relocs << Obj::Reloc.new(layout.fields.fetch("captures").first, :abs64, "zr_captures_#{fn}") if captures
      relocs << Obj::Reloc.new(layout.fields.fetch("fn").first, :abs64, fn) if kind == "KIND_BLOCK" || kind == "KIND_HIDDEN"
      name = "zr_meta_#{fn}"
      @data << Obj::Datum.new(name, :data, bytes, relocs: relocs, align: 8)
      name
    end

    # The scope's locals as data: the count, then one name id for each,
    # in slot order. An eval and a Binding read the scope's names here.
    def local_table(fn, locals)
      id_table("zr_locals_#{fn}", [locals.size, *locals])
    end

    # The scope's captures (outer locals) as data: the count, then a name
    # id and flags for each (1: the scope writes it, 2: the owner scope
    # binds it more than once). A Ractor reads them from a block's meta to
    # refuse a block that it cannot isolate, and to list the captures.
    #
    # The order is ruby's. Ruby keys a block's outer variables by symbol,
    # in the order that the program first uses each name. zr's symbol ids
    # do not follow the program (the runtime used many names first), so
    # the entries follow the order of each local's first declaration.
    def captures_table(fn, rows)
      rows = rows.sort_by { |local, _, _| @spelled.fetch(local, @spelled.size) }
      words = rows.flat_map { |local, written, rebound| [local, (written ? 1 : 0) | (rebound ? 2 : 0)] }
      id_table("zr_captures_#{fn}", [rows.size, *words])
    end

    # Each of `names` in the order the program first declares it.
    def spell(names)
      names.each { |n| @spelled[n] ||= @spelled.size }
    end

    PARAM_KINDS = %i[req opt rest keyreq key keyrest block nokey].each_with_index.to_h.freeze

    # `Method#parameters` as data: the count, then a kind and a name id
    # for each parameter (0 for no name).
    def param_table(fn, params)
      rows = params.rows.flat_map { |kind, name| [PARAM_KINDS.fetch(kind), name] }
      id_table("zr_params_#{fn}", [params.rows.size, *rows])
    end

    # A read-only table of symbol ids: the keywords of a def, or a call's
    # keywords after their count. All sites in the unit that pass the same
    # keys in the same order share one table, so a def's shape cell hits
    # for all of them.
    def keyword_table(words)
      @keyword_tables[words] ||= id_table("#{@prefix}_kw_#{@keyword_tables.size}", words)
    end

    # Lowers a def now into a function, named for the site.
    def define(node)
      name = def_name(node)
      Function.new(self, name, node.locals, node.body, node, :def).lower
      name
    end

    # Lowers a class, module or singleton class body into a function.
    #
    # A `class << self` body keeps `outer`, the Function that contains it,
    # as the parent of its frame metadata, so a `return` in it finds its
    # method.
    def body(node, outer = nil)
      kind = { Hir::ClassDef => :class, Hir::ModuleDef => :module, Hir::SingletonClassDef => :sclass }.fetch(node.class)
      name = "#{@prefix}_body_#{number}_#{kind == :sclass ? "singleton" : node.name}"
      Function.new(self, name, node.locals, node.body, node, kind, outer: kind == :sclass ? outer : nil).lower
      name
    end

    # Lowers a block literal into a function. `outer` is the Function
    # that contains it.
    def block(node, outer)
      @block_names[node] ||= begin
        name = "#{@prefix}_blk_#{number}"
        Function.new(self, name, node.locals, node.body, node, :block, outer: outer).lower
        name
      end
    end

    private

    # Sends the functions lowered since the last call to `finish`. The
    # lowering keeps none of them.
    def finished_functions(&)
      done = @functions.map(&)
      @functions = []
      done
    end

    # A new function number. Functions nest, so the count of finished
    # functions cannot identify them.
    def number
      @next += 1
    end
  end
end
