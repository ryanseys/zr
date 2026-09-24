# frozen_string_literal: true

# The emitter of libyaml 0.2.5 (src/emitter.c): it turns events back into
# YAML text. The functions keep their C names without the
# `yaml_emitter_` prefix.
#
# The writers walk a string with a byte offset where the C code moves
# `string.pointer`. libyaml's event strings end with NUL, and the
# character tests in Chars read past the end as NUL too.
module Psych
  module LibYAML
    class Emitter
      include Chars
      include Writer

      # yaml_emitter_state_t
      EMIT_STREAM_START_STATE = 0
      EMIT_FIRST_DOCUMENT_START_STATE = 1
      EMIT_DOCUMENT_START_STATE = 2
      EMIT_DOCUMENT_CONTENT_STATE = 3
      EMIT_DOCUMENT_END_STATE = 4
      EMIT_FLOW_SEQUENCE_FIRST_ITEM_STATE = 5
      EMIT_FLOW_SEQUENCE_ITEM_STATE = 6
      EMIT_FLOW_MAPPING_FIRST_KEY_STATE = 7
      EMIT_FLOW_MAPPING_KEY_STATE = 8
      EMIT_FLOW_MAPPING_SIMPLE_VALUE_STATE = 9
      EMIT_FLOW_MAPPING_VALUE_STATE = 10
      EMIT_BLOCK_SEQUENCE_FIRST_ITEM_STATE = 11
      EMIT_BLOCK_SEQUENCE_ITEM_STATE = 12
      EMIT_BLOCK_MAPPING_FIRST_KEY_STATE = 13
      EMIT_BLOCK_MAPPING_KEY_STATE = 14
      EMIT_BLOCK_MAPPING_SIMPLE_VALUE_STATE = 15
      EMIT_BLOCK_MAPPING_VALUE_STATE = 16
      EMIT_END_STATE = 17

      INT_MAX = 2_147_483_647

      DEFAULT_TAG_DIRECTIVES = [
        TagDirective.new("!".b.freeze, "!".b.freeze).freeze,
        TagDirective.new("!!".b.freeze, "tag:yaml.org,2002:".b.freeze).freeze
      ].freeze

      # The characters of a tag that go out as they are; the rest go out
      # as %XX escapes.
      TAG_CHARACTERS = ";/?:@&=+$,_.~*'()[]".bytes.freeze

      # The first characters that stop a scalar from being plain in either
      # context.
      LEADING_INDICATORS = "#,[]{}&*!|>'\"%@`".bytes.freeze

      # The characters that stop a scalar from being plain in the flow
      # context wherever they are.
      FLOW_INDICATORS = ",?[]{}".bytes.freeze

      # yaml_emitter_emit: queue the event, and write out every event that
      # does not need the events after it. Returns false on an error;
      # `problem` describes it.
      def emit(event)
        @events.push(event)

        until need_more_events?
          analyze_event(@events.first)
          state_machine(@events.first)
          @events.shift
        end

        true
      rescue Failure
        false
      end

      private

      # --- Output macros ---------------------------------------------------

      # FLUSH: flush the buffer when fewer than six bytes are free.
      def flush_if_full
        flush unless @buffer.bytesize + 5 < OUTPUT_BUFFER_SIZE
      end

      # PUT: write one ASCII octet.
      def put(octet)
        flush_if_full
        @buffer << octet
        @column += 1
      end

      # PUT_BREAK: write the line break.
      def put_break
        flush_if_full
        case @line_break
        when CR_BREAK then @buffer << 0x0D
        when LN_BREAK then @buffer << 0x0A
        when CRLN_BREAK then @buffer << 0x0D << 0x0A
        end
        @column = 0
        @line += 1
      end

      # WRITE: copy the character at `pointer` in `string`. Returns the
      # offset after it.
      def write(string, pointer)
        flush_if_full
        width = width_at(string, pointer)
        if width == 1
          @buffer << string.getbyte(pointer)
        else
          @buffer << string.byteslice(pointer, width)
        end
        @column += 1
        pointer + width
      end

      # WRITE_BREAK: copy the line break at `pointer` in `string`; LF goes
      # out as the emitter's line break. Returns the offset after it.
      def write_break(string, pointer)
        flush_if_full
        if string.getbyte(pointer) == 0x0A
          put_break
          pointer + 1
        else
          width = width_at(string, pointer)
          @buffer << string.byteslice(pointer, width)
          @column = 0
          @line += 1
          pointer + width
        end
      end

      # --- Utilities -------------------------------------------------------

      # yaml_emitter_set_emitter_error
      def emitter_error(problem)
        @error = EMITTER_ERROR
        @problem = problem
        raise Failure
      end

      # yaml_emitter_need_more_events: a DOCUMENT-START waits for one more
      # event, a SEQUENCE-START for two and a MAPPING-START for three, so
      # the emitter can tell an empty collection or a simple key.
      def need_more_events?
        return true if @events.empty?

        accumulate = case @events.first.type
                     when DOCUMENT_START_EVENT then 1
                     when SEQUENCE_START_EVENT then 2
                     when MAPPING_START_EVENT then 3
                     else return false
                     end

        return false if @events.size > accumulate

        level = 0
        @events.each do |event|
          case event.type
          when STREAM_START_EVENT, DOCUMENT_START_EVENT, SEQUENCE_START_EVENT, MAPPING_START_EVENT
            level += 1
          when STREAM_END_EVENT, DOCUMENT_END_EVENT, SEQUENCE_END_EVENT, MAPPING_END_EVENT
            level -= 1
          end
          return false if level.zero?
        end

        true
      end

      # yaml_emitter_append_tag_directive
      def append_tag_directive(value, allow_duplicates)
        if @tag_directives.any? { |tag_directive| tag_directive.handle == value.handle }
          return if allow_duplicates

          emitter_error("duplicate %TAG directive")
        end

        @tag_directives.push(TagDirective.new(value.handle, value.prefix))
      end

      # yaml_emitter_increase_indent
      def increase_indent(flow, indentless)
        @indents.push(@indent)

        if @indent.negative?
          @indent = flow ? @best_indent : 0
        elsif !indentless
          @indent += @best_indent
        end
      end

      # --- States ----------------------------------------------------------

      # yaml_emitter_state_machine
      def state_machine(event)
        case @state
        when EMIT_STREAM_START_STATE then emit_stream_start(event)
        when EMIT_FIRST_DOCUMENT_START_STATE then emit_document_start(event, true)
        when EMIT_DOCUMENT_START_STATE then emit_document_start(event, false)
        when EMIT_DOCUMENT_CONTENT_STATE then emit_document_content(event)
        when EMIT_DOCUMENT_END_STATE then emit_document_end(event)
        when EMIT_FLOW_SEQUENCE_FIRST_ITEM_STATE then emit_flow_sequence_item(event, true)
        when EMIT_FLOW_SEQUENCE_ITEM_STATE then emit_flow_sequence_item(event, false)
        when EMIT_FLOW_MAPPING_FIRST_KEY_STATE then emit_flow_mapping_key(event, true)
        when EMIT_FLOW_MAPPING_KEY_STATE then emit_flow_mapping_key(event, false)
        when EMIT_FLOW_MAPPING_SIMPLE_VALUE_STATE then emit_flow_mapping_value(event, true)
        when EMIT_FLOW_MAPPING_VALUE_STATE then emit_flow_mapping_value(event, false)
        when EMIT_BLOCK_SEQUENCE_FIRST_ITEM_STATE then emit_block_sequence_item(event, true)
        when EMIT_BLOCK_SEQUENCE_ITEM_STATE then emit_block_sequence_item(event, false)
        when EMIT_BLOCK_MAPPING_FIRST_KEY_STATE then emit_block_mapping_key(event, true)
        when EMIT_BLOCK_MAPPING_KEY_STATE then emit_block_mapping_key(event, false)
        when EMIT_BLOCK_MAPPING_SIMPLE_VALUE_STATE then emit_block_mapping_value(event, true)
        when EMIT_BLOCK_MAPPING_VALUE_STATE then emit_block_mapping_value(event, false)
        when EMIT_END_STATE then emitter_error("expected nothing after STREAM-END")
        else raise Failure
        end
      end

      # Expect STREAM-START.
      def emit_stream_start(event)
        @open_ended = 0
        emitter_error("expected STREAM-START") unless event.type == STREAM_START_EVENT

        @encoding = event.encoding if @encoding == ANY_ENCODING
        @encoding = UTF8_ENCODING if @encoding == ANY_ENCODING

        @best_indent = 2 if @best_indent < 2 || @best_indent > 9

        @best_width = 80 if @best_width >= 0 && @best_width <= @best_indent * 2

        @best_width = INT_MAX if @best_width.negative?

        @line_break = LN_BREAK if @line_break == ANY_BREAK

        @indent = -1

        @line = 0
        @column = 0
        @whitespace = true
        @indention = true

        write_bom unless @encoding == UTF8_ENCODING

        @state = EMIT_FIRST_DOCUMENT_START_STATE
      end

      # Expect DOCUMENT-START or STREAM-END.
      def emit_document_start(event, first)
        if event.type == DOCUMENT_START_EVENT
          version_directive = event.version_directive
          tag_directives = event.tag_directives

          analyze_version_directive(version_directive) if version_directive

          tag_directives.each do |tag_directive|
            analyze_tag_directive(tag_directive)
            append_tag_directive(tag_directive, false)
          end

          DEFAULT_TAG_DIRECTIVES.each do |tag_directive|
            append_tag_directive(tag_directive, true)
          end

          implicit = event.implicit
          implicit = false if !first || @canonical

          if (version_directive || !tag_directives.empty?) && @open_ended != 0
            write_indicator("...", true, false, false)
            write_indent
          end
          @open_ended = 0

          if version_directive
            implicit = false
            write_indicator("%YAML", true, false, false)
            if version_directive.minor == 1
              write_indicator("1.1", true, false, false)
            else
              write_indicator("1.2", true, false, false)
            end
            write_indent
          end

          unless tag_directives.empty?
            implicit = false
            tag_directives.each do |tag_directive|
              write_indicator("%TAG", true, false, false)
              write_tag_handle(tag_directive.handle)
              write_tag_content(tag_directive.prefix, true)
              write_indent
            end
          end

          implicit = false if check_empty_document?

          unless implicit
            write_indent
            write_indicator("---", true, false, false)
            write_indent if @canonical
          end

          @state = EMIT_DOCUMENT_CONTENT_STATE

          @open_ended = 0
        elsif event.type == STREAM_END_EVENT
          # A block scalar with trailing empty lines at the end of the
          # stream leaves the stream open ended.
          if @open_ended == 2
            write_indicator("...", true, false, false)
            @open_ended = 0
            write_indent
          end
          flush

          @state = EMIT_END_STATE
        else
          emitter_error("expected DOCUMENT-START or STREAM-END")
        end
      end

      # Expect the root node.
      def emit_document_content(event)
        @states.push(EMIT_DOCUMENT_END_STATE)

        emit_node(event, true, false, false, false)
      end

      # Expect DOCUMENT-END.
      def emit_document_end(event)
        emitter_error("expected DOCUMENT-END") unless event.type == DOCUMENT_END_EVENT

        write_indent
        if !event.implicit
          write_indicator("...", true, false, false)
          @open_ended = 0
          write_indent
        elsif @open_ended.zero?
          @open_ended = 1
        end
        flush

        @state = EMIT_DOCUMENT_START_STATE

        @tag_directives.clear
      end

      # Expect a flow item node.
      def emit_flow_sequence_item(event, first)
        if first
          write_indicator("[", true, true, false)
          increase_indent(true, false)
          @flow_level += 1
        end

        if event.type == SEQUENCE_END_EVENT
          @flow_level -= 1
          @indent = @indents.pop
          if @canonical && !first
            write_indicator(",", false, false, false)
            write_indent
          end
          write_indicator("]", false, false, false)
          @state = @states.pop

          return
        end

        write_indicator(",", false, false, false) unless first

        write_indent if @canonical || @column > @best_width
        @states.push(EMIT_FLOW_SEQUENCE_ITEM_STATE)

        emit_node(event, false, true, false, false)
      end

      # Expect a flow key node.
      def emit_flow_mapping_key(event, first)
        if first
          write_indicator("{", true, true, false)
          increase_indent(true, false)
          @flow_level += 1
        end

        if event.type == MAPPING_END_EVENT
          @flow_level -= 1
          @indent = @indents.pop
          if @canonical && !first
            write_indicator(",", false, false, false)
            write_indent
          end
          write_indicator("}", false, false, false)
          @state = @states.pop

          return
        end

        write_indicator(",", false, false, false) unless first
        write_indent if @canonical || @column > @best_width

        if !@canonical && check_simple_key?
          @states.push(EMIT_FLOW_MAPPING_SIMPLE_VALUE_STATE)

          emit_node(event, false, false, true, true)
        else
          write_indicator("?", true, false, false)
          @states.push(EMIT_FLOW_MAPPING_VALUE_STATE)

          emit_node(event, false, false, true, false)
        end
      end

      # Expect a flow value node.
      def emit_flow_mapping_value(event, simple)
        if simple
          write_indicator(":", false, false, false)
        else
          write_indent if @canonical || @column > @best_width
          write_indicator(":", true, false, false)
        end
        @states.push(EMIT_FLOW_MAPPING_KEY_STATE)
        emit_node(event, false, false, true, false)
      end

      # Expect a block item node.
      def emit_block_sequence_item(event, first)
        increase_indent(false, @mapping_context && !@indention) if first

        if event.type == SEQUENCE_END_EVENT
          @indent = @indents.pop
          @state = @states.pop

          return
        end

        write_indent
        write_indicator("-", true, false, true)
        @states.push(EMIT_BLOCK_SEQUENCE_ITEM_STATE)

        emit_node(event, false, true, false, false)
      end

      # Expect a block key node.
      def emit_block_mapping_key(event, first)
        increase_indent(false, false) if first

        if event.type == MAPPING_END_EVENT
          @indent = @indents.pop
          @state = @states.pop

          return
        end

        write_indent

        if check_simple_key?
          @states.push(EMIT_BLOCK_MAPPING_SIMPLE_VALUE_STATE)

          emit_node(event, false, false, true, true)
        else
          write_indicator("?", true, false, true)
          @states.push(EMIT_BLOCK_MAPPING_VALUE_STATE)

          emit_node(event, false, false, true, false)
        end
      end

      # Expect a block value node.
      def emit_block_mapping_value(event, simple)
        if simple
          write_indicator(":", false, false, false)
        else
          write_indent
          write_indicator(":", true, false, true)
        end
        @states.push(EMIT_BLOCK_MAPPING_KEY_STATE)

        emit_node(event, false, false, true, false)
      end

      # Expect a node.
      def emit_node(event, root, sequence, mapping, simple_key)
        @root_context = root
        @sequence_context = sequence
        @mapping_context = mapping
        @simple_key_context = simple_key

        case event.type
        when ALIAS_EVENT then emit_alias(event)
        when SCALAR_EVENT then emit_scalar(event)
        when SEQUENCE_START_EVENT then emit_sequence_start(event)
        when MAPPING_START_EVENT then emit_mapping_start(event)
        else emitter_error("expected SCALAR, SEQUENCE-START, MAPPING-START, or ALIAS")
        end
      end

      # Expect ALIAS.
      def emit_alias(_event)
        process_anchor
        put(0x20) if @simple_key_context
        @state = @states.pop
      end

      # Expect SCALAR.
      def emit_scalar(event)
        select_scalar_style(event)
        process_anchor
        process_tag
        increase_indent(true, false)
        process_scalar
        @indent = @indents.pop
        @state = @states.pop
      end

      # Expect SEQUENCE-START.
      def emit_sequence_start(event)
        process_anchor
        process_tag

        @state = if @flow_level.positive? || @canonical || event.style == FLOW_SEQUENCE_STYLE ||
                    check_empty_sequence?
                   EMIT_FLOW_SEQUENCE_FIRST_ITEM_STATE
                 else
                   EMIT_BLOCK_SEQUENCE_FIRST_ITEM_STATE
                 end
      end

      # Expect MAPPING-START.
      def emit_mapping_start(event)
        process_anchor
        process_tag

        @state = if @flow_level.positive? || @canonical || event.style == FLOW_MAPPING_STYLE ||
                    check_empty_mapping?
                   EMIT_FLOW_MAPPING_FIRST_KEY_STATE
                 else
                   EMIT_BLOCK_MAPPING_FIRST_KEY_STATE
                 end
      end

      # --- Checkers --------------------------------------------------------

      # yaml_emitter_check_empty_document: libyaml never finds one.
      def check_empty_document? = false

      # yaml_emitter_check_empty_sequence
      def check_empty_sequence?
        return false if @events.size < 2

        @events[0].type == SEQUENCE_START_EVENT && @events[1].type == SEQUENCE_END_EVENT
      end

      # yaml_emitter_check_empty_mapping
      def check_empty_mapping?
        return false if @events.size < 2

        @events[0].type == MAPPING_START_EVENT && @events[1].type == MAPPING_END_EVENT
      end

      # yaml_emitter_check_simple_key: whether the next node fits on one
      # line, in no more than 128 bytes, as a simple key.
      def check_simple_key?
        event = @events.first
        length = 0

        case event.type
        when ALIAS_EVENT
          length += anchor_length
        when SCALAR_EVENT
          return false if @scalar_data_multiline

          length += anchor_length + tag_handle_length + tag_suffix_length + @scalar_data_value.bytesize
        when SEQUENCE_START_EVENT
          return false unless check_empty_sequence?

          length += anchor_length + tag_handle_length + tag_suffix_length
        when MAPPING_START_EVENT
          return false unless check_empty_mapping?

          length += anchor_length + tag_handle_length + tag_suffix_length
        else
          return false
        end

        length <= 128
      end

      def anchor_length = @anchor_data_anchor ? @anchor_data_anchor.bytesize : 0

      def tag_handle_length = @tag_data_handle ? @tag_data_handle.bytesize : 0

      def tag_suffix_length = @tag_data_suffix ? @tag_data_suffix.bytesize : 0

      # yaml_emitter_select_scalar_style: the style that the scalar can
      # take, starting from the one that the event requests.
      def select_scalar_style(event)
        style = event.style
        no_tag = @tag_data_handle.nil? && @tag_data_suffix.nil?

        if no_tag && !event.plain_implicit && !event.quoted_implicit
          emitter_error("neither tag nor implicit flags are specified")
        end

        style = PLAIN_SCALAR_STYLE if style == ANY_SCALAR_STYLE

        style = DOUBLE_QUOTED_SCALAR_STYLE if @canonical

        style = DOUBLE_QUOTED_SCALAR_STYLE if @simple_key_context && @scalar_data_multiline

        if style == PLAIN_SCALAR_STYLE
          if (@flow_level.positive? && !@scalar_data_flow_plain_allowed) ||
             (@flow_level.zero? && !@scalar_data_block_plain_allowed)
            style = SINGLE_QUOTED_SCALAR_STYLE
          end
          if @scalar_data_value.empty? && (@flow_level.positive? || @simple_key_context)
            style = SINGLE_QUOTED_SCALAR_STYLE
          end
          style = SINGLE_QUOTED_SCALAR_STYLE if no_tag && !event.plain_implicit
        end

        if style == SINGLE_QUOTED_SCALAR_STYLE && !@scalar_data_single_quoted_allowed
          style = DOUBLE_QUOTED_SCALAR_STYLE
        end

        if (style == LITERAL_SCALAR_STYLE || style == FOLDED_SCALAR_STYLE) &&
           (!@scalar_data_block_allowed || @flow_level.positive? || @simple_key_context)
          style = DOUBLE_QUOTED_SCALAR_STYLE
        end

        @tag_data_handle = "!".b if no_tag && !event.quoted_implicit && style != PLAIN_SCALAR_STYLE

        @scalar_data_style = style
      end

      # --- Processors ------------------------------------------------------

      # yaml_emitter_process_anchor
      def process_anchor
        return unless @anchor_data_anchor

        write_indicator(@anchor_data_alias ? "*" : "&", true, false, false)

        write_anchor(@anchor_data_anchor)
      end

      # yaml_emitter_process_tag
      def process_tag
        return if @tag_data_handle.nil? && @tag_data_suffix.nil?

        if @tag_data_handle
          write_tag_handle(@tag_data_handle)
          write_tag_content(@tag_data_suffix, false) if @tag_data_suffix
        else
          write_indicator("!<", true, false, false)
          write_tag_content(@tag_data_suffix, false)
          write_indicator(">", false, false, false)
        end
      end

      # yaml_emitter_process_scalar
      def process_scalar
        case @scalar_data_style
        when PLAIN_SCALAR_STYLE then write_plain_scalar(@scalar_data_value, !@simple_key_context)
        when SINGLE_QUOTED_SCALAR_STYLE then write_single_quoted_scalar(@scalar_data_value, !@simple_key_context)
        when DOUBLE_QUOTED_SCALAR_STYLE then write_double_quoted_scalar(@scalar_data_value, !@simple_key_context)
        when LITERAL_SCALAR_STYLE then write_literal_scalar(@scalar_data_value)
        when FOLDED_SCALAR_STYLE then write_folded_scalar(@scalar_data_value)
        end
      end

      # --- Analyzers -------------------------------------------------------

      # yaml_emitter_analyze_version_directive
      def analyze_version_directive(version_directive)
        return if version_directive.major == 1 && (version_directive.minor == 1 || version_directive.minor == 2)

        emitter_error("incompatible %YAML directive")
      end

      # yaml_emitter_analyze_tag_directive
      def analyze_tag_directive(tag_directive)
        handle = c_string(tag_directive.handle)
        prefix = c_string(tag_directive.prefix)

        emitter_error("tag handle must not be empty") if handle.empty?

        emitter_error("tag handle must start with '!'") if handle.getbyte(0) != 0x21

        emitter_error("tag handle must end with '!'") if handle.getbyte(-1) != 0x21

        pointer = 1
        while pointer < handle.bytesize - 1
          emitter_error("tag handle must contain alphanumerical characters only") unless alpha_at?(handle, pointer)

          pointer += width_at(handle, pointer)
        end

        emitter_error("tag prefix must not be empty") if prefix.empty?
      end

      # yaml_emitter_analyze_anchor
      def analyze_anchor(anchor, alias_)
        anchor = c_string(anchor)

        if anchor.empty?
          emitter_error(alias_ ? "alias value must not be empty" : "anchor value must not be empty")
        end

        pointer = 0
        while pointer != anchor.bytesize
          unless alpha_at?(anchor, pointer)
            emitter_error(alias_ ? "alias value must contain alphanumerical characters only" :
                                   "anchor value must contain alphanumerical characters only")
          end
          pointer += width_at(anchor, pointer)
        end

        @anchor_data_anchor = anchor
        @anchor_data_alias = alias_
      end

      # yaml_emitter_analyze_tag: split the tag into a handle and a suffix
      # when a tag directive's prefix starts it.
      def analyze_tag(tag)
        tag = c_string(tag)

        emitter_error("tag value must not be empty") if tag.empty?

        @tag_directives.each do |tag_directive|
          prefix = c_string(tag_directive.prefix)
          next unless prefix.bytesize < tag.bytesize && tag.byteslice(0, prefix.bytesize) == prefix

          @tag_data_handle = c_string(tag_directive.handle)
          @tag_data_suffix = tag.byteslice(prefix.bytesize, tag.bytesize - prefix.bytesize)
          return
        end

        @tag_data_suffix = tag
      end

      # yaml_emitter_analyze_scalar: which styles can show the scalar.
      def analyze_scalar(value)
        block_indicators = false
        flow_indicators = false
        line_breaks = false
        special_characters = false

        leading_space = false
        leading_break = false
        trailing_space = false
        trailing_break = false
        break_space = false
        space_break = false

        previous_space = false
        previous_break = false

        @scalar_data_value = value

        if value.empty?
          @scalar_data_multiline = false
          @scalar_data_flow_plain_allowed = false
          @scalar_data_block_plain_allowed = true
          @scalar_data_single_quoted_allowed = true
          @scalar_data_block_allowed = false

          return
        end

        first = value.getbyte(0)
        if (first == 0x2D && value.getbyte(1) == 0x2D && value.getbyte(2) == 0x2D) ||
           (first == 0x2E && value.getbyte(1) == 0x2E && value.getbyte(2) == 0x2E)
          block_indicators = true
          flow_indicators = true
        end

        preceded_by_whitespace = true
        followed_by_whitespace = blankz_at?(value, width_at(value, 0))

        pointer = 0
        last = value.bytesize
        while pointer != last
          octet = value.getbyte(pointer)
          if pointer.zero?
            if LEADING_INDICATORS.include?(octet)
              flow_indicators = true
              block_indicators = true
            end

            if octet == 0x3F || octet == 0x3A
              flow_indicators = true
              block_indicators = true if followed_by_whitespace
            end

            if octet == 0x2D && followed_by_whitespace
              flow_indicators = true
              block_indicators = true
            end
          else
            flow_indicators = true if FLOW_INDICATORS.include?(octet)

            if octet == 0x3A
              flow_indicators = true
              block_indicators = true if followed_by_whitespace
            end

            if octet == 0x23 && preceded_by_whitespace
              flow_indicators = true
              block_indicators = true
            end
          end

          special_characters = true if !printable_at?(value, pointer) || (!ascii_at?(value, pointer) && !@unicode)

          line_breaks = true if break_at?(value, pointer)

          if space_at?(value, pointer)
            leading_space = true if pointer.zero?
            trailing_space = true if pointer + width_at(value, pointer) == last
            break_space = true if previous_break
            previous_space = true
            previous_break = false
          elsif break_at?(value, pointer)
            leading_break = true if pointer.zero?
            trailing_break = true if pointer + width_at(value, pointer) == last
            space_break = true if previous_space
            previous_space = false
            previous_break = true
          else
            previous_space = false
            previous_break = false
          end

          preceded_by_whitespace = blankz_at?(value, pointer)
          pointer += width_at(value, pointer)
          followed_by_whitespace = blankz_at?(value, pointer + width_at(value, pointer)) if pointer != last
        end

        @scalar_data_multiline = line_breaks

        @scalar_data_flow_plain_allowed = true
        @scalar_data_block_plain_allowed = true
        @scalar_data_single_quoted_allowed = true
        @scalar_data_block_allowed = true

        if leading_space || leading_break || trailing_space || trailing_break
          @scalar_data_flow_plain_allowed = false
          @scalar_data_block_plain_allowed = false
        end

        @scalar_data_block_allowed = false if trailing_space

        if break_space
          @scalar_data_flow_plain_allowed = false
          @scalar_data_block_plain_allowed = false
          @scalar_data_single_quoted_allowed = false
        end

        if space_break || special_characters
          @scalar_data_flow_plain_allowed = false
          @scalar_data_block_plain_allowed = false
          @scalar_data_single_quoted_allowed = false
          @scalar_data_block_allowed = false
        end

        if line_breaks
          @scalar_data_flow_plain_allowed = false
          @scalar_data_block_plain_allowed = false
        end

        @scalar_data_flow_plain_allowed = false if flow_indicators

        @scalar_data_block_plain_allowed = false if block_indicators
      end

      # yaml_emitter_analyze_event
      def analyze_event(event)
        @anchor_data_anchor = nil
        @tag_data_handle = nil
        @tag_data_suffix = nil
        @scalar_data_value = nil

        case event.type
        when ALIAS_EVENT
          analyze_anchor(event.anchor, true)
        when SCALAR_EVENT
          analyze_anchor(event.anchor, false) if event.anchor
          if event.tag && (@canonical || (!event.plain_implicit && !event.quoted_implicit))
            analyze_tag(event.tag)
          end
          analyze_scalar(event.value)
        when SEQUENCE_START_EVENT, MAPPING_START_EVENT
          analyze_anchor(event.anchor, false) if event.anchor
          analyze_tag(event.tag) if event.tag && (@canonical || !event.implicit)
        end
      end

      # --- Writers ---------------------------------------------------------

      # yaml_emitter_write_bom: the UTF-8 BOM, which the writer recodes.
      def write_bom
        flush_if_full

        @buffer << 0xEF << 0xBB << 0xBF
      end

      # yaml_emitter_write_indent: start a new line at the indentation,
      # unless the output is already there.
      def write_indent
        indent = @indent >= 0 ? @indent : 0

        put_break if !@indention || @column > indent || (@column == indent && !@whitespace)

        put(0x20) while @column < indent

        @whitespace = true
        @indention = true
      end

      # yaml_emitter_write_indicator
      def write_indicator(indicator, need_whitespace, is_whitespace, is_indention)
        put(0x20) if need_whitespace && !@whitespace

        pointer = 0
        pointer = write(indicator, pointer) while pointer != indicator.bytesize

        @whitespace = is_whitespace
        @indention = @indention && is_indention
      end

      # yaml_emitter_write_anchor
      def write_anchor(value)
        pointer = 0
        pointer = write(value, pointer) while pointer != value.bytesize

        @whitespace = false
        @indention = false
      end

      # yaml_emitter_write_tag_handle
      def write_tag_handle(value)
        value = c_string(value)
        put(0x20) unless @whitespace

        pointer = 0
        pointer = write(value, pointer) while pointer != value.bytesize

        @whitespace = false
        @indention = false
      end

      # yaml_emitter_write_tag_content: the tag's URI characters, with
      # every other byte as a %XX escape.
      def write_tag_content(value, need_whitespace)
        value = c_string(value)
        put(0x20) if need_whitespace && !@whitespace

        pointer = 0
        while pointer != value.bytesize
          if alpha_at?(value, pointer) || TAG_CHARACTERS.include?(value.getbyte(pointer))
            pointer = write(value, pointer)
          else
            width = width_at(value, pointer)
            # A stray continuation byte has no width in C and loops there;
            # take it as one byte here.
            width = 1 if width.zero?
            width.times do
              octet = value.getbyte(pointer)
              pointer += 1
              put(0x25)
              put(hex_digit(octet >> 4))
              put(hex_digit(octet & 0x0F))
            end
          end
        end

        @whitespace = false
        @indention = false
      end

      def hex_digit(nibble) = nibble < 10 ? 0x30 + nibble : 0x41 + nibble - 10

      # yaml_emitter_write_plain_scalar
      def write_plain_scalar(value, allow_breaks)
        spaces = false
        breaks = false

        # Avoid trailing spaces for empty values in block mode. In flow
        # mode a space still prevents ambiguous things like {a:}.
        put(0x20) if !@whitespace && (!value.empty? || @flow_level.positive?)

        pointer = 0
        last = value.bytesize
        while pointer != last
          if space_at?(value, pointer)
            if allow_breaks && !spaces && @column > @best_width && !space_at?(value, pointer + 1)
              write_indent
              pointer += width_at(value, pointer)
            else
              pointer = write(value, pointer)
            end
            spaces = true
          elsif break_at?(value, pointer)
            put_break if !breaks && value.getbyte(pointer) == 0x0A
            pointer = write_break(value, pointer)
            @indention = true
            breaks = true
          else
            write_indent if breaks
            pointer = write(value, pointer)
            @indention = false
            spaces = false
            breaks = false
          end
        end

        @whitespace = false
        @indention = false
      end

      # yaml_emitter_write_single_quoted_scalar
      def write_single_quoted_scalar(value, allow_breaks)
        spaces = false
        breaks = false

        write_indicator("'", true, false, false)

        pointer = 0
        last = value.bytesize
        while pointer != last
          if space_at?(value, pointer)
            if allow_breaks && !spaces && @column > @best_width && pointer != 0 &&
               pointer != last - 1 && !space_at?(value, pointer + 1)
              write_indent
              pointer += width_at(value, pointer)
            else
              pointer = write(value, pointer)
            end
            spaces = true
          elsif break_at?(value, pointer)
            put_break if !breaks && value.getbyte(pointer) == 0x0A
            pointer = write_break(value, pointer)
            @indention = true
            breaks = true
          else
            write_indent if breaks
            put(0x27) if value.getbyte(pointer) == 0x27
            pointer = write(value, pointer)
            @indention = false
            spaces = false
            breaks = false
          end
        end

        write_indent if breaks

        write_indicator("'", false, false, false)

        @whitespace = false
        @indention = false
      end

      # The short escapes of a double-quoted scalar.
      DOUBLE_QUOTED_ESCAPES = {
        0x00 => "0", 0x07 => "a", 0x08 => "b", 0x09 => "t", 0x0A => "n",
        0x0B => "v", 0x0C => "f", 0x0D => "r", 0x1B => "e", 0x22 => '"',
        0x5C => "\\", 0x85 => "N", 0xA0 => "_", 0x2028 => "L", 0x2029 => "P"
      }.transform_values(&:ord).freeze

      # yaml_emitter_write_double_quoted_scalar
      def write_double_quoted_scalar(value, allow_breaks)
        spaces = false

        write_indicator("\"", true, false, false)

        pointer = 0
        last = value.bytesize
        while pointer != last
          octet = value.getbyte(pointer)
          if !printable_at?(value, pointer) || (!@unicode && !ascii_at?(value, pointer)) ||
             bom_at?(value, pointer) || break_at?(value, pointer) || octet == 0x22 || octet == 0x5C
            width = width_at(value, pointer)
            code = if octet & 0x80 == 0x00 then octet & 0x7F
                   elsif octet & 0xE0 == 0xC0 then octet & 0x1F
                   elsif octet & 0xF0 == 0xE0 then octet & 0x0F
                   elsif octet & 0xF8 == 0xF0 then octet & 0x07
                   else 0
                   end
            k = 1
            while k < width
              code = (code << 6) + ((value.getbyte(pointer + k) || 0) & 0x3F)
              k += 1
            end
            # A stray continuation byte has no width in C and loops there;
            # take it as one byte here.
            pointer += width.zero? ? 1 : width

            put(0x5C)

            if (short = DOUBLE_QUOTED_ESCAPES[code])
              put(short)
            else
              if code <= 0xFF
                put(0x78)
                digits = 2
              elsif code <= 0xFFFF
                put(0x75)
                digits = 4
              else
                put(0x55)
                digits = 8
              end
              shift = (digits - 1) * 4
              while shift >= 0
                put(hex_digit((code >> shift) & 0x0F))
                shift -= 4
              end
            end
            spaces = false
          elsif space_at?(value, pointer)
            if allow_breaks && !spaces && @column > @best_width && pointer != 0 && pointer != last - 1
              write_indent
              put(0x5C) if space_at?(value, pointer + 1)
              pointer += width_at(value, pointer)
            else
              pointer = write(value, pointer)
            end
            spaces = true
          else
            pointer = write(value, pointer)
            spaces = false
          end
        end

        write_indicator("\"", false, false, false)

        @whitespace = false
        @indention = false
      end

      # yaml_emitter_write_block_scalar_hints: the indentation indicator
      # when the text starts with a space or a break, and the chomping
      # indicator its end calls for.
      def write_block_scalar_hints(value)
        chomp_hint = nil

        if space_at?(value, 0) || break_at?(value, 0)
          write_indicator((0x30 + @best_indent).chr, false, false, false)
        end

        @open_ended = 0

        pointer = value.bytesize
        if pointer.zero?
          chomp_hint = "-"
        else
          pointer -= 1
          pointer -= 1 while pointer.positive? && value.getbyte(pointer) & 0xC0 == 0x80
          if !break_at?(value, pointer)
            chomp_hint = "-"
          elsif pointer.zero?
            chomp_hint = "+"
            @open_ended = 2
          else
            pointer -= 1
            pointer -= 1 while pointer.positive? && value.getbyte(pointer) & 0xC0 == 0x80
            if break_at?(value, pointer)
              chomp_hint = "+"
              @open_ended = 2
            end
          end
        end

        write_indicator(chomp_hint, false, false, false) if chomp_hint
      end

      # yaml_emitter_write_literal_scalar
      def write_literal_scalar(value)
        breaks = true

        write_indicator("|", true, false, false)
        write_block_scalar_hints(value)
        put_break
        @indention = true
        @whitespace = true

        pointer = 0
        last = value.bytesize
        while pointer != last
          if break_at?(value, pointer)
            pointer = write_break(value, pointer)
            @indention = true
            breaks = true
          else
            write_indent if breaks
            pointer = write(value, pointer)
            @indention = false
            breaks = false
          end
        end
      end

      # yaml_emitter_write_folded_scalar
      def write_folded_scalar(value)
        breaks = true
        leading_spaces = true

        write_indicator(">", true, false, false)
        write_block_scalar_hints(value)
        put_break
        @indention = true
        @whitespace = true

        pointer = 0
        last = value.bytesize
        while pointer != last
          if break_at?(value, pointer)
            if !breaks && !leading_spaces && value.getbyte(pointer) == 0x0A
              k = 0
              k += width_at(value, pointer + k) while break_at?(value, pointer + k)
              put_break unless blankz_at?(value, pointer + k)
            end
            pointer = write_break(value, pointer)
            @indention = true
            breaks = true
          else
            if breaks
              write_indent
              leading_spaces = blank_at?(value, pointer)
            end
            if !breaks && space_at?(value, pointer) && !space_at?(value, pointer + 1) && @column > @best_width
              write_indent
              pointer += width_at(value, pointer)
            else
              pointer = write(value, pointer)
            end
            @indention = false
            breaks = false
          end
        end
      end
    end
  end
end
