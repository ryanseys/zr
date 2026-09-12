# frozen_string_literal: true

require_relative "inst"

module Ze0
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
        case i.op
        when :iconst, :load, :ireduce, :uextend, :sextend then i.type
        when :call then sig_of(i.callee).ret
        when :call_indirect then sig_named(i.callee).ret
        when :icmp, :fcmp then "i8"
        when :stack_addr, :symbol_value, :func_addr then "i64"
        when *Inst::FBINOPS, *Inst::FUNOPS then "f64"
        when :select then of(i.args[1])
        when :sadd_overflow, :ssub_overflow, :smul_overflow then of(i.args[0])
        else i.type || of(i.args[0])
        end
      end

      # Each row by its key, the first row winning as `find` would.
      def first_by(rows)
        rows.each_with_object({}) { |row, index| index[yield(row)] ||= row }
      end
    end
  end
end
