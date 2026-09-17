# frozen_string_literal: true

module Prism
  module Ruby
    # regexp.c: a scanner over a regexp's source that finds its named
    # capture groups and the errors the regexp engine would report at parse
    # time. Offsets are into the scanned bytes.
    class RegexpScanner
      # PM_REGEXP_PARSE_DEPTH_MAX
      DEPTH_MAX = 4096

      # pm_regexp_option_state_t
      OPTION_INVALID = 0
      OPTION_TOGGLEABLE = 1
      OPTION_ADDABLE = 2
      OPTION_ADDED = 3
      OPTION_REMOVED = 4

      # The states the options of a group start in, by letter.
      OPTION_DEFAULTS = {
        0x69 => OPTION_TOGGLEABLE, 0x6D => OPTION_TOGGLEABLE, 0x78 => OPTION_TOGGLEABLE,
        0x64 => OPTION_ADDABLE, 0x61 => OPTION_ADDABLE, 0x75 => OPTION_ADDABLE
      }.freeze

      # `encoding` is the parser's when `encoding_changed`, for multibyte
      # characters whose trailing bytes can look like ASCII. `on_name`
      # receives each capture group's name as [start, end]; `on_error`
      # receives [start, end, message].
      def initialize(bytes, extended_mode, encoding_changed, encoding, on_name, on_error)
        @source = bytes
        @cursor = 0
        @end = bytes.bytesize
        @extended_mode = extended_mode
        @encoding_changed = encoding_changed
        @encoding = encoding
        @on_name = on_name
        @on_error = on_error
      end

      # pm_regexp_parse_pattern
      def parse
        loop do
          return true if eof?
          return false unless parse_expression(0)
          break unless accept(0x7C) # |
        end
        eof?
      end

      private

      def error(start, finish, message) = @on_error.call(start, finish, message)

      def byte = @source.getbyte(@cursor)

      # pm_regexp_char_is_eof
      def eof? = @cursor >= @end

      # pm_regexp_char_accept, pm_regexp_char_expect
      def accept(value)
        return false if eof? || byte != value

        @cursor += 1
        true
      end

      # pm_memchr: the offset of `value` from `from`, stepping over multibyte
      # characters when the encoding's trailing bytes can equal it.
      def memchr(value, from)
        unless @encoding_changed && @encoding.multibyte? && value >= 0x40
          at = @source.byteindex(value.chr, from)
          return at
        end

        index = from
        while index < @end
          return index if @source.getbyte(index) == value

          width = @encoding.char_width(@source, index, @end - index)
          return if width == 0

          index += width
        end
        nil
      end

      # pm_regexp_char_find: past the next `value`.
      def find(value)
        return false if eof?

        at = memchr(value, @cursor)
        return false if at.nil?

        @cursor = at + 1
        true
      end

      def digit?(value) = value && value >= 0x30 && value <= 0x39

      # pm_regexp_parse_range_quantifier: {n}, {n,}, {n,m}, {,m}; anything
      # else is plain characters, and the cursor goes back.
      def parse_range_quantifier
        savepoint = @cursor
        state = :start

        loop do
          if @cursor >= @end
            @cursor = savepoint
            return true
          end

          current = byte
          case state
          when :start
            if digit?(current)
              @cursor += 1
              state = :minimum
            elsif current == 0x2C
              @cursor += 1
              state = :comma
            else
              @cursor = savepoint
              return true
            end
          when :minimum
            if digit?(current)
              @cursor += 1
            elsif current == 0x2C
              @cursor += 1
              state = :maximum
            elsif current == 0x7D
              @cursor += 1
              return true
            else
              @cursor = savepoint
              return true
            end
          when :comma
            if digit?(current)
              @cursor += 1
              state = :maximum
            else
              @cursor = savepoint
              return true
            end
          when :maximum
            if digit?(current)
              @cursor += 1
            elsif current == 0x7D
              @cursor += 1
              return true
            else
              @cursor = savepoint
              return true
            end
          end
        end
      end

      # pm_regexp_parse_quantifier
      def parse_quantifier
        until eof?
          case byte
          when 0x2A, 0x2B, 0x3F # * + ?
            @cursor += 1
          when 0x7B # {
            @cursor += 1
            return false unless parse_range_quantifier
          else
            return true
          end
        end
        true
      end

      # pm_regexp_parse_posix_class: [[:alpha:]]
      def parse_posix_class
        return false unless accept(0x3A)

        accept(0x5E)
        find(0x3A) && accept(0x5D) && accept(0x5D)
      end

      # pm_regexp_parse_character_set
      def parse_character_set(depth)
        accept(0x5E)

        while !eof? && byte != 0x5D
          current = byte
          @cursor += 1
          case current
          when 0x5B then parse_lbracket(depth + 1)
          when 0x5C then @cursor += 1 unless eof?
          end
        end

        accept(0x5D)
      end

      # pm_regexp_parse_lbracket: a POSIX class or a character set.
      def parse_lbracket(depth)
        if depth >= DEPTH_MAX
          error(0, @end, "parse depth limit over")
          return false
        end

        if @cursor < @end && byte == 0x5D
          @cursor += 1
          error(@cursor - 1, @cursor, "empty char-class")
          return true
        end

        reset = @cursor

        if @cursor + 2 < @end && byte == 0x5B && @source.getbyte(@cursor + 1) == 0x3A
          @cursor += 1
          return true if parse_posix_class

          @cursor = reset
        end

        parse_character_set(depth)
      end

      # pm_regexp_options_add
      def options_add(options, key)
        case options[key]
        when OPTION_TOGGLEABLE, OPTION_ADDABLE
          options[key] = OPTION_ADDED
          true
        when OPTION_ADDED then true
        else false
        end
      end

      # pm_regexp_options_remove
      def options_remove(options, key)
        case options[key]
        when OPTION_TOGGLEABLE, OPTION_ADDED, OPTION_REMOVED
          options[key] = OPTION_REMOVED
          true
        else false
        end
      end

      # pm_regexp_parse_group: after `(`.
      def parse_group(depth)
        group_start = @cursor
        options = OPTION_DEFAULTS.dup

        if accept(0x3F) # ?
          if eof?
            error(group_start, @cursor, "end pattern in group")
            return false
          end

          case byte
          when 0x23 # (?# comment)
            @cursor += 1
            if eof?
              error(group_start, @cursor, "end pattern in group")
              return false
            end

            if @encoding_changed && @encoding.multibyte?
              # A backslash may be a trailing byte, so step by character.
              escaped = false
              while @cursor < @end
                if !escaped && byte == 0x29
                  @cursor += 1
                  return true
                end

                width = @encoding.char_width(@source, @cursor, @end - @cursor)
                return false if width == 0

                escaped = width == 1 && byte == 0x5C
                @cursor += width
              end
              return false
            end

            found = find(0x29)
            found = find(0x29) while found && @cursor - 2 >= 0 && @source.getbyte(@cursor - 2) == 0x5C
            return found
          when 0x3A, 0x3D, 0x21, 0x3E, 0x7E # : = ! > ~
            @cursor += 1
          when 0x3C # <
            @cursor += 1
            if eof?
              error(group_start, @cursor, "end pattern with unmatched parenthesis")
              return false
            end

            if byte == 0x3D || byte == 0x21
              @cursor += 1
            else
              start = @cursor
              return false unless find(0x3E)

              error(start, @cursor, "group name is empty") if @cursor - start == 1
              @on_name&.call(start, @cursor - 1)
            end
          when 0x27 # '
            @cursor += 1
            start = @cursor
            return false unless find(0x27)

            @on_name&.call(start, @cursor - 1)
          when 0x28 # (cond)
            return false unless find(0x29)
          when 0x69, 0x6D, 0x78, 0x64, 0x61, 0x75, 0x2D # i m x d a u -
            unless byte == 0x2D
              while !eof? && byte != 0x2D && byte != 0x3A && byte != 0x29
                return false unless options_add(options, byte)

                @cursor += 1
              end

              return false if eof?

              # (?x) sets the options of the group around.
              if byte == 0x29
                @extended_mode = true if options[0x78] == OPTION_ADDED
                @cursor += 1
                return true
              end
            end

            if byte == 0x2D
              @cursor += 1
              while !eof? && byte != 0x3A && byte != 0x29
                return false unless options_remove(options, byte)

                @cursor += 1
              end

              return false if eof?

              if byte == 0x29
                case options[0x78]
                when OPTION_ADDED then @extended_mode = true
                when OPTION_REMOVED then @extended_mode = false
                end

                @cursor += 1
                return true
              end
            end
          else
            @cursor += 1
            error(@cursor - 1, @cursor, "undefined group option")
          end
        end

        extended_mode = @extended_mode
        case options[0x78]
        when OPTION_ADDED then @extended_mode = true
        when OPTION_REMOVED then @extended_mode = false
        end

        while !eof? && byte != 0x29
          unless parse_expression(depth + 1)
            @extended_mode = extended_mode
            return false
          end
          accept(0x7C)
        end

        @extended_mode = extended_mode
        return true if accept(0x29)

        error(group_start, @cursor, "end pattern with unmatched parenthesis")
        false
      end

      # pm_regexp_parse_item
      def parse_item(depth)
        case byte
        when 0x5E, 0x24 # ^ $
          @cursor += 1
          parse_quantifier
        when 0x5C # \
          @cursor += 1
          @cursor += 1 unless eof?
          parse_quantifier
        when 0x28 # (
          @cursor += 1
          parse_group(depth) && parse_quantifier
        when 0x5B # [
          @cursor += 1
          parse_lbracket(depth) && parse_quantifier
        when 0x2A, 0x3F, 0x2B # * ? +
          @cursor += 1
          error(@cursor - 1, @cursor, "target of repeat operator is not specified")
          true
        when 0x29 # )
          @cursor += 1
          error(@cursor - 1, @cursor, "unmatched close parenthesis")
          true
        else
          if byte == 0x23 && @extended_mode
            @cursor = @end unless find(0x0A)
            return true
          end

          encoding = @encoding_changed ? @encoding : Encodings::UTF_8
          width = encoding.char_width(@source, @cursor, @end - @cursor)
          return false if width == 0

          @cursor += width
          parse_quantifier
        end
      end

      # pm_regexp_parse_expression
      def parse_expression(depth)
        if depth >= DEPTH_MAX
          error(0, @end, "parse depth limit over")
          return false
        end

        return false unless parse_item(depth)

        while !eof? && byte != 0x29 && byte != 0x7C
          return false unless parse_item(depth)
        end
        true
      end
    end

    class Parser
      private

      # pm_regexp_parse over `bytes`: named captures go to `on_name` as
      # [start, end] into the bytes, errors to the block as [start, end,
      # message].
      def regexp_parse(bytes, extended_mode, on_name, &on_error)
        RegexpScanner.new(bytes.b, extended_mode, @encoding_changed, @encoding, on_name, on_error).parse
      end
    end
  end
end
