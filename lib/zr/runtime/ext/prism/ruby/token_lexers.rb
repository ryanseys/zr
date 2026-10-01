# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # prism.c's "Specific token lexers": numbers, global, instance and class
    # variables, identifiers and keywords, character literals and embedded
    # documentation. Each advances @current_end and returns a token type.
    class Parser
      # The punctuation a global variable's name may be (the `PUNCT` hash).
      GLOBAL_NAME_PUNCTUATION = "~*$?!@/\\;,.=:<>\"&`'+0".bytes.freeze

      # The keywords lex_identifier knows: text => [state, type, modifier
      # type or nil]. C tries them by length in turn; no two share a text, so
      # one lookup finds the one C finds.
      KEYWORDS = {
        "do" => [STATE_BEG, :KEYWORD_DO, nil], "if" => [STATE_BEG, :KEYWORD_IF, :KEYWORD_IF_MODIFIER],
        "in" => [STATE_BEG, :KEYWORD_IN, nil], "or" => [STATE_BEG, :KEYWORD_OR, nil],
        "and" => [STATE_BEG, :KEYWORD_AND, nil], "def" => [STATE_FNAME, :KEYWORD_DEF, nil],
        "end" => [STATE_END, :KEYWORD_END, nil], "END" => [STATE_END, :KEYWORD_END_UPCASE, nil],
        "for" => [STATE_BEG, :KEYWORD_FOR, nil], "nil" => [STATE_END, :KEYWORD_NIL, nil],
        "not" => [STATE_ARG, :KEYWORD_NOT, nil],
        "case" => [STATE_BEG, :KEYWORD_CASE, nil], "else" => [STATE_BEG, :KEYWORD_ELSE, nil],
        "next" => [STATE_MID, :KEYWORD_NEXT, nil], "redo" => [STATE_END, :KEYWORD_REDO, nil],
        "self" => [STATE_END, :KEYWORD_SELF, nil], "then" => [STATE_BEG, :KEYWORD_THEN, nil],
        "true" => [STATE_END, :KEYWORD_TRUE, nil], "when" => [STATE_BEG, :KEYWORD_WHEN, nil],
        "alias" => [STATE_FNAME | STATE_FITEM, :KEYWORD_ALIAS, nil], "begin" => [STATE_BEG, :KEYWORD_BEGIN, nil],
        "BEGIN" => [STATE_END, :KEYWORD_BEGIN_UPCASE, nil], "break" => [STATE_MID, :KEYWORD_BREAK, nil],
        "class" => [STATE_CLASS, :KEYWORD_CLASS, nil], "elsif" => [STATE_BEG, :KEYWORD_ELSIF, nil],
        "false" => [STATE_END, :KEYWORD_FALSE, nil], "retry" => [STATE_END, :KEYWORD_RETRY, nil],
        "super" => [STATE_ARG, :KEYWORD_SUPER, nil], "undef" => [STATE_FNAME | STATE_FITEM, :KEYWORD_UNDEF, nil],
        "until" => [STATE_BEG, :KEYWORD_UNTIL, :KEYWORD_UNTIL_MODIFIER],
        "while" => [STATE_BEG, :KEYWORD_WHILE, :KEYWORD_WHILE_MODIFIER], "yield" => [STATE_ARG, :KEYWORD_YIELD, nil],
        "ensure" => [STATE_BEG, :KEYWORD_ENSURE, nil], "module" => [STATE_BEG, :KEYWORD_MODULE, nil],
        "rescue" => [STATE_MID, :KEYWORD_RESCUE, :KEYWORD_RESCUE_MODIFIER], "return" => [STATE_MID, :KEYWORD_RETURN, nil],
        "unless" => [STATE_BEG, :KEYWORD_UNLESS, :KEYWORD_UNLESS_MODIFIER],
        "__LINE__" => [STATE_END, :KEYWORD___LINE__, nil], "__FILE__" => [STATE_END, :KEYWORD___FILE__, nil],
        "__ENCODING__" => [STATE_END, :KEYWORD___ENCODING__, nil]
      }.to_h { |text, row| [text.b.freeze, row.freeze] }.freeze

      # The lengths a keyword has.
      KEYWORD_WIDTHS = KEYWORDS.keys.map(&:bytesize).uniq.freeze

      private

      # -- identifier characters ---------------------------------------------

      # char_is_identifier_start
      def identifier_start_width(at)
        n = @end - at
        return 0 if n <= 0

        byte = @source.getbyte(at)
        if @encoding_changed
          if (width = @encoding.alpha_char(@source, at, n)) != 0
            width
          elsif byte == 0x5F
            1
          elsif byte >= 0x80
            @encoding.char_width(@source, at, n)
          else
            0
          end
        elsif byte < 0x80
          Encodings::UNICODE_TABLE.getbyte(byte).anybits?(Encodings::ALPHABETIC) || byte == 0x5F ? 1 : 0
        else
          Encodings::UTF_8.char_width(@source, at, n)
        end
      end

      # char_is_identifier_utf8
      def identifier_width_utf8(at)
        n = @end - at
        return 0 if n <= 0

        byte = @source.getbyte(at)
        if byte < 0x80
          byte == 0x5F || Encodings::UNICODE_TABLE.getbyte(byte).anybits?(Encodings::ALPHANUMERIC) ? 1 : 0
        else
          Encodings::UTF_8.char_width(@source, at, n)
        end
      end

      # char_is_identifier
      def identifier_width(at)
        n = @end - at
        return 0 if n <= 0
        return identifier_width_utf8(at) unless @encoding_changed

        byte = @source.getbyte(at)
        if (width = @encoding.alnum_char(@source, at, n)) != 0
          width
        elsif byte == 0x5F
          1
        elsif byte >= 0x80
          @encoding.char_width(@source, at, n)
        else
          0
        end
      end

      # char_is_global_name_punctuation
      def global_name_punctuation?(byte) = byte > 0x20 && byte <= 0x7E && GLOBAL_NAME_PUNCTUATION.include?(byte)

      # The width of the character at `at` in the source's encoding, as
      # parser_char_width calculates it: never 0.
      def parser_char_width
        width = @encoding_changed ? @encoding.char_width(@source, @current_end, @end - @current_end) : Encodings::UTF_8.char_width(@source, @current_end, @end - @current_end)
        width == 0 ? 1 : width
      end

      # current_token_starts_line
      def current_token_starts_line? = @current_start == 0 || @source.getbyte(@current_start - 1) == 0x0A

      # pm_token_is_numbered_parameter: /\A_[1-9]\z/.
      def numbered_parameter?(start, finish)
        finish - start == 2 && @source.getbyte(start) == 0x5F && @source.getbyte(start + 1) != 0x30 && decimal_digit?(@source.getbyte(start + 1))
      end

      # -- numbers ------------------------------------------------------------

      # pm_strspn_number_validate: an error for a misplaced underscore.
      def number_validate(from, (length, invalid))
        if invalid
          id = invalid == from + length - 1 ? :invalid_number_underscore_trailing : :invalid_number_underscore_inner
          err(invalid, invalid + 1, id)
        end
        length
      end

      def binary_number_validate(from) = number_validate(from, strspn_binary_number(from, @end))
      def octal_number_validate(from) = number_validate(from, strspn_octal_number(from, @end))
      def decimal_number_validate(from) = number_validate(from, strspn_decimal_number(from, @end))
      def hexadecimal_number_validate(from) = number_validate(from, strspn_hexadecimal_number(from, @end))

      # lex_optional_float_suffix: the type and whether an exponent was seen.
      def lex_optional_float_suffix
        type = :INTEGER
        seen_e = false

        if peek == 0x2E
          return [type, seen_e] unless decimal_digit?(peek_offset(1))

          @current_end += 2
          @current_end += decimal_number_validate(@current_end)
          type = :FLOAT
        end

        if peek == 0x65 || peek == 0x45
          if peek_offset(1) == 0x2B || peek_offset(1) == 0x2D
            @current_end += 2
            if decimal_digit?(peek)
              @current_end += 1
              @current_end += decimal_number_validate(@current_end)
            else
              err_current(:invalid_float_exponent)
            end
          elsif decimal_digit?(peek_offset(1))
            @current_end += 1
            @current_end += decimal_number_validate(@current_end)
          else
            return [type, seen_e]
          end

          seen_e = true
          type = :FLOAT
        end

        [type, seen_e]
      end

      # lex_numeric_prefix
      def lex_numeric_prefix
        type = :INTEGER
        seen_e = false

        if peek_offset(-1) == 0x30
          case @source.getbyte(@current_end)
          when 0x64, 0x44 # 0d
            @current_end += 1
            if decimal_digit?(peek)
              @current_end += decimal_number_validate(@current_end)
            else
              match(0x5F)
              err_current(:invalid_number_decimal)
            end
          when 0x62, 0x42 # 0b
            @current_end += 1
            if binary_digit?(peek)
              @current_end += binary_number_validate(@current_end)
            else
              match(0x5F)
              err_current(:invalid_number_binary)
            end
            @integer_base = INTEGER_BASE_BINARY
          when 0x6F, 0x4F # 0o
            @current_end += 1
            if octal_digit?(peek)
              @current_end += octal_number_validate(@current_end)
            else
              match(0x5F)
              err_current(:invalid_number_octal)
            end
            @integer_base = INTEGER_BASE_OCTAL
          when 0x5F, 0x30..0x37 # 01
            @current_end += octal_number_validate(@current_end)
            @integer_base = INTEGER_BASE_OCTAL
          when 0x78, 0x58 # 0x
            @current_end += 1
            if hexadecimal_digit?(peek)
              @current_end += hexadecimal_number_validate(@current_end)
            else
              match(0x5F)
              err_current(:invalid_number_hexadecimal)
            end
            @integer_base = INTEGER_BASE_HEXADECIMAL
          when 0x2E, 0x65, 0x45 # 0.x 0ex
            type, seen_e = lex_optional_float_suffix
          end
        else
          @current_end += decimal_number_validate(@current_end)
          type, seen_e = lex_optional_float_suffix
        end

        # A second fractional part, 1.2.3, is an error on the extra part.
        if peek_offset(0) == 0x2E && decimal_digit?(peek_offset(1))
          fraction_start = @current_end
          fraction_end = @current_end + 2
          fraction_end += strspn_decimal_digit(fraction_end, @end)
          err(fraction_start, fraction_end, :invalid_number_fraction)
        end

        [type, seen_e]
      end

      # lex_numeric
      def lex_numeric
        type = :INTEGER
        @integer_base = INTEGER_BASE_DECIMAL
        return type unless @current_end < @end

        type, seen_e = lex_numeric_prefix
        finish = @current_end
        suffix_type = type

        if type == :INTEGER
          if match(0x72)
            suffix_type = match(0x69) ? :INTEGER_RATIONAL_IMAGINARY : :INTEGER_RATIONAL
          elsif match(0x69)
            suffix_type = :INTEGER_IMAGINARY
          end
        elsif !seen_e && match(0x72)
          suffix_type = match(0x69) ? :FLOAT_RATIONAL_IMAGINARY : :FLOAT_RATIONAL
        elsif match(0x69)
          suffix_type = :FLOAT_IMAGINARY
        end

        byte = peek
        if byte != 0 && (byte >= 0x80 || (byte >= 0x61 && byte <= 0x7A) || (byte >= 0x41 && byte <= 0x5A) || byte == 0x5F)
          @current_end = finish
        else
          type = suffix_type
        end
        type
      end

      # -- variables ------------------------------------------------------------

      # The error lex_global_variable and lex_at_variable give for an invalid
      # name under 3.3 or later versions.
      def before_3_4? = @version <= Options::VERSION_CRUBY_3_3

      # lex_global_variable
      def lex_global_variable
        if @current_end >= @end
          err_current(:global_variable_bare)
          return :GLOBAL_VARIABLE
        end

        allow_multiple = true
        case @source.getbyte(@current_end)
        when 0x7E, 0x2A, 0x24, 0x3F, 0x21, 0x40, 0x2F, 0x5C, 0x3B, 0x2C, 0x2E, 0x3D, 0x3A, 0x3C, 0x3E, 0x22
          @current_end += 1
          return :GLOBAL_VARIABLE
        when 0x26, 0x60, 0x27, 0x2B
          @current_end += 1
          return lex_state?(STATE_FNAME) ? :GLOBAL_VARIABLE : :BACK_REFERENCE
        when 0x30
          @current_end += 1
          if (width = identifier_width(@current_end)) > 0
            @current_end += width while (width = identifier_width(@current_end)) > 0
            err_current_content(before_3_4? ? :invalid_variable_global_3_3 : :invalid_variable_global)
          end
          return :GLOBAL_VARIABLE
        when 0x31..0x39
          @current_end += strspn_decimal_digit(@current_end, @end)
          return lex_state?(STATE_FNAME) ? :GLOBAL_VARIABLE : :NUMBERED_REFERENCE
        when 0x2D
          @current_end += 1
          allow_multiple = false
        end

        if (width = identifier_width(@current_end)) > 0
          loop do
            @current_end += width
            break unless allow_multiple && (width = identifier_width(@current_end)) > 0
          end
        elsif whitespace?(peek)
          err_current(:global_variable_bare)
        else
          finish = @current_end + @encoding.char_width(@source, @current_end, @end - @current_end)
          err(@current_start, finish, before_3_4? ? :invalid_variable_global_3_3 : :invalid_variable_global,
              @source.byteslice(@current_start, finish - @current_start))
        end
        :GLOBAL_VARIABLE
      end

      # lex_at_variable
      def lex_at_variable
        type = match(0x40) ? :CLASS_VARIABLE : :INSTANCE_VARIABLE

        if (width = identifier_start_width(@current_end)) > 0
          @current_end += width
          @current_end += width while (width = identifier_width(@current_end)) > 0
        elsif @current_end < @end && decimal_digit?(@source.getbyte(@current_end))
          id =
            if before_3_4?
              type == :CLASS_VARIABLE ? :incomplete_variable_class_3_3 : :incomplete_variable_instance_3_3
            else
              type == :CLASS_VARIABLE ? :incomplete_variable_class : :incomplete_variable_instance
            end
          width = @encoding.char_width(@source, @current_end, @end - @current_end)
          err_current(id, @source.byteslice(@current_start, @current_end + width - @current_start))
        else
          err_current(type == :CLASS_VARIABLE ? :class_variable_bare : :instance_variable_bare)
        end

        # An embedded variable goes back to the mode around it.
        lex_mode_pop if @lex_mode.mode == :embvar
        type
      end

      # -- identifiers and keywords ----------------------------------------------

      # lex_keyword, for a text known to be the keyword: the state it moves
      # to, and the type or the modifier type that it returns.
      def lex_keyword(state, type, modifier_type)
        last_state = @lex_state
        if lex_state?(STATE_FNAME)
          @lex_state = STATE_ENDFN
        else
          @lex_state = state
          @command_start = true if state == STATE_BEG

          if modifier_type && !last_state.anybits?(STATE_BEG | STATE_LABELED | STATE_CLASS)
            @lex_state = STATE_BEG | STATE_LABEL
            return modifier_type
          end
        end
        type
      end

      # lex_identifier
      def lex_identifier(previous_command_start)
        start = @current_start
        if @encoding_changed
          while (width = identifier_width(@current_end)) > 0
            @current_end += width
          end
        else
          while (width = identifier_width_utf8(@current_end)) > 0
            @current_end += width
          end
        end
        width = @current_end - start

        if @current_end < @end
          if (@current_end + 1 >= @end || @source.getbyte(@current_end + 1) != 0x3D) && (match(0x21) || match(0x3F))
            width += 1

            if label_position?(previous_command_start) && peek == 0x3A && peek_offset(1) != 0x3A
              @lex_state = STATE_ARG | STATE_LABELED
              match(0x3A)
              return :LABEL
            end

            if @lex_state != STATE_DOT && width == 8 && @source.byteslice(start, 8) == "defined?"
              return lex_keyword(STATE_ARG, :KEYWORD_DEFINED, nil)
            end

            return :METHOD_NAME
          end

          if lex_state?(STATE_FNAME) && peek_offset(1) != 0x7E && peek_offset(1) != 0x3E && (peek_offset(1) != 0x3D || peek_offset(2) == 0x3E) && match(0x3D)
            return :IDENTIFIER
          end

          if label_position?(previous_command_start) && peek == 0x3A && peek_offset(1) != 0x3A
            @lex_state = STATE_ARG | STATE_LABELED
            match(0x3A)
            return :LABEL
          end
        end

        if @lex_state != STATE_DOT && KEYWORD_WIDTHS.include?(width) && (keyword = KEYWORDS[@source.byteslice(start, width)])
          found = lex_keyword(*keyword)
          return do_loop_stack? ? :KEYWORD_DO_LOOP : :KEYWORD_DO if found == :KEYWORD_DO

          return found
        end

        upper = @encoding_changed ? @encoding.isupper_char(@source, start, @end - start) : Encodings::UTF_8.isupper_char(@source, start, @end - start)
        upper ? :CONSTANT : :IDENTIFIER
      end

      # Where an identifier may take a trailing `:` as a label.
      def label_position?(previous_command_start)
        (lex_state?(STATE_LABEL | STATE_ENDFN) && !previous_command_start) || lex_state_arg?
      end

      # -- embedded documentation ------------------------------------------------

      # parser_lex_callback
      def lex_callback
        @lex_callback&.call(@current_type, @current_start, @current_end, @lex_state)
      end

      # lex_embdoc: :EMBDOC_END, or :EOF when the document never ends. The
      # begin, line and end tokens go to the lex callback only.
      def lex_embdoc
        newline = next_newline(@current_end)
        if newline.nil?
          @current_end = @end
        else
          newline_append(newline)
          @current_end = newline + 1
        end
        @current_type = :EMBDOC_BEGIN
        lex_callback

        comment = [:embdoc, @current_start, @current_end]

        while @current_end + 4 <= @end
          @current_start = @current_end

          if @source.byteslice(@current_end, 4) == "=end" &&
             (@current_end + 4 == @end || whitespace?(following = @source.getbyte(@current_end + 4)) || following == 0x00 || following == 0x04 || following == 0x1A)
            newline = next_newline(@current_end)
            if newline.nil?
              @current_end = @end
            else
              newline_append(newline)
              @current_end = newline + 1
            end
            @current_type = :EMBDOC_END
            lex_callback
            comment[2] = @current_end
            @comments << comment
            return :EMBDOC_END
          end

          newline = next_newline(@current_end)
          if newline.nil?
            @current_end = @end
          else
            newline_append(newline)
            @current_end = newline + 1
          end
          @current_type = :EMBDOC_LINE
          lex_callback
        end

        err_current(:embdoc_term)
        comment[2] = @current_end
        @comments << comment
        :EOF
      end
    end
  end
end
