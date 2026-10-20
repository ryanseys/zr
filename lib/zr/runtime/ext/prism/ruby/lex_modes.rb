# frozen_string_literal: true
# shareable_constant_value: literal

# Derived from prism's C (MIT); see THIRD_PARTY_NOTICES.md.

module Prism
  module Ruby
    # pm_token_buffer_t, and with `regexp:` pm_regexp_token_buffer_t: the
    # bytes of a string token whose escapes are read. Until the first escape
    # the cursor is nil and the token is a slice of the source. After that,
    # `bytes` contains the token up to the cursor, and for a regexp,
    # `regexp_bytes` contains the source that the regexp engine reads.
    class TokenBuffer
      attr_reader :bytes, :regexp_bytes
      attr_accessor :cursor

      def initialize(regexp: false)
        @regexp = regexp
      end

      def regexp? = @regexp

      # The source from `start` to `finish`, into each buffer.
      def append(source, start, finish)
        slice = source.byteslice(start, finish - start)
        (@bytes ||= "".b) << slice
        (@regexp_bytes ||= "".b) << slice if @regexp
      end

      def push(byte) = @bytes << byte
      def push_regexp(byte) = @regexp_bytes << byte
    end

    # parser_lex's string, list, regexp and heredoc modes.
    class Parser
      # The terminators of a regexp that keep their backslash when escaped.
      REGEXP_ESCAPED_TERMINATORS = "$)*+.>?]^|}".bytes.freeze

      private

      # -- the token buffer -------------------------------------------------

      # pm_token_buffer_escape: the token up to the backslash before
      # @current_end goes into the buffer.
      def token_buffer_escape(buffer)
        finish = @current_end - 1
        buffer.append(@source, buffer.cursor || @current_start, finish)
        buffer.cursor = finish
      end

      # pm_token_buffer_push_escaped: the character at @current_end as it is.
      def token_buffer_push_escaped(buffer)
        width = parser_char_width
        character = @source.byteslice(@current_end, width)
        buffer.bytes << character
        buffer.regexp_bytes << character if buffer.regexp?
        @current_end += width
      end

      # pm_token_buffer_copy: the buffer is the token's string.
      def token_buffer_copy(buffer)
        @current_string = owned_string(buffer.bytes)
      end

      # pm_token_buffer_flush: the token's string, a slice of the source when
      # nothing was escaped.
      def token_buffer_flush(buffer)
        if buffer.cursor.nil?
          @current_string = shared_string(@current_start, @current_end)
        else
          buffer.append(@source, buffer.cursor, @current_end)
          token_buffer_copy(buffer)
        end
      end

      # A STRING_CONTENT token that ends at `finish`.
      def lex_content(buffer, finish = @current_end)
        @current_end = finish
        token_buffer_flush(buffer)
        lex_token(:STRING_CONTENT)
      end

      # The content after the last breakpoint of a list, string or regexp:
      # what was lexed so far, or else the rest of the source.
      def lex_content_rest(buffer)
        lex_content(buffer, @current_end > @current_start ? @current_end : @end)
      end

      # An escaped newline, with @current_end at the \n. Inside the line a
      # heredoc starts on, the token ends there (:STRING_CONTENT) and the
      # lexer goes on after the heredoc's body; elsewhere the newline counts.
      def escaped_newline(buffer)
        if @heredoc_end
          flush_heredoc_end
          token_buffer_copy(buffer)
          return :STRING_CONTENT
        end

        newline_append(@current_end)
        @current_end += 1
        nil
      end

      # lex_interpolation: at the # at `pound`, the token it gives. That is
      # :EMBEXPR_BEGIN or :EMBVAR with the embedded mode pushed,
      # :STRING_CONTENT for the content before it, or nil when no
      # interpolation starts here and the content goes on.
      def lex_interpolation(pound)
        if pound + 1 >= @end
          @current_end = pound + 1
          return :STRING_CONTENT
        end

        case @source.getbyte(pound + 1)
        when 0x40 # #@ #@@
          if pound + 2 >= @end
            @current_end = pound + 1
            return :STRING_CONTENT
          end

          variable = pound + 2
          variable += 1 if @source.getbyte(variable) == 0x40 && pound + 3 < @end
          return lex_embedded_variable(pound) if identifier_start_width(variable) != 0
        when 0x24 # #$ #$-
          if pound + 2 >= @end
            @current_end = pound + 1
            return :STRING_CONTENT
          end

          name = @source.getbyte(pound + 2)
          dash = name == 0x2D
          if dash && pound + 3 >= @end
            @current_end = pound + 2
            return :STRING_CONTENT
          end

          if identifier_start_width(dash ? pound + 3 : pound + 2) != 0 ||
             (!dash && (decimal_digit?(name) || global_name_punctuation?(name)))
            return lex_embedded_variable(pound)
          end
        when 0x7B # #{
          if pound > @current_start
            @current_end = pound
            return :STRING_CONTENT
          end

          @enclosure_nesting += 1
          lex_mode_push(LexMode.new(:embexpr))
          @current_end = pound + 2
          @command_start = true
          enclosure_frame_push
          return :EMBEXPR_BEGIN
        end

        @current_end = pound + 1
        nil
      end

      # #@ivar #@@cvar #$gvar: the content before it first, then :EMBVAR.
      def lex_embedded_variable(pound)
        if pound > @current_start
          @current_end = pound
          return :STRING_CONTENT
        end

        lex_mode_push(LexMode.new(:embvar))
        @current_end = pound + 1
        :EMBVAR
      end

      # -- PM_LEX_LIST ------------------------------------------------------

      # The elements of %w %W %i %I, and the whitespace between them.
      def lex_list
        if @next_start
          @current_end = @next_start
          @next_start = nil
        end
        @current_start = @current_end

        mode = @lex_mode
        whitespace =
          if @heredoc_end
            inline = strspn_inline_whitespace(@current_end, @end)
            peek_offset(inline) == 0x0A ? inline + 1 : inline
          elsif mode.terminator == 0x0A
            # A newline delimiter ends the list; it separates no words.
            strspn_inline_whitespace(@current_end, @end)
          else
            strspn_whitespace_newlines(@current_end, @end)
          end

        if whitespace > 0
          @current_end += whitespace
          flush_heredoc_end if peek_offset(-1) == 0x0A
          mode.started = true
          mode.separated = true
          return lex_token(:WORDS_SEP)
        end

        return lex_token(:EOF) if @current_end >= @end

        # A list that starts with no whitespace still has a separator after
        # its opener; it goes to the lex callback alone.
        unless mode.started
          mode.started = true
          mode.separated = true
          @current_type = :WORDS_SEP_IMPLICIT
          lex_callback
        end

        breakpoints = mode.breakpoints
        breakpoint = strpbrk(@current_end, breakpoints, true)
        buffer = TokenBuffer.new

        while breakpoint
          byte = @source.getbyte(breakpoint)

          # Whitespace ends an element, which must have content by now; a
          # newline delimiter is the terminator instead.
          if whitespace?(byte) && byte != mode.terminator
            mode.separated = false
            return lex_content(buffer, breakpoint)
          end

          if byte == mode.terminator
            if mode.nesting > 0
              @current_end = breakpoint + 1
              breakpoint = strpbrk(@current_end, breakpoints, true)
              mode.nesting -= 1
              next
            end

            if breakpoint > @current_start
              mode.separated = false
              return lex_content(buffer, breakpoint)
            end

            # So does a list that ends with no whitespace before its
            # terminator.
            unless mode.separated
              mode.separated = true
              @current_end = breakpoint
              @current_type = :WORDS_SEP_IMPLICIT
              lex_callback
            end

            @current_end = breakpoint + 1
            # A newline delimiter still starts a line.
            newline_append(breakpoint) if byte == 0x0A
            lex_mode_pop
            @lex_state = STATE_END
            return lex_token(:STRING_END)
          end

          case byte
          when 0x00
            breakpoint = strpbrk(breakpoint + 1, breakpoints, true)
          when 0x5C
            @current_end = breakpoint + 1
            break if @current_end == @end

            token_buffer_escape(buffer)
            type = list_escape(buffer, mode)
            return lex_token(type) if type

            buffer.cursor = @current_end
            breakpoint = strpbrk(@current_end, breakpoints, true)
          when 0x23
            type = lex_interpolation(breakpoint)
            if type.nil?
              breakpoint = strpbrk(@current_end, breakpoints, true)
              next
            end

            token_buffer_flush(buffer) if type == :STRING_CONTENT
            mode.separated = false
            return lex_token(type)
          else # the incrementor
            @current_end = breakpoint + 1
            breakpoint = strpbrk(@current_end, breakpoints, true)
            mode.nesting += 1
          end
        end

        lex_content_rest(buffer)
      end

      # The escape after a backslash in a list: its bytes into the buffer, or
      # the token type when an escaped newline ends the token.
      def list_escape(buffer, mode)
        case (peeked = peek)
        when 0x20, 0x0C, 0x09, 0x0B, 0x5C
          buffer.push(peeked)
          @current_end += 1
        when 0x0D, 0x0A
          if peeked == 0x0D && peek_offset(1) != 0x0A
            buffer.push(0x0D)
            @current_end += 1
            return
          end

          @current_end += 1 if peeked == 0x0D
          buffer.push(0x0A)
          return escaped_newline(buffer)
        else
          if peeked == mode.incrementor || peeked == mode.terminator
            buffer.push(peeked)
            @current_end += 1
          elsif mode.interpolation
            escape_read(buffer.bytes, nil, ESCAPE_FLAG_NONE)
          else
            buffer.push(0x5C)
            token_buffer_push_escaped(buffer)
          end
        end
        nil
      end

      # -- PM_LEX_STRING and PM_LEX_REGEXP ------------------------------------

      # The content of a string, symbol, xstring or regexp. The two modes
      # differ in how they end, in their escapes, and in that a regexp's
      # bytes are not checked against the source's encoding.
      def lex_literal
        if @next_start.nil?
          @current_start = @current_end
        else
          @current_start = @current_end = @next_start
          @next_start = nil
        end

        return lex_token(:EOF) if @current_end >= @end

        mode = @lex_mode
        regexp = mode.mode == :regexp
        validate = !regexp
        breakpoints = mode.breakpoints
        breakpoint = strpbrk(@current_end, breakpoints, validate)
        buffer = TokenBuffer.new(regexp: regexp)

        while breakpoint
          byte = @source.getbyte(breakpoint)

          if mode.incrementor != 0 && byte == mode.incrementor
            mode.nesting += 1
            @current_end = breakpoint + 1
            breakpoint = strpbrk(@current_end, breakpoints, validate)
            next
          end

          if terminator_at?(breakpoint, mode.terminator)
            if mode.nesting > 0
              @current_end = breakpoint + 1
              breakpoint = strpbrk(@current_end, breakpoints, validate)
              mode.nesting -= 1
              next
            end

            return lex_content(buffer, breakpoint) if breakpoint > @current_start

            # The terminator, and the newline it may be.
            eol_length = match_eol_at(breakpoint)
            if eol_length == 0
              @current_end = breakpoint + 1
            else
              @current_end = breakpoint + eol_length
              newline_append(@current_end - 1) if @heredoc_end.nil?
            end

            return regexp ? lex_regexp_end : lex_string_end(mode)
          end

          case byte
          when 0x00
            @current_end = breakpoint + 1
            breakpoint = strpbrk(@current_end, breakpoints, validate)
          when 0x0D, 0x0A
            if byte == 0x0D
              if peek_at(breakpoint + 1) != 0x0A
                @current_end = breakpoint + 1
                breakpoint = strpbrk(@current_end, breakpoints, validate)
                next
              end

              # A \r\n is content as its \n alone.
              breakpoint += 1
              @current_end = breakpoint
              token_buffer_escape(buffer)
              buffer.cursor = breakpoint
            end

            if @heredoc_end
              flush_heredoc_end
              return lex_content(buffer, breakpoint + 1)
            end

            newline_append(breakpoint)
            @current_end = breakpoint + 1
            breakpoint = strpbrk(@current_end, breakpoints, validate)
          when 0x5C
            @current_end = breakpoint + 1
            break if @current_end == @end

            token_buffer_escape(buffer)
            type = regexp ? regexp_escape(buffer, mode) : string_escape(buffer, mode)
            return lex_token(type) if type

            buffer.cursor = @current_end
            breakpoint = strpbrk(@current_end, breakpoints, validate)
          when 0x23
            type = lex_interpolation(breakpoint)
            if type.nil?
              breakpoint = strpbrk(@current_end, breakpoints, validate)
              next
            end

            token_buffer_flush(buffer) if type == :STRING_CONTENT
            return lex_token(type)
          end
        end

        lex_content_rest(buffer)
      end

      # Whether the byte at `breakpoint` is the terminator. A \r\n counts as a
      # \n, and so is never a \r.
      def terminator_at?(breakpoint, terminator)
        if @source.getbyte(breakpoint) == 0x0D && peek_at(breakpoint + 1) == 0x0A
          return true if terminator == 0x0A
          return false if terminator == 0x0D
        end
        @source.getbyte(breakpoint) == terminator
      end

      # A string's end, which may be a label's `":`.
      def lex_string_end(mode)
        if mode.label_allowed && peek == 0x3A && peek_offset(1) != 0x3A
          @current_end += 1
          @lex_state = STATE_ARG | STATE_LABELED
          lex_mode_pop
          return lex_token(:LABEL_END)
        end

        # A newline terminator is past the place heredocs flush.
        flush_heredoc_end if mode.terminator == 0x0A && @heredoc_end

        @lex_state = STATE_END
        lex_mode_pop
        lex_token(:STRING_END)
      end

      # A regexp's end, with its option letters.
      def lex_regexp_end
        @current_end += strspn_regexp_option(@current_end, @end)
        lex_mode_pop
        @lex_state = STATE_END
        lex_token(:REGEXP_END)
      end

      # The escape after a backslash in a string: its bytes into the buffer,
      # or the token type when an escaped newline ends the token.
      def string_escape(buffer, mode)
        case (peeked = peek)
        when 0x5C
          buffer.push(0x5C)
          @current_end += 1
        when 0x0D, 0x0A
          if peeked == 0x0D && peek_offset(1) != 0x0A
            buffer.push(0x5C) unless mode.interpolation
            buffer.push(0x0D)
            @current_end += 1
            return
          end

          @current_end += 1 if peeked == 0x0D
          buffer.bytes << 0x5C << 0x0A unless mode.interpolation
          return escaped_newline(buffer)
        else
          if (mode.incrementor != 0 && peeked == mode.incrementor) || (mode.terminator != 0 && peeked == mode.terminator)
            buffer.push(peeked)
            @current_end += 1
          elsif mode.interpolation
            escape_read(buffer.bytes, nil, ESCAPE_FLAG_NONE)
          else
            buffer.push(0x5C)
            token_buffer_push_escaped(buffer)
          end
        end
        nil
      end

      # The escape after a backslash in a regexp: the unescaped bytes and the
      # regexp's source into the buffer, or the token type when an escaped
      # newline ends the token. As in C, escape_read takes the regexp source
      # as its buffer and the bytes as its regexp buffer.
      def regexp_escape(buffer, mode)
        case (peeked = peek)
        when 0x0D, 0x0A
          if peeked == 0x0D && peek_offset(1) != 0x0A
            buffer.push(0x5C) if mode.terminator != 0x0D
            buffer.push(0x0D)
            buffer.push_regexp(0x0D)
            @current_end += 1
            return
          end

          @current_end += 1 if peeked == 0x0D
          return escaped_newline(buffer)
        when 0x63, 0x43, 0x4D, 0x75, 0x78 # c C M u x
          escape_read(buffer.regexp_bytes, buffer.bytes, ESCAPE_FLAG_REGEXP)
        else
          if peeked == mode.terminator
            buffer.push(0x5C) if REGEXP_ESCAPED_TERMINATORS.include?(peeked)
            buffer.push(peeked)
            buffer.push_regexp(peeked)
            @current_end += 1
          else
            buffer.push(0x5C) if peeked < 0x80
            token_buffer_push_escaped(buffer)
          end
        end
        nil
      end

      # -- PM_LEX_HEREDOC ---------------------------------------------------

      # A heredoc's body: its content line by line, and its terminator.
      def lex_heredoc
        if @next_start.nil?
          @current_start = @current_end
        else
          @current_start = @current_end = @next_start
          @heredoc_end = nil
          @next_start = nil
        end

        mode = @lex_mode
        line_continuation = mode.line_continuation
        mode.line_continuation = false

        # No terminator: an error, and the code after the heredoc's start
        # still lexes.
        if @current_end >= @end
          err_heredoc_term(mode.ident_start, mode.ident_length)
          @next_start = mode.next_start
          @heredoc_end = @current_end
          @lex_state = STATE_END
          lex_mode_pop
          return lex_token(:HEREDOC_END)
        end

        if current_token_starts_line?
          start = @current_start

          if !line_continuation && start + mode.ident_length <= @end
            newline = next_newline(start)
            if heredoc_terminator?(mode, start, newline)
              newline_append(newline) if newline
              @current_end = newline ? newline + 1 : @end

              # After a line continuation at the heredoc's start, the lexer
              # goes on after the terminator.
              if @source.getbyte(mode.next_start) == 0x5C
                @next_start = nil
              else
                @next_start = mode.next_start
                @heredoc_end = @current_end
              end

              @lex_state = STATE_END
              lex_mode_pop
              return lex_token(:HEREDOC_END)
            end
          end

          whitespace, start = heredoc_indentation(start, mode.indent)
          heredoc_common_whitespace(mode, whitespace, start)
        end

        single_quote = mode.quote == 0x27
        breakpoints = single_quote ? Breakpoints::HEREDOC_SINGLE_QUOTE : Breakpoints::HEREDOC
        breakpoint = strpbrk(@current_end, breakpoints, true)
        buffer = TokenBuffer.new
        continued = false

        while breakpoint
          # Whether a line continuation came right before this breakpoint.
          after_continuation = continued
          continued = false # rubocop:disable Lint/UselessAssignment -- the next pass of the loop reads it

          case @source.getbyte(breakpoint)
          when 0x00
            @current_end = breakpoint + 1
            breakpoint = strpbrk(@current_end, breakpoints, true)
          when 0x0D, 0x0A
            if @source.getbyte(breakpoint) == 0x0D
              @current_end = breakpoint + 1
              if peek_at(breakpoint + 1) != 0x0A
                breakpoint = strpbrk(@current_end, breakpoints, true)
                next
              end

              # A \r\n is content as its \n alone.
              breakpoint += 1
              token_buffer_escape(buffer)
              buffer.cursor = breakpoint
            end

            # The line a later heredoc starts on ends inside this one.
            if @heredoc_end && @heredoc_end > breakpoint
              flush_heredoc_end
              return lex_content(buffer, breakpoint + 1)
            end

            newline_append(breakpoint)
            start = breakpoint + 1

            # The line ends before the terminator, which lexes next.
            if !after_continuation && start + mode.ident_length <= @end && heredoc_terminator?(mode, start, next_newline(start))
              return lex_content(buffer, breakpoint + 1)
            end

            whitespace, start = heredoc_indentation(start, mode.indent)

            # A <<~ heredoc gives each line as a token, to remove its
            # indentation from.
            if mode.indent == :tilde
              heredoc_common_whitespace(mode, whitespace, start)
              return lex_content(buffer, breakpoint + 1)
            end

            @current_end = breakpoint + 1
            breakpoint = strpbrk(@current_end, breakpoints, true)
          when 0x5C
            @current_end = breakpoint + 1
            break if @current_end == @end

            token_buffer_escape(buffer)
            peeked = peek

            if peeked == 0x0D && peek_offset(1) != 0x0A
              buffer.push(0x5C) if single_quote
              buffer.push(0x0D)
              @current_end += 1
            elsif peeked == 0x0D || peeked == 0x0A
              # An escaped newline: the loop stops at the newline, where the
              # terminator may follow.
              @current_end += 1 if peeked == 0x0D

              if single_quote
                buffer.bytes << 0x5C << 0x0A
              elsif mode.indent == :tilde
                return lex_heredoc_line_continuation(buffer, mode, breakpoint)
              else
                continued = true
              end

              buffer.cursor = @current_end + 1
              breakpoint = @current_end
              next
            elsif single_quote
              buffer.push(0x5C)
              token_buffer_push_escaped(buffer)
            else
              escape_read(buffer.bytes, nil, ESCAPE_FLAG_NONE)
            end

            buffer.cursor = @current_end
            breakpoint = strpbrk(@current_end, breakpoints, true)
          when 0x23
            type = lex_interpolation(breakpoint)
            if type.nil?
              breakpoint = strpbrk(@current_end, breakpoints, true)
              next
            end

            token_buffer_flush(buffer) if type == :STRING_CONTENT
            return lex_token(type)
          end
        end

        lex_content(buffer, @end)
      end

      # A line continuation in a <<~ heredoc: the content up to the
      # backslash, with the token past the newline, and the next line not a
      # terminator.
      def lex_heredoc_line_continuation(buffer, mode, backslash)
        newline = @current_end
        newline_append(newline) if @heredoc_end.nil?

        @current_end = backslash
        token_buffer_flush(buffer)
        @current_end = newline + 1
        mode.line_continuation = true
        lex_token(:STRING_CONTENT)
      end

      # Whether the line at `start`, ending at the \n at `newline` (nil at
      # the end of the source), is the heredoc's terminator: its identifier,
      # after indentation for <<- and <<~, then a \r\n, a \n or the end.
      def heredoc_terminator?(mode, start, newline)
        ident_end =
          if newline.nil? then @end
          elsif @source.getbyte(newline - 1) == 0x0D then newline - 1
          else newline
          end
        terminator_start = ident_end - mode.ident_length

        cursor = start
        if mode.indent != :none
          cursor += 1 while cursor < terminator_start && inline_whitespace?(@source.getbyte(cursor))
        end

        cursor == terminator_start &&
          @source.byteslice(terminator_start, mode.ident_length) == @source.byteslice(mode.ident_start, mode.ident_length)
      end

      # pm_heredoc_strspn_inline_whitespace: past the indentation at `cursor`
      # that the heredoc's kind skips. Returns the columns it takes in a <<~
      # heredoc (a tab to the next multiple of 8, else 0) and where it ends.
      def heredoc_indentation(cursor, indent)
        columns = 0
        case indent
        when :dash
          cursor += strspn_inline_whitespace(cursor, @end)
        when :tilde
          while cursor < @end && inline_whitespace?(byte = @source.getbyte(cursor))
            columns = byte == 0x09 ? (columns / TAB_WHITESPACE_SIZE + 1) * TAB_WHITESPACE_SIZE : columns + 1
            cursor += 1
          end
        end
        [columns, cursor]
      end

      # A <<~ heredoc's least indentation so far, which blank lines do not
      # count toward. The parser sets it before the body lexes; nil until
      # then.
      def heredoc_common_whitespace(mode, whitespace, cursor)
        return unless mode.indent == :tilde && mode.common_whitespace
        return unless mode.common_whitespace > whitespace && peek_at(cursor) != 0x0A

        mode.common_whitespace = whitespace
      end
    end
  end
end
