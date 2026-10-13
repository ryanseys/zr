# frozen_string_literal: true
# shareable_constant_value: literal

require_relative "characters"
require_relative "encoding"
require_relative "constant_pool"
require_relative "diagnostics"
require_relative "tokens"
require_relative "scope"
require_relative "options"
require_relative "strpbrk"

module Prism
  module Ruby
    # pm_token_t, where a token is copied by value.
    Token = Struct.new(:type, :start, :end) do
      # Whether the token is not the PM_TOKEN_NOT_PROVIDED placeholder.
      def provided? = type != :NOT_PROVIDED

      # PM_LOCATION_TOKEN_VALUE, packed as `(start << 32) | length`.
      def location = (start << 32) | (self.end - start)

      # PM_OPTIONAL_LOCATION_TOKEN_VALUE: nil for a token not provided.
      def optional_location = provided? ? location : nil
    end

    # not_provided: the placeholder for a token that is absent without
    # error, at the start of the source.
    NOT_PROVIDED = Token.new(:NOT_PROVIDED, 0, 0).freeze

    # A diagnostic in discovery order: its id (a ParseError#type Symbol),
    # its byte range, its message bytes and its level.
    Diagnostic = Struct.new(:id, :start, :end, :message, :level)

    # pm_lex_mode_t: the mode and whichever of its fields that mode reads.
    LexMode = Struct.new(:mode, :nesting, :interpolation, :label_allowed, :incrementor, :terminator, :breakpoints,
                         :ident_start, :ident_length, :quote, :indent, :next_start, :common_whitespace, :line_continuation,
                         :started, :separated)

    # pm_parser_t and prism.c's functions over it. The class is reopened by
    # one file per part of prism.c (lexer.rb, escapes.rb, and the parser's
    # families), as prism.c is one file of sections.
    #
    # Offsets into the source are Integers. The current and previous tokens
    # are three instance variables each, as C reads their fields in place;
    # `previous_token` and `current_token` copy one where C copies a
    # pm_token_t.
    class Parser
      include Characters

      # pm_lex_state_t
      STATE_NONE = 0
      STATE_BEG = 1 << 0
      STATE_END = 1 << 1
      STATE_ENDARG = 1 << 2
      STATE_ENDFN = 1 << 3
      STATE_ARG = 1 << 4
      STATE_CMDARG = 1 << 5
      STATE_MID = 1 << 6
      STATE_FNAME = 1 << 7
      STATE_DOT = 1 << 8
      STATE_CLASS = 1 << 9
      STATE_LABEL = 1 << 10
      STATE_LABELED = 1 << 11
      STATE_FITEM = 1 << 12
      STATE_BEG_ANY = STATE_BEG | STATE_MID | STATE_CLASS
      STATE_ARG_ANY = STATE_ARG | STATE_CMDARG
      STATE_END_ANY = STATE_END | STATE_ENDARG | STATE_ENDFN

      # pm_integer_base_flags, which the lexer leaves for the parser.
      INTEGER_BASE_BINARY = 1 << 2
      INTEGER_BASE_DECIMAL = 1 << 3
      INTEGER_BASE_OCTAL = 1 << 4
      INTEGER_BASE_HEXADECIMAL = 1 << 5

      # PM_TAB_WHITESPACE_SIZE
      TAB_WHITESPACE_SIZE = 8

      # pm_parse_err_is_fatal: the errors that no more input can make valid,
      # unless they reach the end of the source.
      FATAL_ERRORS = %i[
        array_expression_after_star begin_upcase_brace class_variable_bare end_upcase_brace
        escape_invalid_hexadecimal escape_invalid_unicode_list escape_invalid_unicode_short
        expression_not_writable expression_not_writable_self float_parse global_variable_bare hash_key
        heredoc_identifier instance_variable_bare invalid_block_exit invalid_encoding_magic_comment
        invalid_float_exponent invalid_number_binary invalid_number_decimal invalid_number_hexadecimal
        invalid_number_octal invalid_number_underscore_trailing no_local_variable parameter_order
        statement_undef void_expression
      ].to_h { |id| [id, true] }.freeze

      # The errors of a token that does not belong where it is.
      STRAY_ERRORS = { unexpected_token_ignore: true, unexpected_token_close_context: true }.freeze

      attr_reader :source, :errors, :warnings, :comments, :magic_comments, :data_loc, :newlines,
                  :constant_pool, :encoding, :start_line, :options, :shared_strings, :negative_zeros, :filepath

      # The Source that each node refers to.
      attr_accessor :node_source

      # pm_lex_callback_t: called with each token's type, start and end, and
      # the lex state after it.
      attr_writer :lex_callback

      # pm_encoding_changed_callback_t: called when a magic comment changes
      # the encoding.
      attr_writer :encoding_changed_callback

      # pm_parser_init
      def initialize(source, options)
        @source = source.b.freeze
        @end = @source.bytesize
        @options = options

        @node_id = 0
        @lex_state = STATE_BEG
        @enclosure_nesting = 0
        @lambda_enclosure_nesting = -1
        @brace_nesting = 0
        @do_loop_stack = 0
        @accepts_block_stack = 0
        @lex_modes = [LexMode.new(:default)]
        @breakpoints = {}
        @lex_mode = @lex_modes.last
        @previous_type = :EOF
        @previous_start = @previous_end = 0
        @current_type = :EOF
        @current_start = @current_end = 0
        @next_start = nil
        @heredoc_end = nil
        @comments = []
        # The strings that are slices of the source, by identity, with where
        # each starts (pm_string_t's shared kind), for Prism.dump.
        @shared_strings = {}.compare_by_identity
        @magic_comments = []
        @data_loc = nil
        @warnings = []
        @errors = []
        @current_scope = nil
        @contexts = []
        @encoding = Encodings::UTF_8
        @encoding_comment_start = 0
        @lex_callback = nil
        @encoding_changed_callback = nil
        @filepath = (options.filepath || "").b
        @constant_pool = ConstantPool.new(@source, [@end / 120, 4].max)
        @constant_cache_start = @constant_cache_end = @constant_cache_id = nil
        # pm_newline_list_t: the offset each line starts at.
        @newlines = [0]
        @integer_base = 0
        @integer_lexed = false
        @integer_value = 0
        @current_string = nil
        @start_line = 1
        @explicit_encoding = nil
        @current_block_exits = nil
        @version = 0
        @command_line = 0
        @frozen_string_literal = Options::FROZEN_STRING_LITERAL_UNSET
        @parsing_eval = false
        @partial_script = false
        @command_start = true
        @recovering = false
        @encoding_locked = false
        @encoding_changed = false
        @pattern_matching_newlines = false
        @in_keyword_arg = false
        @semantic_token_seen = false
        @warn_mismatched_indentation = true

        @node_source = nil
        # The Symbol of each constant id, made on first use.
        @constant_symbols = []
        # The ids of the numeric nodes negated to a zero (`-0`).
        @negative_zeros = []

        read_options(options)
        @version = Options::VERSION_LATEST if @version == 0
        accepts_block_stack_push(true)
        skip_bom
        find_shebang(options)
        @encoding_comment_start += strspn_inline_whitespace(@encoding_comment_start, @end)
      end

      def current_token = Token.new(@current_type, @current_start, @current_end)
      def previous_token = Token.new(@previous_type, @previous_start, @previous_end)

      # The Symbol of the constant numbered `id`, as the loader makes it.
      def constant_symbol(id) = @constant_pool.bytes(id).dup.force_encoding(ruby_encoding).to_sym

      # The Encoding the source's strings take.
      def ruby_encoding = ::Encoding.find(@encoding.name)

      private

      def read_options(options)
        @start_line = options.line
        magic_comment_encoding_value(options.encoding.b) if options.encoding
        @encoding_locked = options.encoding_locked?
        @frozen_string_literal = options.frozen_string_literal
        @command_line = options.command_line
        @version = options.version
        @partial_script = options.partial_script?
        @parsing_eval = !options.scopes.empty?
        @warn_mismatched_indentation = false if @parsing_eval

        options.scopes.each_with_index do |scope, index|
          scope_push(index == 0)
          # Scopes given from the outside cannot take numbered parameters.
          @current_scope.parameters = scope.forwarding | Scope::IMPLICIT_DISALLOWED
          scope.locals.each { |name| local_add_owned(name.b) }
        end
      end

      def skip_bom
        return unless @end >= 3 && @source.getbyte(0) == 0xEF && @source.getbyte(1) == 0xBB && @source.getbyte(2) == 0xBF

        @current_end += 3
        @encoding_comment_start += 3
        @encoding = Encodings::UTF_8
      end

      # The shebang handling of pm_parser_init: a first line that names ruby
      # moves where an encoding comment may be; with -x, or with a main
      # script whose shebang does not name ruby, parsing starts at the first
      # shebang line that does.
      def find_shebang(options)
        search = command_line?(Options::COMMAND_LINE["x"])
        newline = @source.byteindex("\n", @current_end)
        length = (newline || @end) - @current_end

        if length > 2 && @source.getbyte(@current_end) == 0x23 && @source.getbyte(@current_end + 1) == 0x21
          # pm_strnstr looks from the start of the source, not past a BOM.
          if strnstr(0, "ruby", length)
            if newline
              @encoding_comment_start = newline + 1
              warn_shebang_carriage_return(0, length + 1) if options.main_script?
            end
            search = false
          elsif options.main_script? && !@parsing_eval
            search = true
          end
        end
        return unless search

        cursor = 0
        newline = @source.byteindex("\n", cursor)
        found = false
        until newline.nil?
          newline_append(newline)
          cursor = newline + 1
          newline = @source.byteindex("\n", cursor)
          length = (newline || @end) - cursor
          next unless length > 2 && @source.getbyte(cursor) == 0x23 && @source.getbyte(cursor + 1) == 0x21 && strnstr(cursor, "ruby", length)

          found = true
          if newline
            warn_shebang_carriage_return(cursor, length + 1)
            @encoding_comment_start = newline + 1
          end
          break
        end

        if found
          @previous_type = @current_type = :EOF
          @previous_start = @previous_end = @current_start = @current_end = cursor
        else
          err(0, 0, :script_not_found)
          @newlines = [0]
        end
      end

      # pm_strnstr: whether `little` lies within `length` bytes of `from`.
      def strnstr(from, little, length)
        at = @source.byteindex(little, from)
        !at.nil? && at + little.bytesize <= from + length
      end

      # pm_parser_warn_shebang_carriage_return
      def warn_shebang_carriage_return(start, length)
        return unless length > 2 && @source.getbyte(start + length - 2) == 0x0D && @source.getbyte(start + length - 1) == 0x0A

        warn(start, start + length, :shebang_carriage_return)
      end

      def command_line?(flag) = @command_line.anybits?(flag)

      # -- diagnostics ------------------------------------------------------

      # pm_diagnostic_list_append and its _format twin: the message filled
      # from the C format with `arguments`.
      def diagnostic(list, table, start, finish, id, arguments)
        template, level = table.fetch(id)
        message = arguments.empty? ? template.b : Diagnostics.format(template, arguments)
        list << Diagnostic.new(id, start, finish, message, level)
      end

      # pm_parser_err, PM_PARSER_ERR_FORMAT
      def err(start, finish, id, *arguments) = diagnostic(@errors, Diagnostics::ERRORS, start, finish, id, arguments)

      # pm_parser_warn, PM_PARSER_WARN_FORMAT
      def warn(start, finish, id, *arguments) = diagnostic(@warnings, Diagnostics::WARNINGS, start, finish, id, arguments)

      def err_current(id, *arguments) = err(@current_start, @current_end, id, *arguments)
      def err_previous(id, *arguments) = err(@previous_start, @previous_end, id, *arguments)
      def warn_current(id, *arguments) = warn(@current_start, @current_end, id, *arguments)

      # PM_PARSER_ERR_TOKEN_FORMAT_CONTENT with the current token.
      def err_current_content(id) = err_current(id, @source.byteslice(@current_start, @current_end - @current_start))

      # pm_parser_err_heredoc_term
      def err_heredoc_term(ident_start, ident_length)
        err(ident_start, ident_start + ident_length, :heredoc_term, @source.byteslice(ident_start, ident_length))
      end

      # -- lex modes ----------------------------------------------------------

      # lex_mode_incrementor
      def lex_mode_incrementor(start) = [0x28, 0x5B, 0x7B, 0x3C].include?(start) ? start : 0

      # lex_mode_terminator
      def lex_mode_terminator(start)
        case start
        when 0x28 then 0x29
        when 0x5B then 0x5D
        when 0x7B then 0x7D
        when 0x3C then 0x3E
        else start
        end
      end

      # lex_mode_push
      def lex_mode_push(mode)
        @lex_modes << mode
        @lex_mode = mode
      end

      # lex_mode_push_list
      def lex_mode_push_list(interpolation, delimiter)
        incrementor = lex_mode_incrementor(delimiter)
        terminator = lex_mode_terminator(delimiter)
        breakpoints = "\\ \t\f\r\v\n".b
        breakpoints << terminator if terminator != 0
        breakpoints << "#" if interpolation
        breakpoints << incrementor if incrementor != 0
        @explicit_encoding = nil
        lex_mode_push(LexMode.new(:list, 0, interpolation, nil, incrementor, terminator, breakpoints(breakpoints)))
      end

      # lex_mode_push_list_eof
      def lex_mode_push_list_eof = lex_mode_push_list(false, 0)

      # lex_mode_push_regexp
      def lex_mode_push_regexp(incrementor, terminator)
        breakpoints = "\r\n\\#".b
        breakpoints << terminator if terminator != 0
        breakpoints << incrementor if incrementor != 0
        @explicit_encoding = nil
        lex_mode_push(LexMode.new(:regexp, 0, nil, nil, incrementor, terminator, breakpoints(breakpoints)))
      end

      # lex_mode_push_string
      def lex_mode_push_string(interpolation, label_allowed, incrementor, terminator)
        breakpoints = "\r\n\\".b
        breakpoints << terminator if terminator != 0
        breakpoints << "#" if interpolation
        breakpoints << incrementor if incrementor != 0
        @explicit_encoding = nil
        lex_mode_push(LexMode.new(:string, 0, interpolation, label_allowed, incrementor, terminator, breakpoints(breakpoints)))
      end

      # lex_mode_push_string_eof
      def lex_mode_push_string_eof = lex_mode_push_string(false, false, 0, 0)

      # lex_mode_pop: the bottom mode is never popped, only made default.
      def lex_mode_pop
        if @lex_modes.size == 1
          @lex_mode.mode = :default
        else
          @lex_modes.pop
          @lex_mode = @lex_modes.last
        end
      end

      # -- lex state ------------------------------------------------------------

      def lex_state?(state) = @lex_state.anybits?(state)

      # lex_state_ignored_p: :none, :all or :pattern.
      def lex_state_ignored
        if lex_state?(STATE_BEG | STATE_CLASS | STATE_FNAME | STATE_DOT) && !lex_state?(STATE_LABELED)
          :all
        elsif (@lex_state & ~STATE_LABEL) == (STATE_ARG | STATE_LABELED)
          :pattern
        else
          :none
        end
      end

      # lex_state_beg_p
      def lex_state_beg? = lex_state?(STATE_BEG_ANY) || (@lex_state & (STATE_ARG | STATE_LABELED)) == (STATE_ARG | STATE_LABELED)

      # lex_state_arg_p
      def lex_state_arg? = lex_state?(STATE_ARG_ANY)

      # lex_state_spcarg_p
      def lex_state_spcarg?(space_seen)
        return false if @current_end >= @end

        lex_state_arg? && space_seen && !whitespace?(@source.getbyte(@current_end))
      end

      # lex_state_end_p
      def lex_state_end? = lex_state?(STATE_END_ANY)

      # lex_state_operator_p
      def lex_state_operator? = lex_state?(STATE_FNAME | STATE_DOT)

      # -- stacks ---------------------------------------------------------------

      # pm_accepts_block_stack_push, which pushes the negation.
      def accepts_block_stack_push(value) = @accepts_block_stack = ((@accepts_block_stack << 1) | (value ? 0 : 1)) & 0xFFFF_FFFF
      def accepts_block_stack_pop = @accepts_block_stack >>= 1
      def accepts_block_stack? = @accepts_block_stack.nobits?(1)

      def do_loop_stack_push(value) = @do_loop_stack = ((@do_loop_stack << 1) | (value ? 1 : 0)) & 0xFFFF_FFFF
      def do_loop_stack_pop = @do_loop_stack >>= 1
      def do_loop_stack? = @do_loop_stack.anybits?(1)

      # pm_enclosure_frame_push: an opening delimiter (`(`, `[`, `{` or `#{`)
      # makes a `do` inside it neither a loop's `do` nor one that binds to
      # an enclosing command, as parse.y's COND_PUSH(0) and CMDARG_PUSH(0).
      # The lexer pushes the frame at the delimiter and pops it at its
      # closer.
      def enclosure_frame_push
        do_loop_stack_push(false)
        accepts_block_stack_push(true)
      end

      def enclosure_frame_pop
        do_loop_stack_pop
        accepts_block_stack_pop
      end

      # -- scopes and locals ------------------------------------------------------

      # pm_parser_scope_push
      def scope_push(closed)
        @current_scope = Scope.new(@current_scope, closed)
      end

      # pm_parser_scope_pop
      def scope_pop
        @current_scope = @current_scope.previous
      end

      # pm_parser_constant_id_raw: the id of the source's bytes. A lookup of
      # the range just looked up reuses its id with no insert, so it does
      # not grow the pool.
      def constant_id_location(start, finish)
        return @constant_cache_id if start == @constant_cache_start && finish == @constant_cache_end

        @constant_cache_start = start
        @constant_cache_end = finish
        @constant_cache_id = @constant_pool.insert_shared(start, finish - start)
      end

      # pm_parser_constant_id_owned
      def constant_id_owned(bytes) = @constant_pool.insert_owned(bytes)

      # pm_parser_constant_id_constant
      def constant_id_constant(bytes) = @constant_pool.insert_constant(bytes)

      # pm_parser_local_depth_constant_id: how many scopes out the local is,
      # or -1.
      def local_depth_constant_id(constant_id)
        scope = @current_scope
        depth = 0
        until scope.nil?
          return depth if scope.locals.include?(constant_id)
          break if scope.closed?

          scope = scope.previous
          depth += 1
        end
        -1
      end

      # pm_parser_local_depth, which interns the token's name.
      def local_depth(start, finish) = local_depth_constant_id(constant_id_location(start, finish))

      # pm_parser_local_add
      def local_add(constant_id, start, finish, reads) = @current_scope.locals.write(constant_id, start, finish, reads)

      # pm_parser_local_add_owned
      def local_add_owned(bytes)
        constant_id = constant_id_owned(bytes)
        local_add(constant_id, 0, 0, 1) if constant_id != 0
        constant_id
      end

      # -- newlines -------------------------------------------------------------

      # pm_newline_list_append: the newline at `at` starts a line after it.
      def newline_append(at) = @newlines << at + 1

      # -- bytes ----------------------------------------------------------------

      # peek_at
      def peek_at(cursor) = cursor < @end ? @source.getbyte(cursor) : 0

      # peek_offset
      def peek_offset(offset) = peek_at(@current_end + offset)

      # peek
      def peek = peek_at(@current_end)

      # match
      def match(value)
        return false unless peek == value

        @current_end += 1
        true
      end

      # match_eol_at: the length of a line ending at `cursor`, or 0.
      def match_eol_at(cursor)
        return 1 if peek_at(cursor) == 0x0A
        return 2 if peek_at(cursor) == 0x0D && peek_at(cursor + 1) == 0x0A

        0
      end

      def match_eol_offset(offset) = match_eol_at(@current_end + offset)
      def match_eol = match_eol_at(@current_end)

      # next_newline: the offset of the next \n at or after `cursor` before
      # `limit`, or nil.
      def next_newline(cursor, limit = @end)
        found = @source.byteindex("\n", cursor)
        found && found < limit ? found : nil
      end
    end
  end
end
