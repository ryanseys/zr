# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

using Prism::Ruby::Mutation

module Prism
  module Ruby
    # regexp.c: a scanner over a regexp's bytes that finds its named capture
    # groups, the errors the regexp engine would report at parse time, and
    # what its escapes and literal bytes tell about its encoding, which
    # Parser#regexp_validate_encoding then checks. Offsets are into the
    # scanned bytes.
    class RegexpScanner
      include Characters

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
      }

      # pm_regexp_classify_property: the property names that are not
      # Unicode-only, by their lower-case name. A POSIX property is valid in
      # every encoding, a script property in EUC-JP, Windows-31J and UTF-8.
      PROPERTIES = {
        "han" => :script, "word" => :posix, "alnum" => :posix, "alpha" => :posix, "ascii" => :posix,
        "blank" => :posix, "cntrl" => :posix, "digit" => :posix, "graph" => :posix, "greek" => :script,
        "lower" => :posix, "latin" => :script, "print" => :posix, "punct" => :posix, "space" => :posix,
        "upper" => :posix, "xdigit" => :posix, "hiragana" => :script, "katakana" => :script,
        "cyrillic" => :script
      }

      # The encoding that the escapes set: nil, UTF-8 for a `\u` escape, or
      # the source's encoding for a `\x` escape.
      attr_reader :explicit_encoding
      # The first property name that is not POSIX (for /n), and the first
      # that is Unicode-only (for /e and /s), or nil.
      attr_reader :property_name, :unicode_property_name
      # The bytes of the `\x` escapes past ASCII, a 0 between each run.
      attr_reader :hex_escapes
      # The bytes past ASCII that no escape wrote.
      attr_reader :non_ascii_literal_count
      attr_reader :last_escape_was_unicode

      # `encoding` is the parser's when `encoding_changed`, for multibyte
      # characters whose trailing bytes can look like ASCII. `on_name`
      # receives each capture group's name as [start, end]; `on_error`
      # receives [start, end, diagnostic id, arguments...].
      def initialize(bytes, extended_mode, encoding_changed, encoding, on_name, on_error)
        @source = bytes
        @cursor = 0
        @end = bytes.bytesize
        @extended_mode = extended_mode
        @encoding_changed = encoding_changed
        @encoding = encoding
        @on_name = on_name
        @on_error = on_error
        @explicit_encoding = nil
        @property_name = nil
        @unicode_property_name = nil
        @hex_escapes = +"".b
        @non_ascii_literal_count = 0
        @unicode_escape = false
        @hex_escape = false
        @last_escape_was_unicode = false
        @property_escape = false
        @unicode_property_escape = false
        @invalid_unicode_range = false
        @hex_group_active = false
        @invalid_multibyte = false
      end

      def unicode_escape? = @unicode_escape
      def hex_escape? = @hex_escape
      def property_escape? = @property_escape
      def unicode_property_escape? = @unicode_property_escape
      def invalid_unicode_range? = @invalid_unicode_range
      def invalid_multibyte? = @invalid_multibyte

      # Whether the regexp is ASCII only: no escape and no literal byte past
      # ASCII. The unescaped bytes cannot tell, because a regexp keeps its
      # escapes as text.
      def ascii_only? = !@hex_escape && !@unicode_escape && @non_ascii_literal_count.zero?

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

      # pm_regexp_parse_error
      def error(start, finish, message) = @on_error.call(start, finish, :regexp_parse_error, message)

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

      # pm_regexp_hex_group_boundary: a run of `\x` escapes past ASCII ends.
      def hex_group_boundary
        return unless @hex_group_active

        @hex_escapes << 0
        @hex_group_active = false
      end

      # pm_regexp_track_hex_escape: a byte that an escape writes.
      def track_hex_escape(value)
        unless value >= 0x80
          hex_group_boundary
          return
        end

        @hex_escapes << value
        @hex_group_active = true
        @hex_escape = true
        @explicit_encoding = @encoding
        @last_escape_was_unicode = false
      end

      # pm_regexp_hex_digit_value
      def hex_digit(value)
        case value
        when 0x30..0x39 then value - 0x30
        when 0x61..0x66 then value - 0x61 + 10
        when 0x41..0x46 then value - 0x41 + 10
        end
      end

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

      # pm_regexp_parse_property_escape: \p{...} or \P{...}, with the cursor
      # at the p. A property that is not POSIX, and one that is
      # Unicode-only, is kept for the encoding check.
      def parse_property_escape
        if @cursor + 1 < @end && @source.getbyte(@cursor + 1) == 0x7B
          name_start = @cursor + 2
          close = @source.byteindex("}", name_start)
          if close
            name = @source.byteslice(name_start, close - name_start)
            @property_escape = true

            type = PROPERTIES.fetch(name.delete_prefix("^").downcase(:ascii), :unicode)
            @property_name ||= name unless type == :posix
            if type == :unicode
              @unicode_property_escape = true
              @unicode_property_name ||= name
            end

            @cursor = close + 1
            return true
          end
        end

        # Not a property: only the letter after the backslash.
        @cursor += 1
        false
      end

      # pm_regexp_parse_unicode_escape: \uNNNN or \u{N ...}, with the cursor
      # after the u.
      def parse_unicode_escape
        escape_start = @cursor - 2

        if eof?
          error(escape_start, @cursor, "invalid Unicode escape")
          return
        end

        unless byte == 0x7B
          value = 0
          count = 0
          while count < 4 && !eof? && (digit = hex_digit(byte))
            value = (value << 4) | digit
            count += 1
            @cursor += 1
          end

          if count < 4
            error(escape_start, @cursor, "invalid Unicode escape")
          elsif value >= 0x80
            unicode_escape_seen
          end

          @invalid_unicode_range = true if count == 4 && invalid_codepoint?(value)
          return
        end

        @cursor += 1
        @cursor += 1 while !eof? && whitespace?(byte)
        codepoint = false

        while !eof? && byte != 0x7D
          value = 0
          count = 0
          while !eof? && (digit = hex_digit(byte))
            value = (value << 4) | digit
            count += 1
            @cursor += 1
          end

          if count == 0
            @cursor += 1 while !eof? && byte != 0x7D
            escape_end = @cursor
            unless eof?
              escape_end += 1
              @cursor += 1
            end
            @on_error.call(escape_start, escape_end, :escape_invalid_unicode_list,
                           @source.byteslice(escape_start, escape_end - escape_start))
            return
          end

          error(escape_start, @cursor, "invalid Unicode range") if count > 6
          unicode_escape_seen if value >= 0x80
          @invalid_unicode_range = true if invalid_codepoint?(value)
          codepoint = true

          @cursor += 1 while !eof? && whitespace?(byte)
        end

        if eof?
          error(escape_start, @cursor, "unterminated Unicode escape")
        else
          unless codepoint
            @on_error.call(escape_start, @cursor + 1, :escape_invalid_unicode_list,
                           @source.byteslice(escape_start, @cursor + 1 - escape_start))
          end
          @cursor += 1
        end
      end

      # A `\u` escape past ASCII makes the regexp UTF-8.
      def unicode_escape_seen
        @unicode_escape = true
        @explicit_encoding = Encodings::UTF_8
        @last_escape_was_unicode = true
        hex_group_boundary
      end

      # A surrogate, or past U+10FFFF.
      def invalid_codepoint?(value) = value > 0x10FFFF || (value >= 0xD800 && value <= 0xDFFF)

      # pm_regexp_parse_hex_escape: \x with one or two digits, with the
      # cursor after the x.
      def parse_hex_escape
        return if eof? || (value = hex_digit(byte)).nil?

        @cursor += 1
        if !eof? && (digit = hex_digit(byte))
          value = (value << 4) | digit
          @cursor += 1
        end
        track_hex_escape(value)
      end

      # pm_regexp_parse_backslash_escape: the escape after a backslash,
      # which may set the encoding.
      def parse_backslash_escape
        return if eof?

        case byte
        when 0x75 # u
          @cursor += 1
          parse_unicode_escape
        when 0x70, 0x50 # p P
          parse_property_escape
        when 0x78 # x
          @cursor += 1
          parse_hex_escape
        when 0x4D # \M-x is always past ASCII.
          if @cursor + 2 < @end && @source.getbyte(@cursor + 1) == 0x2D
            @cursor += 2
            unless eof?
              escaped_escape
              track_hex_escape(0x80)
            end
          else
            @cursor += 1
          end
        when 0x43 # \C-x
          if @cursor + 2 < @end && @source.getbyte(@cursor + 1) == 0x2D
            @cursor += 2
            escaped_escape unless eof?
          else
            @cursor += 1
          end
        when 0x63 # \cx
          @cursor += 1
          escaped_escape unless eof?
        else
          hex_group_boundary
          @cursor += 1
        end
      end

      # The character of \M-, \C- or \c, which may be an escape itself.
      def escaped_escape
        if byte == 0x5C
          @cursor += 1
          parse_backslash_escape
        else
          @cursor += 1
        end
      end

      # pm_regexp_parse_invalid_multibyte: a byte past ASCII in a multibyte
      # encoding, the cursor already past it, takes its whole character or
      # is an error.
      def parse_invalid_multibyte(at)
        return unless @source.getbyte(at) >= 0x80 && @encoding_changed && @encoding.multibyte?

        width = @encoding.char_width(@source, at, @end - at)
        if width > 1
          @cursor += width - 1
        elsif width == 0
          invalid_multibyte_at(at)
        end
      end

      def invalid_multibyte_at(at)
        @invalid_multibyte = true
        @on_error.call(at, at + 1, :invalid_multibyte_char, @encoding.name)
      end

      # pm_regexp_parse_character_set
      def parse_character_set(depth)
        accept(0x5E)

        while !eof? && byte != 0x5D
          current = byte
          @cursor += 1
          case current
          when 0x5B then parse_lbracket(depth + 1)
          when 0x5C then parse_backslash_escape
          else
            @non_ascii_literal_count += 1 if current >= 0x80
            parse_invalid_multibyte(@cursor - 1)
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
                if width == 0
                  return false unless byte >= 0x80

                  invalid_multibyte_at(@cursor)
                  @cursor += 1
                  next
                end

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
          parse_backslash_escape
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
          if width == 0
            return false unless byte >= 0x80 && @encoding_changed

            # An invalid character of a multibyte encoding is an error here;
            # a byte past ASCII in a single-byte one is counted for later.
            if @encoding.multibyte?
              invalid_multibyte_at(@cursor)
            else
              @non_ascii_literal_count += 1
            end
            @cursor += 1
            return parse_quantifier
          end

          @non_ascii_literal_count += @source.byteslice(@cursor, width).bytes.count { |value| value >= 0x80 }
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

      # pm_regexp_parse: the encoding flags of a regexp literal. A first
      # pass over its source, as written, finds the parse errors and what
      # its escapes and bytes tell about its encoding; with `on_name`, a
      # second pass over its unescaped bytes finds its named captures, and
      # reports the parse errors again, as C does.
      def regexp_parse(node, on_name = nil)
        content = node.content_loc
        content_start = loc_start(content)
        extended_mode = node.flag?(RegularExpressionFlags::EXTENDED)

        scanner = RegexpScanner.new(@source.byteslice(content_start, loc_end(content) - content_start), extended_mode,
                                    @encoding_changed, @encoding, nil,
                                    ->(start, finish, id, *arguments) { err(content_start + start, content_start + finish, id, *arguments) })
        scanner.parse
        flags = regexp_validate_encoding(node, scanner, node.flags, node.unescaped)
        regexp_parse_named_captures(node.unescaped, @shared_strings[node.unescaped], extended_mode, on_name, node.location) if on_name
        flags
      end

      # pm_regexp_parse_named_captures: the named captures of a regexp's
      # unescaped bytes, `shared` at their offset in the source or nil.
      # Errors of bytes that are no slice of the source go to `location`:
      # C counts from the bytes' own address, which no port can match.
      def regexp_parse_named_captures(bytes, shared, extended_mode, on_name, location)
        on_error = lambda do |start, finish, id, *arguments|
          if shared
            err(shared + start, shared + finish, id, *arguments)
          else
            err(loc_start(location), loc_end(location), id, *arguments)
          end
        end
        RegexpScanner.new(bytes.b, extended_mode, @encoding_changed, @encoding, on_name, on_error).parse
      end

      # PM_REGEXP_ENCODING_ERROR: an error of the encoding check, at the
      # whole regexp.
      def regexp_encoding_error(node, id, *arguments) = err(node.start_offset, node.end_offset, id, *arguments)

      # pm_regexp_validate_encoding: checks the regexp's encoding, and the
      # flags that it forces. `source` is the unescaped bytes, which the
      # messages show.
      def regexp_validate_encoding(node, scanner, flags, source)
        # The parse already reported each invalid character.
        return flags if scanner.invalid_multibyte?

        if scanner.invalid_unicode_range?
          regexp_encoding_error(node, :regexp_invalid_unicode_range, source)
          return flags
        end

        ascii_only = scanner.ascii_only?
        {
          RegularExpressionFlags::ASCII_8BIT => [0x6E, Encodings::ASCII_8BIT],
          RegularExpressionFlags::UTF_8 => [0x75, Encodings::UTF_8],
          RegularExpressionFlags::EUC_JP => [0x65, Encodings::ALL.fetch(:EUC_JP)],
          RegularExpressionFlags::WINDOWS_31J => [0x73, Encodings::ALL.fetch(:WINDOWS_31J)]
        }.each do |flag, (modifier, encoding)|
          return regexp_validate_encoding_modifier(node, scanner, ascii_only, flags, modifier, encoding, source) if flags.anybits?(flag)
        end

        if @encoding == Encodings::US_ASCII && scanner.explicit_encoding.nil? && !ascii_only
          scanner.non_ascii_literal_count.times { regexp_encoding_error(node, :invalid_multibyte_char, @encoding.name) }
        end

        # An ASCII-only regexp is US-ASCII, or UTF-8 with a property escape.
        if ascii_only
          return scanner.property_escape? ? RegularExpressionFlags::FORCED_UTF8_ENCODING : RegularExpressionFlags::FORCED_US_ASCII_ENCODING
        end

        explicit = scanner.explicit_encoding
        return 0 if explicit.nil?

        if scanner.unicode_escape? && scanner.hex_escape? && @encoding != Encodings::UTF_8
          if @encoding != Encodings::US_ASCII && @encoding != Encodings::ASCII_8BIT && !regexp_valid_hex_escapes?(@encoding, scanner.hex_escapes)
            regexp_encoding_error(node, :invalid_multibyte_escape, source)
          elsif scanner.last_escape_was_unicode
            regexp_encoding_error(node, :regexp_utf8_char_non_utf8_regexp, source)
          else
            regexp_encoding_error(node, :regexp_escaped_non_ascii_in_utf8, source)
          end
          return 0
        end

        if explicit == Encodings::UTF_8
          regexp_encoding_error(node, :invalid_multibyte_escape, source) unless regexp_valid_hex_escapes?(explicit, scanner.hex_escapes)
          RegularExpressionFlags::FORCED_UTF8_ENCODING
        elsif @encoding == Encodings::US_ASCII
          RegularExpressionFlags::FORCED_BINARY_ENCODING
        else
          regexp_encoding_error(node, :invalid_multibyte_escape, source) unless regexp_valid_hex_escapes?(explicit, scanner.hex_escapes)
          0
        end
      end

      # pm_regexp_validate_encoding_modifier: the check of a regexp with an
      # encoding modifier (/n, /u, /e, /s).
      def regexp_validate_encoding_modifier(node, scanner, ascii_only, flags, modifier, modifier_encoding, source)
        if scanner.explicit_encoding.nil?
          if ascii_only
            # A property escape must suit the modifier's encoding.
            if modifier == 0x6E && scanner.property_name
              regexp_encoding_error(node, :regexp_invalid_char_property, scanner.property_name, source)
            elsif modifier != 0x75 && scanner.unicode_property_escape?
              regexp_encoding_error(node, :regexp_invalid_char_property, scanner.unicode_property_name, source)
            end
            return modifier == 0x6E ? RegularExpressionFlags::FORCED_US_ASCII_ENCODING : flags
          end

          if @encoding == Encodings::US_ASCII
            scanner.non_ascii_literal_count.times { regexp_encoding_error(node, :invalid_multibyte_char, @encoding.name) }
          elsif @encoding != modifier_encoding
            regexp_encoding_error(node, :regexp_encoding_option_mismatch, modifier, @encoding.name)
            regexp_encoding_error(node, :regexp_non_escaped_mbc, regexp_format_for_error(@encoding, source)) if modifier == 0x6E
          end
          return flags
        end

        if scanner.unicode_escape? && scanner.hex_escape?
          if modifier == 0x6E
            regexp_encoding_error(node, scanner.last_escape_was_unicode ? :regexp_utf8_char_non_utf8_regexp : :regexp_escaped_non_ascii_in_utf8, source)
          elsif !regexp_valid_hex_escapes?(modifier_encoding, scanner.hex_escapes)
            regexp_encoding_error(node, :invalid_multibyte_escape, source)
          end
          return flags
        end

        if modifier != 0x75 && scanner.explicit_encoding == Encodings::UTF_8 &&
           (scanner.last_escape_was_unicode || @encoding != Encodings::UTF_8)
          regexp_encoding_error(node, :regexp_incompat_char_encoding, source)
        end

        if modifier != 0x6E && !regexp_valid_hex_escapes?(modifier_encoding, scanner.hex_escapes)
          regexp_encoding_error(node, :invalid_multibyte_escape, source)
        end
        flags
      end

      # pm_regexp_validate_hex_escapes: each run of escaped bytes is whole
      # characters of `encoding`.
      def regexp_valid_hex_escapes?(encoding, bytes)
        bytes.split("\0").all? do |run|
          at = 0
          while at < run.bytesize
            width = encoding.char_width(run, at, run.bytesize - at)
            return false if width == 0

            at += width
          end
          true
        end
      end

      # pm_regexp_format_for_error: the source for a message, with each byte
      # past ASCII as \xNN, or a multibyte character as \x{NNNN}.
      def regexp_format_for_error(encoding, source)
        return source if encoding == Encodings::UTF_8

        out = +"".b
        at = 0
        while at < source.bytesize
          value = source.getbyte(at)
          if value < 0x80
            out << value
            at += 1
            next
          end

          width = encoding.multibyte? ? encoding.char_width(source, at, source.bytesize - at) : 1
          if width > 1
            out << "\\x{" << source.byteslice(at, width).unpack1("H*").upcase << "}"
            at += width
          else
            out << format("\\x%02X", value)
            at += 1
          end
        end
        out
      end
    end
  end
end
