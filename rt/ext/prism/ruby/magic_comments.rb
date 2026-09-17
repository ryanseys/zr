# frozen_string_literal: true

module Prism
  module Ruby
    # prism.c's magic comments: `# encoding: x`, `# frozen_string_literal:`,
    # `# warn_indent:`, `# shareable_constant_value:`, in the plain and the
    # emacs (`-*- key: value -*-`) forms.
    class Parser
      private

      # pm_strncasecmp's equality over `length` bytes of the source at `at`,
      # which stops early, equal, at a NUL byte in the source.
      def strncasecmp?(at, text, length)
        length.times do |offset|
          byte = @source.getbyte(at + offset)
          return true if byte == 0
          return false if (offset >= text.bytesize ? 0 : ascii_downcase(text.getbyte(offset))) != ascii_downcase(byte)
        end
        true
      end

      def ascii_downcase(byte) = byte >= 0x41 && byte <= 0x5A ? byte + 32 : byte

      # parser_lex_magic_comment_encoding_value: whether the name is an
      # encoding prism knows, which then becomes the source's.
      def magic_comment_encoding_value(bytes)
        encoding = Encodings.find(bytes)
        return false if encoding.nil?

        if encoding != @encoding
          @encoding = encoding
          @encoding_changed_callback&.call
        end
        @encoding_changed = encoding != Encodings::UTF_8
        true
      end

      def magic_comment_encoding_value_at(start, finish) = magic_comment_encoding_value(@source.byteslice(start, finish - start))

      # parser_lex_magic_comment_encoding: `coding` followed by `:` or `=` and
      # a name, anywhere in a first-line comment the key/value pass missed.
      def magic_comment_encoding
        cursor = @current_start + 1
        finish = @current_end
        separator = false

        loop do
          return if finish - cursor <= 6

          case @source.getbyte(cursor + 6)
          when 0x43, 0x63 then cursor += 6
          when 0x4F, 0x6F then cursor += 5
          when 0x44, 0x64 then cursor += 4
          when 0x49, 0x69 then cursor += 3
          when 0x4E, 0x6E then cursor += 2
          when 0x47, 0x67 then cursor += 1
          when 0x3D, 0x3A
            separator = true
            cursor += 6
            break if strncasecmp?(cursor - 6, "coding", 6)

            separator = false
          else
            cursor += 6
            if whitespace?(@source.getbyte(cursor))
              break if strncasecmp?(cursor - 6, "coding", 6)

              separator = false
            end
          end
        end

        loop do
          loop do
            cursor += 1
            return if cursor >= finish
            break unless whitespace?(@source.getbyte(cursor))
          end

          break if separator
          return unless [0x3D, 0x3A].include?(@source.getbyte(cursor))

          separator = true
          cursor += 1
        end

        value_start = cursor
        while (byte = @source.getbyte(cursor)) == 0x2D || byte == 0x5F || @encoding.alnum_char(@source, cursor, 1) != 0
          cursor += 1
          break unless cursor < finish
        end

        # An unknown name keeps the encoding, with an error.
        err(value_start, cursor, :invalid_encoding_magic_comment) unless magic_comment_encoding_value_at(value_start, cursor)
      end

      # parser_lex_magic_comment_boolean_value: :true, :false or :invalid.
      def magic_comment_boolean(start, length)
        if length == 4 && strncasecmp?(start, "true", 4)
          :true
        elsif length == 5 && strncasecmp?(start, "false", 5)
          :false
        else
          :invalid
        end
      end

      # pm_char_is_magic_comment_key_delimiter
      def magic_comment_key_delimiter?(byte) = byte == 0x27 || byte == 0x22 || byte == 0x3A || byte == 0x3B

      # parser_lex_magic_comment_emacs_marker: the offset of `-*-` in
      # [cursor, finish), or nil.
      def magic_comment_emacs_marker(cursor, finish)
        while cursor + 3 <= finish && (cursor = @source.byteindex("-", cursor)) && cursor < finish
          return cursor if cursor + 3 <= finish && @source.getbyte(cursor + 1) == 0x2A && @source.getbyte(cursor + 2) == 0x2D

          cursor += 1
        end
        nil
      end

      # parser_lex_magic_comment: reads the comment as `key: value` pairs,
      # acts on the keys it knows, and records every pair. It answers false
      # when the comment is not a magic comment as a whole.
      def magic_comment(semantic_token_seen)
        result = true
        start = @current_start + 1
        finish = @current_end
        return false if finish - start <= 7

        indicator = false
        if (cursor = magic_comment_emacs_marker(start, finish))
          start = cursor + 3
          return false unless (cursor = magic_comment_emacs_marker(start, finish))

          finish = cursor
          indicator = true
        end

        cursor = start
        while cursor < finish
          cursor += 1 while cursor < finish && (magic_comment_key_delimiter?(@source.getbyte(cursor)) || whitespace?(@source.getbyte(cursor)))

          key_start = cursor
          cursor += 1 while cursor < finish && !magic_comment_key_delimiter?(@source.getbyte(cursor)) && !whitespace?(@source.getbyte(cursor))
          key_end = cursor

          cursor += 1 while cursor < finish && whitespace?(@source.getbyte(cursor))
          break if cursor == finish

          if @source.getbyte(cursor) == 0x3A
            cursor += 1
          else
            return false unless indicator

            next
          end

          cursor += 1 while cursor < finish && whitespace?(@source.getbyte(cursor))
          break if cursor == finish

          if @source.getbyte(cursor) == 0x22
            value_start = cursor += 1
            while cursor < finish && @source.getbyte(cursor) != 0x22
              cursor += 1 if @source.getbyte(cursor) == 0x5C && cursor + 1 < finish
              cursor += 1
            end
            value_end = cursor
            cursor += 1 if cursor < finish && @source.getbyte(cursor) == 0x22
          else
            value_start = cursor
            cursor += 1 while cursor < finish && @source.getbyte(cursor) != 0x22 && @source.getbyte(cursor) != 0x3B && !whitespace?(@source.getbyte(cursor))
            value_end = cursor
          end

          if indicator
            cursor += 1 while cursor < finish && (@source.getbyte(cursor) == 0x3B || whitespace?(@source.getbyte(cursor)))
          else
            cursor += 1 while cursor < finish && whitespace?(@source.getbyte(cursor))
            return false if cursor != finish
          end

          # A key compares with its dashes read as underscores.
          key = @source.byteslice(key_start, key_end - key_start).tr("-", "_")
          key_length = key.bytesize
          value_length = value_end - value_start

          if @current_start == @encoding_comment_start && !@encoding_locked &&
             ((key_length == 8 && key_matches?(key, "encoding")) || (key_length == 6 && key_matches?(key, "coding")))
            result = magic_comment_encoding_value_at(value_start, value_end)
          end

          case key_length
          when 11
            magic_comment_warn_indent(key, value_start, value_length) if key_matches?(key, "warn_indent")
          when 21
            magic_comment_frozen_string_literal(key, value_start, value_length, semantic_token_seen) if key_matches?(key, "frozen_string_literal")
          when 24
            magic_comment_shareable_constant_value(key, value_start, value_length) if key_matches?(key, "shareable_constant_value")
          end

          @magic_comments << [key_start, key_end - key_start, value_start, value_length]
        end

        result
      end

      # pm_strncasecmp over a key made from the source, which may hold NUL.
      def key_matches?(key, text)
        key.each_byte.with_index do |byte, offset|
          return true if byte == 0
          return false if ascii_downcase(byte) != ascii_downcase(text.getbyte(offset))
        end
        true
      end

      def invalid_magic_comment_value(key, value_start, value_length)
        warn_current(:invalid_magic_comment_value, key, @source.byteslice(value_start, value_length))
      end

      def magic_comment_warn_indent(key, value_start, value_length)
        case magic_comment_boolean(value_start, value_length)
        when :invalid then invalid_magic_comment_value(key, value_start, value_length)
        when :false then @warn_mismatched_indentation = false
        when :true then @warn_mismatched_indentation = true
        end
      end

      def magic_comment_frozen_string_literal(key, value_start, value_length, semantic_token_seen)
        # Only before the first token that means something.
        return warn_current(:ignored_frozen_string_literal) if semantic_token_seen

        case magic_comment_boolean(value_start, value_length)
        when :invalid then invalid_magic_comment_value(key, value_start, value_length)
        when :false then @frozen_string_literal = Options::FROZEN_STRING_LITERAL_DISABLED
        when :true then @frozen_string_literal = Options::FROZEN_STRING_LITERAL_ENABLED
        end
      end

      # pm_parser_scope_shareable_constant_set, over every open scope.
      SHAREABLE_CONSTANT_VALUES = {
        "none" => 0, "literal" => 1 << 2, "experimental_everything" => 1 << 3, "experimental_copy" => 1 << 4
      }.freeze

      def magic_comment_shareable_constant_value(key, value_start, value_length)
        cursor = @current_start
        cursor -= 1 while cursor > 0 && (@source.getbyte(cursor - 1) == 0x20 || @source.getbyte(cursor - 1) == 0x09)

        unless cursor == 0 || @source.getbyte(cursor - 1) == 0x0A
          return warn_current(:shareable_constant_value_line)
        end

        name, value = SHAREABLE_CONSTANT_VALUES.find { |text, _| value_length == text.bytesize && strncasecmp?(value_start, text, value_length) }
        return invalid_magic_comment_value(key, value_start, value_length) if name.nil?

        scope = @current_scope
        loop do
          scope.shareable_constant = value
          break if scope.closed? || (scope = scope.previous).nil?
        end
      end
    end
  end
end
