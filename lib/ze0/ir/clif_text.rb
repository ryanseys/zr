# frozen_string_literal: true

module Ze0
  module IR
    # The CLIF text of a function: what `clif2obj` reads, and what the
    # goldens hold byte for byte.
    module ClifText
      module_function

      def render(f)
        out = +"function %#{f.name}(#{f.params.join(", ")})"
        out << " -> #{f.ret_type}" if f.ret_type
        out << " system_v {\n"
        f.slots.each_with_index { |s, i| out << "    ss#{i} = explicit_slot #{s.bytes}, align = #{s.align}\n" }
        f.globals.each { |g| out << "    #{g.gv} = symbol #{g.colocated ? "colocated " : ""}%#{g.symbol}\n" }
        f.sigs.each { |s| out << "    #{s.sig} = #{signature(s)} system_v\n" }
        f.callees.each { |c| out << "    #{c.fn} = #{c.colocated ? "colocated " : ""}%#{c.symbol} #{c.sig}\n" }
        f.blocks.each do |b|
          out << "\n#{b.name}"
          out << "(#{b.params.map { |v, t| "#{v}: #{t}" }.join(", ")})" unless b.params.empty?
          out << ":\n"
          b.insts.each { |i| out << "    #{inst(i)}\n" }
        end
        out << "}\n"
      end

      def signature(s)
        text = "(#{s.params.join(", ")})"
        text += " -> #{s.ret}" if s.ret
        text
      end

      def inst(i)
        head = i.type ? "#{i.op}.#{i.type}" : i.op.to_s
        lhs = i.results.empty? ? "" : "#{i.results.join(", ")} = "
        body =
          case i.op
          when :call then "#{head} #{i.callee}(#{i.args.join(", ")})"
          when :call_indirect then "#{head} #{i.callee}, #{i.args[0]}(#{i.args[1..].join(", ")})"
          when :jump then "#{head} #{target(i.targets[0])}"
          when :brif then "#{head} #{i.args[0]}, #{target(i.targets[0])}, #{target(i.targets[1])}"
          when :return then i.args.empty? ? head : "#{head} #{i.args[0]}"
          when :store then "#{head} #{flags(i)}#{i.args[0]}, #{i.args[1]}#{offset(i)}"
          when :load then "#{head} #{flags(i)}#{i.args[0]}#{offset(i)}"
          when :icmp then "#{head} #{i.cond} #{i.args.join(", ")}"
          else "#{head} #{i.args.join(", ")}"
          end
        lhs + body
      end

      def target((name, args))
        args.empty? ? name : "#{name}(#{args.join(", ")})"
      end

      def flags(i)
        i.flags.to_s.empty? ? "" : "#{i.flags} "
      end

      def offset(i)
        i.offset.zero? ? "" : "+#{i.offset}"
      end
    end
  end
end

module Ze0
  module IR
    module ClifText
      # The functions in `text`, the reverse of `render`: what a
      # hand-written `.clif` or a golden holds, as IR.
      def self.parse(text)
        functions = []
        f = nil
        block = nil
        text.each_line do |raw|
          line = raw.strip
          next if line.empty? || line.start_with?(";")

          if (m = line.match(/\Afunction %(\S+)\((.*?)\)(?: -> (\S+))? system_v \{\z/))
            f = Function.bare(m[1], m[2].empty? ? [] : m[2].split(", "), m[3])
            block = nil
          elsif line == "}"
            functions << f
            f = nil
          elsif (m = line.match(/\Ass(\d+) = explicit_slot (\d+), align = (\d+)\z/))
            f.slots << Slot.new(Integer(m[2]), Integer(m[3]))
          elsif (m = line.match(/\A(gv\d+) = symbol (colocated )?%(\S+)\z/))
            f.globals << Global.new(m[1], m[3], !m[2].nil?)
          elsif (m = line.match(/\A(sig\d+) = \((.*?)\)(?: -> (\S+))? system_v\z/))
            f.sigs << Sig.new(m[1], m[2].empty? ? [] : m[2].split(", "), m[3])
          elsif (m = line.match(/\A(fn\d+) = (colocated )?%(\S+) (sig\d+)\z/))
            f.callees << Callee.new(m[1], m[3], m[4], !m[2].nil?)
          elsif (m = line.match(/\A(block\d+)(?:\((.*)\))?:\z/))
            params = (m[2] || "").split(", ").map { |p| p.split(": ") }
            block = f.add_block(m[1], params)
          else
            block.insts << Inst.parse(line)
          end
        end
        functions
      end
    end
  end
end
