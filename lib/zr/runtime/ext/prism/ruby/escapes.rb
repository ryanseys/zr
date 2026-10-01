# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # prism.c's escape sequences: escape_read reads one after a backslash
    # into a buffer of bytes, and for a regexp also into the source the
    # regexp engine sees; lex_question_mark reads a character literal.
    class Parser
      ESCAPE_FLAG_NONE = 0x0
      ESCAPE_FLAG_CONTROL = 0x1
      ESCAPE_FLAG_META = 0x2
      ESCAPE_FLAG_SINGLE = 0x4
      ESCAPE_FLAG_REGEXP = 0x8

      # ascii_printable_chars
      ASCII_PRINTABLE = Array.new(128) { |b| (b >= 0x09 && b <= 0x0D) || (b >= 0x20 && b <= 0x7E && b != 0x5C) }.freeze

      # The bytes that the simple escapes represent.
      SIMPLE_ESCAPES = {
        0x5C => 0x5C, 0x27 => 0x27, 0x61 => 0x07, 0x62 => 0x08, 0x65 => 0x1B, 0x66 => 0x0C,
        0x6E => 0x0A, 0x72 => 0x0D, 0x73 => 0x20, 0x74 => 0x09, 0x76 => 0x0B
      }

      private

      # char_is_ascii_printable
      def ascii_printable?(byte) = byte < 0x80 && ASCII_PRINTABLE[byte]

      # escape_hexadecimal_digit
      def escape_hexadecimal_digit(byte) = byte <= 0x39 ? byte - 0x30 : (byte & 0x7) + 9

      # escape_unicode: the code point of `length` hexadecimal digits, or
      # U+FFFD with an error for a surrogate.
      def escape_unicode(from, length, error_start = nil, error_end = nil)
        value = 0
        length.times do |index|
          value <<= 4 if index != 0
          value |= escape_hexadecimal_digit(@source.getbyte(from + index))
        end

        if value >= 0xD800 && value <= 0xDFFF
          if error_start
            err(error_start, error_end, :escape_invalid_unicode)
          else
            err(from, from + length, :escape_invalid_unicode)
          end
          return 0xFFFD
        end
        value
      end

      # escape_byte
      def escape_byte(value, flags)
        value &= 0x9F if flags.anybits?(ESCAPE_FLAG_CONTROL)
        value |= 0x80 if flags.anybits?(ESCAPE_FLAG_META)
        value
      end

      # pm_buffer_append_unicode_codepoint: false past U+10FFFF.
      def append_codepoint(buffer, value)
        if value <= 0x7F
          buffer << value
        elsif value <= 0x7FF
          buffer << (0xC0 | ((value >> 6) & 0x3F)) << (0x80 | (value & 0x3F))
        elsif value <= 0xFFFF
          buffer << (0xE0 | ((value >> 12) & 0x3F)) << (0x80 | ((value >> 6) & 0x3F)) << (0x80 | (value & 0x3F))
        elsif value <= 0x10FFFF
          buffer << (0xF0 | ((value >> 18) & 0x3F)) << (0x80 | ((value >> 12) & 0x3F)) << (0x80 | ((value >> 6) & 0x3F)) << (0x80 | (value & 0x3F))
        else
          return false
        end
        true
      end

      # escape_write_unicode: a \u escape past ASCII, or any in a character
      # literal, makes the string UTF-8.
      def escape_write_unicode(buffer, flags, start, finish, value)
        if value >= 0x80 || flags.anybits?(ESCAPE_FLAG_SINGLE)
          if @explicit_encoding && @explicit_encoding != Encodings::UTF_8
            err(start, finish, :mixed_encoding, @explicit_encoding.name)
          end
          @explicit_encoding = Encodings::UTF_8
        end

        return if append_codepoint(buffer, value)

        err(start, finish, :escape_invalid_unicode)
        buffer << 0xEF << 0xBF << 0xBD
      end

      # escape_write_byte_encoded: a byte past ASCII fixes the encoding.
      def escape_write_byte_encoded(buffer, byte)
        if byte >= 0x80
          if @explicit_encoding && @explicit_encoding == Encodings::UTF_8 && @encoding != Encodings::UTF_8
            err_current(:mixed_encoding, @encoding.name)
          end
          @explicit_encoding = @encoding
        end
        buffer << byte
      end

      # escape_write_byte: the byte, and for a regexp its \xNN spelling.
      def escape_write_byte(buffer, regexp_buffer, flags, byte)
        regexp_buffer << format("\\x%02X", byte) if flags.anybits?(ESCAPE_FLAG_REGEXP)
        escape_write_byte_encoded(buffer, byte)
      end

      # escape_write_escape_encoded: the character after the backslash as it
      # is.
      def escape_write_escape_encoded(buffer, regexp_buffer, flags)
        width = @encoding_changed ? @encoding.char_width(@source, @current_end, @end - @current_end) : Encodings::UTF_8.char_width(@source, @current_end, @end - @current_end)

        if width == 1
          byte = escape_byte(@source.getbyte(@current_end), flags)
          @current_end += 1
          escape_write_byte(buffer, regexp_buffer, flags, byte)
        elsif width > 1
          # A valid multibyte character: the escape means nothing.
          target = flags.anybits?(ESCAPE_FLAG_REGEXP) ? regexp_buffer : buffer
          target << @source.byteslice(@current_end, width)
          @current_end += width
        else
          # Not a character: skip the byte and report it.
          @current_end += 1
          err_current(:escape_invalid_control)
        end
      end

      # escape_read_warn: a space or tab inside \c, \C- or \M-.
      def escape_read_warn(flags, flag, type)
        prefix = ->(value) { value.anybits?(ESCAPE_FLAG_CONTROL) ? "\\C-" : value.anybits?(ESCAPE_FLAG_META) ? "\\M-" : "" }
        warn_current(:invalid_character, prefix.(flags), prefix.(flag), type)
      end

      # escape_read: the escape after a backslash at @current_end - 1.
      def escape_read(buffer, regexp_buffer, flags)
        peeked = peek
        if (simple = SIMPLE_ESCAPES[peeked])
          @current_end += 1
          return escape_write_byte(buffer, regexp_buffer, flags, escape_byte(simple, flags))
        end

        case peeked
        when 0x30..0x37 then escape_read_octal(buffer, regexp_buffer, flags)
        when 0x78 then escape_read_hexadecimal(buffer, regexp_buffer, flags)
        when 0x75 then escape_read_unicode(buffer, regexp_buffer, flags)
        when 0x63 then escape_read_control(buffer, regexp_buffer, flags, false)
        when 0x43 then escape_read_control(buffer, regexp_buffer, flags, true)
        when 0x4D then escape_read_meta(buffer, regexp_buffer, flags)
        else
          if peeked == 0x0D && peek_offset(1) == 0x0A
            @current_end += 2
            return escape_write_byte_encoded(buffer, escape_byte(0x0A, flags))
          end

          if flags.anybits?(ESCAPE_FLAG_CONTROL | ESCAPE_FLAG_META) && !ascii_printable?(peeked)
            width = @encoding.char_width(@source, @current_end, @end - @current_end)
            return err(@current_start, @current_end + width, :escape_invalid_meta)
          end

          if @current_end < @end
            escape_write_escape_encoded(buffer, regexp_buffer, flags)
          else
            err_current(:invalid_escape_character)
          end
        end
      end

      # \0 through \777
      def escape_read_octal(buffer, regexp_buffer, flags)
        value = @source.getbyte(@current_end) - 0x30
        @current_end += 1

        if octal_digit?(peek)
          value = ((value << 3) & 0xFF) | (@source.getbyte(@current_end) - 0x30)
          @current_end += 1

          if octal_digit?(peek)
            value = ((value << 3) & 0xFF) | (@source.getbyte(@current_end) - 0x30)
            @current_end += 1
          end
        end

        escape_write_byte(buffer, regexp_buffer, flags, escape_byte(value, flags))
      end

      # \xN and \xNN
      def escape_read_hexadecimal(buffer, regexp_buffer, flags)
        start = @current_end - 1
        @current_end += 1
        byte = peek

        unless hexadecimal_digit?(byte)
          return err_current(:escape_invalid_hexadecimal)
        end

        value = escape_hexadecimal_digit(byte)
        @current_end += 1
        byte = peek
        if hexadecimal_digit?(byte)
          value = ((value << 4) | escape_hexadecimal_digit(byte)) & 0xFF
          @current_end += 1
        end

        value = escape_byte(value, flags)
        if flags.anybits?(ESCAPE_FLAG_REGEXP)
          if flags.anybits?(ESCAPE_FLAG_CONTROL | ESCAPE_FLAG_META)
            regexp_buffer << format("\\x%02X", value)
          else
            regexp_buffer << @source.byteslice(start, @current_end - start)
          end
        end

        escape_write_byte_encoded(buffer, value)
      end

      # \uNNNN and \u{N ...}
      def escape_read_unicode(buffer, regexp_buffer, flags)
        start = @current_end - 1
        @current_end += 1
        regexp = flags.anybits?(ESCAPE_FLAG_REGEXP)

        if @current_end == @end
          short = @current_end - 2
          return err(short, @current_end, :escape_invalid_unicode_short, @source.byteslice(short, 2))
        end

        if peek == 0x7B
          codepoints_start = @current_end - 2
          @current_end += 1

          loop do
            if (whitespace = strspn_inline_whitespace(@current_end, @end)) > 0
              @current_end += whitespace
            elsif peek == 0x5C && peek_offset(1) == 0x6E
              # A \n inside the braces is skipped, so that an unterminated
              # regexp still reaches the regexp engine for its message.
              @current_end += 2
            else
              break
            end
          end

          extra_codepoints_start = nil
          count = 0

          while @current_end < @end && @source.getbyte(@current_end) != 0x7D
            unicode_start = @current_end
            length = strspn_hexadecimal_digit(@current_end, @end)

            if length > 6
              err(unicode_start, unicode_start + length, :escape_invalid_unicode_long)
            elsif length == 0
              if regexp
                regexp_buffer << @source.byteslice(start, @current_end - start)
              else
                err(@current_end, @current_end, :escape_invalid_unicode)
                err(@current_end, @current_end, :escape_invalid_unicode_term)
              end
              return
            end

            @current_end += length
            count += 1
            extra_codepoints_start = unicode_start if flags.anybits?(ESCAPE_FLAG_SINGLE) && count == 2

            value = escape_unicode(unicode_start, length)
            escape_write_unicode(buffer, flags, unicode_start, @current_end, value)
            @current_end += strspn_inline_whitespace(@current_end, @end)
          end

          if flags.anybits?(ESCAPE_FLAG_SINGLE) && count > 1
            err(extra_codepoints_start, @current_end - 1, :escape_invalid_unicode_literal)
          end

          if @current_end == @end
            err(start, @current_end, :escape_invalid_unicode_list, @source.byteslice(start, @current_end - start))
          elsif peek == 0x7D
            @current_end += 1
          elsif regexp
            regexp_buffer << @source.byteslice(start, @current_end - start)
          else
            err(codepoints_start, @current_end, :escape_invalid_unicode_term)
          end

          regexp_buffer << @source.byteslice(codepoints_start, @current_end - codepoints_start) if regexp
        else
          length = strspn_hexadecimal_digit(@current_end, [@end, @current_end + 4].min)

          if length == 0
            if regexp
              regexp_buffer << @source.byteslice(start, @current_end - start)
            else
              short = @current_end - 2
              err(short, @current_end, :escape_invalid_unicode_short, @source.byteslice(short, 2))
            end
          elsif length == 4
            value = escape_unicode(@current_end, 4)
            regexp_buffer << @source.byteslice(start, @current_end + 4 - start) if regexp
            escape_write_unicode(buffer, flags, start, @current_end + 4, value)
            @current_end += 4
          else
            @current_end += length
            if regexp
              regexp_buffer << @source.byteslice(start, @current_end - start)
            else
              err_current(:escape_invalid_unicode)
            end
          end
        end
      end

      # \cx and \C-x
      def escape_read_control(buffer, regexp_buffer, flags, dash)
        @current_end += 1
        err_current(:escape_invalid_control_repeat) if flags.anybits?(ESCAPE_FLAG_CONTROL)

        if dash
          if peek != 0x2D
            width = @encoding.char_width(@source, @current_end, @end - @current_end)
            return err(@current_start, @current_end + width, :escape_invalid_control)
          end
          @current_end += 1
        end

        return err_current(:escape_invalid_control) if @current_end == @end

        peeked = peek
        case peeked
        when 0x3F
          @current_end += 1
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(0x7F, flags))
        when 0x5C
          @current_end += 1
          if match(0x75) || match(0x55)
            return err(@current_start, @current_end, :invalid_escape_character)
          end

          escape_read(buffer, regexp_buffer, flags | ESCAPE_FLAG_CONTROL)
        when 0x20
          @current_end += 1
          escape_read_warn(flags, ESCAPE_FLAG_CONTROL, "\\s")
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(peeked, flags | ESCAPE_FLAG_CONTROL))
        when 0x09
          @current_end += 1
          escape_read_warn(flags, 0, "\\t")
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(peeked, flags | ESCAPE_FLAG_CONTROL))
        else
          unless ascii_printable?(peeked)
            if dash
              width = @encoding.char_width(@source, @current_end, @end - @current_end)
              return err(@current_start, @current_end + width, :escape_invalid_control)
            end
            return err_current(:escape_invalid_control)
          end

          @current_end += 1
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(peeked, flags | ESCAPE_FLAG_CONTROL))
        end
      end

      # \M-x
      def escape_read_meta(buffer, regexp_buffer, flags)
        @current_end += 1
        err_current(:escape_invalid_meta_repeat) if flags.anybits?(ESCAPE_FLAG_META)

        if peek != 0x2D
          width = @encoding.char_width(@source, @current_end, @end - @current_end)
          return err(@current_start, @current_end + width, :escape_invalid_meta)
        end

        @current_end += 1
        return err_current(:escape_invalid_meta) if @current_end == @end

        peeked = peek
        case peeked
        when 0x5C
          @current_end += 1
          if match(0x75) || match(0x55)
            return err(@current_start, @current_end, :invalid_escape_character)
          end

          escape_read(buffer, regexp_buffer, flags | ESCAPE_FLAG_META)
        when 0x20
          @current_end += 1
          escape_read_warn(flags, ESCAPE_FLAG_META, "\\s")
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(peeked, flags | ESCAPE_FLAG_META))
        when 0x09
          @current_end += 1
          escape_read_warn(flags & ~ESCAPE_FLAG_CONTROL, ESCAPE_FLAG_META, "\\t")
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(peeked, flags | ESCAPE_FLAG_META))
        else
          unless ascii_printable?(peeked)
            width = @encoding.char_width(@source, @current_end, @end - @current_end)
            return err(@current_start, @current_end + width, :escape_invalid_meta)
          end

          @current_end += 1
          escape_write_byte(buffer, regexp_buffer, flags, escape_byte(peeked, flags | ESCAPE_FLAG_META))
        end
      end

      # lex_question_mark: a character literal, or the ? of a ternary. The
      # literal's bytes go to @current_string, as a slice of the source or
      # as owned bytes.
      def lex_question_mark
        if lex_state_end?
          @lex_state = STATE_BEG
          return :QUESTION_MARK
        end

        if @current_end >= @end
          err_current(:incomplete_question_mark)
          @current_string = shared_string(@current_start + 1, @current_end)
          return :CHARACTER_LITERAL
        end

        if whitespace?(@source.getbyte(@current_end))
          @lex_state = STATE_BEG
          return :QUESTION_MARK
        end

        @lex_state = STATE_BEG

        if match(0x5C)
          @lex_state = STATE_END
          buffer = "".b
          escape_read(buffer, nil, ESCAPE_FLAG_SINGLE)
          @current_string = owned_string(buffer)
          return :CHARACTER_LITERAL
        end

        width = @encoding.char_width(@source, @current_end, @end - @current_end)
        letter = @encoding.alnum_char(@source, @current_end, @end - @current_end) != 0 || peek == 0x5F
        if !letter || @current_end + width >= @end || identifier_width(@current_end + width) == 0
          @lex_state = STATE_END
          @current_end += width
          @current_string = shared_string(@current_start + 1, @current_end)
          return :CHARACTER_LITERAL
        end

        :QUESTION_MARK
      end

      # pm_string_shared_init: a slice of the source, which remembers where
      # it starts for Prism.dump.
      def shared_string(start, finish)
        string = @source.byteslice(start, finish - start)
        @shared_strings[string] = start
        string
      end

      # pm_string_owned_init: bytes the parser made.
      def owned_string(bytes) = bytes
    end
  end
end
