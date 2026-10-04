# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Binds the arguments to the parameters. A method binds from `argc`
      # and `argv` with CRuby's arity errors. A block binds leniently with
      # the block-argument rules. The task's keyword word tells how the
      # keywords arrive (lib/zr/runtime/kernel/send.rb, `zr_kw_pass`): a flagged
      # trailing Hash, or trailing values with a table of their keys. The
      # word is read and cleared here.
      module Params
        # @type instance: Function
        # @rbs @blk: String
        # @rbs @body: Hir::node?
        # @rbs @bound: Array[Symbol]?
        # @rbs @def: Hir::owner?
        # @rbs @direct: bool
        # @rbs @f: IR::Function
        # @rbs @has_env: bool
        # @rbs @kind: Function::kind
        # @rbs @l: Lower
        # @rbs @name: String
        # @rbs @qnil: String
        # @rbs @raw_block: Symbol?
        # @rbs @rec: String
        # @rbs @slot_of: Hash[Symbol, Integer]
        # @rbs @task: Machine::Layout
        # @rbs @task_addr: String
        # @rbs @twin_of: String?

        private

        #: () -> void
        def bind_params
          case @kind
          when :def then @direct ? bind_direct(own_params) : bind_method(own_params, @f.args[1], @f.args[2])
          when :block then bind_block(own_params)
          end
        end

        # The direct ABI: the arguments are in registers, as many as the
        # def declares. The site or zr_direct_fn has proved the count.
        #: (Hir::Params p) -> void
        def bind_direct(p)
          p.required.each_with_index { |name, i| bind(name, @f.args[4 + i]) }
          bind(p.block, block_param(@blk)) if p.block
        end

        #: (Hir::Params p, String argc, String argv) -> void
        def bind_method(p, argc, argv)
          # Both are set when `keywords?(p)`, and only then read:
          # @type var kwargs_at: Integer
          # @type var tab: String
          if keywords?(p)
            argc, kwargs_at, tab = take_keywords(argc, argv)
          else
            argc = drop_keywords(argc, argv, p.rest && p.rest != :implicit ? :def : nil)
          end
          # `**nil` refuses keywords before the count is checked, as
          # CRuby's setup_parameters_complex does.
          bind_keywords(p, kwargs_at, tab, argc, argv) if p.kwrest == :nokey
          check_arity(p, argc)
          bind_positional(p, argc, argv, strict: true)
          bind_keywords(p, kwargs_at, tab, argc, argv) if keywords?(p) && p.kwrest != :nokey
          bind(p.block, block_param(@blk)) if p.block
        end

        # A lambda checks its arity and never spreads. One function serves
        # both cases, so the Proc's flag decides at run time.
        #: (Hir::Params p) -> void
        def bind_block(p)
          # Both are set when `keywords?(p)`, and only then read:
          # @type var kwargs_at: Integer
          # @type var tab: String
          return strict_empty(p) if p.names.empty? && p.plain?

          argc = @f.args[1]
          argv = @f.args[2]
          keyworded = nil
          if keywords?(p)
            argc, kwargs_at, tab = take_keywords(argc, argv)
            # Keywords given to a block that takes them stop a lone Array
            # from spreading, as setup_parameters_complex allows no
            # autosplat with keywords.
            keyworded = @f.bor(@f.icmp("ne", tab, imm(0)), @f.icmp("ne", @f.fetch("i64", @rec, kwargs_at), @qnil))
          else
            # So do keywords given to any block but a simple one (only
            # leading required parameters), also an empty `**h`.
            unless p.simple? || !p.spread?
              keyworded = @f.icmp("ne", @f.fetch("i64", @task_addr, off(@task, "kw")), imm(0))
            end
            argc = drop_keywords(argc, argv, p.rest && p.rest != :implicit ? :block : nil)
          end
          # A table's values are after the positional arguments as given,
          # before any spread.
          count = argc
          given = argv
          bind_keywords(p, kwargs_at, tab, count, given) if p.kwrest == :nokey
          go = @f.label
          strict = @f.label
          @f.brif(lambda?, strict, go)
          switch(strict)
          check_arity(p, argc)
          @f.jump(go)
          switch(go)
          # A block that spreads (`|a, b|`) calls the kernel to spread one
          # Array argument. A block that does not (`|x|`) takes the
          # arguments as given, with no call.
          keep = p.spread? ? value_offset(reserve(1)) : nil
          if keep
            out = @f.stack_addr(@f.slot(8))
            spread = @f.csel(lambda?, imm(0), imm(p.optional.empty? ? 1 : 2))
            spread = @f.csel(keyworded, imm(0), spread) if keyworded
            argc = @f.sshr(checked(kernel("zr_block_args", argc, argv, spread, out, @f.iadd(@rec, imm(keep)))), imm(1))
            argv = @f.fetch("i64", out)
          end
          bind_positional(p, argc, argv, strict: false, keep: keep)
          bind_keywords(p, kwargs_at, tab, count, given) if keywords?(p) && p.kwrest != :nokey
          bind(p.block, block_param(call_block)) if p.block
        end

        # The value of a `&b` parameter. If the scope only calls, passes
        # or tests it (`Hir::Escape`), it is the block as given (a Proc
        # that can still be on the caller's stack). Else it is a heap cell,
        # because the scope keeps it.
        #: (String blk) -> String
        def block_param(blk)
          @raw_block ? blk : kernel("zr_block_proc", blk)
        end

        # A `&b` parameter stays a stack block if every use in the body and
        # the parameter defaults permits it (`Hir::Escape`), nothing opens
        # the scope's locals (a Binding or an eval reads the Proc), and no
        # hook can get a Binding of the frame.
        #: (Hir::Params p) -> bool
        def raw_block?(p)
          name = p.block or return false

          !@l.traced? && !Hir::Locals.opens_locals?(@body, computed: !@l.internal?) && Hir::Escape.raw_block?([@body, *default_expressions], name)
        end

        # A block with no parameters accepts any arguments. A lambda
        # (including a `define_method` body) accepts none.
        #: (Hir::Params p) -> void
        def strict_empty(p)
          go = @f.label
          strict = @f.label
          @f.brif(lambda?, strict, go)
          switch(strict)
          check_arity(p, @f.args[1])
          @f.jump(go)
          switch(go)
        end

        #: (Hir::Params p) -> bool
        def keywords?(p)
          p.keywords.any? || !p.kwrest.nil?
        end

        #: (Symbol name) -> Integer
        def slot_of(name)
          @slot_of.fetch(name)
        end

        # Removes the call's keywords from the positional arguments. A
        # flagged Hash goes into a record slot (nil if none). A table's
        # values stay in place, and the table is the third return value
        # (0 for a Hash), so `bind_keywords` reads them by column. The
        # task's keyword word is cleared, so it cannot leak to a later send.
        #: (String argc, String argv) -> [String, Integer, String]
        def take_keywords(argc, argv)
          at = value_offset(reserve(1))
          kw = take_keyword_word
          table = @f.label
          hashed = @f.label
          have = @f.label
          none = @f.label
          merge, (count, hash, tab) = @f.block(%w[i64 i64 i64]) #: [String, [String, String, String]]
          @f.brif(@f.icmp("ugt", kw, imm(1)), table, hashed)
          switch(table)
          @f.jump(merge, [@f.isub(argc, @f.fetch("i64", kw)), @qnil, kw])
          switch(hashed)
          @f.brif(@f.band(@f.icmp("ne", kw, imm(0)), @f.icmp("sgt", argc, imm(0))), have, none)
          switch(have)
          last = @f.isub(argc, imm(1))
          @f.jump(merge, [last, @f.fetch("i64", @f.iadd(argv, @f.ishl(last, imm(3)))), imm(0)])
          switch(none)
          @f.jump(merge, [argc, @qnil, imm(0)])
          switch(merge)
          @f.store(hash, @rec, at)
          [count, at, tab]
        end

        # A def or block that declares no keywords clears the task's word.
        # First, a table's values become one Hash argument, and a
        # ruby2_keywords rest (a def's or a block's function, `abi`) flags
        # that Hash. Returns the new argument count.
        #: (String argc, String argv, Symbol? abi) -> String
        def drop_keywords(argc, argv, abi)
          kw = @f.fetch("i64", @task_addr, off(@task, "kw"))
          fn = abi ? @f.func_addr(@f.callee(@twin_of || @name, ABI.fetch(abi), "i64")) : imm(0)
          quick = @f.label
          slow = @f.label
          merge, (count,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("eq", kw, imm(0)), quick, slow)
          switch(quick)
          @f.jump(merge, [argc])
          switch(slow)
          # Clear the word here, not at entry. It is already zero at almost
          # every call, and a store of zero at entry costs every call.
          @f.store(imm(0), @task_addr, off(@task, "kw"), region: :task)
          # The allocation of the table's Hash comes before the arity check
          # fills the argument slots, so set those slots to nil first.
          direct_params.each { |name| write_local(slot_of(name), 0, @qnil) }
          @f.jump(merge, [kernel("zr_kw_undeclared", kw, argc, argv, fn)])
          switch(merge)
          count
        end

        #: () -> String
        def take_keyword_word
          kw = @f.fetch("i64", @task_addr, off(@task, "kw"))
          @f.store(imm(0), @task_addr, off(@task, "kw"), region: :task)
          kw
        end

        # CRuby's messages: an exact count, `min+` with a rest, `min..max`
        # with optionals, then the names of missing required keywords.
        #: (Hir::Params p, String argc) -> void
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
            # The argument slots are not set yet, and the raise below can
            # start a collection.
            direct_params.each { |name| write_local(slot_of(name), 0, @qnil) }
            ids, n = required.empty? ? [imm(0), imm(0)] : keyword_ids(required)
            kernel("zr_wrong_arity_kw", argc, imm(req), imm(max), ids, n)
          end
        end

        # The parameters whose slots get their arguments with no nil first:
        # a method's plain required parameters, when nothing between the
        # record's link and their stores can start a collection. Keywords
        # go into a Hash before the arity check, and a ruby2_keywords rest
        # is flagged, so those methods set every slot to nil first.
        #: () -> Array[Symbol]
        def direct_params
          return [] unless @kind == :def && !@has_env

          p = own_params
          return [] if keywords?(p) || (p.rest && p.rest != :implicit)

          p.required.filter_map { |name| name if name.is_a?(Symbol) && p.required.count(name) == 1 }
        end

        # If `cond` is false, the block raises, and its return value leaves
        # the function.
        #: (String cond) { () -> String } -> void
        def fail_unless(cond)
          go = @f.label
          bad = @f.label
          @f.brif(cond, go, bad)
          switch(bad)
          leave(yield, opened: false)
          switch(go)
        end

        # Required, optional, rest and post parameters in order. A block
        # (`strict` false) gets nil for missing arguments and discards
        # extras. If there are too few arguments, its post parameters get
        # what remains after the required ones. A block's spread Array stays
        # in the record slot at `keep`. A destructured parameter runs Ruby
        # that can change it, so the arguments are read again after each.
        #: (Hir::Params p, String argc, String argv, strict: bool, ?keep: Integer?) -> void
        def bind_positional(p, argc, argv, strict:, keep: nil)
          req = p.required.size + p.post.size
          argc = @f.csel(@f.icmp("sgt", argc, imm(req + p.optional.size)), imm(req + p.optional.size), argc) if !strict && !p.rest
          p.required.each_with_index do |name, i|
            v = strict ? arg_at(argv, imm(i)) : arg_or_nil(argc, argv, imm(i))
            bind(name, v)
            argc, argv = spread_again(keep, argc, argv) if keep && name.is_a?(Hir::MultiTarget)
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
            argc, argv = spread_again(keep, argc, argv) if keep && name.is_a?(Hir::MultiTarget)
          end
        end

        #: (Integer keep, String argc, String argv) -> [String, String]
        def spread_again(keep, argc, argv)
          kept = @f.fetch("i64", @rec, keep)
          [kernel("zr_block_argc", kept, argc), kernel("zr_block_argv", kept, argv)]
        end

        # Whether `name` is already bound in this parameter list. Only `_`
        # can repeat. Ruby refuses all other duplicate names.
        #: (Hir::param name) -> bool
        def repeated?(name)
          !name.is_a?(Hir::MultiTarget) && bound_names.include?(name)
        end

        # The parameter names bound so far.
        #: () -> Array[Symbol]
        def bound_names
          @bound ||= [] #: Array[Symbol]
        end

        # Ruby compiles an optional parameter's default as an assignment to
        # the NAME, so a repeated `_`'s default writes the first `_`'s
        # local. A given argument writes only a slot that nothing reads.
        #: (String present) { () -> void } -> void
        def default_only(present)
          miss = @f.label
          done = @f.label
          @f.brif(present, done, miss)
          switch(miss)
          yield
          @f.jump(done)
          switch(done)
        end

        # Binds `v` to the parameter `name`, or destructures it into a
        # `(a, b)` target. A repeated name (`_`, `_x`) keeps its first binding.
        #: (Hir::param name, String v) -> void
        def bind(name, v)
          if name.is_a?(Hir::MultiTarget)
            whole = name.whole
            write_local(slot_of(whole), 0, v) if whole
            destructure(name, v, {})
          elsif bound_names.include?(name)
            v
          else
            bound_names << name
            write_local(slot_of(name), 0, v)
          end
        end

        #: (String argv, String index) -> String
        def arg_at(argv, index)
          @f.fetch("i64", @f.iadd(argv, @f.ishl(index, imm(3))))
        end

        #: (String argc, String argv, String index) -> String
        def arg_or_nil(argc, argv, index)
          arg_or_default(argv, index, @f.icmp("slt", index, argc)) { @qnil }
        end

        # `argv[index]` when `present`, else the block's value.
        #: (String argv, String index, String present) { () -> String } -> String
        def arg_or_default(argv, index, present)
          have = @f.label
          miss = @f.label
          merge, (v,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(present, have, miss)
          switch(have)
          @f.jump(merge, [arg_at(argv, index)])
          switch(miss)
          @f.jump(merge, [yield])
          switch(merge)
          v
        end

        # Checks required keywords first, then unknown keywords unless a
        # `**rest` takes them. For a Hash, the kernel probes it. For a
        # table, the check runs once per table and fills the def's shape
        # cell with each declared keyword's column. Then each keyword
        # binds, with defaults in order: from a Hash by a probe, from a
        # table by its column in the values after the `count` positional
        # arguments of `argv`.
        #: (Hir::Params p, Integer kwargs_at, String tab, String count, String argv) -> void
        def bind_keywords(p, kwargs_at, tab, count, argv)
          hash = -> { @f.fetch("i64", @rec, kwargs_at) }
          required = p.keywords.select { |_, default| default.nil? }.map(&:first)
          declared = p.keywords.map(&:first)
          ids, n = keyword_ids(declared)
          shape = @f.symbol_value(@f.symbol(@l.cache_cell("kw", 8 * (1 + declared.size))))
          by_table(tab) do |from_table|
            if from_table
              mode = { nokey: 2 }.fetch(p.kwrest, p.kwrest ? 1 : 0)
              req_ids, nreq = required.empty? ? [imm(0), imm(0)] : keyword_ids(required)
              checked(kernel("zr_kw_shape", shape, tab, ids, n, req_ids, nreq, imm(mode)))
            else
              unless required.empty?
                given = hash.call
                req_ids, nreq = keyword_ids(required)
                checked(kernel("zr_kw_missing", given, req_ids, nreq))
              end
              checked(kernel("zr_kw_none", hash.call)) if p.kwrest == :nokey
              checked(kernel("zr_kw_unknown", hash.call, ids, n)) if p.kwrest.nil?
            end
            @qnil
          end
          return if p.kwrest == :nokey

          p.keywords.each_with_index do |(name, default), k|
            v = by_table(tab) do |from_table|
              next kernel("zr_kw_get", hash.call, sym_word(name)) unless from_table

              column = @f.fetch("i64", shape, 8 * (1 + k))
              absent = @f.label
              present = @f.label
              merge, (found,) = @f.block(["i64"]) #: [String, [String]]
              @f.brif(@f.icmp("slt", column, imm(0)), absent, present)
              switch(absent)
              @f.jump(merge, [qundef])
              switch(present)
              @f.jump(merge, [arg_at(argv, @f.iadd(count, column))])
              switch(merge)
              found
            end
            if default
              have = @f.label
              miss = @f.label
              merge, (bound,) = @f.block(["i64"]) #: [String, [String]]
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
          return unless p.kwrest

          rest = by_table(tab) do |from_table|
            if from_table
              checked(kernel("zr_kw_rest_tab", tab, @f.iadd(argv, @f.ishl(count, imm(3))), ids, n))
            else
              checked(kernel("zr_kw_rest", hash.call, ids, n))
            end
          end
          bind(p.kwrest, rest)
        end

        # The block's value for a table (`tab` not 0) or for a Hash, as the
        # call passed them, merged into one value.
        #: (String tab) { (bool) -> String } -> String
        def by_table(tab)
          table = @f.label
          hashed = @f.label
          merge, (v,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("ne", tab, imm(0)), table, hashed)
          switch(table)
          @f.jump(merge, [yield(true)])
          switch(hashed)
          @f.jump(merge, [yield(false)])
          switch(merge)
          v
        end

        # The ids of `names` as a read-only table, and its length.
        #: (Array[Symbol] names) -> [String, String]
        def keyword_ids(names)
          table = @l.keyword_table(names)
          [@f.symbol_value(@f.symbol(table)), imm(names.size)]
        end
      end
    end
  end
end
