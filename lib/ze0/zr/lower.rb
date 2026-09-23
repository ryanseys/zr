# frozen_string_literal: true

require "digest/sha2"
require_relative "../hir"
require_relative "../ir"
require_relative "../obj/model"
require_relative "function"

module Ze0
  module Zr
    # A scope an eval runs inside: the names of its locals in the order
    # its Env holds them, and the scope outside that one. It stands where
    # a Function stands for a block, so a name the string did not declare
    # resolves to the slot the asking scope keeps it in.
    class Outer
      attr_reader :outer

      def initialize(names, outer = nil)
        @slot_of = names.each_with_index.to_h
        @outer = outer
      end

      def meta = nil

      # A scope an eval runs inside is compiled already, so what it
      # reaches outside itself is written down. The eval keeps its own
      # table and the walk stops here.
      def capture(_name, _depth, write:) = nil

      # Its body is not here to count, so no local of it counts as bound
      # twice.
      def bindings = Hash.new(0)

      def slot_index(node)
        @slot_of.fetch(node.name) { raise ArgumentError, "#{node.name} is not a local of the scope this eval runs in" }
      end
    end
    # HIR to IR against the `zr` runtime: one Function per scope (the
    # toplevel, each def, class body and block), the data they name, and
    # the FrameMeta rows backtraces read.
    class Lower
      class Refused < StandardError; end

      # `id` as the Value a Symbol is: the id above the tag the kernel
      # reads it by (rt/kernel/object.rb).
      def self.symbol_value(id, tag) = (id << 8) | tag

      # The bit an ivar table's `names` keeps for the name `id`
      # (rt/kernel/object.rb, zr_ivtab_name_bit), as a signed word.
      def self.ivar_name_bit(id)
        bit = 1 << (id & 63)
        bit < 1 << 63 ? bit : bit - (1 << 64)
      end

      attr_reader :program, :unit, :symbols, :data, :functions, :file, :warnings

      # The id of the prism node `node` came from, or 0.
      def node_id(node)
        @program.node_ids&.[](node) || 0
      end

      # `made`, a node the lowering builds for `node`, runs as `node` does.
      def noted(made, node)
        ids = @program.node_ids
        ids[made] ||= ids[node] if ids&.key?(node)
        made
      end

      # Whether the program names TracePoint, so its own code fires events.
      def traced?
        @program.traced ? true : false
      end

      # True in the core library and in an extension's ruby half: both
      # are the runtime's own code, so `Primitive` resolves there.
      def internal?
        @internal || @unit_internal
      end

      # The builtin classes the kernel names at boot, each with its global
      # slot. The core library reads them straight from the slot, as
      # CRuby's C reads rb_cInteger: a constant a program defines never
      # stands in for one, and no read walks the constant tables.
      def self.boot_classes
        @boot_classes ||= File.read(File.join(Paths::RT, "kernel/main.rb"))
                              .scan(/zr_boot_name\((G_\w+), Machine\.id\(:(\w+)\)\)/)
                              .to_h { |slot, name| [name.to_sym, slot] }
      end

      # The slot for a bare constant `name` in the core library, or nil.
      def boot_class_slot(name) = @internal ? Lower.boot_classes[name] : nil

      # `internal` marks the core library: its methods are builtins to a
      # backtrace, and its blocks and bodies leave no row at all. `ext`
      # marks a program that is one of the native halves, compiled alone,
      # which is internal as a unit of one is. `kind` is `:top` for an
      # eval, whose toplevel is a file's, not a program's: it starts no
      # program and prints no parse warning.
      def initialize(program, kernel, symbols, entry: "zr_toplevel", internal: false, ext: false, kind: :main, outer: nil,
                     target: Target.default, fixed: nil, units: nil)
        @program = program
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

      # A unit stands on its own: every name it spells starts from its
      # own prefix and is numbered from its own counters, so the same
      # file writes the same names whatever was compiled before it. The
      # program's own file keeps the entry it was given.
      def open_unit(prefix = @entry, body = nil)
        close_pool
        @prefix = prefix
        @next = 0
        @lits = 0
        @sites = 0
        @pool = []
        @spelled = {}
        @file_bytes = {}
        @keyword_tables = {}
        # The unit's own tree: what a site may inline a def of
        # (`Function::Inline`), the name each def's function takes, and
        # the cells a site and its inlined copies share.
        @unit_body = body
        @inline_defs = nil
        @def_names = {}.compare_by_identity
        @block_names = {}.compare_by_identity
        @site_cells = {}.compare_by_identity
      end

      # The def of the unit a send of `name` may inline: one written
      # once in the unit, of the shape `Function::Inline` takes; else
      # nil. A def's name is only a guess at what the site calls -- the
      # site's cell decides at run time.
      def inline_def(name)
        @inline_defs ||= Function::Inline.candidates(@unit_body)
        @inline_defs[name]
      end

      # The function name of the def `node`, made once whether the def
      # or a site that inlines it asks first.
      def def_name(node)
        @def_names[node] ||= "#{@prefix}_def_#{number}_#{node.name.to_s.gsub(/[^A-Za-z0-9_]/, "")}"
      end

      # The cell of the site `node`, shared by every lowering of the
      # node: the def's own function and each copy inlined at a call
      # site read one cell, which the def's run fills.
      def site_cell(node, prefix, bytes)
        @site_cells[node] ||= cache_cell(prefix, bytes)
      end

      # The id the program gives `name`, where the program cannot move
      # it: a name the runtime already spells, or any name at all in the
      # lowering that owns the table -- the runtime's, the road's, an
      # eval's. Every other name is the link's to number, and answers
      # nil so that the caller leaves it a word and a relocation.
      def fixed_id(name)
        return @symbols.id(name) unless @fixed

        @fixed[name.to_s]
      end

      # The word this unit's pool keeps for `name` under `kind`, as
      # `[the pool's name, its offset]`. A unit's code loads it instead
      # of carrying a number the compile order decided.
      def pool_word(kind, name)
        row = [kind, name.to_s]
        at = @pool.index(row) || (@pool << row).size - 1
        ["#{@prefix}_pool", at * 8]
      end

      # The pool as data: one zero word per row, each with the
      # relocation that says what the link writes there.
      def close_pool
        return if @pool.nil? || @pool.empty?

        relocs = @pool.each_with_index.map { |(kind, name), i| Obj::Reloc.new(i * 8, kind, name) }
        @data << Obj::Data.new("#{@prefix}_pool", :data_const, "\0".b * (@pool.size * 8), relocs: relocs, align: 8)
        @pool = []
      end

      # The unit's code as an earlier build left it, with its data put
      # back where this build's data stands.
      def taken(unit)
        kept = @units&.take(unit, @prefix) or return nil

        @data.concat(kept[1])
        kept[0]
      end

      # A read-only table of words, where a word given as a name is the
      # program's id for it, or the Symbol Value of that id when `tagged`:
      # baked where the id is fixed, and a word the link fills where it
      # is not.
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
        @data << Obj::Data.new(name, section, filled.pack("q<*"), relocs: relocs, align: 8)
        name
      end

      # The words of an Array or Hash literal of immediates alone, as
      # data zr_ary_of and zr_hash_of read where the record's slots would
      # have been written: each an Integer, or a name whose Symbol the
      # link writes.
      def word_table(words)
        name = "#{@prefix}_lit_#{@lits}"
        @lits += 1
        id_table(name, words, tagged: true)
      end

      # `[functions, data]`: the program's toplevel, then one function
      # per required file, each with its own file name for backtraces.
      #
      # Given a block, each function goes to it once its file is lowered,
      # and the functions are what the block answers: a program of a
      # thousand files then never holds the IR of them all at once.
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
        @unit_internal = @ext
        @unit_hidden = false
        @file = @program.file
        @warnings = @program.warnings || []
        [finish ? finished : @functions, @data]
      end

      # A unit whose code is made and kept, released. Its tree, its
      # locals and its source are what the front end left for the
      # lowering, nothing else reads them once the unit is lowered (each
      # unit's code has come from its own file alone since a unit's names
      # stopped depending on the compile order), and the cache has taken
      # the source it keys on. A self-compile lowers some four thousand
      # units, so holding every tree to the end of the build is most of
      # what the collector marks on every pass.
      #
      # Only the streaming path releases: given no block, `run` answers
      # every function at once and the caller may be a test that lowers a
      # program and then dumps it.
      def spent(unit)
        unit.body = nil
        unit.locals = nil
        unit.source = nil
      end

      # The name every function of the unit being lowered starts from.
      def entry = @prefix

      # A unit's toplevel: the entry a road built already answers for a
      # file it holds, else a name made from this lowering's entry and
      # the file. It is the file and not the place in the program, so
      # that a unit's names -- and so its code -- do not move when a
      # file is added before it. The entry is in the name because the
      # core library is lowered a file at a time and each of those
      # lowerings carries its own copy of what it requires: two copies
      # of one file must still be two symbols.
      def unit_entry(index)
        return index if index.is_a?(String)

        self.class.entry_of(@entry, index, @program.units[index]&.file)
      end

      # The entry of the `index`th unit, at `file`, of a program lowered
      # from `entry`.
      def self.entry_of(entry, index, file)
        return "#{entry}_unit_#{index}" unless file&.start_with?("/")

        "zr_u#{Digest::SHA256.hexdigest("#{entry}\0#{Paths.shown(file)}")[0, 16]}"
      end

      # Every unit's entry, in order: what a require or an autoload in
      # any unit spells for its target, and so an input of that unit's
      # bytes (`UnitCache`).
      def self.entries_of(entry, units) = (units || []).each_with_index.map { |u, i| entry_of(entry, i, u.file) }

      # The FrameMeta kind a function of `kind` gets here.
      # Whether the code goes to the wasm backend, where the preemption
      # count is the clock (rt/kernel/send.rb).
      def wasm? = @target.arch == :wasm32

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
      # spells it (rt/kernel/value.rb).
      def immediate?(word) = @kernel.immediate?(word)

      # The kernel def named `name`, with the signature a call needs.
      def kernel_def(name)
        @kernel.def_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.line}: #{message}"
      end

      # A read-only string literal, as data this unit carries.
      def literal(bytes)
        name = "#{@prefix}_lit_#{@lits}"
        @lits += 1
        @data << Obj::Data.new(name, :text_const, bytes.b, align: 1)
        name
      end

      # Each regexp or range literal site's slot in the runtime's table
      # of them, where this lowering owns the counter.
      def literal_index = @symbols.site

      # The pool word this unit keeps for its next literal site, or nil
      # where the lowering owns the counter and can take a slot now. A
      # site is a place and not a name, so each call takes a row of its
      # own.
      def pool_site
        return nil unless @fixed

        at = @pool.size
        @pool << [:site, "#{@prefix}##{@sites}"]
        @sites += 1
        ["#{@prefix}_pool", at * 8]
      end

      # A zeroed cell of `bytes` for one site's cache (rt/kernel/cache.rb),
      # named from the site count so no two lowerings that share a symbol
      # table name the same cell.
      def cache_cell(prefix, bytes)
        name = "#{@prefix}_cell_#{prefix}_#{number}"
        @data << Obj::Data.new(name, :bss, bytes, align: 8)
        name
      end

      # The FrameMeta of function `fn`: writable, since the runtime fills
      # in the owner and name at definition. A class body's name is the
      # class's, set here; a def or block carries its arity and its
      # parameter rows, and a block its function, so a Proc finds both.
      # The current unit's file name as a build writes it (`Paths.shown`),
      # and as bytes in the object.
      def shown_file = Paths.shown(@file)
      def file_bytes = @file_bytes[@file] ||= literal(shown_file)

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
        # The def-site row this scope claims when it makes a method,
        # plus one, so that 0 stands for a program measuring none.
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
        # What a scope reaches outside itself is known only once its body
        # is lowered, so the caller writes that table afterwards and says
        # so here. The name is the same either way.
        relocs << Obj::Reloc.new(layout.fields.fetch("captures").first, :abs64, "zr_captures_#{fn}") if captures
        relocs << Obj::Reloc.new(layout.fields.fetch("fn").first, :abs64, fn) if kind == "KIND_BLOCK" || kind == "KIND_HIDDEN"
        name = "zr_meta_#{fn}"
        @data << Obj::Data.new(name, :data, bytes, relocs: relocs, align: 8)
        name
      end

      # The scope's locals as data: the row count, then a name id each,
      # in slot order. An eval and a Binding read the scope's names here.
      def local_table(fn, locals)
        id_table("zr_locals_#{fn}", [locals.size, *locals])
      end

      # The locals a scope reaches outside itself, as data: the row count,
      # then a name id and its flags each (1: the scope writes it, 2: the
      # scope that owns it binds it more than once). A Ractor reads them
      # off a block's meta to refuse a block it cannot isolate, and to
      # name what it reaches.
      #
      # In the order ruby names them: its table of a block's outer
      # variables is keyed by symbol, and a symbol takes its place where
      # the program first spells the name. ze0's own symbol ids do not
      # follow the program -- the runtime spelled many names first -- so
      # the rows follow the order the program first declares each local.
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

      # `Method#parameters` as data: the row count, then a kind and a
      # name id per row, 0 for a row with no name.
      def param_table(fn, params)
        rows = params.rows.flat_map { |kind, name| [PARAM_KINDS.fetch(kind), name] }
        id_table("zr_params_#{fn}", [params.rows.size, *rows])
      end

      # A read-only table of symbol ids: the keywords a def declares, or
      # a call's keywords behind their count, shared by every site of
      # the unit that passes the same keys in the same order, so a def's
      # shape cell hits across them.
      def keyword_table(words)
        @keyword_tables[words] ||= id_table("#{@prefix}_kw_#{@keyword_tables.size}", words)
      end

      # The function a def becomes, lowered now and named for the site.
      def define(node)
        name = def_name(node)
        Function.new(self, name, node.locals, node.body, node, :def).lower
        name
      end

      # The function a class, module or singleton class body becomes.
      def body(node)
        kind = { Hir::ClassDef => :class, Hir::ModuleDef => :module, Hir::SingletonClassDef => :sclass }.fetch(node.class)
        name = "#{@prefix}_body_#{number}_#{kind == :sclass ? "singleton" : node.name}"
        Function.new(self, name, node.locals, node.body, node, kind).lower
        name
      end

      # The function a block literal becomes; `outer` is the Function it
      # is written in.
      def block(node, outer)
        @block_names[node] ||= begin
          name = "#{@prefix}_blk_#{number}"
          Function.new(self, name, node.locals, node.body, node, :block, outer: outer).lower
          name
        end
      end

      private

      # The functions lowered since the last call, through `finish`; the
      # lowering keeps none of them.
      def finished_functions(&finish)
        done = @functions.map(&finish)
        @functions = []
        done
      end

      # A fresh function number: functions nest, so the count of finished
      # ones does not name them.
      def number
        @next += 1
      end
    end
  end
end
