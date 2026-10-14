# frozen_string_literal: true

module Zr
  module IR
    module Passes
      # Dead code elimination. The pass removes an instruction with no
      # effect whose result nothing reads. It continues to a fixpoint, so it
      # removes a full chain in one run. A call, a store and a terminator
      # always stay.
      class DCE
        PURE = (%i[iconst stack_addr symbol_value func_addr gates icmp fcmp select ireduce uextend sextend bitcast load
                   fcvt_from_sint fcvt_to_sint_sat] +
                Inst::BINOPS + Inst::BITOPS + Inst::FBINOPS + Inst::FUNOPS + Inst::PAIRS).to_set.freeze

        # Counts the readers of each value one time. When the pass removes an
        # instruction, it subtracts one reader from each operand. An operand
        # with zero readers is then dead.
        #: (Function f) -> Function
        def self.run(f)
          readers = f.analysis.uses.dup
          readers.default = 0
          defined = {} #: Hash[String, Inst]
          f.blocks.each { |b| b.insts.each { |i| i.results.each { |r| defined[r] = i } } }
          dead = {} #: Hash[Inst, bool]
                 .compare_by_identity
          work = f.blocks.flat_map { |b| b.insts.select { |i| unread?(i, readers) } }
          while (i = work.pop)
            next if dead.key?(i)

            dead[i] = true
            i.args.each do |a|
              next unless IR.value?(a)

              readers[a] -= 1
              d = defined[a]
              work << d if d && readers[a].zero? && unread?(d, readers)
            end
          end
          return f if dead.empty?

          f.blocks.each { |b| b.insts.reject! { |i| dead.key?(i) } }
          f.changed!(:insts)
        end

        #: (Inst i, Hash[String, Integer] readers) -> bool
        def self.unread?(i, readers) = PURE.include?(i.op) && i.results.none? { |r| readers[r].positive? }
      end
    end
  end
end
