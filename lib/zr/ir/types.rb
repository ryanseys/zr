# frozen_string_literal: true

require_relative "inst"

module Zr
  module IR
    # The type of every value a function defines: its block parameters
    # carry theirs, and each instruction's result takes the type its opcode
    # answers.
    #
    # One definition of the rule, so the backend and the interpreter cannot
    # disagree about what a value is. A disagreement there would be exactly
    # the miscompile the interpreter exists to find.
    class Types
      class Refused < StandardError; end

      # The bytes a value of each type takes in memory: what a load of
      # the type reads and a store of one writes.
      WIDTH = { "i8" => 1, "i32" => 4, "i64" => 8, "f64" => 8 }.freeze

      # Which rule an opcode's result follows. A table and not a `case`
      # over the opcodes: that case compared an opcode against twenty
      # entries in turn, eleven of them the float opcodes spread out of
      # two arrays, and every instruction in the program went through it.
      RULE = {
        iconst: :own, load: :own, ireduce: :own, uextend: :own, sextend: :own, gates: :own,
        call: :call, call_indirect: :call_indirect,
        icmp: :flag, fcmp: :flag,
        stack_addr: :address, symbol_value: :address, func_addr: :address,
        select: :second,
        sadd_overflow: :first, ssub_overflow: :first, smul_overflow: :first
      }.merge((Inst::FBINOPS + Inst::FUNOPS).to_h { |op| [op, :float] }).freeze

      # `{ "v3" => "i64", ... }`, in block layout order: a value is typed
      # before any block that can use it, because its definition dominates
      # every use.
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

      # The signature a callee entity name (`"fn0"`) was declared with.
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
        # The rule most opcodes follow is the one they do not name, and
        # `iadd` is the commonest opcode there is: it answers here,
        # having been compared against nothing.
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

      # Each row by its key, the first row winning as `find` would.
      def first_by(rows)
        rows.each_with_object({}) { |row, index| index[yield(row)] ||= row }
      end
    end
  end
end
