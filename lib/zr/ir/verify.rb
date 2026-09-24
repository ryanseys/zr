# frozen_string_literal: true

require_relative "analysis"
require_relative "function"
require_relative "types"

module Zr
  module IR
    # The checks every function passes before an emitter sees it: every
    # block ends in a terminator, every branch names a block and passes as
    # many arguments as it takes, and every value used is defined once.
    # Under `strict` also: every use is dominated by its definition,
    # every argument a jump carries has its parameter's type, and every
    # operand has the type its opcode takes (`Strict::OPERANDS`). A
    # failure names the function and the instruction.
    module Verify
      class Error < StandardError; end

      module_function

      def check(f, strict: false)
        blocks = f.blocks.to_h { |b| [b.name, b] }
        defined = {}
        f.blocks.each do |b|
          b.params.each { |v, _| define(f, defined, v, b.name) }
          b.insts.each { |i| i.results.each { |v| define(f, defined, v, b.name) } }
        end
        f.blocks.each do |b|
          raise Error, "#{f.name}: #{b.name} has no terminator" unless b.terminated?

          b.insts.each_with_index do |i, n|
            raise Error, "#{f.name}: #{b.name} has an instruction after its terminator" if n < b.insts.size - 1 && i.terminator?

            i.args.each do |a|
              next unless IR.value?(a)
              raise Error, "#{f.name}: #{b.name} uses #{a}, which nothing defines" unless defined.key?(a)
            end
            (i.targets || []).each do |name, args|
              target = blocks[name] or raise Error, "#{f.name}: #{b.name} jumps to #{name}, which does not exist"
              if args.size != target.params.size
                raise Error, "#{f.name}: #{b.name} passes #{args.size} argument(s) to #{name}, which takes #{target.params.size}"
              end
              raise Error, "#{f.name}: #{b.name} branches to #{name} with arguments" if i.op == :brif && !args.empty?
            end
          end
        end
        Strict.new(f, blocks).check if strict
        f
      end

      def define(f, defined, v, block)
        raise Error, "#{f.name}: #{v} is defined twice" if defined.key?(v)

        defined[v] = block
      end

      # Dominance and types, over `IR::Analysis`; a use in a block the
      # entry does not reach is not checked, since nothing runs it. An
      # analysis the function kept is held to one built afresh: a pass
      # that changed the function and did not say `changed!` is refused
      # here, so the kept answers can be trusted everywhere else.
      class Strict
        INTEGERS = %w[i8 i32 i64].freeze

        def initialize(f, blocks)
          @f = f
          @blocks = blocks
          @typer = nil
        end

        def check
          @typer = Types.new(@f)
          @typer.all
          @analysis = fresh
          order = @analysis.rpo
          defined_in = {}
          at = {}
          @f.blocks.each do |b|
            b.params.each { |v, _| defined_in[v] = b.name }
            b.insts.each_with_index do |i, n|
              i.results.each do |v|
                defined_in[v] = b.name
                at[v] = n
              end
            end
          end
          order.each do |b|
            b.insts.each_with_index do |i, n|
              i.args.each { |a| dominated(a, b, n, defined_in, at) if IR.value?(a) }
              operands(i, b)
              (i.targets || []).each do |name, args|
                params = @blocks.fetch(name).params
                args.each_with_index do |a, k|
                  dominated(a, b, n, defined_in, at) if IR.value?(a)
                  typed(i, b, a, params[k][1], to: name)
                end
              end
            end
          end
        end

        private

        # An analysis built now, and the function's kept one held to it.
        def fresh
          built = Analysis.new(@f)
          if @f.analysis? && !@f.analysis.same_as?(built)
            raise Error, "#{@f.name}: the kept analysis is stale; a pass changed the function and did not say changed!"
          end

          built
        end

        # The types an opcode's operands must have, checked against
        # what `Types` says each value is. An immediate operand has no
        # type and is not checked. A binary integer opcode takes its
        # result's type on both sides -- an `i8` compared with an `i64`
        # is what #43 was, and no backend reads it the same way; a shift
        # takes any integer amount. A call's arguments have the
        # signature's parameter types, a return the function's.
        def operands(i, b)
          case i.op
          when *Inst::BINOPS, *Inst::PAIRS
            want = @typer.of(i.results[0])
            typed(i, b, i.args[0], want)
            Inst::SHIFTS.include?(i.op) ? integer(i, b, i.args[1]) : typed(i, b, i.args[1], want)
          when :icmp
            integer(i, b, i.args[0])
            typed(i, b, i.args[1], type_of(i.args[0]) || type_of(i.args[1]))
          when :fcmp, *Inst::FBINOPS then i.args.each { |a| typed(i, b, a, "f64") }
          when *Inst::FUNOPS, :fcvt_to_sint_sat then typed(i, b, i.args[0], "f64")
          when :fcvt_from_sint, :brif then integer(i, b, i.args[0])
          when *Inst::BITOPS
            raise Error, "#{@f.name}: #{b.name} #{i.op} of an i8" if type_of(i.args[0]) == "i8"
          when :select
            integer(i, b, i.args[0])
            typed(i, b, i.args[2], type_of(i.args[1]))
          when :load, :gates_set, :gates_enter then typed(i, b, i.args[0], "i64")
          when :store then typed(i, b, i.args[1], "i64")
          when :call then arguments(i, b, i.args, @typer.sig_of(i.callee).params)
          when :call_indirect
            typed(i, b, i.args[0], "i64")
            arguments(i, b, i.args.drop(1), @typer.sig_named(i.callee).params)
          when :return
            typed(i, b, i.args[0], @f.ret_type) unless i.args.empty? || @f.ret_type.nil?
          when :ireduce then narrower(i, b, i.type, i.args[0])
          when :uextend, :sextend then narrower(i, b, type_of(i.args[0]), i.args[0], to: i.type)
          when :bitcast then typed(i, b, i.args[0], i.type == "f64" ? "i64" : "f64")
          end
        end

        def arguments(i, b, args, params)
          raise Error, "#{@f.name}: #{b.name} passes #{args.size} argument(s) to #{i.callee}, which takes #{params.size}" if args.size != params.size

          args.zip(params) { |a, want| typed(i, b, a, want) }
        end

        # `a` has type `want`, or is an immediate. `to` names the block
        # a jump passes `a` to.
        def typed(i, b, a, want, to: nil)
          got = type_of(a) or return
          return if want.nil? || got == want

          raise Error, "#{@f.name}: #{b.name} #{i.op} takes #{a} (#{got}) where #{want} is wanted" unless to
          raise Error, "#{@f.name}: #{b.name} passes #{a} (#{got}) to #{to}, whose parameter is #{want}"
        end

        def integer(i, b, a)
          got = type_of(a) or return
          raise Error, "#{@f.name}: #{b.name} #{i.op} takes #{a} (#{got}) where an integer is wanted" unless INTEGERS.include?(got)
        end

        # `a`'s width is more than `type`'s (a reduce), or less than
        # `to`'s (an extend).
        def narrower(i, b, type, a, to: nil)
          got = type_of(a) or return
          from, into = to ? [got, to] : [type, got]
          ok = INTEGERS.index(from) && INTEGERS.index(into) && INTEGERS.index(from) < INTEGERS.index(into)
          raise Error, "#{@f.name}: #{b.name} #{i.op} takes #{a} (#{got}) to #{i.type}, which is not narrower" unless ok
        end

        # The type of a value operand, or nil for an immediate.
        def type_of(a) = IR.value?(a) ? @typer.of(a) : nil

        # Whether the definition of `v` reaches its use at instruction
        # `n` of block `b`: in the same block before it, or in a block
        # that dominates `b`.
        def dominated(v, b, n, defined_in, at)
          home = defined_in.fetch(v)
          if home == b.name
            return if at[v].nil? || at[v] < n

            raise Error, "#{@f.name}: #{b.name} uses #{v} before it is defined"
          end
          return if @analysis.dominates?(home, b.name)

          raise Error, "#{@f.name}: #{b.name} uses #{v}, defined in #{home}, which does not dominate it"
        end
      end
    end
  end
end
