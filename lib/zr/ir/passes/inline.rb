# frozen_string_literal: true

module Zr
  module IR
    module Passes
      # Inlines the small leaf functions of a unit at their call sites. A leaf
      # has no call, at most LIMIT instructions and at most SLOT_BYTES of
      # stack (for example a type or class test, or a frozen test, that the
      # kernel leaves as a call in a loop). The pass copies the callee into
      # the caller: the parameters become the arguments, the slots become
      # caller slots, and each `return` becomes a jump to the block after the
      # call, which takes the result as its parameter. The pass inlines the
      # calls in a callee first, so a callee can become a leaf (zr_class_of
      # after zr_fixnum_p). A cycle stays as calls. The original function
      # stays in the unit, because the unit exports it.
      class Inline
        # @rbs @by_name: Hash[String, Function]
        # @rbs @outputs: Array[Function]
        # @rbs @sources: Hash[String, Function]
        # @rbs @state: Hash[String, Symbol]
        # @rbs @calls: Hash[String, Hash[String, bool]]

        LIMIT = 24
        # Each call site gets a copy of the callee slots, so a callee with a
        # large buffer stays a call.
        SLOT_BYTES = 128

        #: (Array[Function] functions) -> Array[Function]
        def self.run(functions) = new(functions).run

        # `sources` are functions that can be inlined but that this pass
        # does not change, because a pass inlined them already: the kernel
        # under a core file (`Cache::Lowering::Core`).
        #: (Array[Function] functions, ?sources: Array[Function]) -> void
        def initialize(functions, sources: [])
          @by_name = functions.to_h { |f| [f.name, f] }
          @outputs = @by_name.values
          @sources = {}
          sources.each { |f| @by_name[f.name] ||= @sources[f.name] = f }
          @state = {}
          @calls = Hash.new { |h, name| h[name] = {} }
        end

        #: () -> Array[Function]
        def run
          @outputs.each { |f| inlinable?(f.name) }
          @outputs
        end

        # Whether the function `name` is a leaf that this pass inlines, once
        # it ran.
        #: (String name) -> bool
        def settled_leaf?(name) = @state[name] == :leaf

        # The colocated symbols that the calls of the function `name` named,
        # before this pass inlined any of them: a `Cache::Lowering::Core` entry depends on
        # what each of them is.
        #: (String name) -> Array[String]
        def calls(name) = @calls[name].keys

        private

        # Whether the function is a leaf that is small enough to inline, after
        # its own calls are inlined. The first question inlines them (not
        # those of a source, which are inlined already).
        #: (String name) -> bool
        def inlinable?(name)
          case @state[name]
          when :leaf then return true
          when :no, :busy then return false
          end
          @state[name] = :busy
          f = @by_name.fetch(name)
          inline_into(f) unless @sources.key?(name)
          @state[name] = leaf?(f) ? :leaf : :no
          @state[name] == :leaf
        end

        # No call, not too many instructions, and little stack in the slots that
        # are still read (a slot that Mem2Reg promoted does not count).
        #: (Function f) -> bool
        def leaf?(f)
          count = 0
          read = [] #: Array[String]
          f.blocks.each do |b|
            b.insts.each do |i|
              return false if %i[call call_indirect va_list].include?(i.op)

              read << i.args[0] if i.op == :stack_addr
              count += 1
            end
          end
          count <= LIMIT && read.uniq.sum { |slot| slot_of(f, slot).bytes } <= SLOT_BYTES
        end

        #: (Function f, String name) -> Slot
        def slot_of(f, name) = f.slots.fetch(name.delete_prefix("ss").to_i)

        # Expands each site in turn. The blocks before a site's block have no
        # site, and the copy of the callee comes after it, so the search for
        # the next site starts at that block.
        #: (Function f) -> void
        def inline_into(f)
          expanded = false
          from = 0
          while (site = site_in(f, from))
            from, b, k, call, target = site
            expand(f, b, k, call, target)
            expanded = true
          end
          f.changed!(:cfg) if expanded
        end

        # A call in `f`, from the block at `from` on, to a function that this
        # pass inlines: the index of its block, the block, the index of the
        # call, the call and the callee.
        #: (Function f, Integer from) -> [Integer, Block, Integer, Inst, Function]?
        def site_in(f, from)
          callees = {} #: Hash[String, Callee]
          f.callees.each { |c| callees[c.fn] ||= c }
          (from...f.blocks.size).each do |n|
            b = f.blocks[n]
            b.insts.each_with_index do |i, k|
              next unless i.op == :call

              c = callees[i.callee]
              next if c.nil? || c.from || !c.colocated

              @calls[f.name][c.symbol] = true

              target = @by_name[c.symbol]
              next if target.nil? || target.equal?(f) || !inlinable?(target.name)

              return [n, b, k, i, target]
            end
          end
          nil
        end

        # Replaces the call at `k` of `b` with a copy of `target`. `b` ends
        # with a jump to the copy of the entry. If no block of `target` jumps
        # back to its entry, the entry parameters become the arguments (so a
        # constant argument folds in the copy). If not, the jump passes them.
        # The instructions after the call move to a block after the copy. That
        # block takes the result of the call as its parameter.
        #: (Function f, Block b, Integer k, Inst call, Function target) -> void
        def expand(f, b, k, call, target)
          # The copies go between `b` and `rest`, all placed at the end.
          rest = f.unplaced_block
          rest.insts.concat(b.insts.drop(k + 1))
          b.insts.slice!(k..)
          # A call has a result only when its callee returns a value.
          results = call.results.zip([target.ret_type]) #: Array[[String, String]]
          rest.params.concat(results)
          names = {} #: Hash[String, String]
          target.globals.each { |g| names[g.gv] = f.symbol(g.symbol, colocated: g.colocated) }
          target.blocks.each do |cb|
            cb.insts.each { |i| names[i.args[0]] ||= f.slot(slot_of(target, i.args[0]).bytes) if i.op == :stack_addr }
          end
          target.callees.each do |c|
            sig = target.sigs.find { |s| s.sig == c.sig } #: Sig
            names[c.fn] = f.callee(c.symbol, sig.params, sig.ret, colocated: c.colocated, from: c.from, effects: c.effects)
          end
          entry = target.entry_block
          passed = target.blocks.none? { |cb| cb.insts.last.targets&.any? { |(blk, _)| blk == entry.name } }
          entry.params.zip(call.args) { |(v, _), arg| names[v] = arg } if passed
          copies = target.blocks.map do |cb|
            nb = f.unplaced_block
            names[cb.name] = nb.name
            cb.params.each { |(v, _)| names[v] = f.value } unless passed && cb.equal?(entry)
            cb.insts.each { |i| i.results.each { |r| names[r] = f.value } }
            [cb, nb]
          end #: Array[[Block, Block]]
          copies.each do |cb, nb|
            nb.params.concat(cb.params.map { |(v, t)| [names.fetch(v), t] }) unless passed && cb.equal?(entry)
            cb.insts.each { |i| nb.insts << copy(i, names, rest) }
          end
          f.place_after(b, [*copies.map(&:last), rest])
          b.insts << Inst.new(:jump, targets: [[names.fetch(entry.name), passed ? [] : call.args]])
        end

        #: (Inst i, Hash[String, String] names, Block rest) -> Inst
        def copy(i, names, rest)
          return Inst.new(:jump, targets: [[rest.name, i.args.map { |a| renamed(a, names) }]]) if i.op == :return

          Inst.new(i.op, type: i.type, args: i.args.map { |a| renamed(a, names) }, results: i.results.map { |r| names.fetch(r) },
                   cond: i.cond, offset: i.offset, callee: i.callee && names.fetch(i.callee, i.callee), flags: i.flags,
                   targets: i.targets&.map { |(blk, args)| [names.fetch(blk), args.map { |a| renamed(a, names) }] },
                   region: i.region)
        end

        #: (untyped a, Hash[String, String] names) -> untyped
        def renamed(a, names) = a.is_a?(String) ? names.fetch(a, a) : a
      end
    end
  end
end
