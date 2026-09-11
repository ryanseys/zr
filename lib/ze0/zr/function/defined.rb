# frozen_string_literal: true

module Ze0
  module Zr
    class Function
      # `defined?`: the description String, or nil.
      module Defined
        NAMES = {
          local: "local-variable", ivar: "instance-variable", gvar: "global-variable", global: "global-variable",
          backref: "global-variable", attrasgn: "assignment", cvar: "class variable",
          const: "constant", method: "method", yield: "yield", super: "super", self: "self", nil: "nil",
          true: "true", false: "false", assignment: "assignment", expression: "expression"
        }.freeze

        private

        # The forms that ask at run time do so under a guard: a receiver
        # that raises means nil, as CRuby answers.
        def defined(node)
          return defined_name(node.kind) unless %i[ivar gvar backref cvar const method attrasgn yield super].include?(node.kind)

          guarded do
            test = defined_test(node)
            @f.csel(test, defined_name(node.kind), @qnil)
          end
        end

        def defined_test(node)
          case node.kind
          when :ivar then truth(kernel("zr_ivar_defined", @self, imm(sym_id(node.target))))
          when :gvar then truth(kernel("zr_gvar_defined", imm(sym_id(node.target))))
          when :backref then @f.icmp("ne", expr(node.target), @qnil)
          when :cvar
            at_line(node.line)
            truth(checked(kernel("zr_cvar_defined", @cref, imm(sym_id(node.target)))))
          when :const then const_defined(node.target)
          when :method, :attrasgn then method_defined(node.target)
          when :yield then @f.icmp("ne", @blk, @qnil)
          when :super then truth(kernel("zr_super_defined", @rec))
          else imm_bool(true)
          end
        end

        # Whether an expression used as a receiver or argument is itself
        # defined: a name asks its form; anything else is.
        def part_defined(node)
          case node
          when Hir::Send then defined_test(Hir::Defined.new(:method, node, node.line))
          when Hir::ConstRead then const_defined(node)
          when Hir::IvarRead then defined_test(Hir::Defined.new(:ivar, node.name, node.line))
          when Hir::GvarRead then defined_test(Hir::Defined.new(:gvar, node.name, node.line))
          when Hir::CvarRead then defined_test(Hir::Defined.new(:cvar, node.name, node.line))
          else imm_bool(true)
          end
        end

        def truth(value)
          @f.icmp("ne", value, imm(@l.const("QFALSE")))
        end

        def imm_bool(b)
          @f.iconst("i8", b ? 1 : 0)
        end

        def defined_name(kind)
          kernel("zr_str_frozen", @f.symbol_value(@f.symbol(@l.literal(NAMES.fetch(kind)))), imm(NAMES.fetch(kind).bytesize))
        end

        # A constant: through the scope when it is an expression, whose
        # own failure means nil.
        def const_defined(read)
          if read.scope.nil?
            truthy(kernel("zr_const_defined", @cref, imm(sym_id(read.name))))
          else
            scope = read.scope == :top ? global("G_OBJECT") : expr(read.scope)
            truthy(kernel("zr_const_defined_at", scope, imm(sym_id(read.name))))
          end
        end

        # A method: its receiver and arguments must be defined, then the
        # receiver is evaluated and its class asked. The tests short
        # circuit, so nothing after an undefined part runs.
        def method_defined(send)
          parts = [send.recv, *send.args].compact
          go = @f.label
          merge, (ok,) = @f.block(["i8"])
          parts.each do |part|
            next_test = @f.label
            fail = @f.label
            @f.brif(part_defined(part), next_test, fail)
            switch(fail)
            @f.jump(merge, [imm_bool(false)])
            switch(next_test)
          end
          recv = send.recv ? expr(send.recv) : @self
          explicit = imm_bool(!(send.recv.nil? || send.recv.is_a?(Hir::SelfRef)))
          @f.jump(merge, [truth(kernel("zr_method_defined", recv, imm(sym_id(send.name)), explicit))])
          switch(merge)
          ok
        end
      end
    end
  end
end
