# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # Methods, classes, modules and constants: what a scope defines.
      module Definitions
        # @type instance: Function
        # @rbs @cref: String
        # @rbs @f: IR::Function
        # @rbs @l: Lower
        # @rbs @kind: Function::kind
        # @rbs @qnil: String

        private

        # `def`: the body becomes its own function, defined on the cref's
        # class or on the receiver's singleton class. The value is the name.
        #: (Hir::Def node) -> String
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
          entry = if node.receiver then "zr_define_method_public"
                  elsif inside_method? then kind == :block ? "zr_define_method_nested" : "zr_define_method_public"
                  else "zr_define_method"
                  end
          if direct
            # The generic entry is the kernel's. It checks what a direct
            # site proves, then calls the body. The body is the direct entry.
            d = @l.kernel_def("zr_direct_fn")
            # A parameter is never Void, so its IR type is never nil.
            params = d.params.map do |_, t|
              Machine::TYPES.fetch(t) #: String
            end
            generic = @f.func_addr(@f.callee("zr_direct_fn", params, "i64", effects: d.effects || IR::Effects::ALL))
            checked(kernel("#{entry}_direct", owner, sym_word(node.name), generic, addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          else
            checked(kernel(entry, owner, sym_word(node.name), addr, imm(checked_arity), imm(@l.const("KIND_DEF")), meta, @cref))
          end
          # vm_define_method: a class's `initialize` tells how many instance
          # variables its objects get, so they start with room for them.
          kernel("zr_class_estimate_ivars", owner, imm(ivar_writes(node).size)) if node.name == :initialize && !node.receiver
          symbol(node.name)
        end

        # rb_estimate_iv_count: the distinct instance variables that a
        # method's own code writes, its parameters' defaults included, and
        # not its blocks' or the scopes that it defines.
        #: (Hir::Def node) -> Set[Symbol]
        def ivar_writes(node)
          names = Set.new #: Set[Symbol]
          Hir.each_child(node) { |child| collect_ivar_writes(child, names) }
          names
        end

        #: (untyped node, Set[Symbol] names) -> void
        def collect_ivar_writes(node, names)
          case node
          when Hir::Block, Hir::Def, Hir::ClassDef, Hir::ModuleDef, Hir::SingletonClassDef then return
          when Hir::IvarWrite then names << node.name
          end
          Hir.each_child(node) { |child| collect_ivar_writes(child, names) }
        end

        # A def in a method body is public, whatever the class body's
        # visibility was; so is one in a block in a method, unless an eval
        # gave the block a scope of its own (zr_define_method_nested).
        #: () -> bool
        def inside_method?
          fn = self #: Function
          # The walk stops at the first scope that is not a block, so it
          # never reaches an eval's Outer.
          while fn.kind == :block && (up = fn.outer).is_a?(Function)
            fn = up
          end
          fn.kind == :def
        end

        # `class << target`: the singleton class is self and the definee.
        #: (Hir::SingletonClassDef node) -> String
        def singleton_class_body(node)
          fn = @l.body(node, self)
          at_node(node)
          klass = checked(kernel("zr_singleton_class_shown", expr(node.target)))
          cref = kernel("zr_cref_push", klass, @cref)
          checked(@f.call_val(@f.callee(fn, ABI.fetch(:sclass), "i64"), [klass, cref]))
        end

        # `class`/`module`: define or reopen under the scope, push a cref,
        # run the body function with the class as self.
        #: (Hir::ClassDef | Hir::ModuleDef node) -> String
        def class_body(node)
          fn = @l.body(node, self)
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
        #: (Hir::scope scope) -> String
        def scope_class(scope)
          case scope
          when nil then kernel("zr_cref_lexical_class", @cref)
          when :top then global("G_OBJECT")
          else expr(scope)
          end
        end

        #: (Hir::ConstRead node) -> String
        def const_read(node) = const_value(node, report_hit: false)

        # A constant read, and a word that is 1 if every read in its path
        # (`A::B` reads `A` too) came from the site's cell, else 0. A read
        # from the cell ran no lookup, no autoload and no `const_missing`,
        # so the same cref reads the same value with no effect while the
        # constant stamp stays the same. A `case` on class arms trusts
        # only such reads (`Control#class_case`).
        #: (Hir::ConstRead node) -> [String, String]
        def const_hit_read(node)
          return const_value(node, report_hit: true) unless node.scope.is_a?(Hir::ConstRead)

          scope, above = const_hit_read(node.scope)
          value, hit = const_at(node, scope, report_hit: true)
          [value, @f.band(above, hit)]
        end

        #: (Hir::ConstRead node, report_hit: false) -> String
        #: (Hir::ConstRead node, report_hit: true) -> [String, String]
        def const_value(node, report_hit:)
          if node.scope.nil? && (slot = @l.boot_class_slot(node.name))
            return report_hit ? [global(slot), imm(1)] : global(slot)
          end

          # Read the scope first, so the line record refers to this read's
          # node.
          const_at(node, (scope_class(node.scope) if node.scope), report_hit: report_hit)
        end

        # Outside the main ractor, a program's read checks whether it can
        # share the value. The core's reads skip this check, as C's do.
        #: (Hir::ConstRead node, String? scope, report_hit: false) -> String
        #: (Hir::ConstRead node, String? scope, report_hit: true) -> [String, String]
        #: (Hir::ConstRead node, String? scope, report_hit: bool) -> (String | [String, String])
        def const_at(node, scope, report_hit:)
          id = sym_word(node.name)
          at_node(node)
          return nil_lexical_const(scope, id) if scope && node.nil_lexical && !report_hit

          # `scope` is nil exactly when the node has no scope.
          if scope
            cached_const(scope, @l.internal? ? "zr_const_get_at_cached" : "zr_const_read_at_cached", id, report_hit: report_hit)
          else
            cached_const(@cref, @l.internal? ? "zr_const_get_cached" : "zr_const_read_cached", id, report_hit: report_hit)
          end
        end

        # The read of `scope::Name` that reads `Name` lexically when the
        # scope is nil (Hir::ConstRead#nil_lexical).
        #: (String scope, String id) -> String
        def nil_lexical_const(scope, id)
          lexical = @f.label
          scoped = @f.label
          merge, (result,) = @f.block(["i64"]) #: [String, [String]]
          @f.brif(@f.icmp("eq", scope, @qnil), lexical, scoped)
          switch(lexical)
          @f.jump(merge, [cached_const(@cref, @l.internal? ? "zr_const_get_cached" : "zr_const_read_cached", id)])
          switch(scoped)
          @f.jump(merge, [cached_const(scope, @l.internal? ? "zr_const_get_at_cached" : "zr_const_read_at_cached", id)])
          switch(merge)
          result
        end

        # A constant read through the site's own cell (lib/zr/runtime/kernel/cache.rb).
        # The cell keeps the kernel's value for `key` (the cref or the
        # scope) at a constant stamp. If both still match, read the value
        # here. Else call the kernel's lookup, which fills the cell. With
        # `report_hit`, also return 1 for a read from the cell, else 0.
        #: (String key, String lookup, String id, ?report_hit: false) -> String
        #: (String key, String lookup, String id, report_hit: true) -> [String, String]
        #: (String key, String lookup, String id, report_hit: bool) -> (String | [String, String])
        def cached_const(key, lookup, id, report_hit: false)
          cc = cache("cc", "ConstCache")
          cell = @l.layout("ConstCache")
          fast = @f.label
          slow = @f.label
          merge, (result, hit) = @f.block(report_hit ? %w[i64 i64] : ["i64"]) #: [String, [String, String]]
          same_key = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "key")), key)
          same_stamp = @f.icmp("eq", @f.fetch("i64", cc, off(cell, "stamp")), @f.fetch("i64", static("const_stamp")))
          @f.brif(@f.band(same_key, same_stamp), fast, slow)
          switch(fast)
          value = @f.fetch("i64", cc, off(cell, "value"))
          @f.jump(merge, report_hit ? [value, imm(1)] : [value])
          switch(slow)
          value = checked(kernel(lookup, cc, key, id))
          @f.jump(merge, report_hit ? [value, imm(0)] : [value])
          switch(merge)
          report_hit ? [result, hit] : result
        end

        # Set the line to the constant's location. A later incorrect
        # `class Name` reports it.
        #: (Hir::ConstWrite node) -> String
        def const_write(node)
          scope = scope_class(node.scope)
          v = expr(node.value)
          at_node(node)
          refinement_self_check
          checked(kernel("zr_const_set", scope, sym_word(node.name), v))
          v
        end

        # In a block, `self` can be a refinement (in a refine block). A
        # constant or a class variable written there warns, as setconstant
        # and setclassvariable do.
        #: () -> void
        def refinement_self_check
          kernel("zr_refinement_self_warn") if @kind == :block
        end
      end
    end
  end
end
