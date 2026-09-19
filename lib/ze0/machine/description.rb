# frozen_string_literal: true

module Ze0
  module Machine
    TYPES = {
      "I8" => "i8", "Bool" => "i8", "I32" => "i32", "Word" => "i64", "Ptr" => "i64",
      "Value" => "i64", "F64" => "f64", "Void" => nil
    }.freeze
    # Comparisons that read their operands as unsigned: pointers.
    UNSIGNED = %w[Ptr].freeze

    # Whether a word is an immediate and not a pointer to a cell: a
    # Fixnum, a flonum, a Symbol, nil, true or false. This is
    # `zr_special_p` (rt/kernel/value.rb), spelled the same way and asked
    # of a word the compiler already holds, so a lowering can drop a
    # sequence the answer has already decided.
    #
    # Both the unit being lowered and the description a later build reads
    # answer it, over whichever constants each of them keeps.
    module Immediates
      def immediate?(word)
        (word & 7) != 0 || word == const_for("QFALSE") || word == const_for("QNIL")
      end
    end

    # `from`: the module a wasm import comes from, or nil for a symbol
    # the link finds.
    Import = Struct.new(:name, :params, :ret, :from)
    Def = Struct.new(:name, :params, :ret, :node, :file)
    # A function delivered as machine code: `Machine.raw "zr_switch"`.
    Raw = Struct.new(:name, :params, :ret)
    # A signature `Machine.call` goes through: `Machine.sig :name, [types] => type`.
    Signature = Struct.new(:name, :params, :ret)
    # `Machine.struct :Name, field: Type, ...`: fields as `name => [offset, type]`.
    Layout = Struct.new(:name, :fields, :size, :align)

    # The symbol ids a unit names with `Machine.id(:name)`: the compiler
    # owns the table, and a unit compiled alone numbers names as it meets
    # them.
    class Symbols
      attr_reader :ids, :sites

      # `intern` is how a running program names a symbol it has not seen.
      # Only an eval has one, and only past the names it was seeded with.
      def initialize(names = [], sites: 0, intern: nil)
        @ids = {}
        @sites = sites
        names.each { |n| id(n) }
        @intern = intern
      end

      # With an `intern`, a name this table meets first is given to the
      # program at once and takes the id the program's own table answers,
      # so the two never drift apart, whatever else the program interned.
      def id(name)
        name = name.to_s
        @ids.fetch(name) { @ids[name] = @intern ? @intern.call(name) : @ids.size }
      end

      # A fresh index for a code site that owns a run-time slot (a regexp
      # literal's cached object), unique across every lowering that shares
      # this table or descends from it.
      def site
        @sites += 1
        @sites - 1
      end
    end

    # The three tables a lowering reads from a kernel unit: what each
    # `machine def` takes and answers, what each `Machine.const` is worth,
    # and how each `Machine.struct` is laid out. An eval carries this
    # instead of the kernel sources, and answers from it exactly as the
    # unit does.
    class Description
      include Immediates

      attr_reader :defs, :consts, :structs

      # `unit` is a lowered kernel; every constant and layout is resolved
      # here, so the tables the rows come from are plain data.
      def self.of(unit)
        defs = unit.declared_defs.to_h { |name, d| [name, Def.new(name, d.params, d.ret)] }
        consts = unit.declared_consts.to_h { |name| [name, unit.const_for(name)] }
        structs = unit.declared_structs.to_h { |name| [name, unit.struct_for(name)] }
        new(defs, consts, structs)
      end

      # One line per row: a def names its return type then its parameters,
      # a const its value, a layout its size and align then its fields.
      # Text, because a program carries this as one frozen literal and
      # reads it back with nothing but String#split.
      def self.parse(text)
        defs = {}
        consts = {}
        structs = {}
        text.each_line do |line|
          kind, name, *rest = line.split(" ")
          case kind
          when "d" then defs[name] = Def.new(name, rest.drop(1).map { |f| f.split(":") }, rest.first)
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
