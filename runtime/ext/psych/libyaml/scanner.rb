# frozen_string_literal: true

# The scanner of libyaml 0.2.5 (src/scanner.c): it turns the characters
# the reader decodes into tokens. The comments at the top of scanner.c
# describe the token grammar; this port keeps its functions one for one,
# under the same names without the `yaml_parser_` prefix.
#
# The current position is three integers (`@mark_index`, `@mark_line`
# and `@mark_column`), and `current_mark` copies them into a Mark where
# libyaml copies `parser->mark`.
module Psych
  module LibYAML
    module Scanner
      # MAX_NUMBER_LENGTH: the most digits a %YAML version number may have.
      MAX_NUMBER_LENGTH = 9

      # INT_MAX, which bounds the flow level and the indentation.
      INT_MAX = 2_147_483_647

      # The characters that a plain scalar cannot start with, unless the
      # special rules for '-', '?' and ':' allow it.
      PLAIN_START_INDICATORS = "-?:,[]{}#&*!|>'\"%@`".bytes.freeze

      # The characters that may end an anchor or an alias besides a blank.
      ANCHOR_END_INDICATORS = "?:,]}%@`".bytes.freeze

      # The characters of a URI besides the alphanumerics.
      URI_CHARACTERS = ";/?:@&=+$.%!~*'()".bytes.freeze

      # The flow indicators that a verbatim tag <...> may also hold.
      VERBATIM_URI_CHARACTERS = ",[]".bytes.freeze

      # The current position, as a new Mark.
      def current_mark = Mark.new(@mark_index, @mark_line, @mark_column)

      private

      # yaml_parser_fetch_more_tokens: make sure the token queue contains a
      # token that the parser can take. A token can still become a simple
      # key while a potential simple key refers to it, so the scanner reads
      # on until no such key remains.
      def fetch_more_tokens
        loop do
          need_more_tokens = false

          if @tokens.empty?
            need_more_tokens = true
          else
            stale_simple_keys

            @simple_keys.each do |simple_key|
              if simple_key.possible && simple_key.token_number == @tokens_parsed
                need_more_tokens = true
                break
              end
            end
          end

          break unless need_more_tokens

          fetch_next_token
        end

        @token_available = true
      end

      # --- Buffer macros ---------------------------------------------------

      # CACHE: make sure the buffer contains `length` characters.
      def cache(length)
        update_buffer(length) if @unread < length
      end

      # SKIP: move past one character.
      def skip
        @mark_index += 1
        @mark_column += 1
        @unread -= 1
        @pointer += width_at(@buffer, @pointer)
      end

      # SKIP_LINE: move past one line break; CR LF counts as one.
      def skip_line
        if crlf_at?(@buffer, @pointer)
          @mark_index += 2
          @mark_column = 0
          @mark_line += 1
          @unread -= 2
          @pointer += 2
        elsif break_at?(@buffer, @pointer)
          @mark_index += 1
          @mark_column = 0
          @mark_line += 1
          @unread -= 1
          @pointer += width_at(@buffer, @pointer)
        end
      end

      # READ: copy one character into `string` and move past it.
      def read(string)
        width = width_at(@buffer, @pointer)
        if width == 1
          string << @buffer.getbyte(@pointer)
        else
          string << @buffer.byteslice(@pointer, width)
        end
        @pointer += width
        @mark_index += 1
        @mark_column += 1
        @unread -= 1
      end

      # READ_LINE: copy one line break into `string` and move past it.
      # CR LF, CR and NEL all become LF; LS and PS stay as they are.
      def read_line(string)
        buffer = @buffer
        octet = buffer.getbyte(@pointer)
        following = buffer.getbyte(@pointer + 1)
        if octet == 0x0D && following == 0x0A
          string << 0x0A
          @pointer += 2
          @mark_index += 2
          @mark_column = 0
          @mark_line += 1
          @unread -= 2
        elsif octet == 0x0D || octet == 0x0A
          string << 0x0A
          @pointer += 1
          @mark_index += 1
          @mark_column = 0
          @mark_line += 1
          @unread -= 1
        elsif octet == 0xC2 && following == 0x85
          string << 0x0A
          @pointer += 2
          @mark_index += 1
          @mark_column = 0
          @mark_line += 1
          @unread -= 1
        elsif octet == 0xE2 && following == 0x80 &&
              ((third = buffer.getbyte(@pointer + 2)) == 0xA8 || third == 0xA9)
          string << buffer.byteslice(@pointer, 3)
          @pointer += 3
          @mark_index += 1
          @mark_column = 0
          @mark_line += 1
          @unread -= 1
        end
      end

      # CHECK on the current character.
      def check?(char) = @buffer.getbyte(@pointer) == char.ord

      # --- Errors ----------------------------------------------------------

      # yaml_parser_set_scanner_error
      def scanner_error(context, context_mark, problem)
        @error = SCANNER_ERROR
        @context = context
        @context_mark = context_mark
        @problem = problem
        @problem_mark = current_mark
        raise Failure
      end

      def memory_error
        @error = MEMORY_ERROR
        raise Failure
      end

      # --- The dispatcher --------------------------------------------------

      # yaml_parser_fetch_next_token
      def fetch_next_token
        # Ensure that the buffer is initialized.
        cache(1)

        # Fetch STREAM-START first.
        return fetch_stream_start unless @stream_start_produced

        # Eat whitespaces and comments until the next token.
        scan_to_next_token

        # Remove obsolete potential simple keys.
        stale_simple_keys

        # Check the indentation level against the current column.
        unroll_indent(@mark_column)

        # The longest indicators ('--- ' and '... ') take 4 characters.
        cache(4)

        buffer = @buffer
        at = @pointer
        octet = buffer.getbyte(at)

        # Is it the end of the stream?
        return fetch_stream_end if z_at?(buffer, at)

        # Is it a directive?
        return fetch_directive if @mark_column.zero? && octet == 0x25

        # Is it the document start indicator?
        if @mark_column.zero? && octet == 0x2D && buffer.getbyte(at + 1) == 0x2D &&
           buffer.getbyte(at + 2) == 0x2D && blankz_at?(buffer, at + 3)
          return fetch_document_indicator(DOCUMENT_START_TOKEN)
        end

        # Is it the document end indicator?
        if @mark_column.zero? && octet == 0x2E && buffer.getbyte(at + 1) == 0x2E &&
           buffer.getbyte(at + 2) == 0x2E && blankz_at?(buffer, at + 3)
          return fetch_document_indicator(DOCUMENT_END_TOKEN)
        end

        case octet
        when 0x5B then return fetch_flow_collection_start(FLOW_SEQUENCE_START_TOKEN) # [
        when 0x7B then return fetch_flow_collection_start(FLOW_MAPPING_START_TOKEN)  # {
        when 0x5D then return fetch_flow_collection_end(FLOW_SEQUENCE_END_TOKEN)     # ]
        when 0x7D then return fetch_flow_collection_end(FLOW_MAPPING_END_TOKEN)      # }
        when 0x2C then return fetch_flow_entry                                       # ,
        end

        # Is it the block entry indicator?
        return fetch_block_entry if octet == 0x2D && blankz_at?(buffer, at + 1)

        # Is it the key indicator?
        return fetch_key if octet == 0x3F && (@flow_level.positive? || blankz_at?(buffer, at + 1))

        # Is it the value indicator?
        return fetch_value if octet == 0x3A && (@flow_level.positive? || blankz_at?(buffer, at + 1))

        case octet
        when 0x2A then return fetch_anchor(ALIAS_TOKEN)  # *
        when 0x26 then return fetch_anchor(ANCHOR_TOKEN) # &
        when 0x21 then return fetch_tag                  # !
        when 0x7C then return fetch_block_scalar(true) if @flow_level.zero?  # |
        when 0x3E then return fetch_block_scalar(false) if @flow_level.zero? # >
        when 0x27 then return fetch_flow_scalar(true)    # '
        when 0x22 then return fetch_flow_scalar(false)   # "
        end

        # Is it a plain scalar?
        #
        # A plain scalar may start with any non-blank character except
        # the indicators. In the block context (and, for '-', in the flow
        # context too), it may also start with '-', '?' or ':' if a
        # non-space character follows.
        if !(blankz_at?(buffer, at) || PLAIN_START_INDICATORS.include?(octet)) ||
           (octet == 0x2D && !blank_at?(buffer, at + 1)) ||
           (@flow_level.zero? && (octet == 0x3F || octet == 0x3A) && !blankz_at?(buffer, at + 1))
          return fetch_plain_scalar
        end

        # No token starts here.
        scanner_error("while scanning for the next token", current_mark,
                      "found character that cannot start any token")
      end

      # --- Simple keys -----------------------------------------------------

      # yaml_parser_stale_simple_keys: a simple key must stay on one line
      # and be shorter than 1024 characters; drop the ones that cannot.
      def stale_simple_keys
        @simple_keys.each do |simple_key|
          next unless simple_key.possible &&
                      (simple_key.mark.line < @mark_line || simple_key.mark.index + 1024 < @mark_index)

          if simple_key.required
            scanner_error("while scanning a simple key", simple_key.mark, "could not find expected ':'")
          end

          simple_key.possible = false
        end
      end

      # yaml_parser_save_simple_key: note that a simple key may start at
      # the current position. In the block context the key is required
      # when it starts at the indentation column.
      def save_simple_key
        required = @flow_level.zero? && @indent == @mark_column

        return unless @simple_key_allowed

        simple_key = SimpleKey.new(true, required, @tokens_parsed + @tokens.size, current_mark)

        remove_simple_key

        @simple_keys[-1] = simple_key
      end

      # yaml_parser_remove_simple_key: drop the potential simple key at the
      # current flow level.
      def remove_simple_key
        simple_key = @simple_keys[-1]

        if simple_key.possible && simple_key.required
          scanner_error("while scanning a simple key", simple_key.mark, "could not find expected ':'")
        end

        simple_key.possible = false
      end

      # yaml_parser_increase_flow_level
      def increase_flow_level
        @simple_keys.push(SimpleKey.new(false, false, 0, ZERO_MARK))

        memory_error if @flow_level == INT_MAX

        @flow_level += 1
      end

      # yaml_parser_decrease_flow_level
      def decrease_flow_level
        return unless @flow_level.positive?

        @flow_level -= 1
        @simple_keys.pop
      end

      # --- Indentation -----------------------------------------------------

      # yaml_parser_roll_indent: in the block context, open a collection
      # when `column` is deeper than the indentation. The start token goes
      # at the end of the queue, or before token `number` when a simple
      # key turns out to start the collection.
      def roll_indent(column, number, type, mark)
        return if @flow_level.positive?
        return unless @indent < column

        @indents.push(@indent)

        memory_error if column > INT_MAX

        @indent = column

        token = Token.new(type, mark, mark)
        if number == -1
          @tokens.push(token)
        else
          @tokens.insert(number - @tokens_parsed, token)
        end
      end

      # yaml_parser_unroll_indent: close every block collection deeper than
      # `column`, with a BLOCK-END token each.
      def unroll_indent(column)
        return if @flow_level.positive?

        while @indent > column
          mark = current_mark
          @tokens.push(Token.new(BLOCK_END_TOKEN, mark, mark))
          @indent = @indents.pop
        end
      end

      # --- Token fetchers --------------------------------------------------

      # yaml_parser_fetch_stream_start
      def fetch_stream_start
        @indent = -1

        @simple_keys.push(SimpleKey.new(false, false, 0, ZERO_MARK))

        @simple_key_allowed = true

        @stream_start_produced = true

        mark = current_mark
        token = Token.new(STREAM_START_TOKEN, mark, mark)
        token.encoding = @encoding
        @tokens.push(token)
      end

      # yaml_parser_fetch_stream_end
      def fetch_stream_end
        # Force a new line.
        unless @mark_column.zero?
          @mark_column = 0
          @mark_line += 1
        end

        unroll_indent(-1)

        remove_simple_key

        @simple_key_allowed = false

        mark = current_mark
        @tokens.push(Token.new(STREAM_END_TOKEN, mark, mark))
      end

      # yaml_parser_fetch_directive
      def fetch_directive
        unroll_indent(-1)

        remove_simple_key

        @simple_key_allowed = false

        @tokens.push(scan_directive)
      end

      # yaml_parser_fetch_document_indicator
      def fetch_document_indicator(type)
        unroll_indent(-1)

        remove_simple_key

        @simple_key_allowed = false

        start_mark = current_mark

        skip
        skip
        skip

        @tokens.push(Token.new(type, start_mark, current_mark))
      end

      # yaml_parser_fetch_flow_collection_start: '[' or '{', which may
      # start a simple key.
      def fetch_flow_collection_start(type)
        save_simple_key

        increase_flow_level

        @simple_key_allowed = true

        start_mark = current_mark
        skip
        @tokens.push(Token.new(type, start_mark, current_mark))
      end

      # yaml_parser_fetch_flow_collection_end: ']' or '}'.
      def fetch_flow_collection_end(type)
        remove_simple_key

        decrease_flow_level

        @simple_key_allowed = false

        start_mark = current_mark
        skip
        @tokens.push(Token.new(type, start_mark, current_mark))
      end

      # yaml_parser_fetch_flow_entry: ','.
      def fetch_flow_entry
        remove_simple_key

        @simple_key_allowed = true

        start_mark = current_mark
        skip
        @tokens.push(Token.new(FLOW_ENTRY_TOKEN, start_mark, current_mark))
      end

      # yaml_parser_fetch_block_entry: '-'.
      def fetch_block_entry
        if @flow_level.zero?
          unless @simple_key_allowed
            scanner_error(nil, current_mark, "block sequence entries are not allowed in this context")
          end

          roll_indent(@mark_column, -1, BLOCK_SEQUENCE_START_TOKEN, current_mark)
        end
        # In the flow context the parser reports the '-' indicator, since
        # it can point to the context.

        remove_simple_key

        @simple_key_allowed = true

        start_mark = current_mark
        skip
        @tokens.push(Token.new(BLOCK_ENTRY_TOKEN, start_mark, current_mark))
      end

      # yaml_parser_fetch_key: '?'.
      def fetch_key
        if @flow_level.zero?
          unless @simple_key_allowed
            scanner_error(nil, current_mark, "mapping keys are not allowed in this context")
          end

          roll_indent(@mark_column, -1, BLOCK_MAPPING_START_TOKEN, current_mark)
        end

        remove_simple_key

        @simple_key_allowed = @flow_level.zero?

        start_mark = current_mark
        skip
        @tokens.push(Token.new(KEY_TOKEN, start_mark, current_mark))
      end

      # yaml_parser_fetch_value: ':'. When a simple key is possible here,
      # its KEY token (and a BLOCK-MAPPING-START) goes in before the
      # tokens of the key.
      def fetch_value
        simple_key = @simple_keys[-1]

        if simple_key.possible
          @tokens.insert(simple_key.token_number - @tokens_parsed,
                         Token.new(KEY_TOKEN, simple_key.mark, simple_key.mark))

          roll_indent(simple_key.mark.column, simple_key.token_number,
                      BLOCK_MAPPING_START_TOKEN, simple_key.mark)

          simple_key.possible = false

          # A simple key cannot follow another simple key.
          @simple_key_allowed = false
        else
          # The ':' indicator follows a complex key.
          if @flow_level.zero?
            unless @simple_key_allowed
              scanner_error(nil, current_mark, "mapping values are not allowed in this context")
            end

            roll_indent(@mark_column, -1, BLOCK_MAPPING_START_TOKEN, current_mark)
          end

          @simple_key_allowed = @flow_level.zero?
        end

        start_mark = current_mark
        skip
        @tokens.push(Token.new(VALUE_TOKEN, start_mark, current_mark))
      end

      # yaml_parser_fetch_anchor: an ALIAS or an ANCHOR, which may start a
      # simple key.
      def fetch_anchor(type)
        save_simple_key

        @simple_key_allowed = false

        @tokens.push(scan_anchor(type))
      end

      # yaml_parser_fetch_tag
      def fetch_tag
        save_simple_key

        @simple_key_allowed = false

        @tokens.push(scan_tag)
      end

      # yaml_parser_fetch_block_scalar
      def fetch_block_scalar(literal)
        remove_simple_key

        # A simple key may follow a block scalar.
        @simple_key_allowed = true

        @tokens.push(scan_block_scalar(literal))
      end

      # yaml_parser_fetch_flow_scalar
      def fetch_flow_scalar(single)
        save_simple_key

        @simple_key_allowed = false

        @tokens.push(scan_flow_scalar(single))
      end

      # yaml_parser_fetch_plain_scalar
      def fetch_plain_scalar
        save_simple_key

        @simple_key_allowed = false

        @tokens.push(scan_plain_scalar)
      end

      # --- Token scanners --------------------------------------------------

      # yaml_parser_scan_to_next_token: eat blanks, comments and line
      # breaks. A tab is a blank in the flow context, and in the block
      # context where no simple key may start (after '-', '?' or ':').
      def scan_to_next_token
        loop do
          # Allow the BOM mark to start a line.
          cache(1)

          skip if @mark_column.zero? && bom_at?(@buffer, @pointer)

          # Eat whitespaces.
          cache(1)

          while check?(" ") || ((@flow_level.positive? || !@simple_key_allowed) && check?("\t"))
            skip
            cache(1)
          end

          # Eat a comment until a line break.
          if check?("#")
            until breakz_at?(@buffer, @pointer)
              skip
              cache(1)
            end
          end

          # If it is a line break, eat it.
          break unless break_at?(@buffer, @pointer)

          cache(2)
          skip_line

          # In the block context, a new line may start a simple key.
          @simple_key_allowed = true if @flow_level.zero?
        end
      end

      # yaml_parser_scan_directive: a %YAML or a %TAG directive, and the
      # rest of its line.
      def scan_directive
        start_mark = current_mark

        skip

        name = scan_directive_name(start_mark)

        if name == "YAML"
          major, minor = scan_version_directive_value(start_mark)

          token = Token.new(VERSION_DIRECTIVE_TOKEN, start_mark, current_mark)
          token.major = major
          token.minor = minor
        elsif name == "TAG"
          handle, prefix = scan_tag_directive_value(start_mark)

          token = Token.new(TAG_DIRECTIVE_TOKEN, start_mark, current_mark)
          token.handle = handle
          token.prefix = prefix
        else
          scanner_error("while scanning a directive", start_mark, "found unknown directive name")
        end

        # Eat the rest of the line including any comments.
        cache(1)

        while blank_at?(@buffer, @pointer)
          skip
          cache(1)
        end

        if check?("#")
          until breakz_at?(@buffer, @pointer)
            skip
            cache(1)
          end
        end

        unless breakz_at?(@buffer, @pointer)
          scanner_error("while scanning a directive", start_mark, "did not find expected comment or line break")
        end

        if break_at?(@buffer, @pointer)
          cache(2)
          skip_line
        end

        token
      end

      # yaml_parser_scan_directive_name
      def scan_directive_name(start_mark)
        string = new_string

        cache(1)

        while alpha_at?(@buffer, @pointer)
          read(string)
          cache(1)
        end

        if string.empty?
          scanner_error("while scanning a directive", start_mark, "could not find expected directive name")
        end

        unless blankz_at?(@buffer, @pointer)
          scanner_error("while scanning a directive", start_mark, "found unexpected non-alphabetical character")
        end

        string
      end

      # yaml_parser_scan_version_directive_value: "1.1".
      def scan_version_directive_value(start_mark)
        cache(1)

        while blank_at?(@buffer, @pointer)
          skip
          cache(1)
        end

        major = scan_version_directive_number(start_mark)

        unless check?(".")
          scanner_error("while scanning a %YAML directive", start_mark,
                        "did not find expected digit or '.' character")
        end

        skip

        minor = scan_version_directive_number(start_mark)

        [major, minor]
      end

      # yaml_parser_scan_version_directive_number
      def scan_version_directive_number(start_mark)
        value = 0
        length = 0

        cache(1)

        while digit_at?(@buffer, @pointer)
          length += 1
          if length > MAX_NUMBER_LENGTH
            scanner_error("while scanning a %YAML directive", start_mark, "found extremely long version number")
          end

          value = (value * 10) + as_digit_at(@buffer, @pointer)

          skip

          cache(1)
        end

        scanner_error("while scanning a %YAML directive", start_mark, "did not find expected version number") if length.zero?

        value
      end

      # yaml_parser_scan_tag_directive_value: "!yaml! tag:yaml.org,2002:".
      def scan_tag_directive_value(start_mark)
        cache(1)

        while blank_at?(@buffer, @pointer)
          skip
          cache(1)
        end

        handle = scan_tag_handle(true, start_mark)

        cache(1)

        unless blank_at?(@buffer, @pointer)
          scanner_error("while scanning a %TAG directive", start_mark, "did not find expected whitespace")
        end

        while blank_at?(@buffer, @pointer)
          skip
          cache(1)
        end

        prefix = scan_tag_uri(true, true, nil, start_mark)

        cache(1)

        unless blankz_at?(@buffer, @pointer)
          scanner_error("while scanning a %TAG directive", start_mark,
                        "did not find expected whitespace or line break")
        end

        [handle, prefix]
      end

      # yaml_parser_scan_anchor: '&name' or '*name'.
      def scan_anchor(type)
        length = 0
        string = new_string

        start_mark = current_mark

        skip

        cache(1)

        while alpha_at?(@buffer, @pointer)
          read(string)
          cache(1)
          length += 1
        end

        end_mark = current_mark

        # The name must not be empty, and a blank or one of the indicators
        # '?', ':', ',', ']', '}', '%', '@', '`' must follow it.
        if length.zero? ||
           !(blankz_at?(@buffer, @pointer) || ANCHOR_END_INDICATORS.include?(@buffer.getbyte(@pointer)))
          scanner_error(type == ANCHOR_TOKEN ? "while scanning an anchor" : "while scanning an alias",
                        start_mark, "did not find expected alphabetic or numeric character")
        end

        token = Token.new(type, start_mark, end_mark)
        token.value = string
        token
      end

      # yaml_parser_scan_tag: '!<uri>', '!suffix' or '!handle!suffix'.
      def scan_tag
        start_mark = current_mark

        cache(2)

        if check_at?(@buffer, 0x3C, @pointer + 1)
          # The verbatim form: the handle is ''.
          handle = new_string

          skip
          skip

          suffix = scan_tag_uri(true, false, nil, start_mark)

          scanner_error("while scanning a tag", start_mark, "did not find the expected '>'") unless check?(">")

          skip
        else
          # First, try to scan a handle.
          handle = scan_tag_handle(false, start_mark)

          if handle.getbyte(0) == 0x21 && handle.bytesize > 1 && handle.getbyte(-1) == 0x21
            # It is, indeed, a handle; scan the suffix now.
            suffix = scan_tag_uri(false, false, nil, start_mark)
          else
            # It wasn't a handle after all. Scan the rest of the tag.
            suffix = scan_tag_uri(false, false, handle, start_mark)

            handle = "!".b

            # The '!' tag on its own: the handle is '' and the suffix '!'.
            handle, suffix = suffix, handle if suffix.empty?
          end
        end

        cache(1)

        if !blankz_at?(@buffer, @pointer) && (@flow_level.zero? || !check?(","))
          scanner_error("while scanning a tag", start_mark, "did not find expected whitespace or line break")
        end

        token = Token.new(TAG_TOKEN, start_mark, current_mark)
        token.handle = handle
        token.suffix = suffix
        token
      end

      # yaml_parser_scan_tag_handle: '!', '!!' or '!word!'. Outside a %TAG
      # directive, '!word' with no closing '!' is the start of a URI.
      def scan_tag_handle(directive, start_mark)
        string = new_string

        cache(1)

        unless check?("!")
          scanner_error(directive ? "while scanning a tag directive" : "while scanning a tag",
                        start_mark, "did not find expected '!'")
        end

        read(string)

        cache(1)

        while alpha_at?(@buffer, @pointer)
          read(string)
          cache(1)
        end

        if check?("!")
          read(string)
        elsif directive && string != "!"
          scanner_error("while parsing a tag directive", start_mark, "did not find expected '!'")
        end

        string
      end

      # yaml_parser_scan_tag_uri: the URI of a tag or a %TAG prefix, after
      # `head` without its leading '!'. libyaml hands the result on as a C
      # string, so an escaped NUL ends it.
      def scan_tag_uri(uri_char, directive, head, start_mark)
        length = head ? head.bytesize : 0
        string = new_string

        string << head.byteslice(1, length - 1) if length > 1

        cache(1)

        loop do
          octet = @buffer.getbyte(@pointer)
          break unless alpha_at?(@buffer, @pointer) || URI_CHARACTERS.include?(octet) ||
                       (uri_char && VERBATIM_URI_CHARACTERS.include?(octet))

          if octet == 0x25
            scan_uri_escapes(directive, start_mark, string)
          else
            read(string)
          end

          length += 1
          cache(1)
        end

        if length.zero?
          scanner_error(directive ? "while parsing a %TAG directive" : "while parsing a tag",
                        start_mark, "did not find expected tag URI")
        end

        c_string(string)
      end

      # yaml_parser_scan_uri_escapes: '%XX' octets that make one UTF-8
      # character.
      def scan_uri_escapes(directive, start_mark, string)
        context = directive ? "while parsing a %TAG directive" : "while parsing a tag"
        width = 0

        loop do
          cache(3)

          unless check?("%") && hex_at?(@buffer, @pointer + 1) && hex_at?(@buffer, @pointer + 2)
            scanner_error(context, start_mark, "did not find URI escaped octet")
          end

          octet = (as_hex_at(@buffer, @pointer + 1) << 4) + as_hex_at(@buffer, @pointer + 2)

          if width.zero?
            width = if octet & 0x80 == 0x00 then 1
                    elsif octet & 0xE0 == 0xC0 then 2
                    elsif octet & 0xF0 == 0xE0 then 3
                    elsif octet & 0xF8 == 0xF0 then 4
                    else 0
                    end
            scanner_error(context, start_mark, "found an incorrect leading UTF-8 octet") if width.zero?
          elsif octet & 0xC0 != 0x80
            scanner_error(context, start_mark, "found an incorrect trailing UTF-8 octet")
          end

          string << octet
          skip
          skip
          skip

          width -= 1
          break if width.zero?
        end
      end

      # yaml_parser_scan_block_scalar: a literal ('|') or folded ('>')
      # scalar, with its chomping and indentation indicators.
      def scan_block_scalar(literal)
        string = new_string
        leading_break = new_string
        trailing_breaks = new_string
        chomping = 0
        increment = 0
        indent = 0
        leading_blank = false
        trailing_blank = false

        start_mark = current_mark

        skip

        cache(1)

        if check?("+") || check?("-")
          # A chomping indicator, then maybe an indentation indicator.
          chomping = check?("+") ? 1 : -1

          skip

          cache(1)

          if digit_at?(@buffer, @pointer)
            if check?("0")
              scanner_error("while scanning a block scalar", start_mark, "found an indentation indicator equal to 0")
            end

            increment = as_digit_at(@buffer, @pointer)

            skip
          end
        elsif digit_at?(@buffer, @pointer)
          # The same, in the opposite order.
          if check?("0")
            scanner_error("while scanning a block scalar", start_mark, "found an indentation indicator equal to 0")
          end

          increment = as_digit_at(@buffer, @pointer)

          skip

          cache(1)

          if check?("+") || check?("-")
            chomping = check?("+") ? 1 : -1

            skip
          end
        end

        # Eat whitespaces and comments to the end of the line.
        cache(1)

        while blank_at?(@buffer, @pointer)
          skip
          cache(1)
        end

        if check?("#")
          until breakz_at?(@buffer, @pointer)
            skip
            cache(1)
          end
        end

        unless breakz_at?(@buffer, @pointer)
          scanner_error("while scanning a block scalar", start_mark, "did not find expected comment or line break")
        end

        if break_at?(@buffer, @pointer)
          cache(2)
          skip_line
        end

        end_mark = current_mark

        # Set the indentation level if the indicator gave it.
        indent = @indent >= 0 ? @indent + increment : increment unless increment.zero?

        # Scan the leading line breaks and find the indentation if needed.
        indent, end_mark = scan_block_scalar_breaks(indent, trailing_breaks, start_mark, end_mark)

        cache(1)

        while @mark_column == indent && !z_at?(@buffer, @pointer)
          # This is the beginning of a non-empty line.

          trailing_blank = blank_at?(@buffer, @pointer)

          # Fold the leading line break if needed.
          if !literal && leading_break.getbyte(0) == 0x0A && !leading_blank && !trailing_blank
            # Join the lines with a space if no empty line lies between.
            string << 0x20 if trailing_breaks.empty?

            leading_break.clear
          else
            string << leading_break
            leading_break.clear
          end

          # Append the remaining line breaks.
          string << trailing_breaks
          trailing_breaks.clear

          leading_blank = blank_at?(@buffer, @pointer)

          # Consume the current line.
          until breakz_at?(@buffer, @pointer)
            read(string)
            cache(1)
          end

          # Consume the line break.
          cache(2)

          read_line(leading_break)

          # Eat the following indentation spaces and line breaks.
          indent, end_mark = scan_block_scalar_breaks(indent, trailing_breaks, start_mark, end_mark)
        end

        # Chomp the tail.
        string << leading_break unless chomping == -1
        string << trailing_breaks if chomping == 1

        token = Token.new(SCALAR_TOKEN, start_mark, end_mark)
        token.value = string
        token.style = literal ? LITERAL_SCALAR_STYLE : FOLDED_SCALAR_STYLE
        token
      end

      # yaml_parser_scan_block_scalar_breaks: eat indentation spaces and
      # line breaks, and find the indentation when it is still 0. Returns
      # the indentation and the end mark, which C passes back through
      # pointers.
      def scan_block_scalar_breaks(indent, breaks, start_mark, end_mark)
        max_indent = 0

        end_mark = current_mark

        loop do
          # Eat the indentation spaces.
          cache(1)

          while (indent.zero? || @mark_column < indent) && space_at?(@buffer, @pointer)
            skip
            cache(1)
          end

          max_indent = @mark_column if @mark_column > max_indent

          # A tab must not stand where the indentation is.
          if (indent.zero? || @mark_column < indent) && tab_at?(@buffer, @pointer)
            scanner_error("while scanning a block scalar", start_mark,
                          "found a tab character where an indentation space is expected")
          end

          # Stop at a non-empty line.
          break unless break_at?(@buffer, @pointer)

          # Consume the line break.
          cache(2)
          read_line(breaks)
          end_mark = current_mark
        end

        if indent.zero?
          indent = max_indent
          indent = @indent + 1 if indent < @indent + 1
          indent = 1 if indent < 1
        end

        [indent, end_mark]
      end

      # yaml_parser_scan_flow_scalar: a single-quoted or a double-quoted
      # scalar.
      def scan_flow_scalar(single)
        string = new_string
        leading_break = new_string
        trailing_breaks = new_string
        whitespaces = new_string

        start_mark = current_mark

        # Eat the left quote.
        skip

        loop do
          # No document indicator may start a line inside the scalar.
          cache(4)

          buffer = @buffer
          at = @pointer
          if @mark_column.zero? &&
             ((buffer.getbyte(at) == 0x2D && buffer.getbyte(at + 1) == 0x2D && buffer.getbyte(at + 2) == 0x2D) ||
              (buffer.getbyte(at) == 0x2E && buffer.getbyte(at + 1) == 0x2E && buffer.getbyte(at + 2) == 0x2E)) &&
             blankz_at?(buffer, at + 3)
            scanner_error("while scanning a quoted scalar", start_mark, "found unexpected document indicator")
          end

          if z_at?(buffer, at)
            scanner_error("while scanning a quoted scalar", start_mark, "found unexpected end of stream")
          end

          # Consume non-blank characters.
          cache(2)

          leading_blanks = false

          until blankz_at?(@buffer, @pointer)
            buffer = @buffer
            at = @pointer
            octet = buffer.getbyte(at)

            if single && octet == 0x27 && buffer.getbyte(at + 1) == 0x27
              # An escaped single quote.
              string << 0x27
              skip
              skip
            elsif octet == (single ? 0x27 : 0x22)
              # The right quote.
              break
            elsif !single && octet == 0x5C && break_at?(buffer, at + 1)
              # An escaped line break.
              cache(3)
              skip
              skip_line
              leading_blanks = true
              break
            elsif !single && octet == 0x5C
              scan_escape_sequence(string, start_mark)
            else
              # A non-escaped non-blank character.
              read(string)
            end

            cache(2)
          end

          # Check if we are at the end of the scalar.
          cache(1)
          break if check?(single ? "'" : '"')

          # Consume blank characters.
          cache(1)

          while blank_at?(@buffer, @pointer) || break_at?(@buffer, @pointer)
            if blank_at?(@buffer, @pointer)
              # Consume a space or a tab character.
              if leading_blanks
                skip
              else
                read(whitespaces)
              end
            else
              cache(2)

              if leading_blanks
                read_line(trailing_breaks)
              else
                # This is the first line break.
                whitespaces.clear
                read_line(leading_break)
                leading_blanks = true
              end
            end
            cache(1)
          end

          # Join the whitespaces or fold the line breaks.
          if leading_blanks
            if leading_break.getbyte(0) == 0x0A
              if trailing_breaks.empty?
                string << 0x20
              else
                string << trailing_breaks
                trailing_breaks.clear
              end
              leading_break.clear
            else
              string << leading_break
              string << trailing_breaks
              leading_break.clear
              trailing_breaks.clear
            end
          else
            string << whitespaces
            whitespaces.clear
          end
        end

        # Eat the right quote.
        skip

        token = Token.new(SCALAR_TOKEN, start_mark, current_mark)
        token.value = string
        token.style = single ? SINGLE_QUOTED_SCALAR_STYLE : DOUBLE_QUOTED_SCALAR_STYLE
        token
      end

      # The escape characters of a double-quoted scalar and what each one
      # writes. 'x', 'u' and 'U' take a code instead.
      ESCAPES = {
        0x30 => "\0", 0x61 => "\a", 0x62 => "\b", 0x74 => "\t", 0x09 => "\t",
        0x6E => "\n", 0x76 => "\v", 0x66 => "\f", 0x72 => "\r", 0x65 => "\e",
        0x20 => " ", 0x22 => '"', 0x2F => "/", 0x5C => "\\",
        0x4E => "", 0x5F => " ", 0x4C => " ", 0x50 => " "
      }.transform_values { |text| text.b.freeze }.freeze

      ESCAPE_CODE_LENGTHS = { 0x78 => 2, 0x75 => 4, 0x55 => 8 }.freeze

      # The escape sequence part of yaml_parser_scan_flow_scalar: a '\'
      # and what follows it.
      def scan_escape_sequence(string, start_mark)
        escape = @buffer.getbyte(@pointer + 1)
        code_length = ESCAPE_CODE_LENGTHS.fetch(escape, 0)

        if code_length.zero?
          text = ESCAPES[escape]
          scanner_error("while parsing a quoted scalar", start_mark, "found unknown escape character") unless text

          string << text
        end

        skip
        skip

        return if code_length.zero?

        # Scan the character value.
        value = 0
        cache(code_length)

        code_length.times do |k|
          unless hex_at?(@buffer, @pointer + k)
            scanner_error("while parsing a quoted scalar", start_mark, "did not find expected hexdecimal number")
          end
          value = (value << 4) + as_hex_at(@buffer, @pointer + k)
        end

        # Check the value and write the character.
        if (value >= 0xD800 && value <= 0xDFFF) || value > 0x10FFFF
          scanner_error("while parsing a quoted scalar", start_mark, "found invalid Unicode character escape code")
        end

        if value <= 0x7F
          string << value
        elsif value <= 0x7FF
          string << (0xC0 + (value >> 6)) << (0x80 + (value & 0x3F))
        elsif value <= 0xFFFF
          string << (0xE0 + (value >> 12)) << (0x80 + ((value >> 6) & 0x3F)) << (0x80 + (value & 0x3F))
        else
          string << (0xF0 + (value >> 18)) << (0x80 + ((value >> 12) & 0x3F)) <<
            (0x80 + ((value >> 6) & 0x3F)) << (0x80 + (value & 0x3F))
        end

        code_length.times { skip }
      end

      # yaml_parser_scan_plain_scalar
      def scan_plain_scalar
        string = new_string
        leading_break = new_string
        trailing_breaks = new_string
        whitespaces = new_string
        leading_blanks = false
        indent = @indent + 1

        start_mark = end_mark = current_mark

        loop do
          # Stop at a document indicator.
          cache(4)

          buffer = @buffer
          at = @pointer
          break if @mark_column.zero? &&
                   ((buffer.getbyte(at) == 0x2D && buffer.getbyte(at + 1) == 0x2D && buffer.getbyte(at + 2) == 0x2D) ||
                    (buffer.getbyte(at) == 0x2E && buffer.getbyte(at + 1) == 0x2E && buffer.getbyte(at + 2) == 0x2E)) &&
                   blankz_at?(buffer, at + 3)

          # Stop at a comment.
          break if check?("#")

          # Consume non-blank characters.
          until blankz_at?(@buffer, @pointer)
            buffer = @buffer
            at = @pointer
            octet = buffer.getbyte(at)
            following = buffer.getbyte(at + 1)

            # "x:" followed by one of ',?[]{}' in the flow context. This is
            # not completely according to the specification (see
            # http://yaml.org/spec/1.1/#id907281 9.1.3. Plain).
            if @flow_level.positive? && octet == 0x3A &&
               (following == 0x2C || following == 0x3F || following == 0x5B ||
                following == 0x5D || following == 0x7B || following == 0x7D)
              scanner_error("while scanning a plain scalar", start_mark, "found unexpected ':'")
            end

            # Stop at an indicator that may end a plain scalar.
            break if (octet == 0x3A && blankz_at?(buffer, at + 1)) ||
                     (@flow_level.positive? &&
                      (octet == 0x2C || octet == 0x5B || octet == 0x5D || octet == 0x7B || octet == 0x7D))

            # Join the whitespaces or fold the line breaks.
            if leading_blanks || !whitespaces.empty?
              if leading_blanks
                if leading_break.getbyte(0) == 0x0A
                  if trailing_breaks.empty?
                    string << 0x20
                  else
                    string << trailing_breaks
                    trailing_breaks.clear
                  end
                  leading_break.clear
                else
                  string << leading_break
                  string << trailing_breaks
                  leading_break.clear
                  trailing_breaks.clear
                end

                leading_blanks = false
              else
                string << whitespaces
                whitespaces.clear
              end
            end

            # Copy the character.
            read(string)

            end_mark = current_mark

            cache(2)
          end

          # Is it the end?
          break unless blank_at?(@buffer, @pointer) || break_at?(@buffer, @pointer)

          # Consume blank characters.
          cache(1)

          while blank_at?(@buffer, @pointer) || break_at?(@buffer, @pointer)
            if blank_at?(@buffer, @pointer)
              # A tab must not stand where the indentation is.
              if leading_blanks && @mark_column < indent && tab_at?(@buffer, @pointer)
                scanner_error("while scanning a plain scalar", start_mark,
                              "found a tab character that violates indentation")
              end

              # Consume a space or a tab character.
              if leading_blanks
                skip
              else
                read(whitespaces)
              end
            else
              cache(2)

              if leading_blanks
                read_line(trailing_breaks)
              else
                # This is the first line break.
                whitespaces.clear
                read_line(leading_break)
                leading_blanks = true
              end
            end
            cache(1)
          end

          # Check the indentation level.
          break if @flow_level.zero? && @mark_column < indent
        end

        token = Token.new(SCALAR_TOKEN, start_mark, end_mark)
        token.value = string
        token.style = PLAIN_SCALAR_STYLE

        # A line break in the scalar means a simple key may follow it.
        @simple_key_allowed = true if leading_blanks

        token
      end
    end
  end
end
