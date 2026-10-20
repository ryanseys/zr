# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

module Prism
  module Ruby
    # Ruby::Prism's C half (ruby's own prism/extension.c, built for the
    # Ruby::Prism namespace) over the port. The port makes Prism's objects,
    # as the prism gem's C half does. ruby's build of the same C makes the
    # objects of Ruby::Prism's classes of the same names. So each object of
    # a Prism class is made again as one of the Ruby::Prism class, with the
    # same instance variables and the same frozen state. An object that two
    # places share stays one object.
    module Import
      module_function

      # The value with each Prism object made again in `namespace`.
      def call(value, namespace) = import(value, namespace, {}.compare_by_identity)

      # Object#frozen?: a node of a string literal answers its own frozen?,
      # the literal's flag.
      def frozen?(value) = ::Kernel.instance_method(:frozen?).bind_call(value)

      def import(value, namespace, seen)
        return seen[value] if seen.key?(value)

        case value
        when Array
          copy = seen[value] = []
          value.each { |item| copy << import(item, namespace, seen) }
          frozen?(value) ? copy.freeze : copy
        when ::Prism::Node, ::Prism::Source, ::Prism::Location, ::Prism::Comment, ::Prism::MagicComment, ::Prism::ParseError,
             ::Prism::ParseWarning, ::Prism::Result, ::Prism::Token
          copy = seen[value] = namespace.const_get(value.class.name.delete_prefix("Prism::"), false).allocate
          value.instance_variables.each { |name| copy.instance_variable_set(name, import(value.instance_variable_get(name), namespace, seen)) }
          frozen?(value) ? copy.freeze : copy
        else
          value
        end
      end
    end
  end
end
