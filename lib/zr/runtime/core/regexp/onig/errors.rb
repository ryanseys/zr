# frozen_string_literal: true

# Derived from Onigmo (BSD-2-Clause); see THIRD_PARTY_NOTICES.md.
#
# Onigmo's error codes and messages (onigmo.h, regerror.c), and the
# warnings its parser gives. A port under the BSD-2-Clause license
# reproduced in regexp.rb.
class Regexp
  module Onig
    # ONIGERR_*
    module Err
      MISMATCH = -1
      NO_SUPPORT_CONFIG = -2
      MEMORY = -5
      TYPE_BUG = -6
      PARSER_BUG = -11
      STACK_BUG = -12
      UNDEFINED_BYTECODE = -13
      UNEXPECTED_BYTECODE = -14
      MATCH_STACK_LIMIT_OVER = -15
      PARSE_DEPTH_LIMIT_OVER = -16
      DEFAULT_ENCODING_IS_NOT_SET = -21
      SPECIFIED_ENCODING_CANT_CONVERT_TO_WIDE_CHAR = -22
      TIMEOUT = -23
      INVALID_ARGUMENT = -30
      END_PATTERN_AT_LEFT_BRACE = -100
      END_PATTERN_AT_LEFT_BRACKET = -101
      EMPTY_CHAR_CLASS = -102
      PREMATURE_END_OF_CHAR_CLASS = -103
      END_PATTERN_AT_ESCAPE = -104
      END_PATTERN_AT_META = -105
      END_PATTERN_AT_CONTROL = -106
      META_CODE_SYNTAX = -108
      CONTROL_CODE_SYNTAX = -109
      CHAR_CLASS_VALUE_AT_END_OF_RANGE = -110
      CHAR_CLASS_VALUE_AT_START_OF_RANGE = -111
      UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS = -112
      TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED = -113
      TARGET_OF_REPEAT_OPERATOR_INVALID = -114
      NESTED_REPEAT_OPERATOR = -115
      UNMATCHED_CLOSE_PARENTHESIS = -116
      END_PATTERN_WITH_UNMATCHED_PARENTHESIS = -117
      END_PATTERN_IN_GROUP = -118
      UNDEFINED_GROUP_OPTION = -119
      INVALID_POSIX_BRACKET_TYPE = -121
      INVALID_LOOK_BEHIND_PATTERN = -122
      INVALID_REPEAT_RANGE_PATTERN = -123
      INVALID_CONDITION_PATTERN = -124
      TOO_BIG_NUMBER = -200
      TOO_BIG_NUMBER_FOR_REPEAT_RANGE = -201
      UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE = -202
      EMPTY_RANGE_IN_CHAR_CLASS = -203
      MISMATCH_CODE_LENGTH_IN_CLASS_RANGE = -204
      TOO_MANY_MULTI_BYTE_RANGES = -205
      TOO_SHORT_MULTI_BYTE_STRING = -206
      TOO_BIG_BACKREF_NUMBER = -207
      INVALID_BACKREF = -208
      NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED = -209
      TOO_MANY_CAPTURE_GROUPS = -210
      TOO_SHORT_DIGITS = -211
      TOO_LONG_WIDE_CHAR_VALUE = -212
      EMPTY_GROUP_NAME = -214
      INVALID_GROUP_NAME = -215
      INVALID_CHAR_IN_GROUP_NAME = -216
      UNDEFINED_NAME_REFERENCE = -217
      UNDEFINED_GROUP_REFERENCE = -218
      MULTIPLEX_DEFINED_NAME = -219
      MULTIPLEX_DEFINITION_NAME_CALL = -220
      NEVER_ENDING_RECURSION = -221
      GROUP_NUMBER_OVER_FOR_CAPTURE_HISTORY = -222
      INVALID_CHAR_PROPERTY_NAME = -223
      TOO_MANY_RANGE_REPEAT = -224
      TOO_MANY_NULL_CHECK = -225
      INVALID_CODE_POINT_VALUE = -400
      INVALID_WIDE_CHAR_VALUE = -400
      TOO_BIG_WIDE_CHAR_VALUE = -401
      NOT_SUPPORTED_ENCODING_COMBINATION = -402
      INVALID_COMBINATION_OF_OPTIONS = -403

      # onig_error_code_to_format: the text of each code; `%n` is the
      # name the error names.
      MESSAGES = {
        MISMATCH => "mismatch",
        NO_SUPPORT_CONFIG => "no support in this configuration",
        MEMORY => "failed to allocate memory",
        TYPE_BUG => "undefined type (bug)",
        PARSER_BUG => "internal parser error (bug)",
        STACK_BUG => "stack error (bug)",
        UNDEFINED_BYTECODE => "undefined bytecode (bug)",
        UNEXPECTED_BYTECODE => "unexpected bytecode (bug)",
        MATCH_STACK_LIMIT_OVER => "match-stack limit over",
        PARSE_DEPTH_LIMIT_OVER => "parse depth limit over",
        DEFAULT_ENCODING_IS_NOT_SET => "default multibyte-encoding is not set",
        INVALID_ARGUMENT => "invalid argument",
        END_PATTERN_AT_LEFT_BRACE => "end pattern at left brace",
        EMPTY_CHAR_CLASS => "empty char-class",
        PREMATURE_END_OF_CHAR_CLASS => "premature end of char-class",
        END_PATTERN_AT_ESCAPE => "end pattern at escape",
        END_PATTERN_AT_META => "end pattern at meta",
        END_PATTERN_AT_CONTROL => "end pattern at control",
        META_CODE_SYNTAX => "invalid meta-code syntax",
        CONTROL_CODE_SYNTAX => "invalid control-code syntax",
        CHAR_CLASS_VALUE_AT_END_OF_RANGE => "char-class value at end of range",
        UNMATCHED_RANGE_SPECIFIER_IN_CHAR_CLASS => "unmatched range specifier in char-class",
        TARGET_OF_REPEAT_OPERATOR_NOT_SPECIFIED => "target of repeat operator is not specified",
        TARGET_OF_REPEAT_OPERATOR_INVALID => "target of repeat operator is invalid",
        UNMATCHED_CLOSE_PARENTHESIS => "unmatched close parenthesis",
        END_PATTERN_WITH_UNMATCHED_PARENTHESIS => "end pattern with unmatched parenthesis",
        END_PATTERN_IN_GROUP => "end pattern in group",
        UNDEFINED_GROUP_OPTION => "undefined group option",
        INVALID_POSIX_BRACKET_TYPE => "invalid POSIX bracket type",
        INVALID_LOOK_BEHIND_PATTERN => "invalid pattern in look-behind",
        INVALID_REPEAT_RANGE_PATTERN => "invalid repeat range {lower,upper}",
        INVALID_CONDITION_PATTERN => "invalid conditional pattern",
        TOO_BIG_NUMBER => "too big number",
        TOO_BIG_NUMBER_FOR_REPEAT_RANGE => "too big number for repeat range",
        UPPER_SMALLER_THAN_LOWER_IN_REPEAT_RANGE => "upper is smaller than lower in repeat range",
        EMPTY_RANGE_IN_CHAR_CLASS => "empty range in char class",
        TOO_MANY_MULTI_BYTE_RANGES => "too many multibyte code ranges are specified",
        TOO_SHORT_MULTI_BYTE_STRING => "too short multibyte code string",
        INVALID_BACKREF => "invalid backref number/name",
        NUMBERED_BACKREF_OR_CALL_NOT_ALLOWED => "numbered backref/call is not allowed. (use name)",
        TOO_SHORT_DIGITS => "too short digits",
        TOO_LONG_WIDE_CHAR_VALUE => "too long wide-char value",
        EMPTY_GROUP_NAME => "group name is empty",
        INVALID_GROUP_NAME => "invalid group name <%n>",
        INVALID_CHAR_IN_GROUP_NAME => "invalid char in group name <%n>",
        UNDEFINED_NAME_REFERENCE => "undefined name <%n> reference",
        UNDEFINED_GROUP_REFERENCE => "undefined group <%n> reference",
        MULTIPLEX_DEFINED_NAME => "multiplex defined name <%n>",
        MULTIPLEX_DEFINITION_NAME_CALL => "multiplex definition name <%n> call",
        NEVER_ENDING_RECURSION => "never ending recursion",
        INVALID_CHAR_PROPERTY_NAME => "invalid character property name {%n}",
        TOO_MANY_RANGE_REPEAT => "too many range repeat",
        TOO_MANY_NULL_CHECK => "too many null check",
        TOO_MANY_CAPTURE_GROUPS => "too many capture groups are specified",
        INVALID_CODE_POINT_VALUE => "invalid code point value",
        TOO_BIG_WIDE_CHAR_VALUE => "too big wide-char value",
        NOT_SUPPORTED_ENCODING_COMBINATION => "not supported encoding combination",
        INVALID_COMBINATION_OF_OPTIONS => "invalid combination of options",
      }.freeze

      # The codes onig_error_code_to_str fills `%n` for.
      WITH_NAME = [
        UNDEFINED_NAME_REFERENCE, UNDEFINED_GROUP_REFERENCE, MULTIPLEX_DEFINED_NAME,
        MULTIPLEX_DEFINITION_NAME_CALL, INVALID_GROUP_NAME, INVALID_CHAR_IN_GROUP_NAME,
        INVALID_CHAR_PROPERTY_NAME,
      ].freeze

      MAX_ERROR_PAR_LEN = 50

      # onig_error_code_to_str: the message of `code`, with `par` (the
      # bytes the error names, in `enc`) written as to_ascii writes
      # them, cut at 47 bytes with "..." after.
      def self.text(code, par = nil, enc = nil)
        format = MESSAGES.fetch(code, "undefined error code")
        return format unless WITH_NAME.include?(code)

        name, over = to_ascii(par || "".b, enc, MAX_ERROR_PAR_LEN - 3)
        format.sub("%n") { name + (over ? "..." : "") }
      end

      # to_ascii: an encoding of one-byte characters copies the bytes as
      # they are, up to `size`; a wider one (UTF-16, UTF-32) writes each
      # character past ASCII as \xHHHH or \xHHHHHHHH, stopping at `size`.
      def self.to_ascii(par, enc, size)
        return [par.byteslice(0, size).b, par.bytesize > size] if enc.nil? || enc.min_len == 1

        buf = "".b
        p = 0
        e = par.bytesize
        while p < e
          code = enc.mbc_to_code(par, p, e)
          if code >= 0x80
            if code > 0xffff && buf.bytesize + 10 <= size
              buf << format("\\x%02x%02x%02x%02x", (code >> 24) & 0xff, (code >> 16) & 0xff, (code >> 8) & 0xff, code & 0xff)
            elsif buf.bytesize + 6 <= size
              buf << format("\\x%02x%02x", (code >> 8) & 0xff, code & 0xff)
            else
              break
            end
          else
            buf << code
          end
          p += enc.enclen(par, p, e)
          break if buf.bytesize >= size
        end
        [buf, p < e]
      end
    end

    # The exception the parser and compiler raise: an Onigmo error code
    # with the bytes it names. `message` is the text CRuby shows before
    # it appends the pattern.
    class Error < ::RegexpError
      attr_reader :code, :par

      def initialize(code, par = nil, enc = nil)
        @code = code
        @par = par
        super(Err.text(code, par, enc))
      end
    end

    # A failed compile with the warnings that the parser gave before it
    # failed, which ruby has printed by then (onig_syntax_warn writes as
    # the parser goes). Regexp raises a plain RegexpError after them.
    class Failure < ::RegexpError
      attr_reader :warnings

      def initialize(message, warnings)
        @warnings = warnings
        super(message)
      end
    end

    # The warnings the parser gives. Each is text CRuby writes through
    # rb_warn, with the pattern appended as onig_vsnprintf_with_pattern
    # appends it; `verbose` marks those given only when $VERBOSE is true
    # (the RTEST(ruby_verbose) checks in regparse.c).
    class Warnings
      Row = Struct.new(:text, :verbose)

      attr_reader :rows

      def initialize = @rows = []

      def add(text, verbose: false) = @rows << Row.new(text, verbose)
      def empty? = @rows.empty?
    end
  end
end
