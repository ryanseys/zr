# Onigmo's constants: the options, the Ruby syntax, the character
# types, the node and anchor kinds, and the limits. A port of the
# definitions in onigmo.h, regint.h, regparse.h and regparse.c:47-82
# of CRuby 4.0.7 (Onigmo 6.2.0), under the BSD-2-Clause license
# reproduced in regexp.rb.
class Regexp
  module Onig
    # ONIG_OPTION_*: compile-time options, then the search-time ones,
    # then the ctype range options the Ruby syntax turns on by default.
    module Option
      NONE = 0
      IGNORECASE = 1
      EXTEND = IGNORECASE << 1
      MULTILINE = EXTEND << 1
      DOTALL = MULTILINE
      SINGLELINE = MULTILINE << 1
      FIND_LONGEST = SINGLELINE << 1
      FIND_NOT_EMPTY = FIND_LONGEST << 1
      NEGATE_SINGLELINE = FIND_NOT_EMPTY << 1
      DONT_CAPTURE_GROUP = NEGATE_SINGLELINE << 1
      CAPTURE_GROUP = DONT_CAPTURE_GROUP << 1
      NOTBOL = CAPTURE_GROUP << 1
      NOTEOL = NOTBOL << 1
      NOTBOS = NOTEOL << 1
      NOTEOS = NOTBOS << 1
      ASCII_RANGE = NOTEOS << 1
      POSIX_BRACKET_ALL_RANGE = ASCII_RANGE << 1
      WORD_BOUND_ALL_RANGE = POSIX_BRACKET_ALL_RANGE << 1
      NEWLINE_CRLF = WORD_BOUND_ALL_RANGE << 1
    end

    # OnigSyntaxRuby, the one syntax ruby compiles with: its operator
    # bits (op), its second operator word (op2), its behavior bits and
    # its default options, with a predicate for each word.
    module Syntax
      # op
      OP_VARIABLE_META_CHARACTERS = 1 << 0
      OP_DOT_ANYCHAR = 1 << 1
      OP_ASTERISK_ZERO_INF = 1 << 2
      OP_ESC_ASTERISK_ZERO_INF = 1 << 3
      OP_PLUS_ONE_INF = 1 << 4
      OP_ESC_PLUS_ONE_INF = 1 << 5
      OP_QMARK_ZERO_ONE = 1 << 6
      OP_ESC_QMARK_ZERO_ONE = 1 << 7
      OP_BRACE_INTERVAL = 1 << 8
      OP_ESC_BRACE_INTERVAL = 1 << 9
      OP_VBAR_ALT = 1 << 10
      OP_ESC_VBAR_ALT = 1 << 11
      OP_LPAREN_SUBEXP = 1 << 12
      OP_ESC_LPAREN_SUBEXP = 1 << 13
      OP_ESC_AZ_BUF_ANCHOR = 1 << 14
      OP_ESC_CAPITAL_G_BEGIN_ANCHOR = 1 << 15
      OP_DECIMAL_BACKREF = 1 << 16
      OP_BRACKET_CC = 1 << 17
      OP_ESC_W_WORD = 1 << 18
      OP_ESC_LTGT_WORD_BEGIN_END = 1 << 19
      OP_ESC_B_WORD_BOUND = 1 << 20
      OP_ESC_S_WHITE_SPACE = 1 << 21
      OP_ESC_D_DIGIT = 1 << 22
      OP_LINE_ANCHOR = 1 << 23
      OP_POSIX_BRACKET = 1 << 24
      OP_QMARK_NON_GREEDY = 1 << 25
      OP_ESC_CONTROL_CHARS = 1 << 26
      OP_ESC_C_CONTROL = 1 << 27
      OP_ESC_OCTAL3 = 1 << 28
      OP_ESC_X_HEX2 = 1 << 29
      OP_ESC_X_BRACE_HEX8 = 1 << 30
      OP_ESC_O_BRACE_OCTAL = 1 << 31

      # op2
      OP2_ESC_CAPITAL_Q_QUOTE = 1 << 0
      OP2_QMARK_GROUP_EFFECT = 1 << 1
      OP2_OPTION_PERL = 1 << 2
      OP2_OPTION_RUBY = 1 << 3
      OP2_PLUS_POSSESSIVE_REPEAT = 1 << 4
      OP2_PLUS_POSSESSIVE_INTERVAL = 1 << 5
      OP2_CCLASS_SET_OP = 1 << 6
      OP2_QMARK_LT_NAMED_GROUP = 1 << 7
      OP2_ESC_K_NAMED_BACKREF = 1 << 8
      OP2_ESC_G_SUBEXP_CALL = 1 << 9
      OP2_ATMARK_CAPTURE_HISTORY = 1 << 10
      OP2_ESC_CAPITAL_C_BAR_CONTROL = 1 << 11
      OP2_ESC_CAPITAL_M_BAR_META = 1 << 12
      OP2_ESC_V_VTAB = 1 << 13
      OP2_ESC_U_HEX4 = 1 << 14
      OP2_ESC_GNU_BUF_ANCHOR = 1 << 15
      OP2_ESC_P_BRACE_CHAR_PROPERTY = 1 << 16
      OP2_ESC_P_BRACE_CIRCUMFLEX_NOT = 1 << 17
      OP2_ESC_H_XDIGIT = 1 << 19
      OP2_INEFFECTIVE_ESCAPE = 1 << 20
      OP2_ESC_CAPITAL_R_LINEBREAK = 1 << 21
      OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER = 1 << 22
      OP2_ESC_V_VERTICAL_WHITESPACE = 1 << 23
      OP2_ESC_H_HORIZONTAL_WHITESPACE = 1 << 24
      OP2_ESC_CAPITAL_K_KEEP = 1 << 25
      OP2_ESC_G_BRACE_BACKREF = 1 << 26
      OP2_QMARK_SUBEXP_CALL = 1 << 27
      OP2_QMARK_VBAR_BRANCH_RESET = 1 << 28
      OP2_QMARK_LPAREN_CONDITION = 1 << 29
      OP2_QMARK_CAPITAL_P_NAMED_GROUP = 1 << 30
      OP2_QMARK_TILDE_ABSENT = 1 << 31

      # behavior
      CONTEXT_INDEP_ANCHORS = 1 << 31
      CONTEXT_INDEP_REPEAT_OPS = 1 << 0
      CONTEXT_INVALID_REPEAT_OPS = 1 << 1
      ALLOW_UNMATCHED_CLOSE_SUBEXP = 1 << 2
      ALLOW_INVALID_INTERVAL = 1 << 3
      ALLOW_INTERVAL_LOW_ABBREV = 1 << 4
      STRICT_CHECK_BACKREF = 1 << 5
      DIFFERENT_LEN_ALT_LOOK_BEHIND = 1 << 6
      CAPTURE_ONLY_NAMED_GROUP = 1 << 7
      ALLOW_MULTIPLEX_DEFINITION_NAME = 1 << 8
      FIXED_INTERVAL_IS_GREEDY_ONLY = 1 << 9
      ALLOW_MULTIPLEX_DEFINITION_NAME_CALL = 1 << 10
      USE_LEFT_MOST_NAMED_GROUP = 1 << 11
      NOT_NEWLINE_IN_NEGATIVE_CC = 1 << 20
      BACKSLASH_ESCAPE_IN_CC = 1 << 21
      ALLOW_EMPTY_RANGE_IN_CC = 1 << 22
      ALLOW_DOUBLE_RANGE_OP_IN_CC = 1 << 23
      WARN_CC_OP_NOT_ESCAPED = 1 << 24
      WARN_REDUNDANT_NESTED_REPEAT = 1 << 25
      WARN_CC_DUP = 1 << 26

      GNU_REGEX_OP = OP_DOT_ANYCHAR | OP_BRACKET_CC | OP_POSIX_BRACKET | OP_DECIMAL_BACKREF |
                     OP_BRACE_INTERVAL | OP_LPAREN_SUBEXP | OP_VBAR_ALT |
                     OP_ASTERISK_ZERO_INF | OP_PLUS_ONE_INF | OP_QMARK_ZERO_ONE |
                     OP_ESC_AZ_BUF_ANCHOR | OP_ESC_CAPITAL_G_BEGIN_ANCHOR | OP_ESC_W_WORD |
                     OP_ESC_B_WORD_BOUND | OP_ESC_LTGT_WORD_BEGIN_END |
                     OP_ESC_S_WHITE_SPACE | OP_ESC_D_DIGIT | OP_LINE_ANCHOR
      GNU_REGEX_BV = CONTEXT_INDEP_ANCHORS | CONTEXT_INDEP_REPEAT_OPS |
                     CONTEXT_INVALID_REPEAT_OPS | ALLOW_INVALID_INTERVAL |
                     BACKSLASH_ESCAPE_IN_CC | ALLOW_DOUBLE_RANGE_OP_IN_CC

      # OnigSyntaxRuby (regparse.c:47-82), as CRuby builds it: no \uHHHH
      # (RUBY is defined) and no \< \>.
      RUBY_OP = (GNU_REGEX_OP | OP_QMARK_NON_GREEDY | OP_ESC_OCTAL3 | OP_ESC_X_HEX2 |
                 OP_ESC_X_BRACE_HEX8 | OP_ESC_CONTROL_CHARS | OP_ESC_C_CONTROL) & ~OP_ESC_LTGT_WORD_BEGIN_END
      RUBY_OP2 = OP2_QMARK_GROUP_EFFECT | OP2_OPTION_RUBY | OP2_QMARK_LT_NAMED_GROUP |
                 OP2_ESC_K_NAMED_BACKREF | OP2_ESC_G_SUBEXP_CALL | OP2_ESC_P_BRACE_CHAR_PROPERTY |
                 OP2_ESC_P_BRACE_CIRCUMFLEX_NOT | OP2_PLUS_POSSESSIVE_REPEAT | OP2_CCLASS_SET_OP |
                 OP2_ESC_CAPITAL_C_BAR_CONTROL | OP2_ESC_CAPITAL_M_BAR_META | OP2_ESC_V_VTAB |
                 OP2_ESC_H_XDIGIT | OP2_ESC_CAPITAL_X_EXTENDED_GRAPHEME_CLUSTER |
                 OP2_QMARK_LPAREN_CONDITION | OP2_ESC_CAPITAL_R_LINEBREAK |
                 OP2_ESC_CAPITAL_K_KEEP | OP2_QMARK_TILDE_ABSENT
      RUBY_BV = GNU_REGEX_BV | ALLOW_INTERVAL_LOW_ABBREV | DIFFERENT_LEN_ALT_LOOK_BEHIND |
                CAPTURE_ONLY_NAMED_GROUP | ALLOW_MULTIPLEX_DEFINITION_NAME |
                FIXED_INTERVAL_IS_GREEDY_ONLY | WARN_CC_OP_NOT_ESCAPED | WARN_CC_DUP |
                WARN_REDUNDANT_NESTED_REPEAT
      RUBY_OPTIONS = Option::ASCII_RANGE | Option::POSIX_BRACKET_ALL_RANGE | Option::WORD_BOUND_ALL_RANGE

      # The meta characters: only the escape is in effect.
      ESC = 0x5c

      def self.op?(bit) = (RUBY_OP & bit) != 0
      def self.op2?(bit) = (RUBY_OP2 & bit) != 0
      def self.bv?(bit) = (RUBY_BV & bit) != 0
    end

    # ONIGENC_CTYPE_*
    module CType
      NEWLINE = 0
      ALPHA = 1
      BLANK = 2
      CNTRL = 3
      DIGIT = 4
      GRAPH = 5
      LOWER = 6
      PRINT = 7
      PUNCT = 8
      SPACE = 9
      UPPER = 10
      XDIGIT = 11
      WORD = 12
      ALNUM = 13
      ASCII = 14
      MAX_STD = ASCII
    end

    # ANCHOR_* (regint.h)
    module Anchor
      BEGIN_BUF = 1 << 0
      BEGIN_LINE = 1 << 1
      BEGIN_POSITION = 1 << 2
      END_BUF = 1 << 3
      SEMI_END_BUF = 1 << 4
      END_LINE = 1 << 5
      WORD_BOUND = 1 << 6
      NOT_WORD_BOUND = 1 << 7
      WORD_BEGIN = 1 << 8
      WORD_END = 1 << 9
      PREC_READ = 1 << 10
      PREC_READ_NOT = 1 << 11
      LOOK_BEHIND = 1 << 12
      LOOK_BEHIND_NOT = 1 << 13
      ANYCHAR_STAR = 1 << 14
      ANYCHAR_STAR_ML = 1 << 15
      KEEP = 1 << 16
      ANYCHAR_STAR_MASK = ANYCHAR_STAR | ANYCHAR_STAR_ML
      END_BUF_MASK = END_BUF | SEMI_END_BUF
    end

    # ENCLOSE_* (regparse.h)
    module Enclose
      MEMORY = 1 << 0
      OPTION = 1 << 1
      STOP_BACKTRACK = 1 << 2
      CONDITION = 1 << 3
      ABSENT = 1 << 4
    end

    # NST_*: the status bits of enclose, quantifier, backref and call nodes.
    module Status
      MIN_FIXED = 1 << 0
      MAX_FIXED = 1 << 1
      CLEN_FIXED = 1 << 2
      MARK1 = 1 << 3
      MARK2 = 1 << 4
      MEM_BACKREFED = 1 << 5
      STOP_BT_SIMPLE_REPEAT = 1 << 6
      RECURSION = 1 << 7
      CALLED = 1 << 8
      ADDR_FIXED = 1 << 9
      NAMED_GROUP = 1 << 10
      NAME_REF = 1 << 11
      IN_REPEAT = 1 << 12
      NEST_LEVEL = 1 << 13
      BY_NUMBER = 1 << 14
    end

    # NQ_TARGET_*: what a quantifier knows about its target's emptiness.
    module TargetEmpty
      ISNOT_EMPTY = 0
      IS_EMPTY = 1
      IS_EMPTY_MEM = 2
      IS_EMPTY_REC = 3
    end

    # NSTR_*: string node flags.
    module StrFlag
      RAW = 1 << 0
      AMBIG = 1 << 1
      DONT_GET_OPT_INFO = 1 << 2
    end

    REPEAT_INFINITE = -1
    INFINITE_DISTANCE = (1 << 64) - 1

    MAX_CAPTURE_GROUP_NUM = 32767
    MAX_BACKREF_NUM = 1000
    MAX_REPEAT_NUM = 100_000
    MAX_MULTI_BYTE_RANGES_NUM = 10_000
    MAX_ERROR_MESSAGE_LEN = 90
    MAX_CAPTURE_HISTORY_GROUP = 31
    PARSE_DEPTH_LIMIT = 4096
    NODE_BACKREFS_SIZE = 6
    OPT_EXACT_MAXLEN = 24
    BIT_STATUS_BITS_NUM = 32
    INT_MAX_LIMIT = (1 << 31) - 1
    LAST_CODE_POINT = 0xFFFF_FFFF
    CHAR_TABLE_SIZE = 256
    CASE_FOLD_MULTI_CHAR = 1 << 30
    CASE_FOLD_DEFAULT = CASE_FOLD_MULTI_CHAR

    # BIT_STATUS_AT and friends: a group number past 31 folds onto bit 0.
    def self.bit_status_at?(stats, n) = n < BIT_STATUS_BITS_NUM ? (stats & (1 << n)) != 0 : (stats & 1) != 0
    def self.bit_status_on_at(stats, n) = n < BIT_STATUS_BITS_NUM ? stats | (1 << n) : stats | 1
    def self.bit_status_on_at_simple(stats, n) = n < BIT_STATUS_BITS_NUM ? stats | (1 << n) : stats

    # The saturating arithmetic of distances (regcomp.c distance_add and
    # distance_multiply).
    def self.distance_add(d1, d2)
      return INFINITE_DISTANCE if d1 == INFINITE_DISTANCE || d2 == INFINITE_DISTANCE

      d1 < INFINITE_DISTANCE - d2 ? d1 + d2 : INFINITE_DISTANCE
    end

    def self.distance_multiply(d, m)
      return 0 if m == 0

      d < INFINITE_DISTANCE / m ? d * m : INFINITE_DISTANCE
    end
  end
end
