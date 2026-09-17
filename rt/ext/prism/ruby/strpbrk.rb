# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # A lex mode's breakpoints, pm_strpbrk's charset: the bytes a scan stops
    # at, and NUL, which strchr finds as the charset's own terminator, with
    # the patterns that find the next stop with or without the bytes past
    # ASCII. Frozen, so that every Ractor shares the heredoc charsets.
    class Breakpoints
      def initialize(bytes)
        stops = bytes.bytes | [0]
        @mask = stops.sum { |byte| 1 << byte }
        set = stops.map { |byte| format("\\x%02X", byte) }.join
        @ascii = Regexp.new("[#{set}]", Regexp::NOENCODING).freeze
        @past_ascii = Regexp.new("[#{set}\\x80-\\xFF]", Regexp::NOENCODING).freeze
        freeze
      end

      def include?(byte) = @mask[byte] == 1

      def pattern(past_ascii) = past_ascii ? @past_ascii : @ascii

      HEREDOC = new("\r\n\\#")
      HEREDOC_SINGLE_QUOTE = new("\r\n\\")
    end

    # util/pm_strpbrk.c
    class Parser
      private

      # The Breakpoints of a charset, made once per parse.
      def breakpoints(bytes) = @breakpoints[bytes] ||= Breakpoints.new(bytes)

      # pm_strpbrk: the offset of the first breakpoint at or after `from`,
      # or nil. A character past ASCII is stepped over whole in the source's
      # encoding, so a breakpoint byte inside it does not stop the scan. With
      # `validate`, bytes that form no character are an error, and in an
      # encoding other than UTF-8 such a character fixes the literal's
      # encoding.
      def strpbrk(from, breakpoints, validate)
        utf8 = !@encoding_changed
        binary = !utf8 && @encoding == Encodings::ASCII_8BIT
        multibyte = utf8 || (!binary && @encoding.multibyte?)
        pattern = breakpoints.pattern(multibyte || validate)
        encoding = utf8 ? Encodings::UTF_8 : @encoding
        index = from

        while index < @end
          index = @source.byteindex(pattern, index) or return
          return index if breakpoints.include?(@source.getbyte(index))

          # A byte past ASCII.
          if binary
            strpbrk_explicit_encoding(from, 1)
            index += 1
            next
          end

          width = encoding.char_width(@source, index, @end - index)
          strpbrk_explicit_encoding(from, width) if validate && !utf8

          if width > 0
            index += width
          elsif !validate
            index += 1
          else
            # One error for the whole run of bytes that are no character.
            start = index
            index += 1
            index += 1 while index < @end && encoding.char_width(@source, index, @end - index) == 0
            err(start, index, :invalid_multibyte_character, @source.getbyte(start))
          end
        end
        nil
      end

      # pm_strpbrk_explicit_encoding_set: the literal is in the source's
      # encoding, which conflicts with a \u escape read before.
      def strpbrk_explicit_encoding(from, width)
        if @explicit_encoding == Encodings::UTF_8 && @encoding != Encodings::UTF_8
          err(from, from + width, :mixed_encoding, @encoding.name)
        end
        @explicit_encoding = @encoding
      end
    end
  end
end
