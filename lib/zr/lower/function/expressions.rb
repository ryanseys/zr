# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # The Value of each HIR node, in a register. A caller that holds it
      # across a call stores it to the record first.
      module Expressions
        private

        def expr(node)
          case node
          when Hir::Seq then seq(node)
          when Hir::Trace then trace_line(node)
          when Hir::Cover then cover_branch(node)
          when Hir::Literal then literal(node)
          when Hir::SelfRef then @self
          when Hir::Core then kernel("zr_core_class", sym_word(node.name))
          when Hir::Once then once(node)
          when Hir::Send then call(node)
          when Hir::Local then read_local(slot_at(node), node.depth, node.name)
          when Hir::Assign then write_local(slot_at(node), node.depth, expr(node.value), node.name)
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
          when Hir::UsingDefaults
            node.rows.each { |id, from| kernel("zr_using_default", imm(id), imm(from)) }
            @qnil
          when Hir::Activations
            kernel("zr_activations_reserve", imm(node.count))
            @qnil
          when Hir::Stop then checked(kernel("zr_unloadable", string_literal(node.what, "zr_str_literal_freeze")))
          when Hir::Autoload then autoload_unit(node)
          when Hir::Def then define_method(node)
          when Hir::ClassDef, Hir::ModuleDef then class_body(node)
          when Hir::SingletonClassDef then singleton_class_body(node)
          when Hir::ConstRead then const_read(node)
          when Hir::ConstWrite then const_write(node)
          when Hir::ArrayLit then array_literal(node)
          when Hir::KwSplatElement then kernel("zr_ary_kw_element", expr(node.pairs))
          when Hir::HashLit then hash_literal(node)
          when Hir::RangeLit
            staged([node.low, node.high]) do |argv|
              ends = [@f.fetch("i64", argv), @f.fetch("i64", argv, 8), imm(node.exclusive ? 1 : 0)]
              checked(node.static ? kernel("zr_range_literal", site_word, *ends) : kernel("zr_range_new", *ends))
            end
          when Hir::Interp then interp(node)
          when Hir::RegexpLit
            checked(kernel("zr_regexp_literal", site_word, @f.symbol_value(@f.symbol(@l.literal(node.source))), imm(node.source.bytesize), imm(node.options),
                           imm(node.pinned ? ENCODING_INDEX.fetch(node.pinned) : -1)))
          when Hir::IvarRead then ivar_read(node)
          when Hir::FrozenString
            if node.shared then shared_literal(node.value)
            else checked(string_literal(node.value, node.shared == false ? "zr_str_frozen" : "zr_str_literal_freeze"))
            end
          when Hir::GvarRead then gvar_read(node)
          when Hir::BackRef then back_ref(node)
          when Hir::GvarWrite then gvar_write(node, expr(node.value))
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

        # The one shared frozen String of a UTF-8 literal: made the first
        # time the site runs (zr_str_literal_shared, which keeps it
        # rooted), then read from a word of the site's own, with no call.
        def shared_literal(text)
          cell = @f.symbol_value(@f.symbol(@l.cache_cell("lit", 8)))
          hit = @f.label
          miss = @f.label
          merge, (result,) = @f.block(["i64"])
          word = @f.fetch("i64", cell)
          @f.brif(@f.icmp("eq", word, imm(0)), miss, hit)
          switch(hit)
          @f.jump(merge, [word])
          switch(miss)
          made = kernel("zr_str_literal_cell", cell, @f.symbol_value(@f.symbol(@l.literal(text))), imm(text.bytesize))
          @f.jump(merge, [made])
          switch(merge)
          result
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
          _, block = make_block(node.block)
          kernel("zr_proc_lambda", block)
        end

        # `[a, b]`: the elements staged in the record and copied into a
        # new Array, or, where every one is an immediate, copied from
        # data the link wrote once (`word_table`). A splat pushes as it
        # goes. A frozen literal (a shareable constant's) takes the flag
        # and no send, as compile.c freezes what it built.
        def array_literal(node)
          elements = node.elements
          ary = if (words = immediate_words(elements))
                  kernel("zr_ary_of", imm(words.size), @f.symbol_value(@f.symbol(@l.word_table(words))))
                elsif elements.none?(Hir::Splat)
                  staged(elements) { |argv| kernel("zr_ary_of", imm(elements.size), argv) }
                else
                  slot = reserve(1)
                  gathered = gather(elements, slot)
                  @sp = slot
                  gathered
                end
          node.frozen ? kernel("zr_literal_freeze", ary) : ary
        end

        # The words of `nodes` where each is an immediate literal -- a
        # fixnum, a flonum, a Symbol (its name, for the link), nil, true
        # or false -- else nil.
        def immediate_words(nodes)
          return nil if nodes.empty?

          nodes.map do |n|
            return nil unless n.is_a?(Hir::Literal)

            v = n.value
            case v
            when Integer then v.bit_length < 63 ? (v << 1) | 1 : (return nil)
            when Float then flonum_word(v) || (return nil)
            when Symbol then v
            when nil then @l.const("QNIL")
            when true then @l.const("QTRUE")
            when false then @l.const("QFALSE")
            else return nil
            end
          end
        end

        # `{k => v, **h}`: pairs stored one by one into a Hash kept in a
        # record slot when a double splat is among them.
        # `@name`: the guessed row's value inline, nil for a row unset;
        # else the kernel's read.
        def ivar_read(node)
          ivar = ivar_name(node.name)
          ic = site_cache(node, "iv", "IvarCache")
          slow = @f.label
          merge, (v,) = @f.block(["i64"])
          row = guessed_ivar_row(ic, ivar, slow, writing: false)
          found = @f.fetch("i64", row, off(@l.layout("IvEntry"), "value"))
          @f.jump(merge, [@f.csel(@f.icmp("eq", found, qundef), @qnil, found)])
          switch(slow)
          @f.jump(merge, [checked(kernel("zr_ivar_get_cached", @self, sym_word(ivar), ic))])
          switch(merge)
          v
        end

        def hash_literal(node)
          if (words = immediate_words(node.pairs))
            hash = checked(kernel("zr_hash_of", imm(words.size / 2), @f.symbol_value(@f.symbol(@l.word_table(words)))))
            return node.frozen ? kernel("zr_literal_freeze", hash) : hash
          end
          unless node.pairs.any?(Hir::HashSplat)
            hash = staged(node.pairs) { |argv| checked(kernel("zr_hash_of", imm(node.pairs.size / 2), argv)) }
            return node.frozen ? kernel("zr_literal_freeze", hash) : hash
          end

          slot = reserve(1)
          at = value_offset(slot)
          @f.store(kernel("zr_hash_new"), @rec, at)
          node.pairs.each_slice(2) do |key, value|
            if key.is_a?(Hir::HashSplat)
              checked(kernel("zr_hash_update", @f.fetch("i64", @rec, at), expr(key.value)))
            else
              staged([key, value]) { |argv| checked(kernel("zr_hash_store", @f.fetch("i64", @rec, at), @f.fetch("i64", argv), @f.fetch("i64", argv, 8))) }
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
              checked(kernel("zr_big_literal", site_word, @f.symbol_value(@f.symbol(@l.literal(text))), imm(text.bytesize)))
            end
          when Float then float_literal(v)
          when Symbol then symbol(v)
          when String then string_literal(v, node.chilled && !@l.internal? ? "zr_str_new_chilled" : "zr_str_new")
          when nil then @qnil
          when true then imm(@l.const("QTRUE"))
          when false then imm(@l.const("QFALSE"))
          end
        end

        # A Float literal that fits a flonum is its bits rotated, known
        # now, exactly as zr_float_new would make it; +0.0 is the flonum
        # zero; any other double is a heap cell made at run time.
        def float_literal(v)
          word = flonum_word(v)
          return kernel("zr_float_from_bits", imm([v].pack("E").unpack1("q<"))) unless word

          imm(word)
        end

        # The flonum word of `v` as a signed 64-bit value, or nil where
        # the double does not fit one.
        def flonum_word(v)
          b = [v].pack("E").unpack1("Q<")
          top = (b >> 60) & 7
          word = if b.zero? then @l.const("FLONUM_ZERO")
                 elsif b != 0x3000000000000000 && (top == 3 || top == 4)
                   ((((b << 3) | (b >> 61)) & 0xFFFF_FFFF_FFFF_FFFE) | 2)
                 end
          word && [word].pack("Q<").unpack1("q<")
        end

        # `"a#{b}c"`. The pieces between the embedded expressions are
        # never handed to the program: `zr_str_interp` (runtime/kernel/string.rb)
        # reads their bytes and answers a String of its own. So each one is
        # the shared frozen String of those bytes and not a String made
        # again every time control passes the literal, which is what a
        # piece cost before -- an allocation, a malloc and a copy each.
        def interp(node)
          staged(node.parts, evaluate: method(:interp_part)) do |argv|
            checked(kernel("zr_str_interp", imm(node.parts.size), argv))
          end
        end

        # A piece of an interpolation: the shared String where it is a
        # literal this file wrote in UTF-8, and lowered as anything else
        # otherwise. The shared table keys on bytes alone and so cannot
        # tell two encodings apart, which is why a file of another script
        # encoding keeps the plain form.
        def interp_part(node)
          text = node.is_a?(Hir::Literal) ? node.value : nil
          return expr(node) unless text.is_a?(String) && text.encoding == ::Encoding::UTF_8

          string_literal(text, "zr_str_literal_shared")
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
          return kernel("zr_core_class", sym_word(:ARGF)) if node.name == :$<

          # A program's global outside the main ractor is refused unless
          # it is one CRuby keeps for each ractor; the core reads its own.
          @l.internal? ? kernel("zr_gvar_get", sym_word(node.name)) : checked(kernel("zr_gvar_read", sym_word(node.name)))
        end

        # The globals ruby hooks: a write checks the value, or refuses a
        # read-only name. The core library writes them unchecked.
        HOOKED_GVARS = %i[
          $! $@ $& $` $' $+ $$ $? $* $< $FILENAME $LOAD_PATH $LOADED_FEATURES $-a $-l $-p $-W
          $; $, $/ $\\ $stdout $stderr $0 $VERBOSE $.
        ].to_set.freeze

        # `$~` and `$_` live in the frame; the rest are globals, and a
        # command trace_var put on one runs on this line.
        def gvar_write(node, v)
          name = node.name
          return kernel("zr_backref_set", v) if name == :$~ && @l.internal?
          return checked(kernel("zr_backref_assign", v)) if name == :$~
          return kernel("zr_lastline_set", v) if name == :$_

          at_node(node)
          checked(kernel("zr_ractor_gvar_check", sym_word(name))) unless @l.internal?
          return checked(kernel("zr_gvar_assign", sym_word(name), v)) if @l.internal? || !HOOKED_GVARS.include?(name)

          checked(kernel("zr_gvar_hooked", sym_word(node.shown || name), sym_word(name), v))
        end

        # `$1`, `$&`, `` $` ``, `$'` and `$+`: `$~`'s registers, nil
        # without a match.
        def back_ref(node)
          match = kernel("zr_backref_get")
          case node.kind
          when :nth then kernel("zr_match_nth", match, expr(Hir::Literal.new(node.number, node.line)))
          when :last then kernel("zr_match_last", match)
          when :pre then kernel("zr_match_pre", match)
          when :post then kernel("zr_match_post", match)
          end
        end

        def cvar_read(node)
          at_node(node)
          checked(kernel("zr_cvar_get", @cref, sym_word(node.name)))
        end

        def undef_methods(node)
          at_node(node)
          node.names.each { |name| checked(kernel("zr_undef", cref_class, sym_word(name))) }
          @qnil
        end

        def alias_method(node)
          at_node(node)
          checked(kernel("zr_alias", cref_class, sym_word(node.new_name), sym_word(node.old_name)))
        end

        # The names wait in record slots, since making one may collect.
        # `/#{x}/o` runs its site once: the regexp waits in the literal
        # table, and every later run reads it back.
        def regexp_once(node)
          index = site_word
          cached = kernel("zr_regexp_once", index)
          make = @f.label
          have = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.icmp("eq", cached, @qnil), make, have)
          switch(have)
          @f.jump(merge, [cached])
          switch(make)
          made = expr(node.value)
          kernel("zr_regexp_once_set", index, made)
          @f.jump(merge, [made]) unless @f.terminated?
          switch(merge)
          result
        end

        def alias_value(node)
          staged([node.new_name, node.old_name]) do |slots, _base|
            at_node(node)
            checked(kernel("zr_alias_value", cref_class, @f.fetch("i64", slots), @f.fetch("i64", slots, 8)))
          end
        end

        def undef_values(node)
          staged(node.names) do |slots, _base|
            node.names.each_index do |i|
              at_node(node)
              checked(kernel("zr_undef_value", cref_class, @f.fetch("i64", slots, 8 * i)))
            end
          end
          @qnil
        end

        def alias_global(node)
          kernel("zr_gvar_alias", sym_word(node.new_name), sym_word(node.old_name))
          @qnil
        end

        def cvar_write(node)
          v = expr(node.value)
          at_node(node)
          checked(kernel("zr_cvar_set", @cref, sym_word(node.name), v))
        end

        # `Name ||= value`: the constant when it is set and truthy, else
        # the assignment.
        def const_or_write(node)
          at_node(node)
          current = if node.scope.nil?
                      kernel("zr_const_lookup", @cref, sym_word(node.name))
                    else
                      kernel("zr_const_lookup_at", scope_class(node.scope), sym_word(node.name))
                    end
          have = @f.label
          set = @f.label
          merge, (result,) = @f.block(["i64"])
          @f.brif(@f.band(@f.icmp("ne", current, qundef), truthy(current)), have, set)
          switch(have)
          @f.jump(merge, [current])
          switch(set)
          v = expr(node.value)
          checked(kernel("zr_const_set", scope_class(node.scope), sym_word(node.name), v))
          @f.jump(merge, [v])
          switch(merge)
          result
        end

        def symbol(name)
          sym_value(name)
        end
      end
    end
  end
end
