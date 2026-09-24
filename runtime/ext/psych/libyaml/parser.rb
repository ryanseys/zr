# frozen_string_literal: true

# The parser of libyaml 0.2.5 (src/parser.c): it reads the scanner's
# tokens and produces events. It implements this grammar:
#
#   stream               ::= STREAM-START implicit_document? explicit_document* STREAM-END
#   implicit_document    ::= block_node DOCUMENT-END*
#   explicit_document    ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*
#   block_node_or_indentless_sequence    ::=
#                            ALIAS
#                            | properties (block_content | indentless_block_sequence)?
#                            | block_content
#                            | indentless_block_sequence
#   block_node           ::= ALIAS
#                            | properties block_content?
#                            | block_content
#   flow_node            ::= ALIAS
#                            | properties flow_content?
#                            | flow_content
#   properties           ::= TAG ANCHOR? | ANCHOR TAG?
#   block_content        ::= block_collection | flow_collection | SCALAR
#   flow_content         ::= flow_collection | SCALAR
#   block_collection     ::= block_sequence | block_mapping
#   flow_collection      ::= flow_sequence | flow_mapping
#   block_sequence       ::= BLOCK-SEQUENCE-START (BLOCK-ENTRY block_node?)* BLOCK-END
#   indentless_sequence  ::= (BLOCK-ENTRY block_node?)+
#   block_mapping        ::= BLOCK-MAPPING_START
#                            ((KEY block_node_or_indentless_sequence?)?
#                            (VALUE block_node_or_indentless_sequence?)?)*
#                            BLOCK-END
#   flow_sequence        ::= FLOW-SEQUENCE-START
#                            (flow_sequence_entry FLOW-ENTRY)*
#                            flow_sequence_entry?
#                            FLOW-SEQUENCE-END
#   flow_sequence_entry  ::= flow_node | KEY flow_node? (VALUE flow_node?)?
#   flow_mapping         ::= FLOW-MAPPING-START
#                            (flow_mapping_entry FLOW-ENTRY)*
#                            flow_mapping_entry?
#                            FLOW-MAPPING-END
#   flow_mapping_entry   ::= flow_node | KEY flow_node? (VALUE flow_node?)?
#
# One object contains the state of the reader, the scanner and the parser,
# as yaml_parser_t does. api.rb gives it its constructor and its input.
module Psych
  module LibYAML
    class Parser
      include Chars
      include Reader
      include Scanner

      # yaml_parser_state_t
      PARSE_STREAM_START_STATE = 0
      PARSE_IMPLICIT_DOCUMENT_START_STATE = 1
      PARSE_DOCUMENT_START_STATE = 2
      PARSE_DOCUMENT_CONTENT_STATE = 3
      PARSE_DOCUMENT_END_STATE = 4
      PARSE_BLOCK_NODE_STATE = 5
      PARSE_BLOCK_NODE_OR_INDENTLESS_SEQUENCE_STATE = 6
      PARSE_FLOW_NODE_STATE = 7
      PARSE_BLOCK_SEQUENCE_FIRST_ENTRY_STATE = 8
      PARSE_BLOCK_SEQUENCE_ENTRY_STATE = 9
      PARSE_INDENTLESS_SEQUENCE_ENTRY_STATE = 10
      PARSE_BLOCK_MAPPING_FIRST_KEY_STATE = 11
      PARSE_BLOCK_MAPPING_KEY_STATE = 12
      PARSE_BLOCK_MAPPING_VALUE_STATE = 13
      PARSE_FLOW_SEQUENCE_FIRST_ENTRY_STATE = 14
      PARSE_FLOW_SEQUENCE_ENTRY_STATE = 15
      PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_KEY_STATE = 16
      PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_VALUE_STATE = 17
      PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_END_STATE = 18
      PARSE_FLOW_MAPPING_FIRST_KEY_STATE = 19
      PARSE_FLOW_MAPPING_KEY_STATE = 20
      PARSE_FLOW_MAPPING_VALUE_STATE = 21
      PARSE_FLOW_MAPPING_EMPTY_VALUE_STATE = 22
      PARSE_END_STATE = 23

      DEFAULT_TAG_DIRECTIVES = [
        TagDirective.new("!".b.freeze, "!".b.freeze).freeze,
        TagDirective.new("!!".b.freeze, "tag:yaml.org,2002:".b.freeze).freeze
      ].freeze

      attr_reader :error, :problem, :problem_offset, :problem_value, :problem_mark,
                  :context, :context_mark, :encoding

      # yaml_parser_parse: the next event, or an event of type NO_EVENT
      # after the stream ends. Returns nil when an error stops the parser;
      # `error`, `problem` and the marks then describe it.
      def parse
        return Event.new(NO_EVENT) if @stream_end_produced || @error != NO_ERROR || @state == PARSE_END_STATE

        state_machine
      rescue Failure
        nil
      end

      private

      # --- Token queue macros ----------------------------------------------

      # PEEK_TOKEN
      def peek_token
        fetch_more_tokens unless @token_available
        @tokens.first
      end

      # SKIP_TOKEN
      def skip_token
        @token_available = false
        @tokens_parsed += 1
        @stream_end_produced = @tokens.first.type == STREAM_END_TOKEN
        @tokens.shift
      end

      # --- Errors ----------------------------------------------------------

      # yaml_parser_set_parser_error
      def parser_error(problem, problem_mark)
        @error = PARSER_ERROR
        @problem = problem
        @problem_mark = problem_mark
        raise Failure
      end

      # yaml_parser_set_parser_error_context
      def parser_error_context(context, context_mark, problem, problem_mark)
        @error = PARSER_ERROR
        @context = context
        @context_mark = context_mark
        @problem = problem
        @problem_mark = problem_mark
        raise Failure
      end

      # --- States ----------------------------------------------------------

      # yaml_parser_state_machine
      def state_machine
        case @state
        when PARSE_STREAM_START_STATE then parse_stream_start
        when PARSE_IMPLICIT_DOCUMENT_START_STATE then parse_document_start(true)
        when PARSE_DOCUMENT_START_STATE then parse_document_start(false)
        when PARSE_DOCUMENT_CONTENT_STATE then parse_document_content
        when PARSE_DOCUMENT_END_STATE then parse_document_end
        when PARSE_BLOCK_NODE_STATE then parse_node(true, false)
        when PARSE_BLOCK_NODE_OR_INDENTLESS_SEQUENCE_STATE then parse_node(true, true)
        when PARSE_FLOW_NODE_STATE then parse_node(false, false)
        when PARSE_BLOCK_SEQUENCE_FIRST_ENTRY_STATE then parse_block_sequence_entry(true)
        when PARSE_BLOCK_SEQUENCE_ENTRY_STATE then parse_block_sequence_entry(false)
        when PARSE_INDENTLESS_SEQUENCE_ENTRY_STATE then parse_indentless_sequence_entry
        when PARSE_BLOCK_MAPPING_FIRST_KEY_STATE then parse_block_mapping_key(true)
        when PARSE_BLOCK_MAPPING_KEY_STATE then parse_block_mapping_key(false)
        when PARSE_BLOCK_MAPPING_VALUE_STATE then parse_block_mapping_value
        when PARSE_FLOW_SEQUENCE_FIRST_ENTRY_STATE then parse_flow_sequence_entry(true)
        when PARSE_FLOW_SEQUENCE_ENTRY_STATE then parse_flow_sequence_entry(false)
        when PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_KEY_STATE then parse_flow_sequence_entry_mapping_key
        when PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_VALUE_STATE then parse_flow_sequence_entry_mapping_value
        when PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_END_STATE then parse_flow_sequence_entry_mapping_end
        when PARSE_FLOW_MAPPING_FIRST_KEY_STATE then parse_flow_mapping_key(true)
        when PARSE_FLOW_MAPPING_KEY_STATE then parse_flow_mapping_key(false)
        when PARSE_FLOW_MAPPING_VALUE_STATE then parse_flow_mapping_value(false)
        when PARSE_FLOW_MAPPING_EMPTY_VALUE_STATE then parse_flow_mapping_value(true)
        else raise Failure
        end
      end

      # stream ::= STREAM-START implicit_document? explicit_document* STREAM-END
      #            ************
      def parse_stream_start
        token = peek_token

        parser_error("did not find expected <stream-start>", token.start_mark) if token.type != STREAM_START_TOKEN

        @state = PARSE_IMPLICIT_DOCUMENT_START_STATE
        event = Event.new(STREAM_START_EVENT, token.start_mark, token.start_mark)
        event.encoding = token.encoding
        skip_token
        event
      end

      # implicit_document ::= block_node DOCUMENT-END*
      #                       *
      # explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*
      #                       *************************
      def parse_document_start(implicit)
        token = peek_token

        # Parse extra document end indicators.
        unless implicit
          while token.type == DOCUMENT_END_TOKEN
            skip_token
            token = peek_token
          end
        end

        if implicit && token.type != VERSION_DIRECTIVE_TOKEN && token.type != TAG_DIRECTIVE_TOKEN &&
           token.type != DOCUMENT_START_TOKEN && token.type != STREAM_END_TOKEN
          # An implicit document.
          process_directives
          @states.push(PARSE_DOCUMENT_END_STATE)
          @state = PARSE_BLOCK_NODE_STATE
          event = Event.new(DOCUMENT_START_EVENT, token.start_mark, token.start_mark)
          event.tag_directives = []
          event.implicit = true
          event
        elsif token.type != STREAM_END_TOKEN
          # An explicit document.
          start_mark = token.start_mark
          version_directive, tag_directives = process_directives
          token = peek_token
          parser_error("did not find expected <document start>", token.start_mark) if token.type != DOCUMENT_START_TOKEN

          @states.push(PARSE_DOCUMENT_END_STATE)
          @state = PARSE_DOCUMENT_CONTENT_STATE
          event = Event.new(DOCUMENT_START_EVENT, start_mark, token.end_mark)
          event.version_directive = version_directive
          event.tag_directives = tag_directives
          event.implicit = false
          skip_token
          event
        else
          # The stream end.
          @state = PARSE_END_STATE
          event = Event.new(STREAM_END_EVENT, token.start_mark, token.end_mark)
          skip_token
          event
        end
      end

      # explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*
      #                                                 ***********
      def parse_document_content
        token = peek_token

        case token.type
        when VERSION_DIRECTIVE_TOKEN, TAG_DIRECTIVE_TOKEN, DOCUMENT_START_TOKEN, DOCUMENT_END_TOKEN, STREAM_END_TOKEN
          @state = @states.pop
          process_empty_scalar(token.start_mark)
        else
          parse_node(true, false)
        end
      end

      # implicit_document ::= block_node DOCUMENT-END*
      #                                  *************
      # explicit_document ::= DIRECTIVE* DOCUMENT-START block_node? DOCUMENT-END*
      #                                                             *************
      def parse_document_end
        implicit = true

        token = peek_token

        start_mark = end_mark = token.start_mark

        if token.type == DOCUMENT_END_TOKEN
          end_mark = token.end_mark
          skip_token
          implicit = false
        end

        @tag_directives.clear

        @state = PARSE_DOCUMENT_START_STATE
        event = Event.new(DOCUMENT_END_EVENT, start_mark, end_mark)
        event.implicit = implicit
        event
      end

      # block_node_or_indentless_sequence ::= ALIAS
      #                                       *****
      #                                       | properties (block_content | indentless_block_sequence)?
      #                                         **********  *
      #                                       | block_content | indentless_block_sequence
      #                                         *
      # block_node ::= ALIAS
      #                *****
      #                | properties block_content?
      #                  ********** *
      #                | block_content
      #                  *
      # flow_node  ::= ALIAS
      #                *****
      #                | properties flow_content?
      #                  ********** *
      #                | flow_content
      #                  *
      # properties ::= TAG ANCHOR? | ANCHOR TAG?
      #                *************************
      # block_content ::= block_collection | flow_collection | SCALAR
      #                                                        ******
      # flow_content  ::= flow_collection | SCALAR
      #                                     ******
      def parse_node(block, indentless_sequence)
        anchor = nil
        tag_handle = nil
        tag_suffix = nil
        tag = nil
        tag_mark = nil

        token = peek_token

        if token.type == ALIAS_TOKEN
          @state = @states.pop
          event = Event.new(ALIAS_EVENT, token.start_mark, token.end_mark)
          event.anchor = token.value
          skip_token
          return event
        end

        start_mark = end_mark = token.start_mark

        if token.type == ANCHOR_TOKEN
          anchor = token.value
          start_mark = token.start_mark
          end_mark = token.end_mark
          skip_token
          token = peek_token
          if token.type == TAG_TOKEN
            tag_handle = token.handle
            tag_suffix = token.suffix
            tag_mark = token.start_mark
            end_mark = token.end_mark
            skip_token
            token = peek_token
          end
        elsif token.type == TAG_TOKEN
          tag_handle = token.handle
          tag_suffix = token.suffix
          start_mark = tag_mark = token.start_mark
          end_mark = token.end_mark
          skip_token
          token = peek_token
          if token.type == ANCHOR_TOKEN
            anchor = token.value
            end_mark = token.end_mark
            skip_token
            token = peek_token
          end
        end

        if tag_handle
          if tag_handle.empty?
            tag = tag_suffix
          else
            directive = @tag_directives.find { |tag_directive| tag_directive.handle == tag_handle }
            if directive
              tag = directive.prefix + tag_suffix
            else
              parser_error_context("while parsing a node", start_mark, "found undefined tag handle", tag_mark)
            end
          end
        end

        implicit = tag.nil? || tag.empty?

        if indentless_sequence && token.type == BLOCK_ENTRY_TOKEN
          end_mark = token.end_mark
          @state = PARSE_INDENTLESS_SEQUENCE_ENTRY_STATE
          return collection_start_event(SEQUENCE_START_EVENT, anchor, tag, implicit,
                                        BLOCK_SEQUENCE_STYLE, start_mark, end_mark)
        end

        case token.type
        when SCALAR_TOKEN
          plain_implicit = false
          quoted_implicit = false
          end_mark = token.end_mark
          if (token.style == PLAIN_SCALAR_STYLE && tag.nil?) || tag == "!"
            plain_implicit = true
          elsif tag.nil?
            quoted_implicit = true
          end
          @state = @states.pop
          event = Event.new(SCALAR_EVENT, start_mark, end_mark)
          event.anchor = anchor
          event.tag = tag
          event.value = token.value
          event.plain_implicit = plain_implicit
          event.quoted_implicit = quoted_implicit
          event.style = token.style
          skip_token
          event
        when FLOW_SEQUENCE_START_TOKEN
          end_mark = token.end_mark
          @state = PARSE_FLOW_SEQUENCE_FIRST_ENTRY_STATE
          collection_start_event(SEQUENCE_START_EVENT, anchor, tag, implicit,
                                 FLOW_SEQUENCE_STYLE, start_mark, end_mark)
        when FLOW_MAPPING_START_TOKEN
          end_mark = token.end_mark
          @state = PARSE_FLOW_MAPPING_FIRST_KEY_STATE
          collection_start_event(MAPPING_START_EVENT, anchor, tag, implicit,
                                 FLOW_MAPPING_STYLE, start_mark, end_mark)
        else
          if block && token.type == BLOCK_SEQUENCE_START_TOKEN
            end_mark = token.end_mark
            @state = PARSE_BLOCK_SEQUENCE_FIRST_ENTRY_STATE
            collection_start_event(SEQUENCE_START_EVENT, anchor, tag, implicit,
                                   BLOCK_SEQUENCE_STYLE, start_mark, end_mark)
          elsif block && token.type == BLOCK_MAPPING_START_TOKEN
            end_mark = token.end_mark
            @state = PARSE_BLOCK_MAPPING_FIRST_KEY_STATE
            collection_start_event(MAPPING_START_EVENT, anchor, tag, implicit,
                                   BLOCK_MAPPING_STYLE, start_mark, end_mark)
          elsif anchor || tag
            # Properties with no content make an empty plain scalar.
            @state = @states.pop
            event = Event.new(SCALAR_EVENT, start_mark, end_mark)
            event.anchor = anchor
            event.tag = tag
            event.value = new_string
            event.plain_implicit = implicit
            event.quoted_implicit = false
            event.style = PLAIN_SCALAR_STYLE
            event
          else
            parser_error_context(block ? "while parsing a block node" : "while parsing a flow node",
                                 start_mark, "did not find expected node content", token.start_mark)
          end
        end
      end

      def collection_start_event(type, anchor, tag, implicit, style, start_mark, end_mark)
        event = Event.new(type, start_mark, end_mark)
        event.anchor = anchor
        event.tag = tag
        event.implicit = implicit
        event.style = style
        event
      end

      # block_sequence ::= BLOCK-SEQUENCE-START (BLOCK-ENTRY block_node?)* BLOCK-END
      #                    ********************  *********** *             *********
      def parse_block_sequence_entry(first)
        if first
          token = peek_token
          @marks.push(token.start_mark)
          skip_token
        end

        token = peek_token

        if token.type == BLOCK_ENTRY_TOKEN
          mark = token.end_mark
          skip_token
          token = peek_token
          if token.type != BLOCK_ENTRY_TOKEN && token.type != BLOCK_END_TOKEN
            @states.push(PARSE_BLOCK_SEQUENCE_ENTRY_STATE)
            parse_node(true, false)
          else
            @state = PARSE_BLOCK_SEQUENCE_ENTRY_STATE
            process_empty_scalar(mark)
          end
        elsif token.type == BLOCK_END_TOKEN
          @state = @states.pop
          @marks.pop
          event = Event.new(SEQUENCE_END_EVENT, token.start_mark, token.end_mark)
          skip_token
          event
        else
          parser_error_context("while parsing a block collection", @marks.pop,
                               "did not find expected '-' indicator", token.start_mark)
        end
      end

      # indentless_sequence ::= (BLOCK-ENTRY block_node?)+
      #                          *********** *
      def parse_indentless_sequence_entry
        token = peek_token

        if token.type == BLOCK_ENTRY_TOKEN
          mark = token.end_mark
          skip_token
          token = peek_token
          if token.type != BLOCK_ENTRY_TOKEN && token.type != KEY_TOKEN &&
             token.type != VALUE_TOKEN && token.type != BLOCK_END_TOKEN
            @states.push(PARSE_INDENTLESS_SEQUENCE_ENTRY_STATE)
            parse_node(true, false)
          else
            @state = PARSE_INDENTLESS_SEQUENCE_ENTRY_STATE
            process_empty_scalar(mark)
          end
        else
          @state = @states.pop
          Event.new(SEQUENCE_END_EVENT, token.start_mark, token.start_mark)
        end
      end

      # block_mapping ::= BLOCK-MAPPING_START
      #                   *******************
      #                   ((KEY block_node_or_indentless_sequence?)?
      #                     *** *
      #                   (VALUE block_node_or_indentless_sequence?)?)*
      #
      #                   BLOCK-END
      #                   *********
      def parse_block_mapping_key(first)
        if first
          token = peek_token
          @marks.push(token.start_mark)
          skip_token
        end

        token = peek_token

        if token.type == KEY_TOKEN
          mark = token.end_mark
          skip_token
          token = peek_token
          if token.type != KEY_TOKEN && token.type != VALUE_TOKEN && token.type != BLOCK_END_TOKEN
            @states.push(PARSE_BLOCK_MAPPING_VALUE_STATE)
            parse_node(true, true)
          else
            @state = PARSE_BLOCK_MAPPING_VALUE_STATE
            process_empty_scalar(mark)
          end
        elsif token.type == BLOCK_END_TOKEN
          @state = @states.pop
          @marks.pop
          event = Event.new(MAPPING_END_EVENT, token.start_mark, token.end_mark)
          skip_token
          event
        else
          parser_error_context("while parsing a block mapping", @marks.pop,
                               "did not find expected key", token.start_mark)
        end
      end

      # block_mapping ::= BLOCK-MAPPING_START
      #
      #                   ((KEY block_node_or_indentless_sequence?)?
      #
      #                   (VALUE block_node_or_indentless_sequence?)?)*
      #                    ***** *
      #                   BLOCK-END
      def parse_block_mapping_value
        token = peek_token

        if token.type == VALUE_TOKEN
          mark = token.end_mark
          skip_token
          token = peek_token
          if token.type != KEY_TOKEN && token.type != VALUE_TOKEN && token.type != BLOCK_END_TOKEN
            @states.push(PARSE_BLOCK_MAPPING_KEY_STATE)
            parse_node(true, true)
          else
            @state = PARSE_BLOCK_MAPPING_KEY_STATE
            process_empty_scalar(mark)
          end
        else
          @state = PARSE_BLOCK_MAPPING_KEY_STATE
          process_empty_scalar(token.start_mark)
        end
      end

      # flow_sequence ::= FLOW-SEQUENCE-START
      #                   *******************
      #                   (flow_sequence_entry FLOW-ENTRY)*
      #                    *                   **********
      #                   flow_sequence_entry?
      #                   *
      #                   FLOW-SEQUENCE-END
      #                   *****************
      # flow_sequence_entry ::= flow_node | KEY flow_node? (VALUE flow_node?)?
      #                         *
      def parse_flow_sequence_entry(first)
        if first
          token = peek_token
          @marks.push(token.start_mark)
          skip_token
        end

        token = peek_token

        if token.type != FLOW_SEQUENCE_END_TOKEN
          unless first
            if token.type == FLOW_ENTRY_TOKEN
              skip_token
              token = peek_token
            else
              parser_error_context("while parsing a flow sequence", @marks.pop,
                                   "did not find expected ',' or ']'", token.start_mark)
            end
          end

          if token.type == KEY_TOKEN
            @state = PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_KEY_STATE
            event = collection_start_event(MAPPING_START_EVENT, nil, nil, true, FLOW_MAPPING_STYLE,
                                           token.start_mark, token.end_mark)
            skip_token
            return event
          elsif token.type != FLOW_SEQUENCE_END_TOKEN
            @states.push(PARSE_FLOW_SEQUENCE_ENTRY_STATE)
            return parse_node(false, false)
          end
        end

        @state = @states.pop
        @marks.pop
        event = Event.new(SEQUENCE_END_EVENT, token.start_mark, token.end_mark)
        skip_token
        event
      end

      # flow_sequence_entry ::= flow_node | KEY flow_node? (VALUE flow_node?)?
      #                                     *** *
      def parse_flow_sequence_entry_mapping_key
        token = peek_token

        if token.type != VALUE_TOKEN && token.type != FLOW_ENTRY_TOKEN && token.type != FLOW_SEQUENCE_END_TOKEN
          @states.push(PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_VALUE_STATE)
          parse_node(false, false)
        else
          mark = token.end_mark
          skip_token
          @state = PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_VALUE_STATE
          process_empty_scalar(mark)
        end
      end

      # flow_sequence_entry ::= flow_node | KEY flow_node? (VALUE flow_node?)?
      #                                                     ***** *
      def parse_flow_sequence_entry_mapping_value
        token = peek_token

        if token.type == VALUE_TOKEN
          skip_token
          token = peek_token
          if token.type != FLOW_ENTRY_TOKEN && token.type != FLOW_SEQUENCE_END_TOKEN
            @states.push(PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_END_STATE)
            return parse_node(false, false)
          end
        end
        @state = PARSE_FLOW_SEQUENCE_ENTRY_MAPPING_END_STATE
        process_empty_scalar(token.start_mark)
      end

      # flow_sequence_entry ::= flow_node | KEY flow_node? (VALUE flow_node?)?
      #                                                                     *
      def parse_flow_sequence_entry_mapping_end
        token = peek_token

        @state = PARSE_FLOW_SEQUENCE_ENTRY_STATE

        Event.new(MAPPING_END_EVENT, token.start_mark, token.start_mark)
      end

      # flow_mapping ::= FLOW-MAPPING-START
      #                  ******************
      #                  (flow_mapping_entry FLOW-ENTRY)*
      #                   *                  **********
      #                  flow_mapping_entry?
      #                  ******************
      #                  FLOW-MAPPING-END
      #                  ****************
      # flow_mapping_entry ::= flow_node | KEY flow_node? (VALUE flow_node?)?
      #                        *           *** *
      def parse_flow_mapping_key(first)
        if first
          token = peek_token
          @marks.push(token.start_mark)
          skip_token
        end

        token = peek_token

        if token.type != FLOW_MAPPING_END_TOKEN
          unless first
            if token.type == FLOW_ENTRY_TOKEN
              skip_token
              token = peek_token
            else
              parser_error_context("while parsing a flow mapping", @marks.pop,
                                   "did not find expected ',' or '}'", token.start_mark)
            end
          end

          if token.type == KEY_TOKEN
            skip_token
            token = peek_token
            if token.type != VALUE_TOKEN && token.type != FLOW_ENTRY_TOKEN && token.type != FLOW_MAPPING_END_TOKEN
              @states.push(PARSE_FLOW_MAPPING_VALUE_STATE)
              return parse_node(false, false)
            else
              @state = PARSE_FLOW_MAPPING_VALUE_STATE
              return process_empty_scalar(token.start_mark)
            end
          elsif token.type != FLOW_MAPPING_END_TOKEN
            @states.push(PARSE_FLOW_MAPPING_EMPTY_VALUE_STATE)
            return parse_node(false, false)
          end
        end

        @state = @states.pop
        @marks.pop
        event = Event.new(MAPPING_END_EVENT, token.start_mark, token.end_mark)
        skip_token
        event
      end

      # flow_mapping_entry ::= flow_node | KEY flow_node? (VALUE flow_node?)?
      #                                  *                  ***** *
      def parse_flow_mapping_value(empty)
        token = peek_token

        if empty
          @state = PARSE_FLOW_MAPPING_KEY_STATE
          return process_empty_scalar(token.start_mark)
        end

        if token.type == VALUE_TOKEN
          skip_token
          token = peek_token
          if token.type != FLOW_ENTRY_TOKEN && token.type != FLOW_MAPPING_END_TOKEN
            @states.push(PARSE_FLOW_MAPPING_KEY_STATE)
            return parse_node(false, false)
          end
        end

        @state = PARSE_FLOW_MAPPING_KEY_STATE
        process_empty_scalar(token.start_mark)
      end

      # yaml_parser_process_empty_scalar
      def process_empty_scalar(mark)
        event = Event.new(SCALAR_EVENT, mark, mark)
        event.value = new_string
        event.plain_implicit = true
        event.quoted_implicit = false
        event.style = PLAIN_SCALAR_STYLE
        event
      end

      # yaml_parser_process_directives: read the %YAML and %TAG directives
      # before a document, and add the default tag handles. Returns the
      # version directive and the document's own tag directives.
      def process_directives
        version_directive = nil
        tag_directives = []

        token = peek_token

        while token.type == VERSION_DIRECTIVE_TOKEN || token.type == TAG_DIRECTIVE_TOKEN
          if token.type == VERSION_DIRECTIVE_TOKEN
            parser_error("found duplicate %YAML directive", token.start_mark) if version_directive
            if token.major != 1 || (token.minor != 1 && token.minor != 2)
              parser_error("found incompatible YAML document", token.start_mark)
            end
            version_directive = VersionDirective.new(token.major, token.minor)
          else
            value = TagDirective.new(token.handle, token.prefix)
            append_tag_directive(value, false, token.start_mark)
            tag_directives.push(value)
          end

          skip_token
          token = peek_token
        end

        DEFAULT_TAG_DIRECTIVES.each do |default_tag_directive|
          append_tag_directive(default_tag_directive, true, token.start_mark)
        end

        [version_directive, tag_directives]
      end

      # yaml_parser_append_tag_directive
      def append_tag_directive(value, allow_duplicates, mark)
        if @tag_directives.any? { |tag_directive| tag_directive.handle == value.handle }
          return if allow_duplicates

          parser_error("found duplicate %TAG directive", mark)
        end

        @tag_directives.push(TagDirective.new(value.handle, value.prefix))
      end
    end
  end
end
