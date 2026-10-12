# frozen_string_literal: true

require_relative "node"

module Zr
  module Hir
    # What a def of the core library or of an extension declares about
    # itself. The lowering (`Lower::Function`) and the host's walker
    # (`Machine::Host::Walk`) read both from the def's body, so they give
    # the def one meaning.
    module CoreDef
      # The calls that set or read the caller's `$~` or `$_`.
      BACKREF_PRIMITIVES = %i[zr_backref_set zr_backref_get zr_lastline_set zr_lastline_get].freeze #: Array[Symbol]

      # The operators that a def marked `:sends_ops` sends by name, as
      # complex.c's f_add, f_sub, f_mul, f_quo and rb_funcall do: the
      # program's redefinition answers them.
      SENT_OPS = %i[+ - * / % ** -@ +@ quo fdiv].freeze #: Array[Symbol]

      # The sends that match, for an extension's def.
      MATCH_SENDS = %i[match =~ !~ scan sub gsub sub! gsub! partition rpartition].freeze #: Array[Symbol]

      # The leading `Primitive.attr! :name` statements of a def's body.
      # `:hidden` marks a helper that has no CRuby method; it has no
      # backtrace entry. `:ruby` marks a method that CRuby writes in Ruby.
      # `:sends_ops` marks a method whose operators on its values send by
      # name, so a redefined Integer#+ applies.
      # `:frameless` marks a method that ruby runs as an instruction: it is
      # listed as any method is, and has no backtrace entry.
      # `:more_args` marks a method that CRuby lets take any count: a call
      # with more arguments than its parameters take returns what the
      # receiver's private `more_args(name, *args)` gives, so the method
      # needs no rest parameter.
      #: (node? body) -> Array[Symbol]
      def self.attributes(body)
        # For a def with a `rescue` or `ensure`, read its protected body.
        body = body.body if body.is_a?(Begin)
        stmts = body.is_a?(Seq) ? body.stmts : [body]
        names = [] #: Array[Symbol]
        stmts.each { |stmt| names << (attribute_of(stmt) or break) }
        names
      end

      # The name in an attribute row, `Primitive.attr! :name`, or nil.
      #: (node? node) -> Symbol?
      def self.attribute_of(node)
        return unless node.is_a?(Send) && node.name == :attr!

        recv = node.recv
        arg = node.args.first
        return unless recv.is_a?(ConstRead) && recv.name == :Primitive && arg.is_a?(Literal)

        name = arg.value
        name if name.is_a?(Symbol)
      end

      # Whether a def keeps its matches in its own `$~`, so the program's
      # `$~` is left alone, as a C function's matches leave it: one marked
      # `Primitive.attr! :own_backref`, or one with a regexp literal that
      # neither sets nor reads the caller's `$~` or `$_` itself (those are
      # the methods that ruby defines to set them). An extension's def
      # also owns them when it matches by a call (Date's parsers match
      # with Regexps that constants hold).
      #: (node? body, extension: bool) -> bool
      def self.owns_backref?(body, extension:)
        return true if attributes(body).include?(:own_backref)

        matches(body, extension) == :own
      end

      # :own when `node` matches for its own work, :caller when it sets or
      # reads the caller's `$~` or `$_`, else nil. :caller wins.
      #: (node | Array[untyped] | nil node, bool extension) -> Symbol?
      def self.matches(node, extension)
        found = nil #: Symbol?
        case node
        when RegexpLit then found = :own
        when BackRef then return :caller
        when GvarRead then return :caller if %i[$~ $_].include?(node.name)
        when Send
          return :caller if node.recv.is_a?(ConstRead) && node.recv.name == :Primitive && BACKREF_PRIMITIVES.include?(node.name)

          found = :own if extension && MATCH_SENDS.include?(node.name)
        end
        Hir.each_child(node) do |child|
          next unless Hir.node?(child) || child.is_a?(Array)

          inner = matches(child, extension)
          return :caller if inner == :caller

          found ||= inner
        end
        found
      end
    end
  end
end
