# frozen_string_literal: true

module Zr
  class Lower
    class Function
      # `defined?`: the description String, or nil.
      module Defined
        # @type instance: Function

        NAMES = {
          local: "local-variable", ivar: "instance-variable", gvar: "global-variable", global: "global-variable",
          backref: "global-variable", attrasgn: "method", cvar: "class variable",
          const: "constant", method: "method", yield: "yield", super: "super", self: "self", nil: "nil",
          true: "true", false: "false", assignment: "assignment", expression: "expression", list: "expression"
        }.freeze #: Hash[Symbol, String]

        private

        # The forms whose test raises nothing, so they need no guard. An
        # instance variable is one of them: its only error (a read of a
        # non-shareable object outside the main ractor) must reach the
        # program, not become nil.
        PLAIN = %i[ivar gvar backref yield].freeze #: Array[Symbol]

        # The forms with a run-time test use a guard: if the receiver
        # raises, the result is nil, as in CRuby.
        #: (Hir::Defined node) -> String
        def defined(node)
          return defined_name(node.kind) unless %i[ivar gvar backref cvar const method attrasgn yield super list].include?(node.kind)
          return @f.csel(defined_test(node), defined_name(node.kind), @qnil) if PLAIN.include?(node.kind)

          guarded do
            test = defined_test(node)
            @f.csel(test, defined_name(node.kind), @qnil)
          end
        end

        #: (Hir::Defined node) -> String
        def defined_test(node)
          case node.kind
          when :ivar then truth(checked(kernel("zr_ivar_defined", @self, sym_word(ivar_name(node.target)))))
          when :gvar then truth(kernel("zr_gvar_defined", sym_word(node.target)))
          when :backref then @f.icmp("ne", expr(node.target), @qnil)
          when :cvar
            at_node(node)
            truth(checked(kernel("zr_cvar_defined", @cref, sym_word(node.target))))
          when :const then const_defined(node.target)
          when :method, :attrasgn then method_defined(node.target)
          when :list then all_defined(node.target) { imm_bool(true) }
          when :yield then @f.icmp("ne", @blk, @qnil)
          when :super then truth(kernel("zr_super_defined", @rec))
          else imm_bool(true)
          end
        end

        # Whether an expression used as a receiver or argument is itself
        # defined. A name is tested by its form. All other expressions are
        # defined.
        #: (untyped node) -> String
        def part_defined(node)
          case node
          when Hir::Send then defined_test(Hir::Defined.new(:method, node, node.line))
          when Hir::ArrayLit then all_defined(node.elements) { imm_bool(true) }
          when Hir::HashLit then all_defined(node.pairs.compact.map { |p| p.is_a?(Hir::HashSplat) ? p.value : p }) { imm_bool(true) }
          when Hir::ConstRead then const_defined(node)
          when Hir::IvarRead then defined_test(Hir::Defined.new(:ivar, node.name, node.line))
          when Hir::GvarRead then defined_test(Hir::Defined.new(:gvar, node.name, node.line))
          when Hir::CvarRead then defined_test(Hir::Defined.new(:cvar, node.name, node.line))
          else imm_bool(true)
          end
        end

        #: (String value) -> String
        def truth(value)
          @f.icmp("ne", value, imm(@l.const("QFALSE")))
        end

        #: (bool b) -> String
        def imm_bool(b)
          @f.iconst("i8", b ? 1 : 0)
        end

        #: (Symbol kind) -> String
        def defined_name(kind)
          kernel("zr_str_frozen", @f.symbol_value(@f.symbol(@l.literal(NAMES.fetch(kind)))), imm(NAMES.fetch(kind).bytesize))
        end

        # A constant: looked up through its scope if the scope is an
        # expression. If the scope fails, the result is nil.
        #: (Hir::ConstRead read) -> String
        def const_defined(read)
          if read.scope.nil?
            truthy(kernel("zr_const_defined", @cref, sym_word(read.name)))
          else
            scope = read.scope == :top ? global("G_OBJECT") : expr(read.scope)
            truthy(kernel("zr_const_defined_at", scope, sym_word(read.name)))
          end
        end

        # A method: its receiver and arguments must be defined. Then the
        # receiver is evaluated and its class is checked.
        #
        # Any receiver, also `self`, makes the call explicit. `defined?`
        # checks whether `self.helper` can be called as written, and a
        # private `helper` cannot. A private writer also cannot, although a
        # call of `self.x = v` can call one.
        #
        # As compile.c's defined_expr, the arguments are tested first, then
        # the receiver, and a receiver is evaluated once. `keep` is a record
        # slot that gets the receiver's value, for a caller that sends to it.
        #: (Hir::Send send, ?Integer? keep) -> String
        def method_defined(send, keep = nil)
          all_defined(send.args.compact) do
            next truth(kernel("zr_method_defined", @self, sym_word(send.name), imm_bool(false))) unless send.recv

            with_receiver(send.recv) do |recv|
              @f.store(recv, @rec, value_offset(keep)) if keep
              truth(kernel("zr_method_defined", recv, sym_word(send.name), imm_bool(true)))
            end
          end
        end

        # If the receiver `node` is defined, returns the block's value for
        # the receiver's value. A call on a receiver of its own runs once,
        # on the receiver that its test evaluated.
        #: (untyped node) { (String) -> String } -> String
        def with_receiver(node)
          merge, (ok,) = @f.block(["i8"]) #: [String, [String]]
          yes = @f.label
          no = @f.label
          base = @sp
          kept = node.is_a?(Hir::Send) && node.recv && !node.recv.is_a?(Hir::SelfRef) && !node.safe
          slot = reserve(1) if kept
          @f.brif(kept ? method_defined(node, slot) : part_defined(node), yes, no)
          switch(no)
          @f.jump(merge, [imm_bool(false)])
          switch(yes)
          value = if kept
                    call(Hir::Send.of(Hir::Slot.new(slot, node.line), node.name, node.args, node.line,
                                      opt: node.opt, block: node.block, kwargs: node.kwargs, write: node.write, using: node.using))
                  else
                    expr(node)
                  end
          @f.jump(merge, [yield(value)])
          switch(merge)
          @sp = base
          ok
        end

        # If every part is defined, returns the block's value. The tests
        # short-circuit, so nothing after an undefined part runs.
        #: (Array[untyped] parts) { () -> String } -> String
        def all_defined(parts)
          merge, (ok,) = @f.block(["i8"]) #: [String, [String]]
          parts.each do |part|
            next_test = @f.label
            fail = @f.label
            @f.brif(part_defined(part), next_test, fail)
            switch(fail)
            @f.jump(merge, [imm_bool(false)])
            switch(next_test)
          end
          @f.jump(merge, [yield])
          switch(merge)
          ok
        end
      end
    end
  end
end
