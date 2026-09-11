# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # The Value of each HIR node, in a register. A caller that holds it
      # across a call stores it to the record first.
      module Expressions
        private

        def expr(node)
          case node
          when Hir::Seq then seq(node)
          when Hir::Literal then literal(node)
          when Hir::SelfRef then @self
          when Hir::Core then kernel("zr_core_class", imm(sym_id(node.name)))
          when Hir::Once then once(node)
          when Hir::Send then call(node)
          when Hir::Local then read_local(slot_at(node), node.depth)
          when Hir::Assign then write_local(slot_at(node), node.depth, expr(node.value))
          when Hir::MultiAssign then multi_assign(node)
          when Hir::Yield then yield_block(node)
          when Hir::Super then super_call(node)
          when Hir::Lambda then lambda_literal(node)
          when Hir::ZSuper then zsuper(node)
          when Hir::Break then jump_out(node, :break)
          when Hir::Next then jump_out(node, :next)
          when Hir::Return then return_from(node)
          when Hir::Require then require_unit(node)
          when Hir::Using then using_row(node)
          when Hir::Stop then checked(kernel("zr_unloadable", string_literal(node.what, "zr_str_literal_freeze")))
          when Hir::Autoload then autoload_unit(node)
          when Hir::Def then define_method(node)
          when Hir::ClassDef, Hir::ModuleDef then class_body(node)
          when Hir::SingletonClassDef then singleton_class_body(node)
          when Hir::ConstRead then const_read(node)
          when Hir::ConstWrite then const_write(node)
          when Hir::ArrayLit then array_literal(node)
          when Hir::KwSplatElement then kernel("zr_ary_kw_element", expr(node.hash))
          when Hir::HashLit then hash_literal(node)
          when Hir::RangeLit
            staged([node.low, node.high]) do |argv|
              ends = [@f.fetch("i64", argv), @f.fetch("i64", argv, 8), imm(node.exclusive ? 1 : 0)]
              checked(node.static ? kernel("zr_range_literal", imm(@l.literal_index), *ends) : kernel("zr_range_new", *ends))
            end
          when Hir::Interp then staged(node.parts) { |argv| checked(kernel("zr_str_interp", imm(node.parts.size), argv)) }
          when Hir::RegexpLit
            checked(kernel("zr_regexp_literal", imm(@l.literal_index), @f.symbol_value(@f.symbol(@l.literal(node.source))), imm(node.source.bytesize), imm(node.options),
                           imm(node.pinned ? ENCODING_INDEX.fetch(node.pinned) : -1)))
          when Hir::IvarRead then kernel("zr_ivar_get_cached", @self, imm(sym_id(node.name)), cache("iv", "IvarCache"))
          when Hir::FrozenString then checked(string_literal(node.value, "zr_str_literal_freeze"))
          when Hir::GvarRead then gvar_read(node)
          when Hir::GvarWrite then gvar_write(node.name, expr(node.value))
          when Hir::CvarRead then cvar_read(node)
          when Hir::CvarWrite then cvar_write(node)
          when Hir::ConstOrWrite then const_or_write(node)
          when Hir::RegexpOnce then regexp_once(node)
          when Hir::Alias then alias_method(node)
          when Hir::AliasValue then alias_value(node)
          when Hir::UndefValue then undef_values(node)
          when Hir::GvarAlias then alias_global(node)
          when Hir::Undef then undef_methods(node)
          when Hir::Defined then defined(node)
          when Hir::Case then case_when(node)
          when Hir::IndexOpAssign then index_op_assign(node)
          when Hir::AttrOpAssign then attr_op_assign(node)
          when Hir::Slot then @f.fetch("i64", @rec, value_offset(node.index))
          when Hir::IvarWrite then ivar_write(node, expr(node.value))
          when Hir::If then branch(node)
          when Hir::While then loop_while(node)
          when Hir::And, Hir::Or then logical(node)
          when Hir::Not then negate(node)
          when Hir::Begin then protect(node)
          when Hir::Retry then retry_region(node)
          when Hir::Redo then redo_body(node)
          else @l.refuse(node, "#{node.class.name.split("::").last} is not lowered yet")
          end
        end

        # The body the first time the site runs, nil every time: a flag
        # word of the site's own, set before the body runs.
        def once(node)
          cell = @f.symbol_value(@f.symbol(@l.cache_cell("once", 8)))
          run = @f.label
          skip = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", @f.fetch("i64", cell), imm(0)), run, skip)
          switch(skip)
          @f.jump(merge, [@qnil])
          switch(run)
          @f.store(imm(1), cell)
          expr(node.body)
          @f.jump(merge, [@qnil]) unless @f.terminated?
          switch(merge)
          result
        end

        # `-> { }`: a Proc marked a lambda; its `break` and `return` stay
        # inside it, so it has no call site to answer to.
        def lambda_literal(node)
          slot = reserve(1)
          _, proc = make_proc(node.block, slot)
          @sp = slot
          kernel("zr_proc_lambda", proc)
        end

        def array_literal(node)
          return staged(node.elements) { |argv| kernel("zr_ary_of", imm(node.elements.size), argv) } unless node.elements.any?(Hir::Splat)

          slot = reserve(1)
          ary = gather(node.elements, slot)
          @sp = slot
          ary
        end

        # `{k => v, **h}`: pairs stored one by one into a Hash kept in a
        # record slot when a double splat is among them.
        def hash_literal(node)
          return staged(node.pairs) { |argv| checked(kernel("zr_hash_of", imm(node.pairs.size / 2), argv)) } unless node.pairs.any?(Hir::HashSplat)

          slot = reserve(1)
          at = value_offset(slot)
          @f.store(kernel("zr_hash_new"), @rec, at)
          node.pairs.each_slice(2) do |key, value|
            if key.is_a?(Hir::HashSplat)
              checked(kernel("zr_hash_update", @f.fetch("i64", @rec, at), expr(key.value)))
            else
              staged([key, value]) { |argv| kernel("zr_hash_store", @f.fetch("i64", @rec, at), @f.fetch("i64", argv), @f.fetch("i64", argv, 8)) }
            end
          end
          @sp = slot
          @f.fetch("i64", @rec, at)
        end

        def seq(node)
          last = nil
          node.stmts.each do |s|
            last = expr(s)
            break if @f.terminated?
          end
          last || @qnil
        end

        def literal(node)
          v = node.value
          case v
          when Integer
            if v.bit_length < 63
              imm((v << 1) | 1)
            else
              text = v.to_s
              checked(kernel("zr_big_literal", @f.symbol_value(@f.symbol(@l.literal(text))), imm(text.bytesize)))
            end
          when Float then float_literal(v)
          when Symbol then symbol(v)
          when String then string_literal(v, "zr_str_new")
          when nil then @qnil
          when true then imm(@l.const("QTRUE"))
          when false then imm(@l.const("QFALSE"))
          end
        end

        # A Float literal that fits a flonum is its bits rotated, known
        # now, exactly as zr_float_new would make it; +0.0 is the flonum
        # zero; any other double is a heap cell made at run time.
        def float_literal(v)
          b = [v].pack("E").unpack1("Q<")
          top = (b >> 60) & 7
          word = if b.zero? then @l.const("FLONUM_ZERO")
                 elsif b != 0x3000000000000000 && (top == 3 || top == 4)
                   ((((b << 3) | (b >> 61)) & 0xFFFF_FFFF_FFFF_FFFE) | 2)
                 end
          return kernel("zr_float_from_bits", imm([v].pack("E").unpack1("q<"))) unless word

          imm([word].pack("Q<").unpack1("q<"))
        end

        # A String literal, built by `fn` and tagged with the script
        # encoding the file declared. UTF-8 is the usual answer and needs
        # no number.
        def string_literal(text, fn)
          bytes = @f.symbol_value(@f.symbol(@l.literal(text)))
          index = ENCODING_INDEX.fetch(text.encoding)
          return kernel(fn, bytes, imm(text.bytesize)) if index == ENCODING_INDEX.fetch(::Encoding::UTF_8)

          kernel("#{fn}_at", bytes, imm(text.bytesize), imm(index))
        end

        # ruby's own number for an encoding, which is what a String
        # carries at run time.
        ENCODING_INDEX = ::Encoding.list.each_with_index.to_h.freeze

        # The globals with meanings of their own: `$!` is the task's, `$~`
        # and `$_` the frame's, and `$<` is ARGF. Any other, `$.` among
        # them, lives in the globals table, where the core sets it.
        def gvar_read(node)
          return kernel("zr_errinfo") if node.name == :$!
          return kernel("zr_backref_get") if node.name == :$~
          return kernel("zr_lastline_get") if node.name == :$_

          # `$<` is ARGF itself, whatever a program names ARGF.
          return kernel("zr_core_class", imm(sym_id(:ARGF))) if node.name == :$<

          kernel("zr_gvar_get", imm(sym_id(node.name)))
        end

        # `$~` and `$_` live in the frame; the rest are plain globals.
        def gvar_write(name, v)
          return kernel("zr_backref_set", v) if name == :$~
          return kernel("zr_lastline_set", v) if name == :$_

          kernel("zr_gvar_set", imm(sym_id(name)), v)
        end

        def cvar_read(node)
          at_line(node.line)
          checked(kernel("zr_cvar_get", @cref, imm(sym_id(node.name))))
        end

        def undef_methods(node)
          at_line(node.line)
          node.names.each { |name| checked(kernel("zr_undef", cref_class, imm(sym_id(name)))) }
          @qnil
        end

        def alias_method(node)
          at_line(node.line)
          checked(kernel("zr_alias", cref_class, imm(sym_id(node.new_name)), imm(sym_id(node.old_name))))
        end

        # The names wait in record slots, since making one may collect.
        # `/#{x}/o` runs its site once: the regexp waits in the literal
        # table, and every later run reads it back.
        def regexp_once(node)
          index = @l.literal_index
          cached = kernel("zr_regexp_once", imm(index))
          make = @f.label
          have = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", cached, @qnil), make, have)
          switch(have)
          @f.jump(merge, [cached])
          switch(make)
          made = expr(node.value)
          kernel("zr_regexp_once_set", imm(index), made)
          @f.jump(merge, [made]) unless @f.terminated?
          switch(merge)
          result
        end

        def alias_value(node)
          staged([node.new_name, node.old_name]) do |slots, _base|
            at_line(node.line)
            checked(kernel("zr_alias_value", cref_class, @f.fetch("i64", slots), @f.fetch("i64", slots, 8)))
          end
        end

        def undef_values(node)
          staged(node.names) do |slots, _base|
            node.names.each_index do |i|
              at_line(node.line)
              checked(kernel("zr_undef_value", cref_class, @f.fetch("i64", slots, 8 * i)))
            end
          end
          @qnil
        end

        def alias_global(node)
          kernel("zr_gvar_alias", imm(sym_id(node.new_name)), imm(sym_id(node.old_name)))
          @qnil
        end

        def cvar_write(node)
          v = expr(node.value)
          at_line(node.line)
          checked(kernel("zr_cvar_set", @cref, imm(sym_id(node.name)), v))
        end

        # `Name ||= value`: the constant when it is set and truthy, else
        # the assignment.
        def const_or_write(node)
          at_line(node.line)
          current = if node.scope.nil?
                      kernel("zr_const_lookup", @cref, imm(sym_id(node.name)))
                    else
                      kernel("zr_const_lookup_at", scope_class(node.scope), imm(sym_id(node.name)))
                    end
          have = @f.label
          set = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.band(@f.icmp("ne", current, qundef), truthy(current)), have, set)
          switch(have)
          @f.jump(merge, [current])
          switch(set)
          v = expr(node.value)
          checked(kernel("zr_const_set", scope_class(node.scope), imm(sym_id(node.name)), v))
          @f.jump(merge, [v])
          switch(merge)
          result
        end

        def symbol(name)
          imm((sym_id(name) << 8) | @l.const("SYMBOL_TAG"))
        end
      end
    end
  end
end
