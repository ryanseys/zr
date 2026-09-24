# frozen_string_literal: true

# The output writer of libyaml 0.2.5 (src/writer.c).
#
# The emitter writes UTF-8 into `@buffer` and flushes it through the
# write handler when it fills up, at the end of each document and at the
# end of the stream. For a UTF-16 stream the writer recodes the buffer
# into `@raw_buffer` first.
module Psych
  module LibYAML
    module Writer
      private

      # yaml_emitter_set_writer_error
      def writer_error(problem)
        @error = WRITER_ERROR
        @problem = problem
        raise Failure
      end

      # yaml_emitter_flush
      def flush
        buffer = @buffer
        # The C code rewinds the buffer before it writes, so a failed
        # write loses what the buffer held.
        @buffer = new_string

        return if buffer.empty?

        if @encoding == UTF8_ENCODING
          writer_error("write error") unless @write_handler.call(buffer)
          return
        end

        # Recode the buffer into the raw buffer. The buffer holds valid
        # UTF-8, so the decoding checks nothing.
        low = @encoding == UTF16LE_ENCODING ? 0 : 1
        high = @encoding == UTF16LE_ENCODING ? 1 : 0

        @raw_buffer ||= new_string
        pointer = 0
        last = buffer.bytesize
        while pointer != last
          octet = buffer.getbyte(pointer)
          width = if octet & 0x80 == 0x00 then 1
                  elsif octet & 0xE0 == 0xC0 then 2
                  elsif octet & 0xF0 == 0xE0 then 3
                  elsif octet & 0xF8 == 0xF0 then 4
                  else 0
                  end
          value = if octet & 0x80 == 0x00 then octet & 0x7F
                  elsif octet & 0xE0 == 0xC0 then octet & 0x1F
                  elsif octet & 0xF0 == 0xE0 then octet & 0x0F
                  elsif octet & 0xF8 == 0xF0 then octet & 0x07
                  else 0
                  end
          k = 1
          while k < width
            value = (value << 6) + ((buffer.getbyte(pointer + k) || 0) & 0x3F)
            k += 1
          end
          # A zero width never moves in C either; step one byte so that a
          # broken buffer still ends.
          pointer += width.zero? ? 1 : width

          if value < 0x10000
            put_code_unit(value >> 8, value & 0xFF, low, high)
          else
            # A surrogate pair, computed as libyaml 0.2.5 computes it.
            value -= 0x10000
            put_code_unit((0xD8 + (value >> 18)) & 0xFF, (value >> 10) & 0xFF, low, high)
            put_code_unit((0xDC + ((value >> 8) & 0xFF)) & 0xFF, value & 0xFF, low, high)
          end
        end

        writer_error("write error") unless @write_handler.call(@raw_buffer)

        @raw_buffer = new_string
      end

      def put_code_unit(high_octet, low_octet, low, high)
        pair = [0, 0]
        pair[high] = high_octet
        pair[low] = low_octet
        @raw_buffer << pair[0] << pair[1]
      end
    end
  end
end
