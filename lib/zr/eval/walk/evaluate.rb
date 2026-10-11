# frozen_string_literal: true

require_relative "tree"

module Zr
  class Eval
    module Walk
      # Walks `source` in `scope` (the Binding of the calling frame), with
      # `self_` and `cref`. `block` is the block that a `yield` in the
      # string calls. `add` marks a `Binding#eval`: a new local of the
      # string becomes a local of the Binding, as in ruby.
      #
      # It reads the runtime only through `World`, so the tests run it on
      # CRuby over a `World` of plain Ruby (test/support/walk_world.rb).
      #: (untyped source, Binding scope, file: untyped, line: _ToInt, self_: untyped, cref: untyped, block: untyped, ?add: bool) -> untyped
      def self.evaluate(source, scope, file:, line:, self_:, cref:, block:, add: false)
        file = string(file)
        hir = built(string(source), file, line.to_int, scope)
        own = Tree::Scope.new(hir.locals)
        ctx = Tree::Ctx.new(self_: self_, cref: cref, chain: [own, *held(scope)], block: block,
                            name: nil, owner: nil, args: nil, kwargs: nil, tag: nil, home: nil, svars: nil)
        World.walk_enter
        value = begin
          Tree.new(file, scope).run(hir, ctx)
        ensure
          World.walk_leave
        end
        keep(scope, own) if add
        value
      rescue Hir::Invalid => e
        raise SyntaxError.new(e.message).tap { |syntax| syntax.set_backtrace(caller_locations(1)) }
      rescue SyntaxError => e
        e.set_backtrace(caller_locations(1)) unless e.backtrace == [e.path]
        raise e
      end

      # Builds the tree one scope inside the scopes of the frame, as the
      # eval compiler does. A write to a name that the frame has goes to the
      # frame. A new name stays in the scope of the string.
      #: (String source, String file, Integer line, Binding scope) -> Hir::Program
      def self.built(source, file, line, scope)
        # Hir only tests a name for membership, so a slot with no name
        # matches nothing.
        names = World.binding_scopes(scope) #: Array[Array[Symbol]]
        own = [] #: Array[Symbol]
        params = World.binding_parameters(scope)
        # The front end joins, splits and reads lines with ruby's defaults,
        # as the eval compiler's does (`Eval.plainly`); the walk itself runs
        # with the program's separators.
        Runtime.plain_separators do
          Runtime.compiling do
            Hir.build(source, file, eval_support: false, line: line, scopes: [*names.reverse, own], method: params)
          end
        end
      end

      # The scopes of the frame, innermost first, in the order of lookup.
      #: (Binding scope) -> Array[Tree::Held]
      def self.held(scope)
        World.binding_scopes(scope).each_with_index.map { |names, depth| Tree::Held.new(scope, depth, names) }
      end

      # `Binding#eval`: the new locals of the string become locals of the
      # Binding, so a later read there returns the value the string set.
      #: (Binding scope, Tree::Scope own) -> void
      def self.keep(scope, own)
        names = own.names.select { |name| name.to_s.match?(/\A[a-z_][A-Za-z0-9_]*\z/) }
        # The names that the Binding has not got yet go into one new scope
        # inside it first, so `local_variables` lists them before the
        # names of a `local_variable_set`, as in ruby.
        World.binding_push(scope, names.reject { |name| scope.local_variable_defined?(name) })
        names.each { |name| scope.local_variable_set(name, own.get(name)) }
      end

      # The argument as a String, as ruby converts it: a String, or an
      # object that responds to `to_str`.
      #: (untyped value) -> String
      def self.string(value)
        return value if value.is_a?(String)
        raise TypeError, "no implicit conversion of #{name_of(value)} into String" unless value.respond_to?(:to_str)

        value.to_str
      end

      #: (untyped value) -> String
      def self.name_of(value)
        value.nil? || value == true || value == false ? value.inspect : value.class.name.to_s
      end

      private_class_method :built, :held, :keep, :string, :name_of
    end
  end
end
