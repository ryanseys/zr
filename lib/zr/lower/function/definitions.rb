# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Methods, classes, modules and constants: what a scope defines.
      module Definitions
        private

        # `def`: the body becomes its own function, defined on the cref's
        # class or on the receiver's singleton class. The value is the name.
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
            # The generic entry is the kernel's. It checks what a direct
            # site proves, then calls the body. The body is the direct entry.
            d = @l.kernel_def("zr_direct_fn")
            generic = @f.func_addr(@f.callee("zr_direct_fn", d.params.map { |_, t| Machine::TYPES.fetch(t) }, "i64", effects: d.effects || IR::Effects::ALL))
            checked(kernel("#{entry}_direct", owner, sym_word(node.name), generic, addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          else
            checked(kernel(entry, owner, sym_word(node.name), addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          end
          symbol(node.name)
        end

        # A def in a method body (or in a block in one) is public, whatever
        # the class body's visibility was.
        def inside_method?
          fn = self
          fn = fn.outer while fn && fn.kind == :block
          fn&.kind == :def
        end

        # `class << target`: the singleton class is self and the definee.
        def singleton_class_body(node)
          fn = @l.body(node, self)
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
          scoped = imm(node.scope ? 1 : 0)
          klass = if node.is_a?(Hir::ClassDef)
                    sup = node.superclass ? expr(node.superclass) : qundef
                    checked(kernel("zr_class_define", scope, id, sup, scoped))
                  else
                    checked(kernel("zr_module_define", scope, id, scoped))
                  end
          cref = kernel("zr_cref_push", klass, @cref)
          checked(@f.call_val(@f.callee(fn, ABI.fetch(:class), "i64"), [klass, cref]))
        end

        # The class of a constant path's scope: the lexical scope for a
        # bare name, Object for `::`, else the expression's value.
        def scope_class(scope)
          case scope
          when nil then kernel("zr_cref_lexical_class", @cref)
          when :top then global("G_OBJECT")
          else expr(scope)
          end
        end

        def const_read(node) = const_value(node, false)

        # A constant read, and a word that is 1 if every read in its path
        # (`A::B` reads `A` too) came from the site's cell, else 0. A read
        # from the cell ran no lookup, no autoload and no `const_missing`,
        # so the same cref reads the same value with no effect while the
        # constant stamp stays the same. A `case` on class arms trusts
        # only such reads (`Control#class_case`).
        def const_hit_read(node)
          return const_value(node, true) unless node.scope.is_a?(Hir::ConstRead)

          scope, above = const_hit_read(node.scope)
          value, hit = const_at(node, scope, true)
          [value, @f.band(above, hit)]
        end

        def const_value(node, flag)
          if node.scope.nil? && (slot = @l.boot_class_slot(node.name))
            return flag ? [global(slot), imm(1)] : global(slot)
          end

          # Read the scope first, so the line record refers to this read's
          # node.
          const_at(node, (scope_class(node.scope) if node.scope), flag)
        end

        # Outside the main ractor, a program's read checks whether it can
        # share the value. The core's reads skip this check, as C's do.
        def const_at(node, scope, flag)
          id = sym_word(node.name)
          at_node(node)
          if node.scope.nil?
            cached_const(@cref, @l.internal? ? "zr_const_get_cached" : "zr_const_read_cached", id, flag)
          else
            cached_const(scope, @l.internal? ? "zr_const_get_at_cached" : "zr_const_read_at_cached", id, flag)
          end
        end

        # A constant read through the site's own cell (runtime/kernel/cache.rb).
        # The cell keeps the kernel's value for `key` (the cref or the
        # scope) at a constant stamp. If both still match, read the value
        # here. Else call the kernel's lookup, which fills the cell. With
        # `flag`, also return 1 for a read from the cell, else 0.
        def cached_const(key, lookup, id, flag = false)
          cc = cache("cc", "ConstCache")
          cell = @l.layout("ConstCache")
          fast = @f.label
          slow = @f.label
          merge, (result, hit) = @f.block(flag ? %w[i64 i64] : ["i64"])
          same_key = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "key")), key)
          same_stamp = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("const_stamp")))
          @f.brif(@f.band(same_key, same_stamp), fast, slow)
          switch(fast)
          value = @f.fetch("i64", cc, off(cell, "value"))
          @f.jump(merge, flag ? [value, imm(1)] : [value])
          switch(slow)
          value = checked(kernel(lookup, cc, key, id))
          @f.jump(merge, flag ? [value, imm(0)] : [value])
          switch(merge)
          flag ? [result, hit] : result
        end

        # Set the line to the constant's location. A later incorrect
        # `class Name` reports it.
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
