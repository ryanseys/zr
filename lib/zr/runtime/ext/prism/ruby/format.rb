# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

require_relative "diagnostics"

module Prism
  module Ruby
    module Diagnostics
      # The conversions diagnostic.c's formats use: %s and %.*s take bytes
      # (a String here, where C takes a length and a pointer), %.2s the
      # first two of them, %c a byte, %X and %02X a number in hexadecimal,
      # %d a number.
      CONVERSION = /%(?:\.\*s|\.(\d+)s|s|c|(0?)(\d*)X|d)/n

      # vsnprintf over a diagnostic's format: the message bytes.
      def self.format(template, arguments)
        arguments = arguments.dup
        template.b.gsub(CONVERSION) do |conversion|
          argument = arguments.shift
          case conversion
          when "%s", "%.*s" then argument.b
          when "%c" then argument.chr
          when "%d" then argument.to_s
          when /\A%\.(\d+)s\z/n then argument.b.byteslice(0, Integer($1))
          else
            digits = argument.to_s(16).upcase
            width = conversion[/\d+/].to_i
            digits.rjust(width, conversion.start_with?("%0") ? "0" : " ").b
          end
        end
      end
    end
  end
end
