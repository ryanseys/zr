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
          when Hir::Send then call(node)
          when Hir::Local then read_local(slot_at(node), node.depth)
          when Hir::Assign then write_local(slot_at(node), node.depth, expr(node.value))
          when Hir::Yield then yield_block(node)
          when Hir::Break then jump_out(node, :break)
          when Hir::Next then jump_out(node, :next)
          when Hir::Return then return_from(node)
          when Hir::Def then define_method(node)
          when Hir::ClassDef, Hir::ModuleDef then class_body(node)
          when Hir::SingletonClassDef then singleton_class_body(node)
          when Hir::ConstRead then const_read(node)
          when Hir::ConstWrite then const_write(node)
          when Hir::ArrayLit then array_literal(node)
          when Hir::HashLit then hash_literal(node)
          when Hir::Interp then staged(node.parts) { |argv| checked(kernel("zr_str_interp", imm(node.parts.size), argv)) }
          when Hir::IvarRead then kernel("zr_ivar_get", @self, imm(sym_id(node.name)))
          when Hir::GvarRead then gvar_read(node)
          when Hir::IvarWrite then kernel("zr_ivar_set", @self, imm(sym_id(node.name)), expr(node.value))
          when Hir::If then branch(node)
          when Hir::While then loop_while(node)
          when Hir::And, Hir::Or then logical(node)
          when Hir::Not then negate(node)
          when Hir::Begin then protect(node)
          when Hir::Retry then retry_region(node)
          else @l.refuse(node, "#{node.class.name.split("::").last} is not lowered yet")
          end
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
          return staged(node.pairs) { |argv| kernel("zr_hash_of", imm(node.pairs.size / 2), argv) } unless node.pairs.any?(Hir::HashSplat)

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
            @l.refuse(node, "a bignum literal is not lowered yet") unless v.bit_length < 63

            imm((v << 1) | 1)
          when Symbol then symbol(v)
          when String
            fn = @l.program.frozen ? "zr_str_frozen" : "zr_str_new"
            kernel(fn, @f.symbol_value(@f.symbol(@l.literal(v))), imm(v.bytesize))
          when nil then @qnil
          when true then imm(@l.const("QTRUE"))
          when false then imm(@l.const("QFALSE"))
          end
        end

        # `$!` is the task's; every other global waits for the table.
        def gvar_read(node)
          @l.refuse(node, "#{node.name} is not lowered yet") unless node.name == :$!

          kernel("zr_errinfo")
        end

        def symbol(name)
          imm((sym_id(name) << 8) | @l.const("SYMBOL_TAG"))
        end
      end
    end
  end
end
