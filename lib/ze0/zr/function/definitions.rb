# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # Methods, classes, modules and constants: what a scope defines.
      module Definitions
        private

        # `def`: the body becomes its own function, registered on the
        # cref's class, or on the receiver's singleton class; the value
        # is the name.
        def define_method(node)
          fn = @l.define(node)
          owner = if node.receiver
                    at_node(node)
                    checked(kernel("zr_singleton_class", expr(node.receiver)))
                  else
                    cref_class
                  end
          direct = Function.direct_def?(node, @l)
          addr = @f.func_addr(@f.callee(fn, ABI.fetch(direct ? Function.direct_abi(node.params.required.size) : :def), "i64"))
          meta = @f.symbol_value(@f.symbol("zr_meta_#{fn}"))
          checked_arity = node.params.plain? ? node.params.required.size : -1
          at_node(node)
          entry = node.receiver || inside_method? ? "zr_define_method_public" : "zr_define_method"
          if direct
            # The generic entry is the kernel's, which checks what a site
            # proves and calls the body; the body is the direct entry.
            d = @l.kernel_def("zr_direct_fn")
            generic = @f.func_addr(@f.callee("zr_direct_fn", d.params.map { |_, t| Machine::TYPES.fetch(t) }, "i64", effects: d.effects || IR::Effects::ALL))
            checked(kernel("#{entry}_direct", owner, sym_word(node.name), generic, addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          else
            checked(kernel(entry, owner, sym_word(node.name), addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          end
          symbol(node.name)
        end

        # A def in a method body (or a block in one) is public whatever
        # the class body's visibility verb was.
        def inside_method?
          fn = self
          fn = fn.outer while fn && fn.kind == :block
          fn&.kind == :def
        end

        # `class << target`: the singleton class is self and the definee.
        def singleton_class_body(node)
          fn = @l.body(node)
          at_node(node)
          klass = checked(kernel("zr_singleton_class", expr(node.target)))
          cref = kernel("zr_cref_push", klass, @cref)
          checked(@f.call_val(@f.callee(fn, ABI.fetch(:sclass), "i64"), [klass, cref]))
        end

        # `class`/`module`: define or reopen under the scope, push a cref,
        # run the body function with the class as self.
        def class_body(node)
          fn = @l.body(node)
          scope = scope_class(node.scope)
          id = sym_word(node.name)
          at_node(node)
          klass = if node.is_a?(Hir::ClassDef)
                    sup = node.superclass ? expr(node.superclass) : qundef
                    checked(kernel("zr_class_define", scope, id, sup))
                  else
                    checked(kernel("zr_module_define", scope, id))
                  end
          cref = kernel("zr_cref_push", klass, @cref)
          checked(@f.call_val(@f.callee(fn, ABI.fetch(:class), "i64"), [klass, cref]))
        end

        # The class a constant path's scope names: the lexical scope for a
        # bare name, Object for `::`, else the expression's value.
        def scope_class(scope)
          case scope
          when nil then kernel("zr_cref_lexical_class", @cref)
          when :top then global("G_OBJECT")
          else expr(scope)
          end
        end

        def const_read(node)
          if node.scope.nil? && (slot = @l.boot_class_slot(node.name))
            return global(slot)
          end

          id = sym_word(node.name)
          # The scope is read first, so the row names this read's node.
          scope = scope_class(node.scope) if node.scope
          at_node(node)
          # A program's read asks, outside the main ractor, whether it may
          # share the value; the core's reads are its own, as C's are.
          if node.scope.nil?
            cached_const(@cref, @l.internal? ? "zr_const_get_cached" : "zr_const_read_cached", id)
          else
            cached_const(scope, @l.internal? ? "zr_const_get_at_cached" : "zr_const_read_at_cached", id)
          end
        end

        # A constant through the site's own cell (rt/kernel/cache.rb):
        # the value the kernel answered under `key` (the cref, or the
        # scope) at the constant stamp, read here while both hold; else
        # the kernel's lookup, which fills the cell.
        def cached_const(key, lookup, id)
          cc = cache("cc", "ConstCache")
          cell = @l.layout("ConstCache")
          fast = @f.label
          slow = @f.label
          merge, (result,) = @f.block(["i64"])
          same_key = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "key")), key)
          same_stamp = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("const_stamp")))
          @f.brif(@f.band(same_key, same_stamp), fast, slow)
          switch(fast)
          @f.jump(merge, [@f.fetch("i64", cc, off(cell, "value"))])
          switch(slow)
          @f.jump(merge, [checked(kernel(lookup, cc, key, id))])
          switch(merge)
          result
        end

        # The line is the constant's location, which a later mistaken
        # `class Name` names.
        def const_write(node)
          scope = scope_class(node.scope)
          v = expr(node.value)
          at_node(node)
          checked(kernel("zr_const_set", scope, sym_word(node.name), v))
          v
        end
      end
    end
  end
end
