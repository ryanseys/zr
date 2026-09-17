# What Ruby does to a pattern around its engine (re.c): the preprocess
# that decodes the escapes naming characters (rb_reg_preprocess), the
# encoding a pattern takes and a match reads it in, a compile again
# for a subject of another encoding, and the pattern as messages,
# inspect and to_s show it. `Regexp#source` keeps the text as written.
# Plain Ruby: it loads under CRuby too, for tools/regexp_diff.rb.
class Regexp
  module Pattern
    BYTE_ESCAPES = { "n" => 0x0a, "t" => 0x09, "r" => 0x0d, "f" => 0x0c, "v" => 0x0b, "a" => 0x07, "e" => 0x1b, "\\" => 0x5c }.freeze

    module_function

    # The option bits, as Regexp names them; regexp.rb, which defines
    # those, loads after this file.
    IGNORECASE = 1
    EXTENDED = 2
    MULTILINE = 4
    FIXEDENCODING = 16
    NOENCODING = 32
    ENGINE_OPTIONS = IGNORECASE | EXTENDED | MULTILINE
    # The encodings whose characters the engine reads as UTF-8.
    WIDE = %w[UTF-8 UTF8-MAC UTF8-DoCoMo UTF8-KDDI UTF8-SoftBank].freeze

    # The engine for a pattern of `enc`: the Onigmo encoding ruby reads
    # it with.
    def engine_for(enc) = Onig::Enc.for(enc)

    # rb_reg_initialize_str and rb_reg_initialize: `source` compiled under
    # the option `bits`, as [encoding, bits, compiled, warnings]: the
    # pattern's encoding, the bits with the flags ruby keeps beside them
    # (FIXEDENCODING where a character or an escape fixed the encoding,
    # or the option did), and what Regexp::Onig.compile answered. Ruby
    # preprocesses under the source's own encoding (BINARY under /n), and
    # the engine reads the text under the pattern's. RegexpError names
    # the reason, then the pattern as written (rb_reg_raise_str).
    def compile(source, bits)
      enc = source.encoding
      if bits & NOENCODING != 0 && enc != Encoding::BINARY
        raise RegexpError, "/.../n has a non escaped non ASCII character in non ASCII-8BIT script" unless source.ascii_only?

        enc = Encoding::BINARY
      end
      raise RegexpError, "can't make regexp with dummy encoding" if enc.dummy?

      text, fixed = preprocess(source, enc, bits & EXTENDED != 0)
      encoding, fixed_bits = fixed_encoding(enc, fixed, bits)
      compiled, warnings = Onig.compile(text, fixed_bits & ENGINE_OPTIONS, engine_for(encoding))
      [encoding, fixed_bits, compiled, warnings]
    rescue RegexpError => e
      raise RegexpError, error_desc(e.message, source, source.encoding, bits)
    end

    # The encoding a pattern read in `enc` takes when its preprocess
    # `fixed` one (or nil), and the option `bits` with FIXEDENCODING
    # where the encoding is fixed.
    def fixed_encoding(enc, fixed, bits)
      if fixed
        if (fixed != enc && bits & FIXEDENCODING != 0) || (fixed != Encoding::BINARY && bits & NOENCODING != 0)
          raise RegexpError, "incompatible character encoding"
        end

        [fixed == Encoding::BINARY ? enc : fixed, bits | FIXEDENCODING]
      elsif bits & FIXEDENCODING == 0
        [Encoding::US_ASCII, bits]
      else
        [enc, bits]
      end
    end

    # rb_reg_prepare_enc: the encoding a match of a subject of
    # `text_encoding` (`ascii`: all its bytes below 128) reads a pattern
    # in, when the engine reads it in `engine` and the pattern's own is
    # `encoding`, and the warning ruby gives of a /n pattern read as
    # characters: [encoding, warning or nil]. A subject the pattern
    # cannot read is refused.
    def prepared_encoding(engine, encoding, bits, text_encoding, ascii)
      return [engine, nil] if engine == text_encoding
      return [engine, nil] if ascii && engine == Encoding::US_ASCII

      incompatible(encoding, text_encoding) unless text_encoding.ascii_compatible?
      if bits & FIXEDENCODING != 0
        incompatible(encoding, text_encoding) unless engine.ascii_compatible? && ascii
        return [engine, nil]
      end
      if bits & NOENCODING != 0 && text_encoding != Encoding::BINARY && !ascii
        return [text_encoding, "historical binary regexp match /.../n against #{text_encoding} string"]
      end

      [text_encoding, nil]
    end

    def incompatible(encoding, text_encoding)
      raise Encoding::CompatibilityError,
            "incompatible encoding regexp match (#{inspect_name(encoding)} regexp with #{inspect_name(text_encoding)} string)"
    end

    # rb_enc_inspect_name.
    def inspect_name(enc) = enc == Encoding::BINARY ? "BINARY (ASCII-8BIT)" : enc.name

    # rb_reg_prepare_re: the pattern `source` (of a Regexp with the
    # option `bits`) compiled again for a subject read in `enc`, as
    # [compiled, warnings]. Ruby
    # decodes the escapes under `enc`, as if no option were given; a
    # text that refuses is an ArgumentError, and a text the engine
    # refuses a RegexpError naming the Regexp (rb_reg_raise).
    def recompile(source, bits, encoding, enc)
      begin
        text, = preprocess(source, enc, false)
      rescue RegexpError => e
        raise ArgumentError, "regexp preprocess failed: #{e.message}"
      end
      begin
        Onig.compile(text, bits & ENGINE_OPTIONS, engine_for(enc))
      rescue RegexpError => e
        shown = desc(source, encoding, bits)
        raise RegexpError, (c_text(e.message) << ": " << shown.b).force_encoding(shown.encoding)
      end
    end

    # An engine message as ruby formats it, a C string: up to its first NUL.
    def c_text(message) = message.b[/\A[^\0]*/]

    # The encoding a reader of messages and inspect sees.
    def result_encoding = Encoding.default_internal || Encoding.default_external

    # rb_enc_reg_error_desc: `message`, then the pattern `source` (read in
    # `enc`) as written between slashes with its option letters, in
    # `enc`.
    def error_desc(message, source, enc, bits)
      out = c_text(message)
      out << ": /" << expr_str(source, enc, result_encoding, "/") << "/" << option_letters(bits)
      out.force_encoding(enc)
    end

    # rb_reg_desc: what Regexp#inspect shows of a pattern `source` of
    # `encoding` with the option `bits`.
    def desc(source, encoding, bits)
      out = "/".b
      out << expr_str(source, encoding, result_encoding, "/") << "/" << option_letters(bits)
      out << "n" if bits & NOENCODING != 0
      out.force_encoding(encoding.ascii_compatible? ? encoding : Encoding::US_ASCII)
    end

    # option_to_str.
    def option_letters(bits)
      "#{bits & MULTILINE != 0 ? 'm' : ''}#{bits & IGNORECASE != 0 ? 'i' : ''}#{bits & EXTENDED != 0 ? 'x' : ''}"
    end

    OPTION_BITS = { "m" => MULTILINE, "i" => IGNORECASE, "x" => EXTENDED }.freeze

    # rb_reg_str_with_term: Regexp#to_s of a pattern `source` of `encoding`
    # with the option `bits`. A source that is one `(?opts-opts:...)`
    # group (or starts with `(?opts)` runs) folds its letters into the
    # options when the engine takes the group's body alone.
    def str_with_term(source, encoding, bits, term)
      bytes = source.b
      options = bits
      at = 0
      len = bytes.bytesize
      while len >= 4 && bytes.getbyte(at) == 0x28 && bytes.getbyte(at + 1) == 0x3f
        folded = options
        at += 2
        len -= 2
        while len > 0 && (bit = OPTION_BITS[bytes.getbyte(at).chr])
          folded |= bit
          at += 1
          len -= 1
        end
        if len > 1 && bytes.getbyte(at) == 0x2d
          at += 1
          len -= 1
          while len > 0 && (bit = OPTION_BITS[bytes.getbyte(at).chr])
            folded &= ~bit
            at += 1
            len -= 1
          end
        end
        if bytes.getbyte(at) == 0x29
          len -= 1
          at += 1
          options = folded
          next
        end
        ok = false
        if bytes.getbyte(at) == 0x3a && bytes.getbyte(at + len - 1) == 0x29
          at += 1
          len -= 2
          begin
            Onig.compile(bytes.byteslice(at, len), folded & ENGINE_OPTIONS, engine_for(encoding))
            ok = true
          rescue RegexpError
            ok = false
          end
        end
        if ok
          options = folded
        else
          options = bits
          at = 0
          len = bytes.bytesize
        end
        break
      end
      out = "(?".b
      out << option_letters(options)
      out << "-" << option_letters(~options) if options & ENGINE_OPTIONS != ENGINE_OPTIONS
      out << ":"
      out << expr_str(bytes.byteslice(at, len), encoding, nil, term) << ")"
      out.force_encoding(encoding)
    end

    # rb_reg_expr_str: `text` as a message or inspect shows it between
    # `term`s. Read under `enc`; `resenc` is the encoding the reader
    # sees (nil for none). Text of an ASCII-compatible encoding that is
    # valid, all printable, has no bare `term` and no non-ASCII character
    # a reader could not show goes as it is; otherwise an escape keeps
    # its next character, a bare `term` takes a backslash, a character
    # past ASCII is written as \uXXXX (or \xHH) when there is a reader, a
    # character that is neither printable nor a space as \xHH, the rest
    # as they are. "Printable" and "space" are the encoding's own
    # classes. The answer is bytes; the caller sets the encoding.
    def expr_str(text, enc, resenc, term)
      bytes = text.b
      onig = Onig::Enc.reader(enc)
      compat = enc.ascii_compatible?
      n = bytes.bytesize
      need_escape = !(compat && bytes.dup.force_encoding(enc).valid_encoding?)
      i = 0
      while !need_escape && i < n
        c = bytes.getbyte(i)
        if c >= 0x80
          need_escape = true unless enc == resenc
          i += onig.mbclen(bytes, i)
        elsif c != term.ord && onig.code_ctype?(c, Onig::CType::PRINT)
          i += 1
        else
          need_escape = true
        end
      end
      return bytes unless need_escape
    
      out = "".b
      i = 0
      while i < n
        c, clen = onig.ascget(bytes, i, compat)
        if c == 0x5c && i + clen < n
          m = clen + onig.mbclen(bytes, i + clen)
          out << bytes.byteslice(i, m)
          i += m
          next
        elsif c.nil?
          clen = onig.precise_mbclen(bytes, i)
          if clen <= 0
            out << format("\\x%02X", bytes.getbyte(i))
            clen = 1
          elsif resenc
            out << escaped_char(onig.mbc_to_code(bytes, i, n), onig.unicode?)
          else
            out << bytes.byteslice(i, clen)
          end
        elsif c == term.ord
          out << "\\" << bytes.byteslice(i, clen)
        elsif onig.code_ctype?(c, Onig::CType::PRINT)
          out << bytes.byteslice(i, clen)
        elsif !onig.code_ctype?(c, Onig::CType::SPACE)
          out << format("\\x%02X", c)
        else
          out << bytes.byteslice(i, clen)
        end
        i += clen
      end
      out
    end
    
    # rb_str_buf_cat_escaped_char, for a character past ASCII.
    def escaped_char(code, unicode)
      if unicode
        code < 0x10000 ? format("\\u%04X", code) : format("\\u{%X}", code)
      else
        code < 0x100 ? format("\\x%02X", code) : format("\\x{%X}", code)
      end
    end
    
    # rb_reg_preprocess: the text the engine compiles for `source` read in
    # `enc`, and the encoding its characters and escapes fix, or nil:
    # [text (BINARY), fixed]. Ruby decodes the `\u` escapes and the byte
    # escapes that name a character past ASCII, drops comments, and
    # keeps the rest as written. RegexpError carries the reason alone.
    def preprocess(source, enc, extended)
      scan = Preprocess.new(source.b, enc)
      scan.walk(extended, false)
      fixed = scan.fixed
      fixed = enc if scan.property && fixed.nil?
      [scan.buf, fixed]
    end

    # unescape_nonascii0 and the escapes it reads, over a pattern's bytes.
    class Preprocess
      attr_reader :buf, :fixed, :property

      def initialize(bytes, enc)
        @s = bytes
        @b = bytes.bytes
        @end = @b.size
        @enc = enc
        @fixed = enc.ascii_compatible? ? nil : enc
        @property = false
        @p = 0
        @buf = "".b
      end

      # The pattern from @p on; with `recurse`, only up to the `)` that
      # closes the group whose `(` was just read.
      def walk(extended, recurse)
        in_class = 0
        parens = 1
        while @p < @end
          len = char_len(@p)
          if len > 1 || @b[@p] >= 0x80
            multibyte(@p, len)
            next
          end
          c = @b[@p]
          @p += 1
          case c
          when 0x5c then escape
          when 0x23
            if extended && in_class.zero?
              # A comment in an extended pattern is dropped.
              while @p < @end
                c = @b[@p]
                @p += 1
                break if c == 0x0a

                @fixed = @enc if c >= 0x80 && @fixed.nil? && @enc == Encoding::UTF_8
              end
            else
              @buf << c
            end
          when 0x5b
            in_class += 1
            @buf << c
          when 0x5d
            in_class -= 1 if in_class.positive?
            @buf << c
          when 0x29
            @buf << c
            return if in_class.zero? && recurse && (parens -= 1).zero?
          when 0x28
            if in_class.zero? && @p + 1 < @end && @b[@p] == 0x3f
              if @b[@p + 1] == 0x23
                comment
                next
              end
              parens += 1 if recurse
              changed = option_group(extended)
              if changed == :group
                @buf << c
                walk(!extended, true)
                next
              end
              extended = changed unless changed.nil?
            elsif in_class.zero? && recurse
              parens += 1
            end
            @buf << c
          else
            @buf << c
          end
        end
      end

      # `(?opts:` or `(?opts)` at @p - 1 flipping the extended flag:
      # :group for a group that flips it until its `)`, the new flag for
      # the rest of the pattern, or nil for no change.
      def option_group(extended)
        invert = false
        local = 0
        s = @p + 1
        while s < @end
          case @b[s]
          when 0x78 then local = invert ? -1 : 1
          when 0x2d then invert = true
          when 0x3a, 0x29
            return nil if local.zero? || (local == -1 && !extended) || (local == 1 && extended)
            return :group if @b[s] == 0x3a

            return local == 1
          when 0x69, 0x6d, 0x61, 0x64, 0x75 then nil
          else return nil
          end
          s += 1
        end
        nil
      end

      # `(?#...)`, dropped whole; one without its `)` is kept, so the
      # engine names the error.
      def comment
        orig = @p
        while @p < @end
          c = @b[@p]
          @p += 1
          if c == 0x29
            return
          elsif c >= 0x80
            @fixed = @enc if @fixed.nil? && @enc == Encoding::UTF_8
            @p -= 1
            @p += char_len(@p)
          elsif c == 0x5c
            @p += char_len(@p)
          end
        end
        @p = orig
        @buf << 0x28
      end

      def multibyte(at, len)
        @buf << @s.byteslice(at, len)
        @p = at + len
        fix(@enc, "non ASCII character in UTF-8 regexp")
      end

      def escape
        raise RegexpError, "too short escape sequence" if @p == @end

        len = char_len(@p)
        # A backslash before a character past ASCII keeps both.
        return multibyte(@p - 1, len + 1) if len > 1

        c = @b[@p]
        @p += 1
        case c
        when 0x31..0x37
          # A backreference or an octal escape of ASCII stays as written.
          digits = @b[@p - 1, 3].take_while { |x| x.between?(0x30, 0x37) }
          return asis(c) if digits.pack("C*").to_i(8) <= 0o177

          escaped_nonascii
        when 0x30, 0x78, 0x63, 0x43, 0x4d then escaped_nonascii
        when 0x75 then unicode
        when 0x70, 0x50
          @property = true if @fixed.nil?
          asis(c)
        else asis(c)
        end
      end

      def asis(c)
        @buf << 0x5c << c
      end

      # The byte escape at @p - 2: kept as written in a US-ASCII pattern,
      # else the character of the encoding it names.
      def escaped_nonascii
        @p -= 2
        if @enc == Encoding::US_ASCII
          start = @p
          _, @p = Pattern.escaped_byte(@b, @p)
          @buf << @s.byteslice(start, @p - start)
          return
        end
        max = Pattern.mbmaxlen(@enc)
        byte, @p = Pattern.escaped_byte(@b, @p)
        bytes = [byte]
        while bytes.size < max && Pattern.needs_more?(bytes, @enc)
          byte, @p = Pattern.escaped_byte(@b, @p)
          bytes << byte
        end
        raise RegexpError, "invalid multibyte escape" if Pattern.invalid?(bytes, @enc)

        if bytes.size > 1 || bytes[0] >= 0x80
          @buf << bytes.pack("C*")
          fix(@enc, "escaped non ASCII character in UTF-8 regexp")
        else
          @buf << format("\\x%02X", bytes[0])
        end
      end

      # `\uHHHH` and `\u{H HH ...}`.
      def unicode
        raise RegexpError, "too short escape sequence" if @p == @end

        if @b[@p] == 0x7b
          @p += 1
          unicode_list
          raise RegexpError, "invalid Unicode list" if @p == @end || @b[@p] != 0x7d

          @p += 1
        else
          raise RegexpError, "invalid Unicode escape" if @end < @p + 4 || !@b[@p, 4].all? { |x| Pattern.hex_byte?(x) }

          utf8(@s.byteslice(@p, 4).to_i(16))
          @p += 4
        end
      end

      def unicode_list
        p = @p
        p += 1 while p < @end && space?(@b[p])
        any = false
        loop do
          start = p
          p += 1 while p < @end && Pattern.hex_byte?(@b[p])
          break if p == start
          raise RegexpError, "invalid Unicode range" if p - start > 6

          utf8(@s.byteslice(start, p - start).to_i(16))
          any = true
          p += 1 while p < @end && space?(@b[p])
        end
        raise RegexpError, "invalid Unicode list" unless any

        @p = p
      end

      # append_utf8: a code point below 128 as `\xHH`, any other as its
      # UTF-8 bytes, which fix the pattern to UTF-8.
      def utf8(code)
        raise RegexpError, "invalid Unicode range" if code.between?(0xd800, 0xdfff) || code > 0x10ffff

        if code < 0x80
          @buf << format("\\x%02X", code)
        else
          @buf << [code].pack("U").b
          if @fixed.nil?
            @fixed = Encoding::UTF_8
          elsif @fixed != Encoding::UTF_8
            raise RegexpError, "UTF-8 character in non UTF-8 regexp"
          end
        end
      end

      def fix(encoding, message)
        if @fixed.nil?
          @fixed = encoding
        elsif @fixed != encoding
          raise RegexpError, message
        end
      end

      # rb_enc_precise_mbclen at `at`, refused when no character starts there.
      def char_len(at)
        len = Onig::Enc.reader(@enc).precise_mbclen(@s, at)
        raise RegexpError, "invalid multibyte character" if len <= 0

        len
      end

      def space?(x) = x == 0x20 || x.between?(0x09, 0x0d)
    end

    # rb_enc_mbmaxlen
    def mbmaxlen(enc) = Onig::Enc.reader(enc).max_len

    # MBCLEN_NEEDMORE_P: whether `bytes` are the start of a character of
    # `enc` that more bytes complete.
    def needs_more?(bytes, enc) = Onig::Enc.reader(enc).precise_mbclen(bytes.pack("C*"), 0) < -1

    # MBCLEN_INVALID_P: `bytes` are neither a character nor the start of one.
    def invalid?(bytes, enc) = Onig::Enc.reader(enc).precise_mbclen(bytes.pack("C*"), 0) == -1

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
