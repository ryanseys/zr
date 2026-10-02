# frozen_string_literal: true

# `Sends` that run a core method in place at a cell hit, with no
# call: readers and writers, struct members, `is_a?`, `frozen?`
# and `Module#===`.

module Zr
  class Lower
    class Function
      module Sends
        private

        # The global of a literal receiver's class, or nil. A Symbol, nil,
        # true and false have no singleton class.
        def literal_class(recv)
          return nil unless recv.is_a?(Hir::Literal)

          case recv.value
          when Symbol then "G_SYMBOL"
          when nil then "G_NIL"
          when true then "G_TRUE"
          when false then "G_FALSE"
          end
        end

        # Whether a site can use a def's direct entry: only positional
        # arguments, four at most, so the site proves the count.
        def direct_site?(node)
          node.args.size <= DIRECT_ARGS && node.kwargs.nil? && node.args.none?(Hir::Splat)
        end

        # The shapes that a site can have, in test order. The site's form
        # permits them. At run time, the cell tells whether its entry has
        # the shape (lib/zr/runtime/kernel/cache.rb, `zr_entry_shape`). Each shape
        # needs a call with no block, no keywords and no splat, and the
        # exact argument count of the body (none for a reader or a check,
        # one for a writer, `is_a?` or `instance_of?`), because only the
        # call can raise for a wrong count. A type check is selected by
        # name, so only a site with that name pays for its test. `size`
        # and `length` can be Array's or a reader's, so they test both. A
        # traced program keeps the call, as `opt_send` does.
        def site_shapes(node)
          return [] if node.block || node.kwargs || node.args.any?(Hir::Splat) || traced?
          # In an `initialize`, no check or accessor is worth a test.
          return [] if node.name == :initialize

          case node.args.size
          when 0 then QUESTIONS.fetch(node.name) { [:reader] }
          when 1 then ARGUED.fetch(node.name) { node.name.end_with?("=") ? [:writer] : [] }
          else []
          end
        end

        # What a site does if the cell's shape is `shape`. A failed accessor
        # guard goes to `miss`, the kernel's send (which sets the guess). A
        # check that the fast path cannot decide goes to `call`, the cell's
        # own function, which the cell already found to be valid.
        def in_place(shape, site, klass, call, miss, held)
          recv = site.recv
          merge = site.merge
          case shape
          when :reader, :writer then accessor_in_place(shape, site, miss, held)
          when :nil_p then @f.jump(merge, [ruby_bool(@f.icmp("eq", recv, @qnil))])
          when :frozen_p then frozen_in_place(recv, merge)
          when :ary_length then @f.jump(merge, [@f.bor(@f.ishl(array_len(recv), imm(1)), imm(1))])
          when :is_a then answered(kernel("zr_is_a_fast", klass, @f.fetch("i64", site.argv, 0)), merge, call)
          when :instance_of then answered(kernel("zr_instance_of_fast", klass, @f.fetch("i64", site.argv, 0)), merge, call)
          when :mod_eqq then mod_eqq_in_place(recv, @f.fetch("i64", site.argv, 0), merge, call)
          when :eq, :eqq then @f.jump(merge, [ruby_bool(@f.icmp("eq", recv, @f.fetch("i64", site.argv, 0)))])
          when :ne then @f.jump(merge, [ruby_bool(@f.icmp("ne", recv, @f.fetch("i64", site.argv, 0)))])
          end
        end

        # `Mod === obj` if the cell has Module#===. For a ranked class
        # receiver, decide inline from the classes. For a module or a class
        # not ranked yet, call the kernel. If that does not decide, go to
        # `call`.
        def mod_eqq_in_place(recv, obj, merge, call)
          classed = @f.label
          asked = @f.label
          @f.brif(ranked?(recv), classed, asked)
          switch(classed)
          is_a_in_place(class_of(obj), recv, merge, call)
          switch(asked)
          answered(kernel("zr_mod_eqq_fast", recv, obj), merge, call)
        end

        # Whether the class `klass` is ranked (FL_RANKED): under Object,
        # with its rank table built, and in no box.
        def ranked?(klass)
          @f.icmp("ne", @f.band(@f.fetch("i64", klass, off(@l.layout("RBasic"), "flags")), imm(@l.const("FL_RANKED"))), imm(0))
        end

        # The class of any value: a cell's from its header, the rest from
        # the kernel.
        def class_of(v)
          cell = @f.label
          special = @f.label
          have, (klass,) = @f.block(["i64"])
          @f.brif(@f.band(@f.icmp("eq", @f.band(v, imm(7)), imm(0)), @f.icmp("ugt", v, @qnil)), cell, special)
          switch(cell)
          @f.jump(have, [@f.fetch("i64", v, off(@l.layout("RBasic"), "klass"))])
          switch(special)
          @f.jump(have, [kernel("zr_class_of", v)])
          switch(have)
          klass
        end

        # `klass.is_a?(mod)` inline, as `zr_is_a_fast` does. If `mod` is
        # also a ranked class, `mod`'s rank gives the only position in
        # `klass`'s table where it can be. All other cases (a module, a
        # class with no table yet, a box's view) go to `open`, the path
        # that calls the kernel, which builds the tables.
        def is_a_in_place(klass, mod, merge, open)
          ext_of = @l.layout("RClass")
          ext = @l.layout("ClassExt")
          cell = @f.label
          ranked = @f.label
          within = @f.label
          above = @f.label
          cellp = @f.band(@f.icmp("eq", @f.band(mod, imm(7)), imm(0)), @f.icmp("ugt", mod, @qnil))
          @f.brif(cellp, cell, open)
          switch(cell)
          @f.brif(@f.band(ranked?(mod), ranked?(klass)), ranked, open)
          switch(ranked)
          r = @f.fetch("i64", @f.fetch("i64", mod, off(ext_of, "ext")), off(ext, "rank"))
          mine = @f.fetch("i64", klass, off(ext_of, "ext"))
          @f.brif(@f.icmp("ule", r, @f.fetch("i64", mine, off(ext, "rank"))), within, above)
          switch(within)
          at = @f.iadd(@f.fetch("i64", mine, off(ext, "supers")), @f.ishl(@f.isub(r, imm(1)), imm(3)))
          @f.jump(merge, [ruby_bool(@f.icmp("eq", @f.fetch("i64", at, 0), mod))])
          switch(above)
          @f.jump(merge, [imm(@l.const("QFALSE"))])
        end

        # `frozen?` as `zr_frozen_p` reads it: every special constant is
        # frozen, and a cell has a flag. This is inline and not a call,
        # because the kernel returns a Bool, which is an i32 in wasm, but
        # every Value is an i64.
        def frozen_in_place(recv, merge)
          cell = @f.label
          special = @f.label
          @f.brif(@f.band(@f.icmp("eq", @f.band(recv, imm(7)), imm(0)), @f.icmp("ugt", recv, @qnil)), cell, special)
          switch(special)
          @f.jump(merge, [imm(@l.const("QTRUE"))])
          switch(cell)
          flags = @f.fetch("i64", recv, off(@l.layout("RBasic"), "flags"))
          @f.jump(merge, [ruby_bool(@f.icmp("ne", @f.band(flags, imm(@l.const("FL_FREEZE"))), imm(0)))])
        end

        # A fast result, or nil if the call must decide.
        def answered(v, merge, call)
          settled = @f.label
          @f.brif(@f.icmp("eq", v, @qnil), call, settled)
          switch(settled)
          @f.jump(merge, [v])
        end

        def ruby_bool(cond) = @f.csel(cond, imm(@l.const("QTRUE")), imm(@l.const("QFALSE")))

        # An accessor's full body at the site. The cell's entry is an
        # accessor, and the receiver's class matches the cell, so the
        # remaining tests are the receiver's kind, GATE_RACTOR, and the
        # guessed ivar entry (the same tests that `guessed_ivar_row` does
        # for `@name`). A receiver that is not a plain object, a ractor, a
        # frozen receiver for the writer, or a wrong guess goes to `slow`,
        # the kernel's send, which calls the accessor and sets the guess.
        #
        # `held` is the cell's shape. When it can be a struct member's
        # (`struct_member?`), the guessed entry is the struct's values, and
        # the member is the element at the entry's index
        # (`struct_member_in_place`).
        #
        # Clear the keyword word as the accessor call would.
        def accessor_in_place(shape, site, slow, held = nil)
          recv = site.recv
          entry = site.entry
          argv = site.argv
          merge = site.merge
          table = @l.layout("IvTab")
          row = @l.layout("IvEntry")
          meta = @l.layout("MEntry")
          plain = @f.label
          indexed = @f.label
          hit = @f.label
          @f.store(imm(0), @task_addr, off(@task, "kw"), region: :task)
          mask = @l.const("T_MASK") | (shape == :writer ? @l.const("FL_FREEZE") : 0)
          kind = @f.band(@f.fetch("i64", recv, off(@l.layout("RBasic"), "flags")), imm(mask))
          @f.brif(@f.band(@f.icmp("eq", kind, imm(@l.const("T_OBJECT"))), gate_test(["GATE_RACTOR"])), plain, slow)
          switch(plain)
          t = @f.iadd(recv, imm(off(@l.layout("RObject"), "iv")))
          i = @f.fetch("i64", @f.iadd(entry, imm(off(meta, "ivar"))), off(@l.layout("IvarCache"), "index"))
          @f.brif(@f.icmp("ult", i, @f.fetch("i64", t, off(table, "len"))), indexed, slow)
          switch(indexed)
          at = @f.iadd(@f.fetch("i64", t, off(table, "rows")), @f.ishl(i, imm(Math.log2(row.size).to_i)))
          fn = @f.fetch("i64", entry, off(meta, "fn"))
          member = held && struct_member?(shape, held)
          @f.brif(@f.icmp("eq", @f.fetch("i64", at, off(row, "id")), member ? @f.csel(member, sym_word(:__values__), fn) : fn), hit, slow)
          switch(hit)
          if member
            ivar = @f.label
            element = @f.label
            @f.brif(member, element, ivar)
            switch(element)
            struct_member_in_place(shape, @f.fetch("i64", at, off(row, "value")), fn, argv, merge, slow)
            switch(ivar)
          end
          if shape == :writer
            v = @f.fetch("i64", argv, 0)
            @f.store(v, at, off(row, "value"), region: :malloc)
            cell_barrier(recv, v)
            @f.jump(merge, [v])
          else
            value = @f.fetch("i64", at, off(row, "value"))
            @f.jump(merge, [@f.csel(@f.icmp("eq", value, qundef), @qnil, value)])
          end
        end

        # Whether the cell's shape `held` is a struct member's reader or
        # writer, for an accessor `shape`.
        def struct_member?(shape, held)
          @f.icmp("eq", held, imm(@l.const(shape == :writer ? "SHAPE_STRUCT_WRITER" : "SHAPE_STRUCT_READER")))
        end

        # A struct member's reader or writer at the site, as the kernel's
        # `zr_struct_aref_fn` and `zr_struct_aset_fn` do: element `index`
        # of `values`, the struct's values Array. Values that are not an
        # Array yet (nil until the first read of a struct from `allocate`)
        # or an index past their end go to `slow`.
        def struct_member_in_place(shape, values, index, argv, merge, slow)
          array = @f.label
          inside = @f.label
          cell = @f.band(@f.icmp("eq", @f.band(values, imm(7)), imm(0)), @f.icmp("ugt", values, @qnil))
          @f.brif(cell, array, slow)
          switch(array)
          kind = @f.band(@f.fetch("i64", values, off(@l.layout("RBasic"), "flags")), imm(@l.const("T_MASK")))
          @f.brif(@f.band(@f.icmp("eq", kind, imm(@l.const("T_ARRAY"))), @f.icmp("ult", index, array_len(values))), inside, slow)
          switch(inside)
          slot = @f.iadd(array_ptr(values), @f.ishl(index, imm(3)))
          if shape == :writer
            v = @f.fetch("i64", argv, 0)
            @f.store(v, slot, 0, region: :malloc)
            cell_barrier(values, v)
            @f.jump(merge, [v])
          else
            @f.jump(merge, [@f.fetch("i64", slot)])
          end
        end
      end
    end
  end
end
