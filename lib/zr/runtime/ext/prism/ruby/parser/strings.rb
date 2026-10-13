# frozen_string_literal: true
# shareable_constant_value: literal

using Prism::Ruby::Mutation

module Prism
  module Ruby
    class Parser
      # PM_CASE_KEYWORD
      CASE_KEYWORD = %i[
        KEYWORD___ENCODING__ KEYWORD___FILE__ KEYWORD___LINE__ KEYWORD_ALIAS KEYWORD_AND KEYWORD_BEGIN
        KEYWORD_BEGIN_UPCASE KEYWORD_BREAK KEYWORD_CASE KEYWORD_CLASS KEYWORD_DEF KEYWORD_DEFINED KEYWORD_DO
        KEYWORD_DO_BLOCK KEYWORD_DO_LAMBDA KEYWORD_DO_LOOP KEYWORD_ELSE KEYWORD_ELSIF KEYWORD_END KEYWORD_END_UPCASE KEYWORD_ENSURE KEYWORD_FALSE
        KEYWORD_FOR KEYWORD_IF KEYWORD_IN KEYWORD_MODULE KEYWORD_NEXT KEYWORD_NIL KEYWORD_NOT KEYWORD_OR
        KEYWORD_REDO KEYWORD_RESCUE KEYWORD_RETRY KEYWORD_RETURN KEYWORD_SELF KEYWORD_SUPER KEYWORD_THEN
        KEYWORD_TRUE KEYWORD_UNDEF KEYWORD_UNLESS KEYWORD_UNTIL KEYWORD_WHEN KEYWORD_WHILE KEYWORD_YIELD
      ]

      # PM_CASE_OPERATOR
      CASE_OPERATOR = %i[
        AMPERSAND BACKTICK BANG_EQUAL BANG_TILDE BANG BRACKET_LEFT_RIGHT_EQUAL BRACKET_LEFT_RIGHT CARET
        EQUAL_EQUAL_EQUAL EQUAL_EQUAL EQUAL_TILDE GREATER_EQUAL GREATER_GREATER GREATER LESS_EQUAL_GREATER
        LESS_EQUAL LESS_LESS LESS MINUS PERCENT PIPE PLUS SLASH STAR_STAR STAR TILDE UAMPERSAND UMINUS
        UMINUS_NUM UPLUS USTAR USTAR_STAR
      ]

      # PM_CASE_PRIMITIVE
      CASE_PRIMITIVE = %i[
        INTEGER INTEGER_IMAGINARY INTEGER_RATIONAL INTEGER_RATIONAL_IMAGINARY FLOAT FLOAT_IMAGINARY
        FLOAT_RATIONAL FLOAT_RATIONAL_IMAGINARY SYMBOL_BEGIN REGEXP_BEGIN XSTRING_BEGIN PERCENT_LOWER_X
        PERCENT_LOWER_I PERCENT_LOWER_W PERCENT_UPPER_I PERCENT_UPPER_W STRING_BEGIN KEYWORD_NIL KEYWORD_SELF
        KEYWORD_TRUE KEYWORD_FALSE KEYWORD___FILE__ KEYWORD___LINE__ KEYWORD___ENCODING__ MINUS_GREATER
        HEREDOC_START UMINUS_NUM CHARACTER_LITERAL
      ]

      # PM_CASE_PARAMETER
      CASE_PARAMETER = %i[
        UAMPERSAND AMPERSAND UDOT_DOT_DOT IDENTIFIER LABEL USTAR STAR STAR_STAR USTAR_STAR CONSTANT
        INSTANCE_VARIABLE GLOBAL_VARIABLE CLASS_VARIABLE
      ]

      # The tokens a symbol or alias may name without quotes.
      SYMBOL_NAMES = (%i[
        IDENTIFIER CONSTANT INSTANCE_VARIABLE METHOD_NAME CLASS_VARIABLE GLOBAL_VARIABLE NUMBERED_REFERENCE
        BACK_REFERENCE
      ] + CASE_KEYWORD).freeze

      private

      # parse_unescaped_encoding: the encoding flag a string's escapes force.
      def parse_unescaped_encoding(explicit = @explicit_encoding)
        return 0 if explicit.nil?
        return StringFlags::FORCED_UTF8_ENCODING if explicit == Encodings::UTF_8
        return StringFlags::FORCED_BINARY_ENCODING if @encoding == Encodings::US_ASCII

        0
      end

      # parse_string_part: string content, `#{...}` or `#@var`; nil (with an
      # error) for anything else.
      def parse_string_part(depth)
        case @current_type
        when :STRING_CONTENT
          node = string_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
          node.flag_set(parse_unescaped_encoding)

          lex
          node
        when :EMBEXPR_BEGIN
          # Ruby does not see an encoding across an interpolation.
          @explicit_encoding = nil

          state = @lex_state
          brace_nesting = @brace_nesting

          @brace_nesting = 0
          @lex_state = STATE_BEG
          lex

          opening = previous_token
          statements = nil

          unless match?(:EMBEXPR_END, :HEREDOC_END, :EOF)
            statements = parse_statements(:embexpr, depth + 1)
          end

          @brace_nesting = brace_nesting
          @lex_state = state

          expect(:EMBEXPR_END, :embexpr_end)
          closing = previous_token

          # A single statement emits no line event.
          statements.body[0].flag_unset(NodeFlags::NEWLINE) if statements && statements.body.size == 1

          embedded_statements_node(opening, statements, closing)
        when :EMBVAR
          @explicit_encoding = nil

          @lex_state = STATE_BEG
          lex

          operator = previous_token
          variable =
            case @current_type
            when :BACK_REFERENCE
              lex
              back_reference_read_node(previous_token)
            when :NUMBERED_REFERENCE
              lex
              numbered_reference_read_node(previous_token)
            when :GLOBAL_VARIABLE
              lex
              global_variable_read_node(previous_token)
            when :INSTANCE_VARIABLE
              lex
              instance_variable_read_node(previous_token)
            when :CLASS_VARIABLE
              lex
              class_variable_read_node(previous_token)
            else
              expect(:IDENTIFIER, :embvar_invalid)
              error_recovery_node(@current_start, @current_end)
            end

          embedded_variable_node(operator, variable)
        else
          lex
          err_previous(:cannot_parse_string_part)
          nil
        end
      end

      # parse_operator_symbol_name: `~@` and `!@` name `~` and `!`.
      def operator_symbol_name_end(name)
        if (name.type == :TILDE || name.type == :BANG) && @source.getbyte(name.end - 1) == 0x40
          name.end - 1
        else
          name.end
        end
      end

      # parse_operator_symbol
      def parse_operator_symbol(opening, next_state)
        symbol = symbol_node(opening, current_token, NOT_PROVIDED)
        finish = operator_symbol_name_end(current_token)

        @lex_state = next_state if next_state != STATE_NONE
        lex

        symbol.unescaped = shared_string(@previous_start, finish)
        symbol.flag_set(SymbolFlags::FORCED_US_ASCII_ENCODING)
        symbol
      end

      # parse_symbol: a symbol or interpolated symbol after its opening, in
      # `lex_mode`, the mode that opening pushed.
      def parse_symbol(lex_mode, next_state, depth)
        opening = previous_token

        unless lex_mode.mode == :string
          @lex_state = next_state if next_state != STATE_NONE

          case @current_type
          when *CASE_OPERATOR
            return parse_operator_symbol(opening, next_state == STATE_NONE ? STATE_ENDFN : next_state)
          when *SYMBOL_NAMES
            lex
          else
            expect(:IDENTIFIER, :METHOD_NAME, :symbol_invalid)
          end

          symbol = symbol_node(opening, previous_token, NOT_PROVIDED)
          symbol.unescaped = shared_string(@previous_start, @previous_end)
          symbol.flag_set(symbol_encoding(previous_token, symbol.unescaped, false))
          return symbol
        end

        if lex_mode.interpolation
          # :""
          if @current_type == :STRING_END
            @lex_state = next_state if next_state != STATE_NONE
            lex

            # Its content is empty, at the closing quote.
            return symbol_node(opening, Token.new(:STRING_CONTENT, @previous_start, @previous_start), previous_token)
          end

          part = parse_string_part(depth + 1)

          # :"abc" is a plain symbol.
          if part.is_a?(StringNode) && match?(:STRING_END, :EOF)
            @lex_state = next_state if next_state != STATE_NONE
            expect(:STRING_END, :symbol_term_interpolated)

            return string_node_to_symbol_node(part, opening, previous_token)
          end

          symbol = interpolated_symbol_node(opening, nil, opening)
          interpolated_symbol_node_append(symbol, part) if part

          until match?(:STRING_END, :EOF)
            part = parse_string_part(depth + 1)
            interpolated_symbol_node_append(symbol, part) if part
          end

          @lex_state = next_state if next_state != STATE_NONE
          if @current_type == :EOF
            err_token(opening, :symbol_term_interpolated)
          else
            expect(:STRING_END, :symbol_term_interpolated)
          end

          interpolated_node_closing_set(symbol, previous_token)
          return symbol
        end

        if @current_type == :STRING_CONTENT
          content = current_token
          unescaped = @current_string
          lex

          # Heredoc content inside the symbol splits it in two: `<<A; :'a` then
          # `b'` after the heredoc's body.
          if @current_type == :STRING_CONTENT
            symbol = interpolated_symbol_node(opening, nil, opening)

            part = string_node_unescaped(NOT_PROVIDED, content, NOT_PROVIDED, unescaped)
            interpolated_symbol_node_append(symbol, part)

            part = string_node_unescaped(NOT_PROVIDED, current_token, NOT_PROVIDED, @current_string)
            interpolated_symbol_node_append(symbol, part)

            @lex_state = next_state if next_state != STATE_NONE

            lex
            expect(:STRING_END, :symbol_term_dynamic)

            interpolated_node_closing_set(symbol, previous_token)
            return symbol
          end
        else
          content = Token.new(:STRING_CONTENT, @previous_end, @previous_end)
          unescaped = shared_string(content.start, content.end)
        end

        @lex_state = next_state if next_state != STATE_NONE

        if @current_type == :EOF
          err_token(opening, :symbol_term_dynamic)
        else
          expect(:STRING_END, :symbol_term_dynamic)
        end

        flags = symbol_encoding(content, unescaped, false)
        symbol_node_unescaped(opening, content, previous_token, unescaped, flags)
      end

      # A bare name as a symbol: `foo` in `undef foo` or `alias foo bar`.
      def parse_bare_symbol
        symbol = symbol_node(NOT_PROVIDED, previous_token, NOT_PROVIDED)
        symbol.unescaped = shared_string(@previous_start, @previous_end)
        symbol.flag_set(symbol_encoding(previous_token, symbol.unescaped, false))
        symbol
      end

      # parse_undef_argument
      def parse_undef_argument(depth)
        case @current_type
        when *CASE_OPERATOR
          parse_operator_symbol(NOT_PROVIDED, STATE_NONE)
        when *CASE_KEYWORD, :CONSTANT, :IDENTIFIER, :METHOD_NAME
          lex
          parse_bare_symbol
        when :SYMBOL_BEGIN
          lex_mode = @lex_mode.dup
          lex
          parse_symbol(lex_mode, STATE_NONE, depth + 1)
        else
          err_current(:undef_argument)
          error_recovery_node(@current_start, @current_end)
        end
      end

      # parse_alias_argument: after the first name, the state lexes the
      # second as a method name.
      def parse_alias_argument(first, depth)
        case @current_type
        when *CASE_OPERATOR
          parse_operator_symbol(NOT_PROVIDED, first ? STATE_FNAME | STATE_FITEM : STATE_NONE)
        when *CASE_KEYWORD, :CONSTANT, :IDENTIFIER, :METHOD_NAME
          @lex_state = STATE_FNAME | STATE_FITEM if first
          lex
          parse_bare_symbol
        when :SYMBOL_BEGIN
          lex_mode = @lex_mode.dup
          lex
          parse_symbol(lex_mode, first ? STATE_FNAME | STATE_FITEM : STATE_NONE, depth + 1)
        when :BACK_REFERENCE
          lex
          back_reference_read_node(previous_token)
        when :NUMBERED_REFERENCE
          lex
          numbered_reference_read_node(previous_token)
        when :GLOBAL_VARIABLE
          lex
          global_variable_read_node(previous_token)
        else
          err_current(:alias_argument)
          error_recovery_node(@current_start, @current_end)
        end
      end

      # The names in pm_numbered_parameter_names.
      NUMBERED_PARAMETER_NAMES = (1..9).map { |number| "_#{number}".b.freeze }.freeze

      # parse_variable: the previous identifier as a local variable read, a
      # numbered parameter, or `it`; nil when it is none of them.
      def parse_variable
        name_id = constant_id_location(@previous_start, @previous_end)
        numbered = numbered_parameter?(@previous_start, @previous_end)

        if !numbered && (depth = local_depth_constant_id(name_id)) != -1
          return local_variable_read_node_constant_id(previous_token, name_id, depth, false)
        end

        scope = @current_scope
        return if scope.closed? || scope.parameters.anybits?(Scope::IMPLICIT_DISALLOWED)

        if numbered
          # _2 implies _1.
          maximum = @source.getbyte(@previous_start + 1) - 0x30
          (1..maximum).each { |number| local_add_constant(NUMBERED_PARAMETER_NAMES[number - 1]) }

          scope.parameters |= Scope::NUMBERED_FOUND unless @current_type == :EQUAL

          node = local_variable_read_node_constant_id(previous_token, name_id, 0, false)
          scope.implicit_parameters << node
          node
        elsif @version >= Options::VERSION_CRUBY_3_4 && token_it?(@previous_start, @previous_end)
          node = it_local_variable_read_node(previous_token)
          scope.implicit_parameters << node
          node
        end
      end

      # parse_variable_call: the previous identifier as a local variable read
      # or a method call.
      def parse_variable_call
        flags = 0
        last = @source.getbyte(@previous_end - 1)

        if @current_type != :PARENTHESIS_LEFT && last != 0x21 && last != 0x3F
          node = parse_variable
          return node if node

          flags |= CallNodeFlags::VARIABLE_CALL
        end

        node = call_node_variable_call(previous_token)
        node.flag_set(flags)
        node
      end

      # parse_method_definition_name: the name after `def`, or a missing token
      # with an error.
      def parse_method_definition_name
        case @current_type
        when *CASE_KEYWORD, :CONSTANT, :METHOD_NAME
          lex
          previous_token
        when :IDENTIFIER
          refute_numbered_parameter(@current_start, @current_end)
          lex
          previous_token
        when *CASE_OPERATOR
          @lex_state = STATE_ENDFN
          lex
          previous_token
        else
          err_current(:def_name, Tokens::HUMAN.fetch(@current_type))
          Token.new(:MISSING, @current_start, @current_end)
        end
      end

      # parse_heredoc_dedent_string: the string without up to
      # `common_whitespace` columns of indentation. It is always a copy, as
      # pm_string_ensure_owned makes it.
      def parse_heredoc_dedent_string(string, common_whitespace)
        cursor = 0
        trimmed_whitespace = 0

        while cursor < string.bytesize && inline_whitespace?(byte = string.getbyte(cursor)) && trimmed_whitespace < common_whitespace
          if byte == 0x09
            trimmed_whitespace = (trimmed_whitespace / TAB_WHITESPACE_SIZE + 1) * TAB_WHITESPACE_SIZE
            break if trimmed_whitespace > common_whitespace
          else
            trimmed_whitespace += 1
          end
          cursor += 1
        end

        owned_string(string.byteslice(cursor..))
      end

      # parse_heredoc_dedent: the indentation of a <<~ heredoc's lines, which
      # are the string parts at the start or after another string part; a
      # part left empty goes, unless it is a line continuation
      # (heredoc_dedent_discard_string_node).
      def parse_heredoc_dedent(nodes, common_whitespace)
        dedent_next = true

        nodes.select! do |node|
          unless node.is_a?(StringNode)
            dedent_next = false
            next true
          end

          node.unescaped = parse_heredoc_dedent_string(node.unescaped, common_whitespace) if dedent_next
          dedent_next = true
          next true unless node.unescaped.empty?

          content = node.content_loc
          memchr(@source.byteslice(loc_start(content), loc_end(content) - loc_start(content)), 0x5C, 0)
        end
      end

      # parse_strings: string literals, joined when adjacent (`"a" 'b'`), or
      # a symbol from a label (`"a":`).
      def parse_strings(current, accepts_label, depth)
        concating = false

        while @current_type == :STRING_BEGIN
          lex_mode = @lex_mode
          lex_interpolation = lex_mode.interpolation
          label_allowed = lex_mode.label_allowed && accepts_label

          opening = current_token
          lex

          if match?(:STRING_END, :EOF)
            expect(:STRING_END, :string_literal_eof)

            # An empty string.
            content = Token.new(:STRING_CONTENT, @previous_start, @previous_start)
            node = string_node(opening, content, previous_token)
            node.unescaped = shared_string(content.start, content.end)
          elsif accept(:LABEL_END)
            # "": has no content token, and C gives its content the location
            # at offset 0, of no length.
            node = symbol_node(opening, Token.new(:STRING_CONTENT, 0, 0), previous_token)
            node.unescaped = shared_string(@previous_start, @previous_start)

            err_node(node, :unexpected_label) unless label_allowed
          elsif !lex_interpolation
            if @current_type == :EOF
              unescaped = "".b
              content = NOT_PROVIDED
            else
              unescaped = @current_string
              expect(:STRING_CONTENT, :expect_string_content)
              content = previous_token
            end

            if @current_type == :STRING_CONTENT
              # Heredoc content in the middle: `<<-END+'b` ... `c'`.
              parts = [string_node_unescaped(NOT_PROVIDED, content, NOT_PROVIDED, unescaped)]

              loop do
                parts << string_node_current_string(NOT_PROVIDED, current_token, NOT_PROVIDED)
                lex
                break unless @current_type == :STRING_CONTENT
              end

              expect(:STRING_END, :string_literal_eof)
              node = interpolated_string_node(opening, parts, previous_token)
            elsif accept(:LABEL_END)
              flags = symbol_encoding(content, unescaped, true)
              node = symbol_node_unescaped(opening, content, previous_token, unescaped, flags)
              err_node(node, :unexpected_label) unless label_allowed
            elsif @current_type == :EOF
              err_token(opening, :string_literal_eof)
              node = string_node_unescaped(opening, content, current_token, unescaped)
            elsif accept(:STRING_END)
              node = string_node_unescaped(opening, content, previous_token, unescaped)
            else
              err_previous(:string_literal_term, Tokens::HUMAN.fetch(@previous_type))
              @previous_start = @previous_end
              @previous_type = :MISSING
              node = string_node_unescaped(opening, content, previous_token, unescaped)
            end
          elsif @current_type == :STRING_CONTENT
            content = current_token
            unescaped = @current_string
            # The content's encoding, before the next token lexes another.
            explicit = @explicit_encoding
            lex

            if match?(:STRING_END, :EOF)
              node = string_node_unescaped(opening, content, current_token, unescaped)
              node.flag_set(parse_unescaped_encoding(explicit))

              # An unterminated string: the error is at the end of its last
              # line of content.
              unless accept(:STRING_END)
                location = @previous_end
                location -= 1 if location > 0 && @source.getbyte(location - 1) == 0x0A
                err(location, location, :string_literal_eof)

                @previous_start = @previous_end
                @previous_type = :MISSING
              end
            elsif accept(:LABEL_END)
              flags = symbol_encoding(content, unescaped, true, explicit)
              node = symbol_node_unescaped(opening, content, previous_token, unescaped, flags)
              err_node(node, :unexpected_label) unless label_allowed
            else
              # Interpolation.
              part = string_node_unescaped(NOT_PROVIDED, previous_token, NOT_PROVIDED, unescaped)
              part.flag_set(parse_unescaped_encoding(explicit))
              parts = [part]

              until match?(:STRING_END, :LABEL_END, :EOF)
                part = parse_string_part(depth + 1)
                parts << part if part
              end

              node = parse_strings_close(opening, parts, label_allowed)
            end
          else
            # Interpolation from the start.
            parts = []
            until match?(:STRING_END, :LABEL_END, :EOF)
              part = parse_string_part(depth + 1)
              parts << part if part
            end

            node = parse_strings_close(opening, parts, label_allowed)
          end

          if current.nil?
            # A symbol cannot be joined to anything.
            return node if node.is_a?(SymbolNode) || node.is_a?(InterpolatedSymbolNode)

            current = node
          else
            unless node.is_a?(StringNode) || node.is_a?(InterpolatedStringNode)
              err_node(node, :string_concatenation)
            end

            unless concating
              unless current.is_a?(StringNode) || current.is_a?(InterpolatedStringNode)
                err_node(current, :string_concatenation)
              end

              concating = true
              container = interpolated_string_node(NOT_PROVIDED, nil, NOT_PROVIDED)
              interpolated_string_node_append(container, current)
              current = container
            end

            interpolated_string_node_append(current, node)
          end
        end

        current
      end

      # The end of an interpolated string, or a symbol from a label.
      def parse_strings_close(opening, parts, label_allowed)
        if accept(:LABEL_END)
          node = interpolated_symbol_node(opening, parts, previous_token)
          err_node(node, :unexpected_label) unless label_allowed
          node
        elsif @current_type == :EOF
          err_token(opening, :string_interpolated_term)
          interpolated_string_node(opening, parts, current_token)
        else
          expect(:STRING_END, :string_interpolated_term)
          interpolated_string_node(opening, parts, previous_token)
        end
      end
    end
  end
end
