# frozen_string_literal: true

# Derived from libyaml 0.2.5 (MIT); see THIRD_PARTY_NOTICES.md.
#
# The object setup and the event constructors of libyaml 0.2.5
# (src/api.c).
module Psych
  module LibYAML
    class Parser
      # yaml_parser_initialize
      def initialize
        @error = NO_ERROR
        @problem = nil
        @problem_offset = 0
        @problem_value = 0
        @problem_mark = ZERO_MARK
        @context = nil
        @context_mark = ZERO_MARK

        @read_handler = nil
        @encoding = ANY_ENCODING
        @eof = false
        @raw_buffer = new_string
        @raw_pointer = 0
        @buffer = new_string
        @pointer = 0
        @unread = 0
        @offset = 0

        @mark_index = 0
        @mark_line = 0
        @mark_column = 0

        @stream_start_produced = false
        @stream_end_produced = false
        @flow_level = 0
        @tokens = []
        @tokens_parsed = 0
        @token_available = false
        @indents = []
        @indent = 0
        @simple_key_allowed = false
        @simple_keys = []

        @states = []
        @state = PARSE_STREAM_START_STATE
        @marks = []
        @tag_directives = []
      end

      def inspect = "#<#{self.class}>"

      # yaml_parser_set_input_string: read the bytes of `input`.
      def set_input_string(input)
        current = 0
        size = input.bytesize
        @read_handler = lambda do |wanted|
          wanted = size - current if wanted > size - current
          chunk = input.byteslice(current, wanted).force_encoding(Encoding::BINARY)
          current += wanted
          chunk
        end
      end

      # yaml_parser_set_input: read from a handler that takes the maximum
      # number of bytes it can return and returns a binary string (empty at
      # the end of the input), or nil for an input error.
      def set_input(&handler)
        @read_handler = handler
      end

      # yaml_parser_set_encoding
      def set_encoding(encoding)
        @encoding = encoding
      end
    end

    class Emitter
      OUTPUT_BUFFER_SIZE = 16_384

      attr_reader :error, :problem
      attr_reader :canonical, :best_indent, :best_width

      # yaml_emitter_initialize
      def initialize
        @error = NO_ERROR
        @problem = nil

        @write_handler = nil
        @buffer = new_string
        @encoding = ANY_ENCODING

        @canonical = false
        @best_indent = 0
        @best_width = 0
        @unicode = false
        @line_break = ANY_BREAK

        @states = []
        @state = EMIT_STREAM_START_STATE
        @events = []
        @indents = []
        @tag_directives = []
        @indent = 0
        @flow_level = 0

        @root_context = false
        @sequence_context = false
        @mapping_context = false
        @simple_key_context = false

        @line = 0
        @column = 0
        @whitespace = false
        @indention = false
        @open_ended = 0

        @anchor_data_anchor = nil
        @anchor_data_alias = false
        @tag_data_handle = nil
        @tag_data_suffix = nil
        @scalar_data_value = nil
        @scalar_data_multiline = false
        @scalar_data_flow_plain_allowed = false
        @scalar_data_block_plain_allowed = false
        @scalar_data_single_quoted_allowed = false
        @scalar_data_block_allowed = false
        @scalar_data_style = ANY_SCALAR_STYLE
      end

      def inspect = "#<#{self.class}>"

      # yaml_emitter_set_output: write through a handler that takes a
      # binary string and returns whether it wrote it.
      def set_output(&handler)
        @write_handler = handler
      end

      # yaml_emitter_set_encoding
      def set_encoding(encoding)
        @encoding = encoding
      end

      # yaml_emitter_set_canonical
      def set_canonical(canonical)
        @canonical = canonical
      end

      # yaml_emitter_set_indent
      def set_indent(indent)
        @best_indent = indent > 1 && indent < 10 ? indent : 2
      end

      # yaml_emitter_set_width
      def set_width(width)
        @best_width = width >= 0 ? width : -1
      end

      # yaml_emitter_set_unicode
      def set_unicode(unicode)
        @unicode = unicode
      end
    end

    # The event constructors. libyaml checks that every string is valid
    # UTF-8 and returns 0 when one is not; these return nil then.
    module Events
      module_function

      # yaml_check_utf8
      def check_utf8(string)
        pointer = 0
        last = string.bytesize
        while pointer < last
          octet = string.getbyte(pointer)
          width = if octet & 0x80 == 0x00 then 1
                  elsif octet & 0xE0 == 0xC0 then 2
                  elsif octet & 0xF0 == 0xE0 then 3
                  elsif octet & 0xF8 == 0xF0 then 4
                  else 0
                  end
          value = if octet & 0x80 == 0x00 then octet & 0x7F
                  elsif octet & 0xE0 == 0xC0 then octet & 0x1F
                  elsif octet & 0xF0 == 0xE0 then octet & 0x0F
                  elsif octet & 0xF8 == 0xF0 then octet & 0x07
                  else 0
                  end
          return false if width.zero?
          return false if pointer + width > last

          k = 1
          while k < width
            octet = string.getbyte(pointer + k)
            return false if octet & 0xC0 != 0x80

            value = (value << 6) + (octet & 0x3F)
            k += 1
          end
          return false unless width == 1 || (width == 2 && value >= 0x80) ||
                              (width == 3 && value >= 0x800) || (width == 4 && value >= 0x10000)

          pointer += width
        end
        true
      end

      # yaml_stream_start_event_initialize
      def stream_start(encoding)
        event = Event.new(STREAM_START_EVENT, ZERO_MARK, ZERO_MARK)
        event.encoding = encoding
        event
      end

      # yaml_stream_end_event_initialize
      def stream_end = Event.new(STREAM_END_EVENT, ZERO_MARK, ZERO_MARK)

      # yaml_document_start_event_initialize
      def document_start(version_directive, tag_directives, implicit)
        tag_directives.each do |tag_directive|
          return nil unless check_utf8(tag_directive.handle) && check_utf8(tag_directive.prefix)
        end

        event = Event.new(DOCUMENT_START_EVENT, ZERO_MARK, ZERO_MARK)
        event.version_directive = version_directive
        event.tag_directives = tag_directives
        event.implicit = implicit
        event
      end

      # yaml_document_end_event_initialize
      def document_end(implicit)
        event = Event.new(DOCUMENT_END_EVENT, ZERO_MARK, ZERO_MARK)
        event.implicit = implicit
        event
      end

      # yaml_alias_event_initialize
      def alias(anchor)
        return nil unless check_utf8(anchor)

        event = Event.new(ALIAS_EVENT, ZERO_MARK, ZERO_MARK)
        event.anchor = anchor
        event
      end

      # yaml_scalar_event_initialize
      def scalar(anchor, tag, value, plain_implicit, quoted_implicit, style)
        return nil if anchor && !check_utf8(anchor)
        return nil if tag && !check_utf8(tag)
        return nil unless check_utf8(value)

        event = Event.new(SCALAR_EVENT, ZERO_MARK, ZERO_MARK)
        event.anchor = anchor
        event.tag = tag
        event.value = value
        event.plain_implicit = plain_implicit
        event.quoted_implicit = quoted_implicit
        event.style = style
        event
      end

      # yaml_sequence_start_event_initialize
      def sequence_start(anchor, tag, implicit, style)
        collection_start(SEQUENCE_START_EVENT, anchor, tag, implicit, style)
      end

      # yaml_sequence_end_event_initialize
      def sequence_end = Event.new(SEQUENCE_END_EVENT, ZERO_MARK, ZERO_MARK)

      # yaml_mapping_start_event_initialize
      def mapping_start(anchor, tag, implicit, style)
        collection_start(MAPPING_START_EVENT, anchor, tag, implicit, style)
      end

      # yaml_mapping_end_event_initialize
      def mapping_end = Event.new(MAPPING_END_EVENT, ZERO_MARK, ZERO_MARK)

      def collection_start(type, anchor, tag, implicit, style)
        return nil if anchor && !check_utf8(anchor)
        return nil if tag && !check_utf8(tag)

        event = Event.new(type, ZERO_MARK, ZERO_MARK)
        event.anchor = anchor
        event.tag = tag
        event.implicit = implicit
        event.style = style
        event
      end
    end
  end
end
