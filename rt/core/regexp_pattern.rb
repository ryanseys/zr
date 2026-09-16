# What the engine compiles for a Ruby pattern (rb_reg_preprocess). Ruby
# decodes two families itself before Onigmo reads the text: `\u`
# escapes and the `\M-`/`\C-`/`\c` byte escapes. `Regexp#source` and
# every error message keep the text as written.
class Regexp
  module Pattern
    BYTE_ESCAPES = { "n" => 0x0a, "t" => 0x09, "r" => 0x0d, "f" => 0x0c, "v" => 0x0b, "a" => 0x07, "e" => 0x1b, "\\" => 0x5c }.freeze

    module_function

    # The engine's text for `source`, or raises RegexpError with the
    # reason alone (the caller adds the pattern).
    def engine_text(source, extended, binary)
      text = unicode_escapes(source)
      text = control_escapes(text, binary)
      # The engine reads a binary pattern byte by byte, whatever the
      # source it was written in.
      binary ? text.dup.force_encoding(Encoding::BINARY) : text
    end

    # The most bytes one character takes, by encoding name.
    MBMAXLEN = { "UTF-8" => 4, "EUC-JP" => 3, "Shift_JIS" => 2, "Windows-31J" => 2, "GBK" => 2, "GB18030" => 4,
                 "Big5" => 2, "EUC-KR" => 2, "UTF-16LE" => 4, "UTF-16BE" => 4, "UTF-32LE" => 4, "UTF-32BE" => 4 }.freeze

    # rb_reg_preprocess, for what it decides of the encoding: the one the
    # pattern's characters and escapes fix it to, or nil where it holds
    # none; RegexpError, with the reason alone, for a pattern ruby
    # refuses before its engine reads it.
    def fixed_encoding(source, enc, extended)
      fixed = enc.ascii_compatible? ? nil : enc
      return fixed if source.ascii_only? && !source.include?("\\") && !(extended && enc == Encoding::UTF_8)

      scan = Scan.new(source.b.bytes, enc, fixed, false)
      scan.walk(extended, false)
      scan.property && scan.fixed.nil? ? enc : scan.fixed
    end

    # The walk unescape_nonascii0 makes over a pattern's bytes.
    Scan = Struct.new(:b, :enc, :fixed, :property, :i) do
      def walk(extended, recurse)
        self.i ||= 0
        in_class = 0
        parens = 1
        while i < b.size
          len = char_len(i)
          if len > 1 || b[i] >= 0x80
            self.i += len
            fix(enc, "non ASCII character in UTF-8 regexp")
            next
          end
          c = b[i]
          self.i += 1
          case c
          when 0x5c then escape
          when 0x23
            next unless extended && in_class.zero?

            while i < b.size
              byte = b[i]
              self.i += 1
              break if byte == 0x0a

              self.fixed = enc if byte >= 0x80 && fixed.nil? && enc == Encoding::UTF_8
            end
          when 0x5b then in_class += 1
          when 0x5d then in_class -= 1 if in_class.positive?
          when 0x29
            return if in_class.zero? && recurse && (parens -= 1).zero?
          when 0x28
            next if in_class.positive?

            if b[i] == 0x3f && i + 1 < b.size
              if b[i + 1] == 0x23
                comment
              else
                parens += 1 if recurse
                extended = group(extended)
              end
            elsif recurse
              parens += 1
            end
          end
        end
      end

      def char_len(at)
        return 1 if b[at] < 0x80 && enc.ascii_compatible?

        max = [MBMAXLEN.fetch(enc.name, 1), b.size - at].min
        char = b[at, max].pack("C*").force_encoding(enc)[0]
        raise RegexpError, "invalid multibyte character" unless char.valid_encoding?

        char.bytesize
      end

      def fix(encoding, message)
        if fixed.nil?
          self.fixed = encoding
        elsif fixed != encoding
          raise RegexpError, message
        end
      end

      def escape
        raise RegexpError, "too short escape sequence" if i >= b.size

        len = char_len(i)
        if len > 1
          self.i += len
          return fix(enc, "non ASCII character in UTF-8 regexp")
        end
        e = b[i]
        self.i += 1
        case e
        when 0x31..0x37
          digits = b[i - 1, 3].take_while { |x| x.between?(0x30, 0x37) }
          return if digits.pack("C*").to_i(8) <= 0o177

          escaped_nonascii
        when 0x30, 0x78, 0x63, 0x43, 0x4d then escaped_nonascii
        when 0x75 then unicode
        when 0x70, 0x50 then self.property = true if fixed.nil?
        end
      end

      # unescape_escaped_nonascii: the escaped bytes of one character.
      def escaped_nonascii
        self.i -= 2
        if enc == Encoding::US_ASCII
          _, self.i = Pattern.escaped_byte(b, i)
          return
        end
        max = MBMAXLEN.fetch(enc.name, 1)
        byte, self.i = Pattern.escaped_byte(b, i)
        bytes = [byte]
        while bytes.size < max && needs_more?(bytes)
          byte, self.i = Pattern.escaped_byte(b, i)
          bytes << byte
        end
        raise RegexpError, "invalid multibyte escape" unless bytes.pack("C*").force_encoding(enc).valid_encoding?

        fix(enc, "escaped non ASCII character in UTF-8 regexp") if bytes.size > 1 || bytes[0] >= 0x80
      end

      def needs_more?(bytes)
        text = bytes.pack("C*").force_encoding(enc)
        return false if text.valid_encoding?
        return Pattern.utf8_prefix?(bytes) if enc == Encoding::UTF_8

        true
      end

      def unicode
        raise RegexpError, "too short escape sequence" if i >= b.size

        if b[i] == 0x7b
          self.i += 1
          self.i += 1 while i < b.size && space?(b[i])
          any = false
          loop do
            start = i
            self.i += 1 while i < b.size && hex?(b[i])
            break if i == start
            raise RegexpError, "invalid Unicode range" if i - start > 6

            utf8(b[start...i].pack("C*").to_i(16))
            any = true
            self.i += 1 while i < b.size && space?(b[i])
          end
          raise RegexpError, "invalid Unicode list" unless any
          raise RegexpError, "invalid Unicode list" unless b[i] == 0x7d

          self.i += 1
        else
          digits = b[i, 4]
          raise RegexpError, "invalid Unicode escape" unless digits.size == 4 && digits.all? { |x| hex?(x) }

          utf8(digits.pack("C*").to_i(16))
          self.i += 4
        end
      end

      # append_utf8.
      def utf8(code)
        raise RegexpError, "invalid Unicode range" if code.between?(0xd800, 0xdfff) || code > 0x10ffff

        fix(Encoding::UTF_8, "UTF-8 character in non UTF-8 regexp") if code >= 0x80
      end

      # `(?#...)`, a comment whose high bytes still fix a UTF-8 pattern.
      def comment
        start = i
        while i < b.size
          byte = b[i]
          self.i += 1
          return if byte == 0x29
          next unless byte == 0x5c || byte >= 0x80

          if byte >= 0x80
            self.fixed = enc if fixed.nil? && enc == Encoding::UTF_8
            self.i -= 1
          end
          self.i += char_len(i) if i < b.size
        end
        self.i = start
      end

      # `(?x)`, `(?-x:`: the extended flag for the rest of the pattern, or
      # for the group that follows, whose walk returns at its `)`.
      def group(extended)
        invert = false
        local = 0
        s = i + 1
        while s < b.size
          case b[s]
          when 0x78 then local = invert ? -1 : 1
          when 0x2d then invert = true
          when 0x3a, 0x29
            return extended if local.zero? || (local == -1 && !extended) || (local == 1 && extended)

            if b[s] == 0x3a
              walk(local == 1, true)
              return extended
            end
            return local == 1
          when 0x69, 0x6d, 0x61, 0x64, 0x75 then nil
          else return extended
          end
          s += 1
        end
        extended
      end

      def space?(x) = x == 0x20 || x.between?(0x09, 0x0d)

      def hex?(x) = x.between?(0x30, 0x39) || x.between?(0x41, 0x46) || x.between?(0x61, 0x66)
    end

    # `\u{...}` is a space-separated list of code points and `\uHHHH`
    # exactly four hex digits; an ASCII code point becomes `\xHH` so
    # it stays literal.
    def unicode_escapes(source)
      return source unless source.include?("\\u")

      out = +""
      i = 0
      while i < source.size
        c = source[i]
        if c != "\\"
          out << c
          i += 1
          next
        end
        if source[i + 1] != "u"
          out << "\\" << source[i + 1].to_s
          i += 2
          next
        end
        i += 2
        if source[i] == "{"
          i += 1
          any = false
          loop do
            i += 1 while source[i] && source[i].match?(/[ \t\n\v\f\r]/)
            start = i
            i += 1 while source[i] && source[i].match?(/[0-9a-fA-F]/)
            break if i == start
            raise RegexpError, "invalid Unicode range" if i - start > 6

            out << code_text(source[start...i].to_i(16))
            any = true
          end
          raise RegexpError, "invalid Unicode list" if !any || source[i] != "}"

          i += 1
        else
          digits = source[i, 4]
          raise RegexpError, "invalid Unicode escape" unless digits && digits.size == 4 && digits.match?(/\A[0-9a-fA-F]{4}\z/)

          out << code_text(digits.to_i(16))
          i += 4
        end
      end
      out
    end

    def code_text(code)
      raise RegexpError, "invalid Unicode range" if code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)

      code < 0x80 ? format("\\x%02X", code) : code.chr(Encoding::UTF_8)
    end

    # CRuby's `unescape_nonascii` for the escapes ruby decodes itself:
    # `\M-x`, `\C-x` and `\cx` become the byte they name (as `\xHH` when
    # ASCII, raw otherwise). In UTF-8 a high byte must complete a
    # character through the escapes that follow it.
    def control_escapes(source, binary)
      return source unless source.include?("\\")

      b = source.bytes
      out = "".b
      i = 0
      while i < b.size
        if b[i] != 0x5c || i + 1 >= b.size
          out << b[i]
          i += 1
          next
        end
        if b[i + 1] == 0x4d || b[i + 1] == 0x43 || b[i + 1] == 0x63
          i = escaped_char(b, i, binary, out)
        else
          out << b[i] << b[i + 1]
          i += 2
        end
      end
      out.force_encoding(source.encoding)
    end

    # The escape run at `i`, spliced into `out` as the character it
    # names; the index past it.
    def escaped_char(b, i, binary, out)
      byte, i = escaped_byte(b, i)
      bytes = [byte]
      unless binary
        while bytes.size < 4
          text = bytes.pack("C*").force_encoding(Encoding::UTF_8)
          break if text.valid_encoding?
          raise RegexpError, "invalid multibyte escape" unless utf8_prefix?(bytes)

          byte, i = escaped_byte(b, i)
          bytes << byte
        end
        raise RegexpError, "invalid multibyte escape" unless bytes.pack("C*").force_encoding(Encoding::UTF_8).valid_encoding?
      end
      if bytes.size > 1 || bytes[0] >= 0x80
        bytes.each { |x| out << x }
      else
        out << format("\\x%02X", bytes[0]).b
      end
      i
    end

    # Whether `bytes` can still grow into one UTF-8 character.
    def utf8_prefix?(bytes)
      lead = bytes[0]
      need = if lead >= 0xf0 && lead <= 0xf4 then 4
             elsif lead >= 0xe0 && lead <= 0xef then 3
             elsif lead >= 0xc2 && lead <= 0xdf then 2
             else 0
             end
      bytes.size < need && bytes.drop(1).all? { |x| x >= 0x80 && x <= 0xbf }
    end

    # One `\M-X` / `\C-X` / `\cX` run at `i` as [byte, index past it].
    def escaped_byte(b, i)
      raise RegexpError, "too short escaped multibyte character" unless b[i] == 0x5c

      i += 1
      meta = false
      ctrl = false
      code = nil
      while code.nil?
        c = b[i]
        raise RegexpError, "too short escape sequence" if c.nil?

        i += 1
        ch = c.chr
        if BYTE_ESCAPES.key?(ch)
          code = BYTE_ESCAPES[ch]
        elsif ch >= "0" && ch <= "7"
          i -= 1
          code = 0
          n = 0
          while n < 3 && b[i] && b[i] >= 0x30 && b[i] <= 0x37
            code = code * 8 + (b[i] - 0x30)
            i += 1
            n += 1
          end
        elsif ch == "x"
          code = 0
          n = 0
          while n < 2 && b[i] && hex_byte?(b[i])
            code = code * 16 + b[i].chr.to_i(16)
            i += 1
            n += 1
          end
          raise RegexpError, "invalid hex escape" if n < 1
        elsif ch == "M"
          raise RegexpError, "duplicate meta escape" if meta

          meta = true
          following = b[i + 1]
          raise RegexpError, "too short meta escape" unless b[i] == 0x2d && following && following < 0x80

          i += 1
          if following == 0x5c
            i += 1
          else
            i += 1
            code = following
          end
        elsif ch == "C" || ch == "c"
          if ch == "C"
            raise RegexpError, "too short control escape" unless b[i] == 0x2d

            i += 1
          end
          raise RegexpError, "duplicate control escape" if ctrl

          ctrl = true
          following = b[i]
          raise RegexpError, "too short control escape" unless following && following < 0x80

          i += 1
          code = following unless following == 0x5c
        else
          raise RegexpError, "unexpected escape sequence"
        end
      end
      raise RegexpError, "invalid escape code" if code > 0xff

      code &= 0x1f if ctrl
      code |= 0x80 if meta
      [code, i]
    end

    def hex_byte?(x)
      (x >= 0x30 && x <= 0x39) || (x >= 0x41 && x <= 0x46) || (x >= 0x61 && x <= 0x66)
    end

  end
  private_constant :Pattern
end
