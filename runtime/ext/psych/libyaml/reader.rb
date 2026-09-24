# frozen_string_literal: true

# The input reader of libyaml 0.2.5 (src/reader.c).
#
# The read handler fills a raw buffer of at most RAW_BUFFER_SIZE bytes.
# The reader decodes all of the raw buffer it can (UTF-8 or UTF-16) into
# a UTF-8 buffer, and checks each character on the way. So an invalid
# character stops the stream as soon as the reader decodes its chunk,
# which can be before the scanner comes near it, exactly as in libyaml.
#
# In the parser, `@raw_buffer` and `@buffer` are binary strings. The
# "last" pointer of each C buffer is the end of its Ruby string, and
# `@raw_pointer` and `@pointer` are the byte offsets the C code moves.
module Psych
  module LibYAML
    module Reader
      RAW_BUFFER_SIZE = 16_384

      # MAX_FILE_SIZE is (~(size_t)0 / 2) on a 64-bit build.
      MAX_FILE_SIZE = (1 << 63) - 1

      BOM_UTF8 = "\xEF\xBB\xBF".b.freeze
      BOM_UTF16LE = "\xFF\xFE".b.freeze
      BOM_UTF16BE = "\xFE\xFF".b.freeze

      # Any byte but the ones that decode to themselves and pass the
      # character check: tab, LF, CR and printable ASCII.
      NOT_PLAIN = /[^\t\n\r\x20-\x7E]/n

      private

      # yaml_parser_update_buffer: make sure the buffer contains at least
      # `length` characters, or all the rest of the input and its NUL.
      def update_buffer(length)
        # Once the input ends and the reader decodes all of it, there is
        # nothing to add.
        return if @eof && @raw_pointer == @raw_buffer.bytesize

        return if @unread >= length

        determine_encoding if @encoding == ANY_ENCODING

        # Move the unread characters to the beginning of the buffer.
        if @pointer.positive? && @pointer < @buffer.bytesize
          @buffer = @buffer.byteslice(@pointer, @buffer.bytesize - @pointer)
          @pointer = 0
        elsif @pointer == @buffer.bytesize
          @buffer = new_string
          @pointer = 0
        end

        first = true
        while @unread < length
          update_raw_buffer if !first || @raw_pointer == @raw_buffer.bytesize
          first = false

          decode_raw_buffer

          # At the end of the input, put NUL into the buffer and return.
          if @eof
            @buffer << 0
            @unread += 1
            return
          end
        end

        reader_error("input is too long", @offset, -1) if @offset >= MAX_FILE_SIZE
      end

      # yaml_parser_set_reader_error
      def reader_error(problem, offset, value)
        @error = READER_ERROR
        @problem = problem
        @problem_offset = offset
        @problem_value = value
        raise Failure
      end

      def raw_unread = @raw_buffer.bytesize - @raw_pointer

      # yaml_parser_determine_encoding: read the byte order mark, if any.
      # With no mark the input is UTF-8.
      def determine_encoding
        update_raw_buffer while !@eof && raw_unread < 3

        if raw_unread >= 2 && @raw_buffer.byteslice(@raw_pointer, 2) == BOM_UTF16LE
          @encoding = UTF16LE_ENCODING
          @raw_pointer += 2
          @offset += 2
        elsif raw_unread >= 2 && @raw_buffer.byteslice(@raw_pointer, 2) == BOM_UTF16BE
          @encoding = UTF16BE_ENCODING
          @raw_pointer += 2
          @offset += 2
        elsif raw_unread >= 3 && @raw_buffer.byteslice(@raw_pointer, 3) == BOM_UTF8
          @encoding = UTF8_ENCODING
          @raw_pointer += 3
          @offset += 3
        else
          @encoding = UTF8_ENCODING
        end
      end

      # yaml_parser_update_raw_buffer: move the unread raw bytes to the
      # front and read as many bytes as fit after them from the read handler.
      def update_raw_buffer
        return if @raw_pointer.zero? && @raw_buffer.bytesize == RAW_BUFFER_SIZE
        return if @eof

        if @raw_pointer.positive?
          @raw_buffer = @raw_buffer.byteslice(@raw_pointer, raw_unread)
          @raw_pointer = 0
        end

        chunk = @read_handler.call(RAW_BUFFER_SIZE - @raw_buffer.bytesize)
        reader_error("input error", @offset, -1) if chunk.nil?

        @raw_buffer << chunk
        @eof = true if chunk.empty?
      end

      # The inner loop of yaml_parser_update_buffer: decode characters
      # from the raw buffer until it runs out or ends in the middle of a
      # character.
      def decode_raw_buffer
        raw = @raw_buffer
        last = raw.bytesize
        while @raw_pointer != last
          # Printable ASCII passes through unchanged, and the checks below
          # all pass for it, so a run of it goes over in one copy.
          if @encoding == UTF8_ENCODING && (run = plain_run_length(raw, @raw_pointer)).positive?
            @buffer << raw.byteslice(@raw_pointer, run)
            @raw_pointer += run
            @offset += run
            @unread += run
            next
          end

          raw_unread = last - @raw_pointer
          if @encoding == UTF8_ENCODING
            value, width = decode_utf8(raw, raw_unread)
          else
            value, width = decode_utf16(raw, raw_unread)
          end
          # The raw buffer ends inside a character; read more first.
          break if value.nil?

          unless value == 0x09 || value == 0x0A || value == 0x0D ||
                 (value >= 0x20 && value <= 0x7E) || value == 0x85 ||
                 (value >= 0xA0 && value <= 0xD7FF) || (value >= 0xE000 && value <= 0xFFFD) ||
                 (value >= 0x10000 && value <= 0x10FFFF)
            reader_error("control characters are not allowed", @offset, value)
          end

          @raw_pointer += width
          @offset += width
          put_utf8(value)
          @unread += 1
        end
      end

      def plain_run_length(raw, from)
        (raw.byteindex(NOT_PLAIN, from) || raw.bytesize) - from
      end

      # One UTF-8 character (RFC 3629), with the checks that libyaml makes.
      # Returns [value, width], or nil when the character is incomplete
      # and more input can follow.
      def decode_utf8(raw, raw_unread)
        octet = raw.getbyte(@raw_pointer)
        width = if octet & 0x80 == 0x00 then 1
                elsif octet & 0xE0 == 0xC0 then 2
                elsif octet & 0xF0 == 0xE0 then 3
                elsif octet & 0xF8 == 0xF0 then 4
                else 0
                end

        reader_error("invalid leading UTF-8 octet", @offset, octet) if width.zero?

        if width > raw_unread
          reader_error("incomplete UTF-8 octet sequence", @offset, -1) if @eof
          return nil
        end

        value = if octet & 0x80 == 0x00 then octet & 0x7F
                elsif octet & 0xE0 == 0xC0 then octet & 0x1F
                elsif octet & 0xF0 == 0xE0 then octet & 0x0F
                else octet & 0x07
                end

        k = 1
        while k < width
          octet = raw.getbyte(@raw_pointer + k)
          reader_error("invalid trailing UTF-8 octet", @offset + k, octet) if octet & 0xC0 != 0x80

          value = (value << 6) + (octet & 0x3F)
          k += 1
        end

        unless width == 1 || (width == 2 && value >= 0x80) ||
               (width == 3 && value >= 0x800) || (width == 4 && value >= 0x10000)
          reader_error("invalid length of a UTF-8 sequence", @offset, -1)
        end

        if (value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF
          reader_error("invalid Unicode character", @offset, value)
        end

        [value, width]
      end

      # One UTF-16 character (RFC 2781), which a surrogate pair makes from
      # two code units. Returns [value, width], or nil when the character
      # is incomplete and more input can follow.
      def decode_utf16(raw, raw_unread)
        low = @encoding == UTF16LE_ENCODING ? 0 : 1
        high = @encoding == UTF16LE_ENCODING ? 1 : 0

        if raw_unread < 2
          reader_error("incomplete UTF-16 character", @offset, -1) if @eof
          return nil
        end

        value = raw.getbyte(@raw_pointer + low) + (raw.getbyte(@raw_pointer + high) << 8)

        reader_error("unexpected low surrogate area", @offset, value) if value & 0xFC00 == 0xDC00

        return [value, 2] unless value & 0xFC00 == 0xD800

        if raw_unread < 4
          reader_error("incomplete UTF-16 surrogate pair", @offset, -1) if @eof
          return nil
        end

        value2 = raw.getbyte(@raw_pointer + low + 2) + (raw.getbyte(@raw_pointer + high + 2) << 8)
        reader_error("expected low surrogate area", @offset + 2, value2) if value2 & 0xFC00 != 0xDC00

        [0x10000 + ((value & 0x3FF) << 10) + (value2 & 0x3FF), 4]
      end

      # Append a character to the buffer as UTF-8.
      def put_utf8(value)
        buffer = @buffer
        if value <= 0x7F
          buffer << value
        elsif value <= 0x7FF
          buffer << (0xC0 + (value >> 6)) << (0x80 + (value & 0x3F))
        elsif value <= 0xFFFF
          buffer << (0xE0 + (value >> 12)) << (0x80 + ((value >> 6) & 0x3F)) << (0x80 + (value & 0x3F))
        else
          buffer << (0xF0 + (value >> 18)) << (0x80 + ((value >> 12) & 0x3F)) <<
            (0x80 + ((value >> 6) & 0x3F)) << (0x80 + (value & 0x3F))
        end
      end
    end
  end
end
