# frozen_string_literal: true

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
      def initialize(program, unit, symbols, entry: "zr_toplevel", internal: false, ext: false, kind: :main, outer: nil)
        @program = program
        @unit = unit
        @symbols = symbols
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
        @spelled = {}
        @next = 0
      end

      # `[functions, data]`: the program's toplevel, then one function
      # per required file, each with its own file name for backtraces.
      #
      # Given a block, each function goes to it once its file is lowered,
      # and the functions are what the block answers: a program of a
      # thousand files then never holds the IR of them all at once.
      def run(&finish)
        finished = []
        Function.new(self, @entry, @program.locals, @program.body, nil, @kind, outer: @outer).lower
        finished.concat(finished_functions(&finish)) if finish
        (@program.units || []).each_with_index do |u, i|
          @file = u.file
          @warnings = u.warnings || []
          @unit_internal = u.internal
          @unit_hidden = u.hidden
          Function.new(self, unit_entry(i), u.locals, u.body, nil, :top).lower
          finished.concat(finished_functions(&finish)) if finish
        end
        @unit_internal = @ext
        @unit_hidden = false
        @file = @program.file
        @warnings = @program.warnings || []
        [finish ? finished : @functions, @data]
      end

      # The name every function this lowering makes starts from.
      attr_reader :entry

      # A unit's toplevel: this program's unit at `index`, or the entry a
      # road built already answers for a file it holds.
      def unit_entry(index)
        index.is_a?(String) ? index : "#{@entry}_unit_#{index}"
      end

      # The FrameMeta kind a function of `kind` gets here.
      def frame_kind(kind)
        return Function::KINDS.fetch(kind) unless internal?

        kind == :def ? "KIND_BUILTIN" : "KIND_HIDDEN"
      end

      def const(name)
        @unit.const_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      def layout(name)
        @unit.struct_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      # The kernel def named `name`, with the signature a call needs.
      def kernel_def(name)
        @unit.def_for(name) or raise ArgumentError, "the kernel declares no #{name}"
      end

      def refuse(node, message)
        raise Refused, "#{@file}:#{node.line}: #{message}"
      end

      # A read-only string literal, as data this unit carries.
      def literal(bytes)
        name = "#{@entry}_lit_#{@data.size}"
        @data << Obj::Data.new(name, :text_const, bytes.b, align: 1)
        name
      end

      # Each regexp or range literal site's slot in the runtime's table
      # of them.
      def literal_index = @symbols.site

      # A zeroed cell of `bytes` for one site's cache (rt/kernel/cache.rb),
      # named from the site count so no two lowerings that share a symbol
      # table name the same cell.
      def cache_cell(prefix, bytes)
        name = "zr_#{prefix}_#{@symbols.site}"
        @data << Obj::Data.new(name, :bss, bytes, align: 8)
        name
      end

      # The FrameMeta of function `fn`: writable, since the runtime fills
      # in the owner and name at definition. A class body's name is the
      # class's, set here; a def or block carries its arity and its
      # parameter rows, and a block its function, so a Proc finds both.
      # The current unit's file name as bytes in the object.
      def file_bytes
        @file_bytes ||= {}
        @file_bytes[@file] ||= literal(@file)
      end

      def meta(fn, kind, line, name = 0, parent = nil, params = nil, locals = [], env = false, ruby = false,
               captures: false, node: 0)
        layout = layout("FrameMeta")
        file = file_bytes
        bytes = ("\0" * layout.size).b
        word = ->(field, value) { bytes[layout.fields.fetch(field).first, 8] = [value].pack("q<") }
        word.call("name", name)
        word.call("file_len", internal? ? 0 : @file.bytesize)
        word.call("kind", const(kind))
        word.call("line", line)
        word.call("node", node)
        word.call("arity", params ? params.arity : 0)
        word.call("env", env ? 1 : 0)
        word.call("ruby", ruby ? 1 : 0)
        word.call("hidden", @unit_hidden ? 1 : 0)
        relocs = [Obj::Reloc.new(layout.fields.fetch("file").first, :abs64, file)]
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
        name = "zr_locals_#{fn}"
        @data << Obj::Data.new(name, :text_const, [locals.size, *locals.map { |n| @symbols.id(n) }].pack("q<*"), align: 8)
        name
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
        name = "zr_captures_#{fn}"
        rows = rows.sort_by { |local, _, _| @spelled.fetch(local, @spelled.size) }
        words = rows.flat_map { |local, written, rebound| [@symbols.id(local), (written ? 1 : 0) | (rebound ? 2 : 0)] }
        @data << Obj::Data.new(name, :text_const, [rows.size, *words].pack("q<*"), align: 8)
        name
      end

      # Each of `names` in the order the program first declares it.
      def spell(names)
        names.each { |n| @spelled[n] ||= @spelled.size }
      end

      PARAM_KINDS = %i[req opt rest keyreq key keyrest block nokey].each_with_index.to_h.freeze

      # `Method#parameters` as data: the row count, then a kind and a
      # name id per row, 0 for a row with no name.
      def param_table(fn, params)
        rows = params.rows.flat_map { |kind, name| [PARAM_KINDS.fetch(kind), name ? @symbols.id(name) : 0] }
        name = "zr_params_#{fn}"
        @data << Obj::Data.new(name, :text_const, [params.rows.size, *rows].pack("q<*"), align: 8)
        name
      end

      # A read-only table of symbol ids: the keywords a def declares.
      def keyword_table(ids)
        @keyword_tables ||= {}
        @keyword_tables[ids] ||= begin
          name = "#{@entry}_kw_#{@data.size}"
          @data << Obj::Data.new(name, :text_const, ids.pack("Q<*"), align: 8)
          name
        end
      end

      # The function a def becomes, lowered now and named for the site.
      def define(node)
        name = "#{@entry}_def_#{number}_#{node.name.to_s.gsub(/[^A-Za-z0-9_]/, "")}"
        Function.new(self, name, node.locals, node.body, node, :def).lower
        name
      end

      # The function a class, module or singleton class body becomes.
      def body(node)
        kind = { Hir::ClassDef => :class, Hir::ModuleDef => :module, Hir::SingletonClassDef => :sclass }.fetch(node.class)
        name = "#{@entry}_body_#{number}_#{kind == :sclass ? "singleton" : node.name}"
        Function.new(self, name, node.locals, node.body, node, kind).lower
        name
      end

      # The function a block literal becomes; `outer` is the Function it
      # is written in.
      def block(node, outer)
        name = "#{@entry}_blk_#{number}"
        Function.new(self, name, node.locals, node.body, node, :block, outer: outer).lower
        name
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
