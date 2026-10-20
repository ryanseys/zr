# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

module Prism
  module Ruby
    # parser_lex: the next token, moved into @current_* with the one before
    # it in @previous_*. The default mode (also the embedded expression and
    # variable modes) is here; the string, list, regexp and heredoc modes
    # are in lex_modes.rb.
    class Parser
      private

      # parser_lex
      def lex
        @previous_type = @current_type
        @previous_start = @current_start
        @previous_end = @current_end

        # This mirrors cmd_state in CRuby.
        previous_command_start = @command_start
        @command_start = false

        # A token that does not count as meaningful puts the flag back.
        semantic_token_seen = @semantic_token_seen
        @semantic_token_seen = true

        lex_mode_dispatch(previous_command_start, semantic_token_seen)
      end

      # The lexer of the current lex mode (C's `switch_lex_modes`).
      def lex_mode_dispatch(previous_command_start, semantic_token_seen)
        case @lex_mode.mode
        when :default, :embexpr, :embvar then lex_default(previous_command_start, semantic_token_seen)
        when :list then lex_list
        when :string, :regexp then lex_literal
        when :heredoc then lex_heredoc
        end
      end

      # LEX: the token is done.
      def lex_token(type)
        @current_type = type
        lex_callback
        nil
      end

      # The default mode. Each turn of the loop is C's `lex_next_token`, the
      # label a comment, an ignored newline or an invalid token jumps back to.
      def lex_default(previous_command_start, semantic_token_seen)
        lexed_comment = false

        loop do
          if @next_start
            @current_end = @next_start
            @next_start = nil
          end

          space_seen = skip_space

          @current_start = @current_end

          if @current_end >= @end
            # A construct left open at the end closes mode by mode, so that
            # each one cleans up (a heredoc moves next_start); only then is
            # the EOF lexed.
            unless @lex_mode.mode == :default
              lex_mode_pop
              return lex_mode_dispatch(previous_command_start, semantic_token_seen)
            end

            # An EOF right after a newline is reported on the newline's line.
            @current_start -= 1 if @current_start > 0 && @source.getbyte(@current_start - 1) == 0x0A
            return lex_token(:EOF)
          end

          byte = @source.getbyte(@current_end)
          @current_end += 1

          type =
            case byte
            when 0x00, 0x04, 0x1A # NUL, ^D, ^Z end the script
              @current_end -= 1
              :EOF
            when 0x23, 0x0D, 0x0A # a comment, then the newline it ends in
              # A comment at the end of the file has no newline to lex.
              lexed_comment = !lex_comment(semantic_token_seen) if byte == 0x23
              case lex_newline(lexed_comment, semantic_token_seen)
              when :again
                lexed_comment = false
                next
              when :done then return
              end
              # A comment at the end of the file has no newline to report.
              lex_callback unless lexed_comment
              return
            when 0x2C # ,
              if @previous_type == :COMMA && @enclosure_nesting > 0
                err_current(:array_term, Tokens::HUMAN.fetch(@current_type))
              end
              @lex_state = STATE_BEG | STATE_LABEL
              :COMMA
            when 0x28 then lex_parenthesis_left(space_seen)
            when 0x29 # )
              @enclosure_nesting -= 1
              @lex_state = STATE_ENDFN
              enclosure_frame_pop
              :PARENTHESIS_RIGHT
            when 0x3B # ;
              @lex_state = STATE_BEG
              @command_start = true
              :SEMICOLON
            when 0x5B then lex_bracket_left(space_seen)
            when 0x5D # ]
              @enclosure_nesting -= 1
              @lex_state = STATE_END
              enclosure_frame_pop
              :BRACKET_RIGHT
            when 0x7B then lex_brace_left
            when 0x7D then lex_brace_right
            when 0x2A then lex_star(space_seen)
            when 0x21 then lex_bang
            when 0x3D then lex_equal
            when 0x3C then lex_less(space_seen)
            when 0x3E then lex_greater
            when 0x22 # double-quoted string
              lex_mode_push_string(true, label_position?(previous_command_start), 0, 0x22)
              :STRING_BEGIN
            when 0x60 then lex_backtick(previous_command_start)
            when 0x27 # single-quoted string
              lex_mode_push_string(false, label_position?(previous_command_start), 0, 0x27)
              :STRING_BEGIN
            when 0x3F then lex_question_mark
            when 0x26 then lex_ampersand(space_seen)
            when 0x7C then lex_pipe
            when 0x2B then lex_plus(space_seen)
            when 0x2D then lex_minus(space_seen)
            when 0x2E then lex_dot
            when 0x30..0x39
              type = lex_numeric
              @lex_state = STATE_END
              type
            when 0x3A then lex_colon(space_seen)
            when 0x2F then lex_slash(space_seen)
            when 0x5E # ^ ^=
              @lex_state = lex_state_operator? ? STATE_ARG : STATE_BEG
              match(0x3D) ? :CARET_EQUAL : :CARET
            when 0x7E # ~ ~@
              if lex_state_operator?
                match(0x40)
                @lex_state = STATE_ARG
              else
                @lex_state = STATE_BEG
              end
              :TILDE
            when 0x25 then lex_percent(space_seen)
            when 0x24 # global variable
              type = lex_global_variable
              lex_mode_pop if @lex_mode.mode == :embvar
              @lex_state = STATE_END
              type
            when 0x40 # instance or class variable
              @lex_state = lex_state?(STATE_FNAME) ? STATE_ENDFN : STATE_END
              lex_at_variable
            else
              lex_word(previous_command_start)
            end

          # A nil type is C's `goto lex_next_token`.
          next if type.nil?

          return lex_token(type)
        end
      end

      # The whitespace before a token, and escaped newlines: whether any was
      # seen (CRuby's space_seen).
      def skip_space
        space_seen = false
        while @current_end < @end
          case @source.getbyte(@current_end)
          when 0x20, 0x09, 0x0C, 0x0B
            @current_end += 1
            space_seen = true
          when 0x0D
            break if match_eol_offset(1) != 0

            warn(@current_end, @current_end + 1, :unexpected_carriage_return)
            @current_end += 1
            space_seen = true
          when 0x5C
            eol_length = match_eol_offset(1)
            if eol_length != 0
              if @heredoc_end
                @current_end = @heredoc_end
                @heredoc_end = nil
              else
                @current_end += eol_length + 1
                newline_append(@current_end - 1)
                space_seen = true
              end
            else
              # C tests the backslash itself for inline whitespace here, which
              # it never is.
              break
            end
          else
            break
          end
        end
        space_seen
      end

      # A # comment to the end of its line, which may be a magic comment.
      # The comment leaves out its newline, which then lexes as a token of
      # its own: the current token is that newline. It returns whether the
      # comment ends in a newline.
      def lex_comment(semantic_token_seen)
        ending = next_newline(@current_end)
        @current_end = ending.nil? ? @end : ending

        comment = [:inline, @current_start, @current_end]
        @comments << comment

        @current_type = :COMMENT
        lex_callback

        # A first-line comment that is no key/value magic comment may still
        # name an encoding.
        if !magic_comment(semantic_token_seen) && @current_start == @encoding_comment_start &&
           @current_end - @current_start >= 10 && !@encoding_locked
          magic_comment_encoding
        end
        return false if ending.nil?

        @current_start = ending
        @current_end = ending + 1
        true
      end

      # The newline that ends a construct where a newline is otherwise
      # not significant: the lexer reports it, then gives the parser a
      # NEWLINE.
      def lex_newline_terminator
        @current_type = :NEWLINE_TERMINATOR
        lex_callback
      end

      # parser_lex_ignored_newline
      def lex_ignored_newline
        @current_type = :IGNORED_NEWLINE
        lex_callback
      end

      # parser_flush_heredoc_end
      def flush_heredoc_end
        @next_start = @heredoc_end
        @heredoc_end = nil
      end

      # parser_end_of_line_p: only inline whitespace before a newline or a
      # comment.
      def end_of_line?
        cursor = @current_end
        while cursor < @end && (byte = @source.getbyte(cursor)) != 0x0A && byte != 0x23
          return false unless inline_whitespace?(byte)

          cursor += 1
        end
        true
      end

      # The newline after a comment or on its own. It returns :again to lex
      # the next token instead (an ignored newline), :done when the token is
      # set and reported, or nil for a NEWLINE token whose report depends
      # on whether a comment came before.
      def lex_newline(lexed_comment, semantic_token_seen)
        @semantic_token_seen = semantic_token_seen
        eol_length = match_eol_at(@current_end - 1)

        if eol_length != 0
          # A \r\n is one newline token; a comment has already moved past it.
          @current_end += eol_length - 1 unless lexed_comment
          newline_append(@current_end - 1) if @heredoc_end.nil?
        end

        flush_heredoc_end if @heredoc_end

        case lex_state_ignored
        when :pattern
          if @pattern_matching_newlines || @in_keyword_arg
            lex_newline_terminator unless lexed_comment
            @lex_state = STATE_BEG
            @command_start = true
            @current_type = :NEWLINE
            return :done
          end
          lex_ignored_newline unless lexed_comment
          return :again
        when :all
          lex_ignored_newline unless lexed_comment
          return :again
        end

        # A call operator or (from 4.0) a logical operator starting the next
        # line makes this newline ignored and lexes that operator instead.
        next_content = @next_start.nil? ? @current_end : @next_start
        next_content += strspn_inline_whitespace(next_content, @end)

        if next_content < @end
          if @source.getbyte(next_content) == 0x23
            following = next_newline(next_content)
            while following && following + 1 < @end
              following += 1
              following += strspn_inline_whitespace(following, @end)
              break if peek_at(following) != 0x23

              following = next_newline(following)
            end

            if lex_state_ignored != :none
              lex_ignored_newline unless lexed_comment
              return :again
            end

            if following && (peek_at(following) == 0x2E || (peek_at(following) == 0x26 && peek_at(following + 1) == 0x2E))
              lex_ignored_newline unless lexed_comment
              return :again
            end

            if @version >= Options::VERSION_CRUBY_4_0 && following && logical_operator_at?(following, next_content)
              lex_ignored_newline unless lexed_comment
              return :again
            end
          end

          if @source.getbyte(next_content) == 0x2E
            # A beginless range on the next line means that this newline
            # ends the statement, not that a method chain goes on.
            if peek_at(next_content + 1) == 0x2E
              lex_newline_terminator unless lexed_comment
              @lex_state = STATE_BEG
              @command_start = true
              @current_type = :NEWLINE
              return :done
            end

            return newline_operator(lexed_comment, STATE_DOT, next_content, 1, :DOT)
          end

          if peek_at(next_content) == 0x26 && peek_at(next_content + 1) == 0x2E
            return newline_operator(lexed_comment, STATE_DOT, next_content, 2, :AMPERSAND_DOT)
          end

          if @version >= Options::VERSION_CRUBY_4_0
            if peek_at(next_content) == 0x26 && peek_at(next_content + 1) == 0x26
              return newline_operator(lexed_comment, STATE_BEG, next_content, 2, :AMPERSAND_AMPERSAND)
            end

            if peek_at(next_content) == 0x7C && peek_at(next_content + 1) == 0x7C
              return newline_operator(lexed_comment, STATE_BEG, next_content, 2, :PIPE_PIPE)
            end

            if peek_at(next_content) == 0x61 && peek_at(next_content + 1) == 0x6E && peek_at(next_content + 2) == 0x64 &&
               !predicate_suffix?(next_content + 3) && identifier_width(next_content + 3) == 0
              @command_start = true
              return newline_operator(lexed_comment, STATE_BEG, next_content, 3, :KEYWORD_AND)
            end

            if peek_at(next_content) == 0x6F && peek_at(next_content + 1) == 0x72 &&
               !predicate_suffix?(next_content + 2) && identifier_width(next_content + 2) == 0
              @command_start = true
              return newline_operator(lexed_comment, STATE_BEG, next_content, 2, :KEYWORD_OR)
            end
          end
        end

        # A plain newline.
        @lex_state = STATE_BEG
        @command_start = true
        @current_type = :NEWLINE
        nil
      end

      # `&&`, `||`, `and` or `or` at `at`, as a line may start with them.
      # `and?` and `or!` are method names, not keywords (from 4.0). After a
      # comment, C tests the byte after the keyword's length from `guard`,
      # the start of the next line's content, not from `at`.
      def logical_operator_at?(at, guard)
        (peek_at(at) == 0x26 && peek_at(at + 1) == 0x26) ||
          (peek_at(at) == 0x7C && peek_at(at + 1) == 0x7C) ||
          (peek_at(at) == 0x61 && peek_at(at + 1) == 0x6E && peek_at(at + 2) == 0x64 && !predicate_suffix?(guard + 3) &&
            identifier_width(at + 3) == 0) ||
          (peek_at(at) == 0x6F && peek_at(at + 1) == 0x72 && !predicate_suffix?(guard + 2) && identifier_width(at + 2) == 0)
      end

      # A `!` or `?` that makes a method name of a keyword.
      def predicate_suffix?(at) = peek_at(at) == 0x21 || peek_at(at) == 0x3F

      # The ignored newline, then the operator that starts the next line.
      def newline_operator(lexed_comment, state, at, length, type)
        lex_ignored_newline unless lexed_comment
        @lex_state = state
        @current_start = at
        @current_end = at + length
        @next_start = nil
        lex_token(type)
        :done
      end

      # ( that groups the expression it wraps at the start of an
      # expression, wraps a command argument after a space in argument
      # position, or else opens an argument list
      def lex_parenthesis_left(space_seen)
        type = if lex_state_beg? then :PARENTHESIS_LEFT_GROUPING
               elsif space_seen && (lex_state_arg? || @lex_state == (STATE_END | STATE_LABEL)) then :PARENTHESIS_LEFT_PARENTHESES
               else :PARENTHESIS_LEFT
               end

        @enclosure_nesting += 1
        @lex_state = STATE_BEG | STATE_LABEL
        enclosure_frame_push
        type
      end

      # [ [] []=
      def lex_bracket_left(space_seen)
        @enclosure_nesting += 1

        if lex_state_operator?
          if match(0x5D)
            @enclosure_nesting -= 1
            @lex_state = STATE_ARG
            return match(0x3D) ? :BRACKET_LEFT_RIGHT_EQUAL : :BRACKET_LEFT_RIGHT
          end

          @lex_state = STATE_ARG | STATE_LABEL
          return :BRACKET_LEFT
        end

        type = :BRACKET_LEFT
        type = :BRACKET_LEFT_ARRAY if lex_state_beg? || (lex_state_arg? && (space_seen || lex_state?(STATE_LABELED)))

        @lex_state = STATE_BEG | STATE_LABEL
        enclosure_frame_push
        type
      end

      # { as a lambda's body, a hash, a block, or a block after a
      # parenthesized command argument
      def lex_brace_left
        type = :BRACE_LEFT

        if @enclosure_nesting == @lambda_enclosure_nesting
          @command_start = true
          @lex_state = STATE_BEG
          type = :LAMBDA_BEGIN
        elsif lex_state?(STATE_LABELED)
          @lex_state = STATE_BEG | STATE_LABEL
          type = :BRACE_LEFT_HASH
        elsif lex_state?(STATE_ARG_ANY | STATE_END | STATE_ENDFN)
          @command_start = true
          @lex_state = STATE_BEG
        elsif lex_state?(STATE_ENDARG)
          @command_start = true
          @lex_state = STATE_BEG
          type = :BRACE_LEFT_ARGUMENT
        else
          @lex_state = STATE_BEG | STATE_LABEL
          type = :BRACE_LEFT_HASH
        end

        @enclosure_nesting += 1
        @brace_nesting += 1
        enclosure_frame_push
        type
      end

      # } which may end an embedded expression
      def lex_brace_right
        @enclosure_nesting -= 1
        enclosure_frame_pop

        if @lex_mode.mode == :embexpr && @brace_nesting == 0
          lex_mode_pop
          return :EMBEXPR_END
        end

        @brace_nesting -= 1
        @lex_state = STATE_END
        :BRACE_RIGHT
      end

      # The state after an operator: an operator method name takes
      # arguments.
      def operator_state = lex_state_operator? ? STATE_ARG : STATE_BEG

      # * ** **= *=
      def lex_star(space_seen)
        if match(0x2A)
          if match(0x3D)
            @lex_state = STATE_BEG
            return :STAR_STAR_EQUAL
          end

          type = :STAR_STAR
          if lex_state_spcarg?(space_seen)
            warn_current(:ambiguous_prefix_star_star)
            type = :USTAR_STAR
          elsif lex_state_beg?
            type = :USTAR_STAR
          elsif ambiguous_operator?(space_seen)
            warn_current(:ambiguous_binary_operator, "**", "argument prefix")
          end

          @lex_state = operator_state
          return type
        end

        if match(0x3D)
          @lex_state = STATE_BEG
          return :STAR_EQUAL
        end

        type = :STAR
        if lex_state_spcarg?(space_seen)
          warn_current(:ambiguous_prefix_star)
          type = :USTAR
        elsif lex_state_beg?
          type = :USTAR
        elsif ambiguous_operator?(space_seen)
          warn_current(:ambiguous_binary_operator, "*", "argument prefix")
        end

        @lex_state = operator_state
        type
      end

      # ambiguous_operator_p, CRuby's warn_balanced
      def ambiguous_operator?(space_seen)
        !lex_state?(STATE_CLASS | STATE_DOT | STATE_FNAME | STATE_ENDFN) && space_seen && !whitespace?(peek)
      end

      # ! != !~ !@
      def lex_bang
        if lex_state_operator?
          @lex_state = STATE_ARG
          return :BANG if match(0x40)
        else
          @lex_state = STATE_BEG
        end

        return :BANG_EQUAL if match(0x3D)
        return :BANG_TILDE if match(0x7E)

        :BANG
      end

      # = => =~ == === and =begin at the start of a line
      def lex_equal
        if current_token_starts_line? && @current_end + 5 <= @end && @source.byteslice(@current_end, 5) == "begin" &&
           (whitespace?(peek_offset(5)) || peek_offset(5) == 0)
          return lex_embdoc == :EOF ? :EOF : nil
        end

        @lex_state = operator_state
        return :EQUAL_GREATER if match(0x3E)
        return :EQUAL_TILDE if match(0x7E)
        return match(0x3D) ? :EQUAL_EQUAL_EQUAL : :EQUAL_EQUAL if match(0x3D)

        :EQUAL
      end

      # < << <<= <= <=> and a heredoc's start
      def lex_less(space_seen)
        if match(0x3C)
          if !lex_state?(STATE_DOT | STATE_CLASS) && !lex_state_end? &&
             (!lex_state?(STATE_ARG_ANY) || lex_state?(STATE_LABELED) || space_seen)
            heredoc = lex_heredoc_start
            return heredoc if heredoc
          end

          if match(0x3D)
            @lex_state = STATE_BEG
            return :LESS_LESS_EQUAL
          end

          warn_current(:ambiguous_binary_operator, "<<", "here document") if ambiguous_operator?(space_seen)

          if lex_state_operator?
            @lex_state = STATE_ARG
          else
            @command_start = true if lex_state?(STATE_CLASS)
            @lex_state = STATE_BEG
          end
          return :LESS_LESS
        end

        if lex_state_operator?
          @lex_state = STATE_ARG
        else
          @command_start = true if lex_state?(STATE_CLASS)
          @lex_state = STATE_BEG
        end

        if match(0x3D)
          return :LESS_EQUAL_GREATER if match(0x3E)

          return :LESS_EQUAL
        end
        :LESS
      end

      # A heredoc's start after <<: :HEREDOC_START with the heredoc mode
      # pushed, or nil to lex << as an operator.
      def lex_heredoc_start
        finish = @current_end
        quote = nil
        indent = :none

        if match(0x2D)
          indent = :dash
        elsif match(0x7E)
          indent = :tilde
        end

        if match(0x60)
          quote = 0x60
        elsif match(0x22)
          quote = 0x22
        elsif match(0x27)
          quote = 0x27
        end

        ident_start = @current_end
        width = 0

        if @current_end >= @end || (quote.nil? && (width = identifier_width(@current_end)) == 0)
          @current_end = finish
          return
        end

        if quote.nil?
          @current_end += width
          @current_end += width while (width = identifier_width(@current_end)) > 0
        else
          while @current_end < @end && quote != (byte = @source.getbyte(@current_end))
            break if byte == 0x0D || byte == 0x0A

            @current_end += 1
          end
        end

        ident_length = @current_end - ident_start
        ident_error = false

        if quote && !match(quote)
          err(ident_start, ident_start + ident_length, :heredoc_identifier)
          ident_error = true
        end

        @explicit_encoding = nil
        mode = LexMode.new(:heredoc)
        mode.ident_start = ident_start
        mode.ident_length = ident_length
        mode.quote = quote
        mode.indent = indent
        mode.next_start = @current_end
        mode.common_whitespace = nil
        mode.line_continuation = false
        lex_mode_push(mode)

        if @heredoc_end.nil?
          body_start = next_newline(@current_end)
          if body_start.nil?
            # No newline after the identifier: an error, and still a heredoc.
            err_heredoc_term(ident_start, ident_length) unless ident_error
            body_start = @end
          else
            newline_append(body_start)
            body_start += 1
          end
          @next_start = body_start
        else
          @next_start = @heredoc_end
        end

        :HEREDOC_START
      end

      # > >> >>= >=
      def lex_greater
        if match(0x3E)
          @lex_state = operator_state
          return match(0x3D) ? :GREATER_GREATER_EQUAL : :GREATER_GREATER
        end

        @lex_state = operator_state
        match(0x3D) ? :GREATER_EQUAL : :GREATER
      end

      # ` as a method name or an xstring's start
      def lex_backtick(previous_command_start)
        if lex_state?(STATE_FNAME)
          @lex_state = STATE_ENDFN
          return :BACKTICK
        end

        if lex_state?(STATE_DOT)
          @lex_state = previous_command_start ? STATE_CMDARG : STATE_ARG
          return :BACKTICK
        end

        lex_mode_push_string(true, false, 0, 0x60)
        :XSTRING_BEGIN
      end

      # & && &&= &= &.
      def lex_ampersand(space_seen)
        if match(0x26)
          @lex_state = STATE_BEG
          return match(0x3D) ? :AMPERSAND_AMPERSAND_EQUAL : :AMPERSAND_AMPERSAND
        end

        if match(0x3D)
          @lex_state = STATE_BEG
          return :AMPERSAND_EQUAL
        end

        if match(0x2E)
          @lex_state = STATE_DOT
          return :AMPERSAND_DOT
        end

        type = :AMPERSAND
        if lex_state_spcarg?(space_seen)
          if peek != 0x3A || peek_offset(1) == 0
            warn_current(:ambiguous_prefix_ampersand)
          else
            delimiter = peek_offset(1)
            if delimiter != 0x27 && delimiter != 0x22 && identifier_width(@current_end + 1) == 0
              warn_current(:ambiguous_prefix_ampersand)
            end
          end
          type = :UAMPERSAND
        elsif lex_state_beg?
          type = :UAMPERSAND
        elsif ambiguous_operator?(space_seen)
          warn_current(:ambiguous_binary_operator, "&", "argument prefix")
        end

        @lex_state = operator_state
        type
      end

      # | || ||= |=
      def lex_pipe
        if match(0x7C)
          if match(0x3D)
            @lex_state = STATE_BEG
            return :PIPE_PIPE_EQUAL
          end

          if lex_state?(STATE_BEG)
            @current_end -= 1
            return :PIPE
          end

          @lex_state = STATE_BEG
          return :PIPE_PIPE
        end

        if match(0x3D)
          @lex_state = STATE_BEG
          return :PIPE_EQUAL
        end

        @lex_state = lex_state_operator? ? STATE_ARG : STATE_BEG | STATE_LABEL
        :PIPE
      end

      # + += +@ and a signed number
      def lex_plus(space_seen)
        if lex_state_operator?
          @lex_state = STATE_ARG
          return match(0x40) ? :UPLUS : :PLUS
        end

        if match(0x3D)
          @lex_state = STATE_BEG
          return :PLUS_EQUAL
        end

        if lex_state_beg? || (lex_state_spcarg?(space_seen) && (warn_current(:ambiguous_first_argument_plus) || true))
          @lex_state = STATE_BEG

          if decimal_digit?(peek)
            @current_end += 1
            type = lex_numeric
            @lex_state = STATE_END
            return type
          end

          return :UPLUS
        end

        warn_current(:ambiguous_binary_operator, "+", "unary operator") if ambiguous_operator?(space_seen)

        @lex_state = STATE_BEG
        :PLUS
      end

      # - -= -@ -> and a negative number's sign
      def lex_minus(space_seen)
        if lex_state_operator?
          @lex_state = STATE_ARG
          return match(0x40) ? :UMINUS : :MINUS
        end

        if match(0x3D)
          @lex_state = STATE_BEG
          return :MINUS_EQUAL
        end

        if match(0x3E)
          @lex_state = STATE_ENDFN
          return :MINUS_GREATER
        end

        spcarg = lex_state_spcarg?(space_seen)
        is_beg = lex_state_beg?
        warn_current(:ambiguous_first_argument_minus) if !is_beg && spcarg

        if is_beg || spcarg
          @lex_state = STATE_BEG
          return decimal_digit?(peek) ? :UMINUS_NUM : :UMINUS
        end

        warn_current(:ambiguous_binary_operator, "-", "unary operator") if ambiguous_operator?(space_seen)

        @lex_state = STATE_BEG
        :MINUS
      end

      # . .. ...
      def lex_dot
        beg = lex_state_beg?

        if match(0x2E)
          if match(0x2E)
            # ... among a method's parameters, but not in a default value.
            if !@contexts.include?(:default_params) && @contexts.include?(:def_params)
              @lex_state = lex_state?(STATE_END) ? STATE_BEG : STATE_ENDARG
              return :UDOT_DOT_DOT
            end

            warn_current(:dot_dot_dot_eol) if @enclosure_nesting == 0 && end_of_line?

            @lex_state = STATE_BEG
            return beg ? :UDOT_DOT_DOT : :DOT_DOT_DOT
          end

          @lex_state = STATE_BEG
          return beg ? :UDOT_DOT : :DOT_DOT
        end

        @lex_state = STATE_DOT
        :DOT
      end

      # : :: and a symbol's start
      def lex_colon(space_seen)
        if match(0x3A)
          if lex_state_beg? || lex_state?(STATE_CLASS) || (lex_state?(STATE_ARG_ANY) && space_seen)
            @lex_state = STATE_BEG
            return :UCOLON_COLON
          end

          @lex_state = STATE_DOT
          return :COLON_COLON
        end

        if lex_state_end? || whitespace?(peek) || peek == 0x23
          @lex_state = STATE_BEG
          return :COLON
        end

        if peek == 0x22 || peek == 0x27
          lex_mode_push_string(peek == 0x22, false, 0, @source.getbyte(@current_end))
          @current_end += 1
        else
          # A bare symbol pushes no lex mode, which would clear the encoding.
          @explicit_encoding = nil
        end

        @lex_state = STATE_FNAME
        :SYMBOL_BEGIN
      end

      # / /= and a regexp's start
      def lex_slash(space_seen)
        if lex_state_beg?
          lex_mode_push_regexp(0, 0x2F)
          return :REGEXP_BEGIN
        end

        if match(0x3D)
          @lex_state = STATE_BEG
          return :SLASH_EQUAL
        end

        if lex_state_spcarg?(space_seen)
          # Ruby 4.1 no longer warns (#21994).
          warn_current(:ambiguous_slash) if @version <= Options::VERSION_CRUBY_4_0
          lex_mode_push_regexp(0, 0x2F)
          return :REGEXP_BEGIN
        end

        warn_current(:ambiguous_binary_operator, "/", "regexp literal") if ambiguous_operator?(space_seen)

        @lex_state = operator_state
        :SLASH
      end

      # pm_lex_percent_delimiter: the delimiter after %, a newline counting
      # as \n.
      def lex_percent_delimiter
        eol_length = match_eol
        if eol_length != 0
          if @heredoc_end
            flush_heredoc_end
          else
            newline_append(@current_end + eol_length - 1)
          end

          delimiter = @source.getbyte(@current_end)
          delimiter = @source.getbyte(@current_end + 1) if eol_length == 2
          @current_end += eol_length
          return delimiter
        end

        delimiter = @source.getbyte(@current_end)
        @current_end += 1
        delimiter
      end

      # % %= and the %-literals
      def lex_percent(space_seen)
        if (lex_state_beg? || lex_state_arg?) && @current_end >= @end
          err_current(:invalid_percent_eof)
          return :PERCENT
        end

        if !lex_state_beg? && match(0x3D)
          @lex_state = STATE_BEG
          return :PERCENT_EQUAL
        elsif lex_state_beg? || (lex_state?(STATE_FITEM) && peek == 0x73) || lex_state_spcarg?(space_seen)
          if @encoding.alnum_char(@source, @current_end, @end - @current_end) == 0
            # A multibyte character that is not alphanumeric: skip the `%`.
            if @source.getbyte(@current_end) >= 0x80
              err_current(:invalid_percent)
              return
            end

            delimiter = lex_percent_delimiter
            lex_mode_push_string(true, false, lex_mode_incrementor(delimiter), lex_mode_terminator(delimiter))
            return :STRING_BEGIN
          end

          # A %-literal's delimiter cannot be alphanumeric.
          delimiter = peek_offset(1)
          if delimiter >= 0x80 || @encoding.alnum_char(delimiter.chr, 0, 1) != 0
            err_current(:invalid_percent)
            return
          end

          return lex_percent_literal
        end

        warn_current(:ambiguous_binary_operator, "%", "string literal") if ambiguous_operator?(space_seen)

        @lex_state = operator_state
        :PERCENT
      end

      # %i %I %r %q %Q %s %w %W %x: the literal's start, or nil for an
      # unknown letter (with an error, and the % dropped).
      def lex_percent_literal
        letter = peek
        case letter
        when 0x69, 0x49, 0x77, 0x57 # %i %I %w %W
          @current_end += 1
          if @current_end < @end
            lex_mode_push_list(letter == 0x49 || letter == 0x57, lex_percent_delimiter)
          else
            lex_mode_push_list_eof
          end
          { 0x69 => :PERCENT_LOWER_I, 0x49 => :PERCENT_UPPER_I, 0x77 => :PERCENT_LOWER_W, 0x57 => :PERCENT_UPPER_W }.fetch(letter)
        when 0x72 # %r
          @current_end += 1
          if @current_end < @end
            delimiter = lex_percent_delimiter
            lex_mode_push_regexp(lex_mode_incrementor(delimiter), lex_mode_terminator(delimiter))
          else
            lex_mode_push_regexp(0, 0)
          end
          :REGEXP_BEGIN
        when 0x71, 0x51, 0x78 # %q %Q %x
          @current_end += 1
          if @current_end < @end
            delimiter = lex_percent_delimiter
            lex_mode_push_string(letter != 0x71, false, lex_mode_incrementor(delimiter), lex_mode_terminator(delimiter))
          else
            lex_mode_push_string_eof
          end
          letter == 0x78 ? :PERCENT_LOWER_X : :STRING_BEGIN
        when 0x73 # %s
          @current_end += 1
          if @current_end < @end
            delimiter = lex_percent_delimiter
            lex_mode_push_string(false, false, lex_mode_incrementor(delimiter), lex_mode_terminator(delimiter))
            @lex_state = STATE_FNAME | STATE_FITEM
          else
            lex_mode_push_string_eof
          end
          :SYMBOL_BEGIN
        else
          err_current(:invalid_percent)
          nil
        end
      end

      # An identifier, a keyword, __END__, or an invalid character: the type,
      # or nil (with an error) to lex the next token instead.
      def lex_word(previous_command_start)
        first = @source.getbyte(@current_start)

        if first != 0x5F
          width = identifier_start_width(@current_start)
          if width == 0
            invalid_character(first)
            return
          end
          @current_end = @current_start + width
        end

        type = lex_identifier(previous_command_start)

        # __END__ alone on its line ends the program; the rest is data.
        if @current_end - @current_start == 7 && current_token_starts_line? && @source.byteslice(@current_start, 7) == "__END__" &&
           (@current_end == @end || match_eol != 0)
          cursor = @current_end
          while (cursor = next_newline(cursor))
            newline_append(cursor)
            cursor += 1
          end

          @current_end = @end
          @current_type = :__END__
          lex_callback
          @data_loc = [@current_start, @current_end]
          return :EOF
        end

        last_state = @lex_state

        if type == :IDENTIFIER || type == :CONSTANT || type == :METHOD_NAME
          @lex_state =
            if lex_state?(STATE_BEG_ANY | STATE_ARG_ANY | STATE_DOT)
              previous_command_start ? STATE_CMDARG : STATE_ARG
            elsif @lex_state == STATE_FNAME
              STATE_ENDFN
            else
              STATE_END
            end
        end

        if !last_state.anybits?(STATE_DOT | STATE_FNAME) && type == :IDENTIFIER &&
           (local_depth(@current_start, @current_end) != -1 || numbered_parameter?(@current_start, @current_end))
          @lex_state = STATE_END | STATE_LABEL
        end

        type
      end

      # The error for a byte no token starts with.
      def invalid_character(first)
        if first >= 0x80
          err_current(:invalid_multibyte_character, first)
        elsif first == 0x5C
          case peek_at(@current_start + 1)
          when 0x20 then escaped_ignore("escaped space")
          when 0x0C then escaped_ignore("escaped form feed")
          when 0x09 then escaped_ignore("escaped horizontal tab")
          when 0x0B then escaped_ignore("escaped vertical tab")
          when 0x0D
            if peek_at(@current_start + 2) != 0x0A
              escaped_ignore("escaped carriage return")
            else
              err_current(:unexpected_token_ignore, "backslash")
            end
          else err_current(:unexpected_token_ignore, "backslash")
          end
        elsif ascii_printable?(first)
          err_current(:invalid_printable_character, first)
        else
          err_current(:invalid_character, first)
        end
      end

      def escaped_ignore(what)
        @current_end += 1
        err_current(:unexpected_token_ignore, what)
      end
    end
  end
end
