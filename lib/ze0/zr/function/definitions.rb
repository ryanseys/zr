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
                    at_line(node.line)
                    checked(kernel("zr_singleton_class", expr(node.receiver)))
                  else
                    cref_class
                  end
          addr = @f.func_addr(@f.callee(fn, ABI.fetch(:def), "i64"))
          meta = @f.symbol_value(@f.symbol("zr_meta_#{fn}"))
          checked_arity = node.params.plain? ? node.params.required.size : -1
          at_line(node.line)
          checked(kernel("zr_define_method", owner, imm(sym_id(node.name)), addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          symbol(node.name)
        end

        # `class << target`: the singleton class is self and the definee.
        def singleton_class_body(node)
          fn = @l.body(node)
          at_line(node.line)
          klass = checked(kernel("zr_singleton_class", expr(node.target)))
          cref = kernel("zr_cref_push", klass, @cref)
          checked(@f.call_val(@f.callee(fn, ABI.fetch(:sclass), "i64"), [klass, cref]))
        end

        # `class`/`module`: define or reopen under the scope, push a cref,
        # run the body function with the class as self.
        def class_body(node)
          fn = @l.body(node)
          scope = scope_class(node.scope)
          id = imm(sym_id(node.name))
          at_line(node.line)
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
          id = imm(sym_id(node.name))
          at_line(node.line)
          if node.scope.nil?
            checked(kernel("zr_const_get", @cref, id))
          else
            checked(kernel("zr_const_get_at", scope_class(node.scope), id))
          end
        end

        # The line is the constant's location, which a later mistaken
        # `class Name` names.
        def const_write(node)
          scope = scope_class(node.scope)
          v = expr(node.value)
          at_line(node.line)
          kernel("zr_const_set", scope, imm(sym_id(node.name)), v)
          v
        end
      end
    end
  end
end
