# frozen_string_literal: true

module Zr
  module Machine
    TYPES = {
      "I8" => "i8", "Bool" => "i8", "I32" => "i32", "Word" => "i64", "Ptr" => "i64",
      "Value" => "i64", "F64" => "f64", "Void" => nil
    }.freeze

    # Whether a word is an immediate and not a pointer to a cell: a
    # Fixnum, a flonum, a Symbol, nil, true or false. This is the same
    # test as `zr_special_p` (runtime/kernel/value.rb), applied at compile
    # time to a known word. Thus a lowering can remove a sequence whose
    # result the test already decides.
    #
    # The unit being lowered and the description that a later build reads
    # both include it, each with its own constants.
    module Immediates
      def immediate?(word)
        (word & 7) != 0 || word == const_for("QFALSE") || word == const_for("QNIL")
      end
    end

    # `from`: the wasm module of the import, or nil for a symbol that the
    # linker finds.
    Import = Data.define(:name, :params, :ret, :from)
    # `effects`: the `IR::Effects` bits that a call of the def can write,
    # including the defs it calls. Nil until the fixpoint of the unit
    # sets it.
    Def = Struct.new(:name, :params, :ret, :node, :file, :effects)
    # A function delivered as machine code: `Machine.raw "zr_switch"`.
    Raw = Data.define(:name, :params, :ret)
    # The raw functions by name. The dialect knows only their signatures;
    # the native build gets their machine code from the backend
    # (`Backend::Aarch64::Stub`).
    RAW = [Raw.new("zr_switch", %w[Ptr Ptr], "Void")].to_h { |r| [r.name, r] }.freeze
    # A signature for `Machine.call`: `Machine.sig :name, [types] => type`.
    Signature = Data.define(:name, :params, :ret)
    # `Machine.struct :Name, field: Type, ...`: fields as `name => [offset, type]`.
    Layout = Data.define(:name, :fields, :size, :align)

    # The symbol ids that a unit gets with `Machine.id(:name)`. The
    # compiler owns the table. A unit compiled alone numbers the names in
    # the order it finds them.
    #
    # A table can have pads: ids that no name has (nil in `names`). The
    # runtime's table ends in pads up to a multiple of `BLOCK`, so the ids
    # after it (eval support's own names, and a program's) start at the
    # same id while the runtime gains names. With `fill`, a new name takes
    # the first pad; the runtime's table fills, and every table made from
    # it appends. A binary's table marks a pad, so no symbol has its id.
    class Symbols
      BLOCK = 1024

      attr_reader :ids, :sites, :names

      # `intern` lets a running program get an id for a new symbol. Only
      # eval support has one, and it applies only to names after `names`.
      # `names` gives a name, or nil for a pad, for each id from 0.
      def initialize(names = [], sites: 0, intern: nil, fill: false)
        @ids = {}
        @names = []
        @free = []
        @sites = sites
        @used = {}
        names.each do |name|
          @free << @names.size if name.nil? && fill
          @ids[name] = @names.size unless name.nil?
          @names << name
        end
        @intern = intern
      end

      # Whether a lowering asked for the name of `id` (not only the table
      # that this one started from).
      def used?(id) = @used.key?(id)

      # With an `intern`, a new name goes to the program immediately, and
      # gets the id that the program's own table returns. Thus the two
      # tables always agree, whatever other names the program interned.
      def id(name)
        name = name.to_s
        at = @ids.fetch(name) do
          fresh = @intern ? @intern.call(name) : (@free.shift || @names.size)
          @names[fresh] = name
          @ids[name] = fresh
        end
        @used[at] = true
        at
      end

      # Ends the table in pads up to a multiple of BLOCK.
      def pad!
        @names << nil until (@names.size % BLOCK).zero?
        self
      end

      # A new index for a site that owns a run-time slot (the cached
      # object of a regexp literal). It is unique across all lowerings that
      # share this table or start from a copy of it.
      def site
        @sites += 1
        @sites - 1
      end
    end

    # The three tables that a lowering reads from a kernel unit: the
    # parameters and return type of each `machine def`, the value of each
    # `Machine.const`, and the layout of each `Machine.struct`. Eval
    # support contains this in place of the kernel sources, and returns
    # the same results as the unit.
    class Description
      include Immediates

      attr_reader :defs, :consts, :structs

      # `unit` is a lowered kernel. This resolves each constant and
      # layout, so the tables contain only plain data.
      # The Ruby file that carries `text` into eval support
      # (`runtime/ext/os/<os>/zr_description.rb`, which `zr-dev gen
      # description` writes).
      def self.carried(text)
        rows = text.each_line.map { |line| "        #{line}" }.join
        rows << "\n" unless rows.empty? || rows.end_with?("\n")
        "# Generated by `zr-dev gen description` from runtime/kernel. Do not edit.\n" \
          "module Zr\n  module Machine\n    class Description\n      KERNEL = <<~ROWS\n" \
          "#{rows}      ROWS\n    end\n  end\nend\n"
      end

      def self.of(unit)
        defs = unit.declared_defs.to_h { |name, d| [name, Def.new(name, d.params, d.ret, nil, nil, d.effects)] }
        consts = unit.declared_consts.to_h { |name| [name, unit.const_for(name)] }
        structs = unit.declared_structs.to_h { |name| [name, unit.struct_for(name)] }
        new(defs, consts, structs)
      end

      # One line for each entry. A def line gives its return type, then
      # its parameters. An `e` line gives the effects of a def. A const
      # line gives its value. A layout line gives its size and alignment,
      # then its fields. The format is text because a program contains it
      # as one frozen literal and reads it with only String#split.
      def self.parse(text)
        defs = {}
        consts = {}
        structs = {}
        text.each_line do |line|
          kind, name, *rest = line.split(" ")
          case kind
          when "d" then defs[name] = Def.new(name, rest.drop(1).map { |f| f.split(":") }, rest.first)
          when "e" then defs.fetch(name).effects = Integer(rest.first)
          when "c" then consts[name] = Integer(rest.first)
          when "s"
            fields = rest.drop(2).to_h { |f| n, at, type = f.split(":"); [n, [Integer(at), type]] }
            structs[name] = Layout.new(name, fields, Integer(rest[0]), Integer(rest[1]))
          end
        end
        new(defs, consts, structs)
      end

      def to_text
        rows = @defs.map { |name, d| ["d", name, d.ret, *d.params.map { |n, t| "#{n}:#{t}" }] }
        rows += @defs.map { |name, d| ["e", name, d.effects] }
        rows += @consts.map { |name, value| ["c", name, value] }
        rows += @structs.map { |name, l| ["s", name, l.size, l.align, *l.fields.map { |n, (at, type)| "#{n}:#{at}:#{type}" }] }
        rows.map { |row| "#{row.join(" ")}\n" }.join
      end

      def initialize(defs, consts, structs)
        @defs = defs
        @consts = consts
        @structs = structs
      end

      def def_for(name) = @defs[name]
      def const_for(name) = @consts[name]
      def struct_for(name) = @structs[name]

    end
  end
end
