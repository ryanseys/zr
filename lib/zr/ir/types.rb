# frozen_string_literal: true

require_relative "inst"

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
      class Refused < StandardError; end

      # The bytes that a value of each type uses in memory: what a load of
      # the type reads and a store of the type writes.
      WIDTH = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze

      # The rule for the result type of each opcode. This is a table and not
      # a `case`, because a `case` compares the opcode with about twenty
      # entries one at a time, and each instruction of the program goes
      # through it.
      RULE = {
        iconst: :own, load: :own, ireduce: :own, uextend: :own, sextend: :own, gates: :own,
        call: :call, call_indirect: :call_indirect,
        icmp: :flag, fcmp: :flag,
        stack_addr: :address, symbol_value: :address, func_addr: :address,
        select: :second,
        sadd_overflow: :first, ssub_overflow: :first, smul_overflow: :first
      }.merge((Inst::FBINOPS + Inst::FUNOPS).to_h { |op| [op, :float] }).freeze

      # `{ "v3" => "i64", ... }`, in block layout order. A value gets its type
      # before any block that can use it, because its definition dominates
      # each use.
      def self.of(function) = new(function).all

      def initialize(function)
        @f = function
        @type = {}
      end

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
      def of(v)
        @type.fetch(v) { raise Refused, "#{@f.name}: no type for #{v}" }
      end

      # The signature of a callee entity name (`"fn0"`).
      def sig_of(fn)
        callee = callee_named(fn) or raise Refused, "#{@f.name}: no callee #{fn}"
        sig_named(callee.sig)
      end

      def sig_named(sig)
        @sig_named ||= first_by(@f.sigs, &:sig)
        @sig_named[sig] or raise Refused, "#{@f.name}: no signature #{sig}"
      end

      def callee_named(fn)
        @callee_named ||= first_by(@f.callees, &:fn)
        @callee_named[fn]
      end

      def global_named(gv)
        @global_named ||= first_by(@f.globals, &:gv)
        @global_named[gv]
      end

      def block_named(name)
        @block_named ||= first_by(@f.blocks, &:name)
        @block_named.fetch(name)
      end

      private

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
        when :call then sig_of(i.callee).ret
        when :call_indirect then sig_named(i.callee).ret
        when :second then of(i.args[1])
        else of(i.args[0])
        end
      end

      # Each entry by its key. The first entry wins, as with `find`.
      def first_by(rows)
        rows.each_with_object({}) { |row, index| index[yield(row)] ||= row }
      end
    end
  end
end
