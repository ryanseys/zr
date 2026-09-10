# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # Binding the arguments to the parameters: a method's from `argc`
      # and `argv` with CRuby's arity errors, a block's leniently through
      # the block-argument rules. Keywords arrive as a trailing Hash the
      # task flags; the flag is taken here.
      module Params
        private

        def bind_params
          case @kind
          when :def then bind_method(@def.params, @f.args[1], @f.args[2])
          when :block then bind_block(@def.params)
          end
        end

        def bind_method(p, argc, argv)
          if keywords?(p)
            argc, kwargs_at = take_keywords(argc, argv)
          elsif p.rest && p.rest != :implicit
            # A ruby2_keywords method flags the keywords Hash it takes
            # into its rest.
            kernel("zr_kw_ruby2_in", argc, argv, @f.func_addr(@f.callee(@name, ABI.fetch(:def), "i64")))
          else
            @f.store(imm(0), @task_addr, off(@task, "kw"))
          end
          check_arity(p, argc)
          bind_positional(p, argc, argv, strict: true)
          bind_keywords(p, kwargs_at) if keywords?(p)
          bind(p.block, @blk) if p.block
        end

        # A lambda checks its arity and never spreads; the same function
        # serves either way, so the Proc's flag decides at run time.
        def bind_block(p)
          return if p.names.empty? && p.plain?

          argc = @f.args[1]
          argv = @f.args[2]
          if keywords?(p)
            argc, kwargs_at = take_keywords(argc, argv)
          elsif p.rest && p.rest != :implicit
            kernel("zr_kw_ruby2_in", argc, argv, @f.func_addr(@f.callee(@name, ABI.fetch(:block), "i64")))
          else
            @f.store(imm(0), @task_addr, off(@task, "kw"))
          end
          go = @f.label
          strict = @f.label
          @f.brif(lambda?, strict, go)
          switch(strict)
          check_arity(p, argc)
          @f.jump(go)
          switch(go)
          out = @f.stack_addr(@f.slot(8))
          spread = p.spread? ? @f.csel(lambda?, imm(0), imm(1)) : imm(0)
          argc = @f.sshr(checked(kernel("zr_block_args", argc, argv, spread, out)), imm(1))
          argv = @f.fetch("i64", out)
          bind_positional(p, argc, argv, strict: false)
          bind_keywords(p, kwargs_at) if keywords?(p)
          bind(p.block, @f.args[3]) if p.block
        end

        def keywords?(p)
          p.keywords.any? || !p.kwrest.nil?
        end

        def slot_of(name)
          @slot_of.fetch(name)
        end

        # The keywords Hash, when the call flagged one, leaves the
        # positional arguments; it waits in a record slot. A method that
        # declares none clears the flag, so it cannot leak to a later send.
        def take_keywords(argc, argv)
          at = value_offset(reserve(1))
          have = @f.label
          none = @f.label
          merge, (count, hash) = @f.block(%w[i64 i64])
          flagged = @f.icmp("ne", kernel("zr_kw_take"), imm(0))
          @f.brif(@f.band(flagged, @f.icmp("sgt", argc, imm(0))), have, none)
          switch(have)
          last = @f.isub(argc, imm(1))
          @f.jump(merge, [last, @f.fetch("i64", @f.iadd(argv, @f.ishl(last, imm(3))))])
          switch(none)
          @f.jump(merge, [argc, @qnil])
          switch(merge)
          @f.store(hash, @rec, at)
          [count, at]
        end

        # CRuby's messages: an exact count, `min+` with a rest, `min..max`
        # with optionals, and the required keywords named after.
        def check_arity(p, argc)
          req = p.required.size + p.post.size
          rest = p.rest && p.rest != :implicit
          max = rest ? -1 : req + p.optional.size
          ok = if rest
                 @f.icmp("sge", argc, imm(req))
               elsif p.optional.empty?
                 @f.icmp("eq", argc, imm(req))
               else
                 @f.band(@f.icmp("sge", argc, imm(req)), @f.icmp("sle", argc, imm(max)))
               end
          required = p.keywords.select { |_, default| default.nil? }.map(&:first)
          fail_unless(ok) do
            ids, n = required.empty? ? [imm(0), imm(0)] : keyword_ids(required)
            kernel("zr_wrong_arity_kw", argc, imm(req), imm(max), ids, n)
          end
        end

        # The block raises; its answer leaves the function.
        def fail_unless(cond)
          go = @f.label
          bad = @f.label
          @f.brif(cond, go, bad)
          switch(bad)
          leave(yield)
          switch(go)
        end

        # Required, optional, rest and post parameters in order. A block
        # (`strict` false) takes nil for what is missing and drops extras;
        # its post parameters take what is left after the required ones
        # when the count falls short.
        def bind_positional(p, argc, argv, strict:)
          req = p.required.size + p.post.size
          argc = @f.csel(@f.icmp("sgt", argc, imm(req + p.optional.size)), imm(req + p.optional.size), argc) if !strict && !p.rest
          p.required.each_with_index do |name, i|
            v = strict ? arg_at(argv, imm(i)) : arg_or_nil(argc, argv, imm(i))
            bind(name, v)
          end
          avail = @f.isub(argc, imm(req))
          avail = @f.csel(@f.icmp("slt", avail, imm(0)), imm(0), avail) unless strict
          p.optional.each_with_index do |(name, default), j|
            present = @f.icmp("slt", imm(j), avail)
            if repeated?(name)
              default_only(present) { write_local(slot_of(name), 0, expr(default)) }
            else
              bind(name, arg_or_default(argv, imm(p.required.size + j), present) { expr(default) })
            end
          end
          given_opt = @f.csel(@f.icmp("slt", avail, imm(p.optional.size)), avail, imm(p.optional.size))
          if p.rest && p.rest != :implicit
            start = @f.iadd(imm(p.required.size), given_opt)
            count = @f.isub(avail, given_opt)
            bind(p.rest, kernel("zr_ary_of", count, @f.iadd(argv, @f.ishl(start, imm(3)))))
          end
          p.post.each_with_index do |name, i|
            index = @f.iadd(@f.isub(argc, imm(p.post.size)), imm(i))
            if strict
              bind(name, arg_at(argv, index))
            else
              short = @f.icmp("slt", argc, imm(req))
              index = @f.csel(short, imm(p.required.size + i), index)
              bind(name, arg_or_nil(argc, argv, index))
            end
          end
        end

        # Whether `name` already took a binding in this parameter list.
        # Only `_` may repeat; ruby refuses every other duplicate name.
        def repeated?(name)
          !name.is_a?(Hir::MultiTarget) && (@bound ||= []).include?(name)
        end

        # Ruby compiles an optional parameter's default as an assignment to
        # the NAME, so a repeated `_`'s default writes the local the first
        # `_` owns. A given argument writes only the slot nothing reads.
        def default_only(present)
          miss = @f.label
          done = @f.label
          @f.brif(present, done, miss)
          switch(miss)
          yield
          @f.jump(done)
          switch(done)
        end

        # `v` into the parameter `name`, or apart into a `(a, b)` target.
        # A name that repeats (`_`, `_x`) keeps its first binding.
        def bind(name, v)
          if name.is_a?(Hir::MultiTarget)
            write_local(slot_of(name.whole), 0, v) if name.whole
            destructure(name, v, {})
          elsif (@bound ||= []).include?(name)
            v
          else
            @bound << name
            write_local(slot_of(name), 0, v)
          end
        end

        def arg_at(argv, index)
          @f.fetch("i64", @f.iadd(argv, @f.ishl(index, imm(3))))
        end

        def arg_or_nil(argc, argv, index)
          arg_or_default(argv, index, @f.icmp("slt", index, argc)) { @qnil }
        end

        # `argv[index]` when `present`, else the block's value.
        def arg_or_default(argv, index, present)
          have = @f.label
          miss = @f.label
          merge, (v,) = @f.block(["i64"])
          @f.brif(present, have, miss)
          switch(have)
          @f.jump(merge, [arg_at(argv, index)])
          switch(miss)
          @f.jump(merge, [yield])
          switch(merge)
          v
        end

        # Required keywords are checked first, then unknown ones unless a
        # `**rest` takes them; then each keyword binds, defaults in order.
        def bind_keywords(p, kwargs_at)
          hash = -> { kwargs_at ? @f.fetch("i64", @rec, kwargs_at) : @qnil }
          required = p.keywords.select { |_, default| default.nil? }.map(&:first)
          declared = p.keywords.map(&:first)
          unless required.empty?
            ids, n = keyword_ids(required)
            checked(kernel("zr_kw_missing", hash.call, ids, n))
          end
          ids, n = keyword_ids(declared)
          if p.kwrest == :nokey
            checked(kernel("zr_kw_none", hash.call))
            return
          end
          checked(kernel("zr_kw_unknown", hash.call, ids, n)) unless p.kwrest
          p.keywords.each do |name, default|
            v = kernel("zr_kw_get", hash.call, imm(sym_id(name)))
            if default
              have = @f.label
              miss = @f.label
              merge, (bound,) = @f.block(["i64"])
              @f.brif(@f.icmp("eq", v, qundef), miss, have)
              switch(have)
              @f.jump(merge, [v])
              switch(miss)
              @f.jump(merge, [expr(default)])
              switch(merge)
              v = bound
            end
            bind(name, v)
          end
          bind(p.kwrest, kernel("zr_kw_rest", hash.call, ids, n)) if p.kwrest
        end

        # The ids of `names` as a read-only table, and its length.
        def keyword_ids(names)
          table = @l.keyword_table(names.map { |name| sym_id(name) })
          [@f.symbol_value(@f.symbol(table)), imm(names.size)]
        end
      end
    end
  end
end
