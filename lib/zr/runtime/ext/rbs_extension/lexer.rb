# frozen_string_literal: true

require "strscan"

module RBS
  class Parser
    # rbs's lexer (src/lexer.re and src/lexstate.c), in Ruby.
    #
    # re2c makes a DFA from lexer.re that reads one character at a time and
    # takes the longest match; of two rules that match the same length, the
    # first rule in the file wins. This lexer gives the same tokens: at
    # each position, it finds the length of every rule that can start with
    # the character, and keeps the longest.
    #
    # The C reads code points, but a rule tests a code point only for
    # being ASCII, being an invalid byte (U+FFFD), or being another
    # character. So the lexer reads a copy of the input where each
    # character is one byte: an ASCII character is itself, another valid
    # character is 0x80, and a byte that is not valid in the encoding is
    # 0x81. A position in the copy is a character position, as the C
    # counts them. For an input that has characters of more than one
    # byte, `extra` records where they are, to find the byte position of a
    # character position.
    class Lexer
      # One token: its type (the name in rbs_token_type_str, as a Symbol),
      # the character positions of its start and end, and the line of its
      # start (1 is the first line).
      Lexeme = Struct.new(:type, :start, :end, :line)

      NULL_TOKEN = Lexeme.new(:NullType, 0, 0, 0).freeze

      KEYWORDS = {
        "alias" => :kALIAS, "attr_accessor" => :kATTRACCESSOR, "attr_reader" => :kATTRREADER,
        "attr_writer" => :kATTRWRITER, "bool" => :kBOOL, "bot" => :kBOT, "class" => :kCLASS, "def" => :kDEF,
        "end" => :kEND, "extend" => :kEXTEND, "false" => :kFALSE, "in" => :kIN, "include" => :kINCLUDE,
        "instance" => :kINSTANCE, "interface" => :kINTERFACE, "module" => :kMODULE, "nil" => :kNIL,
        "out" => :kOUT, "prepend" => :kPREPEND, "private" => :kPRIVATE, "public" => :kPUBLIC, "self" => :kSELF,
        "singleton" => :kSINGLETON, "top" => :kTOP, "true" => :kTRUE, "type" => :kTYPE,
        "unchecked" => :kUNCHECKED, "untyped" => :kUNTYPED, "void" => :kVOID, "use" => :kUSE, "as" => :kAS,
        "__todo__" => :k__TODO__, "skip" => :kSKIP, "return" => :kRETURN
      }.freeze

      # The keywords with a `-`, which no identifier run contains.
      DASHED = { "class-alias" => :kCLASSALIAS, "module-alias" => :kMODULEALIAS, "module-self" => :kMODULESELF }.freeze

      # The tokens of one character that start no longer rule.
      SINGLE = {
        "(" => :pLPAREN, ")" => :pRPAREN, "]" => :pRBRACKET, "{" => :pLBRACE, "}" => :pRBRACE,
        "," => :pCOMMA, "|" => :pBAR, "^" => :pHAT, "&" => :pAMP, "?" => :pQUESTION, "/" => :tOPERATOR, "~" => :tOPERATOR
      }.transform_keys(&:ord).freeze

      # `operator`, `"=>"`, `"="`, `"<"` and `">"` after a `=`, `<`, `>` or `!`:
      # the longest first, and a punctuation token before an operator of
      # the same text.
      AFTER_EQ = [["===", :tOPERATOR], ["==", :tOPERATOR], ["=~", :tOPERATOR], ["=>", :pFATARROW], ["=", :pEQ]].freeze
      AFTER_LT = [["<=>", :tOPERATOR], ["<<", :tOPERATOR], ["<=", :tOPERATOR], ["<", :pLT]].freeze
      AFTER_GT = [[">=", :tOPERATOR], [">>", :tOPERATOR], [">", :pGT]].freeze
      AFTER_BANG = [["!=", :tOPERATOR], ["!~", :tOPERATOR], ["!", :tOPERATOR]].freeze

      SYMBOL_OPERATORS = %w[
        :| :& :/ :% :~ :` :^ :== :=~ :=== :! :!= :!~ :< :<= :<< :<=> :> :>= :>> :- :-@ :+ :+@ :* :** :[] :[]=
      ].sort_by { -it.bytesize }.freeze

      IDENT_RUN = /[A-Za-z0-9_\x80]*/n
      INTEGER = /[-+]?[0-9][0-9_]*/n
      DQSTRING = /"(?:\\u\h{4}|\\x[0-9a-f]|\\[^xu]|[^\\"])*+"/n
      QIDENT = /`[^ :][^`]*`/n
      COMMENT = /#[^\n\x81]*/n
      SYMBOL = /:@{0,2}[A-Za-z_\x80][A-Za-z0-9_\x80]*[!?=]?/n
      ANNOTATION = /%a(?:\{[^}]*\}|\([^)]*\)|\[[^\]]*\]|\|[^|]*\||<[^>]*>)/n
      BLANKS = /[ \t]+/n
      DIGITS = /[0-9]+/n
      GLOBAL_DASH = /-[a-zA-Z0-9_]/n
      GLOBAL_PUNCT = /[~*$?!@\\\/;,.=:<>"&'`+]/n
      GLOBAL_RUN = /[^ \t\r\n:;=.,!"$%&()*+~|\\'\[\]{}\/<>^]+/n
      private_constant :SINGLE, :AFTER_EQ, :AFTER_LT, :AFTER_GT, :AFTER_BANG, :SYMBOL_OPERATORS, :IDENT_RUN, :INTEGER,
                       :DQSTRING, :QIDENT, :COMMENT, :SYMBOL, :ANNOTATION, :BLANKS, :DIGITS, :GLOBAL_DASH, :GLOBAL_PUNCT,
                       :GLOBAL_RUN

      # One valid character of two to four bytes (the DFA of rbs_encoding.c).
      UTF8_CHAR = /[\xC2-\xDF][\x80-\xBF]|\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|
                   \xED[\x80-\x9F][\x80-\xBF]|\xF0[\x90-\xBF][\x80-\xBF]{2}|[\xF1-\xF3][\x80-\xBF]{3}|\xF4[\x80-\x8F][\x80-\xBF]{2}/xn
      private_constant :UTF8_CHAR

      attr_reader :string, :encoding

      # rbs_lexer_new: a lexer of `string`'s bytes up to `end_pos`, which
      # starts at byte `start_pos`. It raises ArgumentError when
      # `start_pos` is inside a character.
      def initialize(string, start_pos, end_pos)
        @string = string
        @encoding = string.encoding
        @extra = []
        @chars = characters(string, end_pos)
        @scanner = StringScanner.new(@chars)
        @size = @chars.bytesize
        @line = 1
        @first_of_line = true
        @newline = @chars.index("\n") || @size
        @pos = char_at(start_pos)
        raise ArgumentError, "position range starts inside a character: #{start_pos}...#{end_pos}" unless @pos

        skip_lines(@pos)
      end

      # The bytes between two character positions of the input.
      def bytes(start, stop)
        from = byte_at(start)
        @string.byteslice(from, byte_at(stop) - from)
      end

      def byte_at(char)
        return char if @extra.empty?

        index = @extra.bsearch_index { |at, _| at >= char } || @extra.size
        index.zero? ? char : char + @extra[index - 1][1]
      end

      # rbs_lexer_next_token.
      def next_token
        start = @pos
        type, length = token_at(start)
        stop = start + length
        line = @line
        skip_lines(stop)
        if type == :tTRIVIA
          @first_of_line = true if @chars.getbyte(start) == 0x0A
        else
          @first_of_line = false
        end
        @pos = stop
        Lexeme.new(type, start, stop, line)
      end

      private

      # The type and the length of the token at `at`, as lexer.re's rules
      # give them.
      def token_at(at)
        c = @chars.getbyte(at)
        return [:pEOF, 0] if c.nil?
        if (type = SINGLE[c]) then return [type, 1] end

        case c
        when 0x20, 0x09 then [:tTRIVIA, scan(BLANKS, at)]
        when 0x0A, 0x0D then [:tTRIVIA, 1]
        when 0x5B then bracket(at)
        when 0x2A then text?("**", at) ? [:pSTAR2, 2] : [:pSTAR, 1]
        when 0x2E then text?("...", at) ? [:pDOT3, 3] : [:pDOT, 1]
        when 0x60 then (length = scan(QIDENT, at)) ? [:tQIDENT, length] : [:tOPERATOR, 1]
        when 0x2D then minus(at)
        when 0x2B then plus(at)
        when 0x3D then longest_text(AFTER_EQ, at)
        when 0x3C then longest_text(AFTER_LT, at)
        when 0x3E then longest_text(AFTER_GT, at)
        when 0x21 then longest_text(AFTER_BANG, at)
        when 0x25 then (length = scan(ANNOTATION, at)) ? [:tANNOTATION, length] : [:tOPERATOR, 1]
        when 0x30..0x39 then [:tINTEGER, scan(INTEGER, at)]
        when 0x23 then comment(at)
        when 0x22 then (length = scan(DQSTRING, at)) ? [:tDQSTRING, length] : [:ErrorToken, 1]
        when 0x27 then (length = sqstring(at)) ? [:tSQSTRING, length] : [:ErrorToken, 1]
        when 0x3A then colon(at)
        when 0x40 then at_sign(at)
        when 0x24 then (length = global(at + 1)) ? [:tGIDENT, length + 1] : [:ErrorToken, 1]
        when 0x41..0x5A, 0x61..0x7A, 0x5F, 0x80 then word(c, at)
        else [:ErrorToken, 1]
        end
      end

      def bracket(at)
        if text?("[]=", at) then [:tOPERATOR, 3]
        elsif text?("[]", at) then [:pAREF_OPR, 2]
        else [:pLBRACKET, 1]
        end
      end

      # `->`, `-@`, `-`, an inline comment `--...` (to the end of the
      # input) and a negative integer.
      def minus(at)
        return [:tINLINECOMMENT, @size - at] if text?("--", at)
        return [:pARROW, 2] if text?("->", at)
        return [:tINTEGER, scan(INTEGER, at)] if digit?(at + 1)

        text?("-@", at) ? [:tOPERATOR, 2] : [:tOPERATOR, 1]
      end

      def plus(at)
        return [:tINTEGER, scan(INTEGER, at)] if digit?(at + 1)

        text?("+@", at) ? [:tOPERATOR, 2] : [:tOPERATOR, 1]
      end

      # A comment runs to the end of the line, or to a byte that is no
      # character. It leaves the CR of a CRLF for a trivia token.
      def comment(at)
        length = scan(COMMENT, at)
        length -= 1 if @chars.getbyte(at + length) == 0x0A && @chars.getbyte(at + length - 1) == 0x0D
        [@first_of_line ? :tLINECOMMENT : :tCOMMENT, length]
      end

      # A sqstring is `'` and `'` around characters where each `'` follows
      # a `\`, and a `\` is a character too: the longest match ends at the
      # last `'` that a valid body reaches.
      def sqstring(at)
        return nil unless @chars.getbyte(at) == 0x27

        last = nil
        from = at + 1
        while (quote = @chars.index("'", from))
          last = quote
          break unless quote > at + 1 && @chars.getbyte(quote - 1) == 0x5C

          from = quote + 1
        end
        last && last + 1 - at
      end

      def colon(at)
        best = [:pCOLON, 1]
        best = [:pCOLON2, 2] if text?("::", at)
        if (length = scan(DQSTRING, at + 1)) && length + 1 > best[1] then best = [:tDQSYMBOL, length + 1] end
        if (length = sqstring(at + 1)) && length + 1 > best[1] then best = [:tSQSYMBOL, length + 1] end
        length = scan(SYMBOL, at)
        length = global(at + 2)&.+(2) if length.nil? && text?(":$", at)
        operator = SYMBOL_OPERATORS.find { text?(it, at) }
        length = [length || 0, operator&.bytesize || 0].max
        length > best[1] ? [:tSYMBOL, length] : best
      end

      # `@rbs`, an instance variable and a class variable.
      def at_sign(at)
        if @chars.getbyte(at + 1) == 0x40
          start = at + 2
          type = :tA2IDENT
        else
          start = at + 1
          type = :tAIDENT
        end
        return [:ErrorToken, 1] unless ident_start?(start)

        length = start - at + scan(IDENT_RUN, start)
        length == 4 && text?("@rbs", at) ? [:kATRBS, 4] : [type, length]
      end

      # The length of `global_ident` at `at`, the longest of its four
      # forms, or nil.
      def global(at)
        length = [scan(DIGITS, at), scan(GLOBAL_DASH, at), scan(GLOBAL_PUNCT, at), scan(GLOBAL_RUN, at)].compact.max
        length&.nonzero?
      end

      # An identifier or a keyword: a keyword wins over an identifier of
      # its length, and an identifier that a `!` or a `=` follows is longer.
      def word(c, at)
        run = 1 + scan(IDENT_RUN, at + 1)
        text = @chars.byteslice(at, run)
        type = KEYWORDS[text] || ident_type(c, at, run)
        best = [type, run]
        DASHED.each { |word, keyword| best = [keyword, word.bytesize] if text?(word, at) }
        case @chars.getbyte(at + run)
        when 0x21 then best = [:tBANGIDENT, run + 1] if run + 1 > best[1]
        when 0x3D then best = [:tEQIDENT, run + 1] if run + 1 > best[1]
        end
        best
      end

      def ident_type(c, at, run)
        case c
        when 0x61..0x7A then :tLIDENT
        when 0x41..0x5A then :tUIDENT
        when 0x80 then :tNONASCIIIDENT
        else
          case @chars.getbyte(at + 1)
          when 0x61..0x7A, 0x30..0x39, 0x5F then :tULLIDENT
          when 0x41..0x5A then :tULIDENT
          else run == 1 ? :tULLIDENT : :tNONASCIIIDENT
          end
        end
      end

      def longest_text(rules, at)
        rules.each { |text, type| return [type, text.bytesize] if text?(text, at) }
      end

      def text?(text, at) = @chars.byteslice(at, text.bytesize) == text
      def digit?(at) = (0x30..0x39).cover?(@chars.getbyte(at))
      def ident_start?(at) = (c = @chars.getbyte(at)) && (c == 0x5F || c == 0x80 || (0x41..0x5A).cover?(c) || (0x61..0x7A).cover?(c))

      def scan(pattern, at)
        @scanner.pos = at
        @scanner.match?(pattern)
      end

      # rbs_skip's line count: the line of position `to`.
      def skip_lines(to)
        while @newline < to
          @line += 1
          @newline = @chars.index("\n", @newline + 1) || @size
        end
      end

      # The character position of byte `byte`, or nil when it is inside a
      # character or past the input.
      def char_at(byte)
        return (byte if byte <= @size) if @extra.empty?

        char = (0..@size).bsearch { byte_at(it) >= byte }
        char if char && byte_at(char) == byte
      end

      # The input up to the first character that ends at or past
      # `end_pos`, one byte for each character.
      def characters(string, end_pos)
        bytes = string.b
        stop = [end_pos, bytes.bytesize].min
        return bytes.byteslice(0, stop) if bytes.ascii_only?

        utf8 = @encoding == Encoding::UTF_8
        chars = +"".b
        scanner = StringScanner.new(bytes)
        extra = 0
        while scanner.pos < stop
          if (run = scanner.scan(/[\x00-\x7F]+/n))
            over = scanner.pos - stop
            chars << (over.positive? ? run.byteslice(0, run.bytesize - over) : run)
            next
          end

          width = utf8 ? utf8_width(scanner) : width(string, scanner.pos)
          if width.zero?
            chars << 0x81
            scanner.pos += 1
          else
            chars << 0x80
            scanner.pos += width
            if width > 1
              extra += width - 1
              @extra << [chars.bytesize - 1, extra]
            end
          end
        end
        chars
      end

      def utf8_width(scanner)
        valid = scanner.check(UTF8_CHAR)
        valid ? valid.bytesize : 0
      end

      # The width of the character at byte `at` in the string's encoding,
      # or 0 when the byte starts no valid character.
      def width(string, at)
        char = string.byteslice(at, 4).force_encoding(@encoding)[0]
        char&.valid_encoding? ? char.bytesize : 0
      end
    end
    private_constant :Lexer
  end
end
