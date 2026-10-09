# frozen_string_literal: true

require_relative "inst"
require_relative "../refused"

module Zr
  module IR
    # The type of each value that a function defines. A block parameter
    # has its declared type, and the result of an instruction has the type
    # that its opcode gives.
    #
    # The rule is defined only here, so the backend and the interpreter
    # cannot differ about the type of a value. Such a difference is the
    # miscompile that the interpreter must find.
    class Types
      # @rbs @f: Function
      # @rbs @type: Hash[String, String?]
      # @rbs @sig_named: Hash[String, Sig]?
      # @rbs @callee_named: Hash[String, Callee]?
      # @rbs @global_named: Hash[String, Global]?
      # @rbs @block_named: Hash[String, Block]?

      class Refused < StandardError
        include Zr::Refusal
      end

      # The bytes that a value of each type uses in memory: what a load of
      # the type reads and a store of the type writes.
      WIDTH = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze #: Hash[String, Integer]

      # The rule for the result type of each opcode. This is a table and not
      # a `case`, because a `case` compares the opcode with about twenty
      # entries one at a time, and each instruction of the program goes
      # through it.
      RULE = {
        iconst: :own, load: :own, ireduce: :own, uextend: :own, sextend: :own, gates: :own,
        call: :call, call_indirect: :call_indirect,
        icmp: :flag, fcmp: :flag,
        stack_addr: :address, va_list: :address, symbol_value: :address, func_addr: :address,
        select: :second,
        sadd_overflow: :first, ssub_overflow: :first, smul_overflow: :first
      }.merge((Inst::FBINOPS + Inst::FUNOPS).to_h { |op| [op, :float] }).freeze #: Hash[op, Symbol]

      # `{ "v3" => "i64", ... }`, in block layout order. A value gets its type
      # before any block that can use it, because its definition dominates
      # each use.
      #: (Function function) -> Hash[String, String?]
      def self.of(function) = new(function).all

      #: (Function function) -> void
      def initialize(function)
        @f = function
        @type = {} #: Hash[String, String?]
      end

      #: () -> Hash[String, String?]
      def all
        @f.blocks.each { |b| b.params.each { |v, t| @type[v] = t } }
        @f.blocks.each do |b|
          b.insts.each do |i|
            next if i.results.empty?

            @type[i.results[0]] = result_of(i)
            # The second result of an overflow pair is the flag.
            @type[i.results[1]] = "i8" if i.results.size > 1
          end
        end
        @type
      end

      # The type of `v`, which must already be typed.
      #: (String v) -> String?
      def of(v)
        @type.fetch(v) { raise Refused, "#{@f.name}: no type for #{v}" }
      end

      # The signature of a callee entity name (`"fn0"`). A nil name (an
      # `Inst#callee` that is not set) raises Refused.
      #: (String? fn) -> Sig
      def sig_of(fn)
        callee = callee_named(fn) or raise Refused, "#{@f.name}: no callee #{fn}"
        sig_named(callee.sig)
      end

      #: (String? sig) -> Sig
      def sig_named(sig)
        (@sig_named ||= first_by(@f.sigs, &:sig))[sig] or raise Refused, "#{@f.name}: no signature #{sig}"
      end

      #: (String? fn) -> Callee?
      def callee_named(fn)
        (@callee_named ||= first_by(@f.callees, &:fn))[fn]
      end

      #: (String gv) -> Global?
      def global_named(gv)
        (@global_named ||= first_by(@f.globals, &:gv))[gv]
      end

      #: (String name) -> Block
      def block_named(name)
        (@block_named ||= first_by(@f.blocks, &:name)).fetch(name)
      end

      private

      #: (Inst i) -> String?
      def result_of(i)
        rule = RULE[i.op]
        # Most opcodes have no entry in the table, and `iadd` is the most
        # frequent opcode. So this path comes first, with no compare.
        return i.type || of(i.args[0]) if rule.nil?

        case rule
        when :own then i.type
        when :flag then "i8"
        when :address then "i64"
        when :float then "f64"
        when :call then sig_of(callee_of(i)).ret
        when :call_indirect then sig_named(callee_of(i)).ret
        when :second then of(i.args[1])
        else of(i.args[0])
        end
      end

      # The callee (or signature) name of a call, which must have one.
      #: (Inst i) -> String
      def callee_of(i)
        i.callee or raise Refused, "#{@f.name}: #{i.op} has no callee"
      end

      # Each entry by its key. The first entry wins, as with `find`. The
      # types are `untyped` because the key type of a Hash is bounded
      # and Steep does not take that bound from a generic method.
      #: (Array[untyped] rows) { (untyped row) -> untyped } -> Hash[untyped, untyped]
      def first_by(rows)
        index = {} #: Hash[untyped, untyped]
        rows.each_with_object(index) { |row, entries| entries[yield(row)] ||= row }
      end
    end
  end
end
