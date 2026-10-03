# frozen_string_literal: true

require_relative "analysis"
require_relative "function"
require_relative "types"

module Zr
  module IR
    # The checks for each function before an emitter gets it: each block
    # ends in a terminator, each branch targets a block and passes the
    # correct number of arguments, and each used value has one definition.
    # With `strict`, also: each definition dominates its uses, each jump
    # argument has the type of its parameter, and each operand has the type
    # that its opcode takes (`Strict::OPERANDS`). A failure message gives
    # the function and the instruction.
    module Verify
      class Error < StandardError; end

      module_function

      #: (Function f, ?strict: bool) -> Function
      def check(f, strict: false)
        blocks = f.blocks.to_h { |b| [b.name, b] }
        defined = {} #: Hash[String, String]
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
              raise Error, "#{f.name}: #{b.name} branches to #{name} with arguments" if (i.op == :brif || i.op == :switch) && !args.empty?
            end
          end
        end
        Strict.new(f, blocks).check if strict
        f
      end

      #: (Function f, Hash[String, String] defined, String v, String block) -> String
      def define(f, defined, v, block)
        raise Error, "#{f.name}: #{v} is defined twice" if defined.key?(v)

        defined[v] = block
      end

      # Checks dominance and types with `IR::Analysis`. A use in an
      # unreachable block is not checked, because it never runs. A kept
      # analysis is checked against a new one, so a pass that changed the
      # function without `changed!` fails here. Thus all other code can trust
      # a kept analysis.
      class Strict
        # @rbs @f: Function
        # @rbs @blocks: Hash[String, Block]
        # @rbs @typer: Types
        # @rbs @analysis: Analysis

        INTEGERS = %w[i8 i32 i64].freeze

        # `@typer` is nil until `check` sets it, before each read.
        #: (Function f, Hash[String, Block] blocks) -> void
        def initialize(f, blocks)
          @f = f
          @blocks = blocks
          @typer = nil #: untyped
        end

        #: () -> void
        def check
          @typer = Types.new(@f)
          @typer.all
          @analysis = fresh
          order = @analysis.rpo
          defined_in = {} #: Hash[String, String]
          at = {} #: Hash[String, Integer]
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

        # Makes a new analysis, and checks the kept analysis against it.
        #: () -> Analysis
        def fresh
          built = Analysis.new(@f)
          if @f.analysis? && !@f.analysis.same_as?(built)
            raise Error, "#{@f.name}: the kept analysis is stale; a pass changed the function and did not say changed!"
          end

          built
        end

        # Checks the operand types of an opcode against the types from `Types`.
        # An immediate operand has no type and is not checked. A binary integer
        # opcode takes its result type on both sides: backends read an `i8`
        # compared with an `i64` differently (see #43). A shift takes an amount
        # of any integer type. Call arguments have the parameter types of the
        # signature, and a return has the return type of the function.
        #: (Inst i, Block b) -> void
        def operands(i, b)
          case i.op
          # Inst::BINOPS and Inst::PAIRS, written out.
          when :iadd, :isub, :imul, :udiv, :sdiv, :urem, :srem, :band, :bor, :bxor, :ishl, :ushr, :sshr,
               :sadd_overflow, :ssub_overflow, :smul_overflow
            want = @typer.of(i.results[0])
            typed(i, b, i.args[0], want)
            Inst::SHIFTS.include?(i.op) ? integer(i, b, i.args[1]) : typed(i, b, i.args[1], want)
          when :icmp
            integer(i, b, i.args[0])
            typed(i, b, i.args[1], type_of(i.args[0]) || type_of(i.args[1]))
          # Inst::FBINOPS, written out.
          when :fcmp, :fadd, :fsub, :fmul, :fdiv then i.args.each { |a| typed(i, b, a, "f64") }
          # Inst::FUNOPS, written out.
          when :fneg, :fabs, :sqrt, :floor, :ceil, :trunc, :nearest, :fcvt_to_sint_sat then typed(i, b, i.args[0], "f64")
          when :fcvt_from_sint, :brif then integer(i, b, i.args[0])
          when :switch
            integer(i, b, i.args[0])
            keys = i.args.drop(1)
            rising = keys.all?(Integer) && keys.each_cons(2).all? { |x, y| x < y }
            raise Error, "#{@f.name}: #{b.name} switch keys are not rising Integers" unless rising
            raise Error, "#{@f.name}: #{b.name} switch has #{i.targets.size} targets for #{keys.size} keys" unless i.targets.size == keys.size + 1
          # Inst::BITOPS, written out.
          when :ctz, :clz, :popcnt, :bswap
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

        #: (Inst i, Block b, Array[untyped] args, Array[String] params) -> void
        def arguments(i, b, args, params)
          raise Error, "#{@f.name}: #{b.name} passes #{args.size} argument(s) to #{i.callee}, which takes #{params.size}" if args.size != params.size

          args.zip(params) { |a, want| typed(i, b, a, want) }
        end

        # `a` has type `want`, or is an immediate. `to` is the block that a
        # jump passes `a` to.
        #: (Inst i, Block b, untyped a, String? want, ?to: String?) -> void
        def typed(i, b, a, want, to: nil)
          got = type_of(a) or return
          return if want.nil? || got == want

          raise Error, "#{@f.name}: #{b.name} #{i.op} takes #{a} (#{got}) where #{want} is wanted" unless to
          raise Error, "#{@f.name}: #{b.name} passes #{a} (#{got}) to #{to}, whose parameter is #{want}"
        end

        #: (Inst i, Block b, untyped a) -> void
        def integer(i, b, a)
          got = type_of(a) or return
          raise Error, "#{@f.name}: #{b.name} #{i.op} takes #{a} (#{got}) where an integer is wanted" unless INTEGERS.include?(got)
        end

        # The width of `a` is more than the width of `type` (a reduce), or less
        # than the width of `to` (an extend).
        #: (Inst i, Block b, String? type, untyped a, ?to: String?) -> void
        def narrower(i, b, type, a, to: nil)
          got = type_of(a) or return
          from, into = to ? [got, to] : [type, got]
          ok = INTEGERS.index(from) && INTEGERS.index(into) && INTEGERS.index(from) < INTEGERS.index(into)
          raise Error, "#{@f.name}: #{b.name} #{i.op} takes #{a} (#{got}) to #{i.type}, which is not narrower" unless ok
        end

        # The type of a value operand, or nil for an immediate.
        #: (untyped a) -> String?
        def type_of(a) = IR.value?(a) ? @typer.of(a) : nil

        # Whether the definition of `v` reaches its use at instruction
        # `n` of block `b`: in the same block before it, or in a block
        # that dominates `b`.
        #: (String v, Block b, Integer n, Hash[String, String] defined_in, Hash[String, Integer] at) -> void
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
