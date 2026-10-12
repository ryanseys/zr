# frozen_string_literal: true

module Zr
  module Dev
    module Fuzz
      # The differences from ruby that zr has on purpose
      # (docs/reference/differences-from-ruby.md). A failure that matches
      # one is counted as `known` and not reported.
      #
      # A rule reads only the verdict, never the program: a program that
      # names `methods` or `ObjectSpace` can still show a real gap. The
      # generator stays away from the forms whose output differs on
      # purpose (the order of a list of names, heap details, the
      # platform), so their rules are not needed here.
      module Known
        # Each row: the kinds it covers, a pattern of the verdict's key or
        # detail, and the reason.
        RULES = [
          [%w[unimplemented exception-diff output-diff],
           /InstructionSequence#(?:disasm|disassemble|to_a|to_binary|each_child|trace_points)/,
           "zr has no YARV bytecode (differences-from-ruby.md, Refusals)"],
          [%w[unimplemented exception-diff], /Coverage.*eval|eval.*Coverage/, "no coverage of eval code (Refusals)"],
          [%w[exception-diff output-diff], /stack level too deep|SystemStackError|levels\.\.\./,
           "zr recurses deeper before SystemStackError (Details)"],
          [%w[output-diff], /arm64-darwin|aarch64-linux-musl/, "the platform of the target (Details)"]
        ].freeze

        module_function

        # The reason when `verdict` is a known difference, else nil.
        def reason(verdict)
          RULES.each do |kinds, pattern, why|
            next unless kinds.include?(verdict.kind)
            return why if pattern.match?(verdict.key.to_s) || pattern.match?(verdict.detail.to_s)
          end
          nil
        end
      end
    end
  end
end
