# frozen_string_literal: true

module Zr
  module Machine
    TYPES = {
      "I8" => "i8", "Bool" => "i8", "I32" => "i32", "Word" => "i64", "Ptr" => "i64",
      "Value" => "i64", "F64" => "f64", "Void" => nil
    }.freeze #: Hash[String, String?]

    # The names of the types in a def's `#:` comment, which is inline RBS:
    # `#: (i32, ptr) -> i32`. sig/zr/kern.rbs declares each name as a type
    # alias, so RBS reads the comment too.
    RBS_TYPES = {
      "i8" => "I8", "bool" => "Bool", "i32" => "I32", "word" => "Word", "ptr" => "Ptr",
      "value" => "Value", "f64" => "F64", "void" => "Void"
    }.freeze #: Hash[String, String]

    DEF_TYPE = /\A#:\s*\((?<params>[^()]*)\)\s*->\s*(?<ret>\w+)\s*\z/

    # The `#:` comments of a parsed file, by line.
    #: (Prism::ParseResult result) -> Hash[Integer, String]
    def self.annotations(result)
      lines = {} #: Hash[Integer, String]
      result.comments.each do |comment|
        text = comment.location.slice
        lines[comment.location.start_line] = text if text.start_with?("#:")
      end
      lines
    end

    # The parameter types and the return type of the `#:` comment `text`,
    # as names of TYPES, or nil when `text` is not `#: (types) -> type`.
    # Only a return is `void`.
    #: (String text) -> [Array[String], String]?
    def self.def_type(text)
      m = DEF_TYPE.match(text) or return nil
      params = m[:params].split(",").map { |name| RBS_TYPES[name.strip] }
      ret = RBS_TYPES[m[:ret]]
      return nil if ret.nil? || params.any? { |type| type.nil? || type == "Void" }

      [params.compact, ret]
    end

    # Whether a word is an immediate and not a pointer to a cell: a
    # Fixnum, a flonum, a Symbol, nil, true or false. This is the same
    # test as `zr_special_p` (lib/zr/runtime/kernel/value.rb), applied at compile
    # time to a known word. Thus a lowering can remove a sequence whose
    # result the test already decides.
    #
    # The unit being lowered and the description that a later build reads
    # both include it, each with its own constants.
    # @rbs module-self: _Constants
    module Immediates
      #: (Integer word) -> bool
      def immediate?(word)
        (word & 7) != 0 || word == const_for("QFALSE") || word == const_for("QNIL")
      end
    end

    # `from`: the wasm module of the import, or nil for a symbol that the
    # linker finds.
    #
    # The fields of these records are typed in
    # sig/zr/machine/description.rbs.
    # @rbs skip
    Import = Data.define(:name, :params, :ret, :from)
    # `effects`: the `IR::Effects` bits that a call of the def can write,
    # including the defs it calls. Nil until the fixpoint of the unit
    # sets it.
    # @rbs skip
    Def = Struct.new(:name, :params, :ret, :node, :file, :effects)
    # A function delivered as machine code: `Machine.raw "zr_switch"`.
    # @rbs skip
    Raw = Data.define(:name, :params, :ret)
    # The raw functions by name. The kernel subset knows only their signatures;
    # the native build gets their machine code from the backend
    # (`Backend::Aarch64::Stub`).
    RAW = [Raw.new("zr_switch", %w[Ptr Ptr], "Void")].to_h { |r| [r.name, r] }.freeze #: Hash[String, Raw]
    # A signature for `Machine.call`: `Machine.sig :name, [types] => type`.
    # @rbs skip
    Signature = Data.define(:name, :params, :ret)
    # `Machine.struct :Name, field: Type, ...`: fields as `name => [offset, type]`.
    # @rbs skip
    Layout = Data.define(:name, :fields, :size, :align)

    # The symbol ids that a unit gets with `Machine.id(:name)`. The
    # compiler owns the table. A unit compiled alone numbers the names in
    # the order it finds them.
    #
    # Only the kernel's ids are fixed in code. Every other lowering (the
    # core, the gem prelude, eval support, a program) loads the id of any
    # other name from its unit's pool, and the link numbers the pools in
    # the order of the pieces (`Zr.numbered`). So a table is the kernel's
    # names, then the core's, then eval support's or the program's.
    #
    # A table can have pads: ids that no name has (nil in `names`). A
    # binary's table marks a pad, so no symbol has its id.
    class Symbols
      # @rbs @intern: Method?

      attr_reader :ids #: Hash[String, Integer]
      attr_reader :names #: Array[String?]
      attr_accessor :sites #: Integer

      # `intern` lets a running program get an id for a new symbol. Only
      # eval support has one, and it applies only to names after `names`.
      # `names` gives a name, or nil for a pad, for each id from 0.
      #: (?Array[String?] names, ?sites: Integer, ?intern: Method?) -> void
      def initialize(names = [], sites: 0, intern: nil)
        @ids = {}
        @names = []
        @sites = sites
        names.each do |name|
          @ids[name] = @names.size unless name.nil?
          @names << name
        end
        @intern = intern
      end

      # With an `intern`, a new name goes to the program immediately, and
      # gets the id that the program's own table returns. Thus the two
      # tables always agree, whatever other names the program interned.
      #: (_ToS name) -> Integer
      def id(name)
        # @type ivar @intern: Method
        name = name.to_s
        @ids.fetch(name) do
          fresh = @intern ? @intern.call(name) : @names.size #: Integer
          @names[fresh] = name
          @ids[name] = fresh
        end
      end

      # A new index for a site that owns a run-time slot (the cached
      # object of a regexp literal). It is unique across all lowerings that
      # share this table or start from a copy of it.
      #: () -> Integer
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
      # @rbs @reads: Hash[[Symbol, String], String?]?

      include Immediates

      attr_reader :defs #: Hash[String, Def]
      attr_reader :consts #: Hash[String, Integer]
      attr_reader :structs #: Hash[String, Layout]

      # `unit` is a lowered kernel. This resolves each constant and
      # layout, so the tables contain only plain data.
      # The Ruby file that carries `text` into eval support
      # (`Runtime#carried_text`, which the loader finds as `Library::Roots::DESCRIPTION`).
      #: (String text) -> String
      def self.carried(text)
        rows = text.each_line.map { |line| "        #{line}" }.join
        rows << "\n" unless rows.empty? || rows.end_with?("\n")
        "# Generated by zr from lib/zr/runtime/kernel. Do not edit.\n" \
          "module Zr\n  module Machine\n    class Description\n      KERNEL = <<~ROWS\n" \
          "#{rows}      ROWS\n    end\n  end\nend\n"
      end

      #: (Lower unit) -> Description
      def self.of(unit)
        defs = unit.declared_defs.to_h { |name, d| [name, Def.new(name, d.params, d.ret, nil, nil, d.effects)] }
        # A declared constant always has a value, and a declared struct a
        # layout.
        consts = unit.declared_consts.to_h do |name|
          [name, unit.const_for(name)] #: [String, Integer]
        end
        structs = unit.declared_structs.to_h do |name|
          [name, unit.struct_for(name)] #: [String, Layout]
        end
        new(defs, consts, structs)
      end

      # One line for each entry. A def line gives its return type, then
      # its parameters. An `e` line gives the effects of a def. A const
      # line gives its value. A layout line gives its size and alignment,
      # then its fields. The format is text because a program contains it
      # as one frozen literal and reads it with only String#split.
      #: (String text) -> Description
      def self.parse(text)
        defs = {} #: Hash[String, Def]
        consts = {} #: Hash[String, Integer]
        structs = {} #: Hash[String, Layout]
        text.each_line do |line|
          # A row that `to_text` wrote: its fields are there.
          kind, name, *rest = line.split(" ") #: Array[untyped]
          case kind
          when "d" then defs[name] = Def.new(name, rest.drop(1).map { |f| f.split(":") }, rest.first)
          when "e" then defs.fetch(name).effects = Integer(rest.first)
          when "c" then consts[name] = Integer(rest.first)
          when "s"
            fields = rest.drop(2).to_h do |f|
              n, at, type = f.split(":")
              [n, [Integer(at), type]] #: [String, [Integer, String]]
            end
            structs[name] = Layout.new(name, fields, Integer(rest[0]), Integer(rest[1]))
          end
        end
        new(defs, consts, structs)
      end

      #: () -> String
      def to_text
        rows = @defs.map { |name, d| ["d", name, d.ret, *d.params.map { |n, t| "#{n}:#{t}" }] }
        rows += @defs.map { |name, d| ["e", name, d.effects] }
        rows += @consts.map { |name, value| ["c", name, value] }
        rows += @structs.map { |name, l| ["s", name, l.size, l.align, *l.fields.map { |n, (at, type)| "#{n}:#{at}:#{type}" }] }
        rows.map { |row| "#{row.join(" ")}\n" }.join
      end

      #: (Hash[String, Def] defs, Hash[String, Integer] consts, Hash[String, Layout] structs) -> void
      def initialize(defs, consts, structs)
        @defs = defs
        @consts = consts
        @structs = structs
      end

      #: (String name) -> Def?
      def def_for(name) = read(:d, name, @defs[name])
      #: (String name) -> Integer?
      def const_for(name) = read(:c, name, @consts[name])
      #: (String name) -> Layout?
      def struct_for(name) = read(:s, name, @structs[name])

      # The rows that the lookups in the block read, as `rows` gives them.
      # A cache of lowered code keys a piece on these, not on the whole
      # description, so a new kernel function keeps each piece that does
      # not call it (`Cache::Lowering::EvalSupport`).
      #: () { () -> void } -> Hash[[Symbol, String], String?]?
      def record
        outer = @reads
        begin
          @reads = {}
          yield
          @reads
        ensure
          reads = @reads
          outer&.merge!(reads) if reads
          @reads = outer
        end
      end

      # The text of each row that `reads` (from `record`) names, now: nil
      # for a name that has none.
      #: (Hash[[Symbol, String], String?] reads) -> Hash[[Symbol, String], String?]
      def rows(reads) = reads.keys.to_h { |kind, name| [[kind, name], row(kind, name)] }

      private

      #: [T] (Symbol kind, String name, T found) -> T
      def read(kind, name, found)
        # @type ivar @reads: Hash[[Symbol, String], String?]
        @reads[[kind, name]] ||= row(kind, name) if @reads
        found
      end

      #: (Symbol kind, String name) -> String?
      def row(kind, name)
        case kind
        when :d then (d = @defs[name]) && ["d", name, d.ret, *d.params.map { |n, t| "#{n}:#{t}" }, "e", d.effects].join(" ")
        when :c then @consts.key?(name) ? "c #{name} #{@consts[name]}" : nil
        when :s
          (l = @structs[name]) && ["s", name, l.size, l.align, *l.fields.map { |n, (at, type)| "#{n}:#{at}:#{type}" }].join(" ")
        end
      end

    end
  end
end
