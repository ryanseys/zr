# frozen_string_literal: true

# rbs_extension, the C part of the rbs gem 4.2.0 (ext/rbs_extension over
# the parser in src/), in Ruby. The gem's own rbs.rb requires this file
# after its AST classes, and its parser_aux.rb and location_aux.rb build
# RBS::Parser's and RBS::Location's public API on what it defines.
#
# The parser builds the gem's RBS::AST and RBS::Types objects directly,
# where the C builds its own nodes and translates them after a parse
# without errors (ast_translation.c). It gives the same objects: the same
# classes, fields, locations and child locations, and the same symbols in
# the buffer's encoding. An error raises the same RBS::ParsingError, with
# the first error that the parse found.
require_relative "rbs_extension/lexer"
require_relative "rbs_extension/parser"
require_relative "rbs_extension/serializer"

module RBS
  # legacy_location.c: a range of character positions in a buffer, and
  # its named child ranges, each required or optional, in the order they
  # were added.
  class Location
    def buffer = @buffer
    def _start_pos = @start_pos || -1
    def _end_pos = @end_pos || -1

    # rbs_loc_legacy_add_optional_child, and a required child is an
    # optional one with its bit set. The bits are an unsigned int's 32.
    def _add_optional_child(name, start_pos, end_pos)
      children = @children ||= []
      raise RuntimeError, "Too many children added to location: #{children.size + 1}" if children.size == 32

      children << [name, start_pos, end_pos, false]
      nil
    end

    def _add_required_child(name, start_pos, end_pos)
      _add_optional_child(name, start_pos, end_pos)
      @children.last[3] = true
      nil
    end

    def _add_optional_no_child(name) = _add_optional_child(name, -1, -1)

    def _required_keys = @children ? @children.filter_map { |name, _, _, required| name if required } : []
    def _optional_keys = @children ? @children.filter_map { |name, _, _, required| name unless required } : []

    # A child that is optional and has no range is nil.
    def [](name)
      @children&.each do |child, start_pos, end_pos, required|
        next unless child == name
        return nil if !required && start_pos == -1

        return Location.new(@buffer, start_pos, end_pos)
      end
      raise RuntimeError, "Unknown child name given: #{name}"
    end

    private

    def initialize(buffer, start_pos, end_pos)
      @buffer = buffer
      @start_pos = start_pos
      @end_pos = end_pos
      @children = nil
    end

    # A copy has its own children, as the C copies the struct.
    def initialize_copy(_other)
      @children = @children&.map(&:dup)
    end
  end

  # main.c: the entry points of the parser.
  class Parser
    class << self
      def _parse_type(buffer, start_pos, end_pos, variables, require_eof, void_allowed, self_allowed, classish_allowed)
        parse(buffer, start_pos, end_pos, variables: variables) do |engine|
          engine.type_entry(require_eof, void_allowed, self_allowed, classish_allowed)
        end
      end

      def _parse_method_type(buffer, start_pos, end_pos, variables, require_eof, enable_forwarding_params)
        parse(buffer, start_pos, end_pos, variables: variables, forwarding: enable_forwarding_params) do |engine|
          engine.method_type_entry(require_eof)
        end
      end

      def _parse_signature(buffer, start_pos, end_pos, enable_forwarding_params)
        parse(buffer, start_pos, end_pos, forwarding: enable_forwarding_params, &:signature_entry)
      end

      def _parse_type_params(buffer, start_pos, end_pos, module_type_params)
        parse(buffer, start_pos, end_pos) { |engine| engine.type_params_entry(module_type_params) }
      end

      def _parse_inline_leading_annotation(buffer, start_pos, end_pos, variables)
        parse(buffer, start_pos, end_pos, variables: variables, &:inline_leading_entry)
      end

      def _parse_inline_trailing_annotation(buffer, start_pos, end_pos, variables)
        parse(buffer, start_pos, end_pos, variables: variables, &:inline_trailing_entry)
      end

      # The `_*_to_bytes` forms give the AST in the binary form of
      # src/serialize.c, which the gem's WebAssembly build reads back.
      def _parse_type_to_bytes(buffer, start_pos, end_pos, variables, require_eof, void_allowed, self_allowed, classish_allowed)
        parse(buffer, start_pos, end_pos, variables: variables, bytes: true) do |engine|
          type = engine.type_entry(require_eof, void_allowed, self_allowed, classish_allowed)
          type && Serializer.new.node(type)
        end
      end

      def _parse_method_type_to_bytes(buffer, start_pos, end_pos, variables, require_eof, enable_forwarding_params)
        parse(buffer, start_pos, end_pos, variables: variables, forwarding: enable_forwarding_params, bytes: true) do |engine|
          method_type = engine.method_type_entry(require_eof)
          method_type && Serializer.new.node(method_type)
        end
      end

      def _parse_signature_to_bytes(buffer, start_pos, end_pos, enable_forwarding_params)
        parse(buffer, start_pos, end_pos, forwarding: enable_forwarding_params, bytes: true) do |engine|
          Serializer.new.signature(engine.signature_entry)
        end
      end

      # rbsparser_lex: each token up to `end_pos`, and the pEOF token, as
      # pairs of its type and its location.
      def _lex(buffer, end_pos)
        string = content(buffer)
        validate_position_range(string, 0, end_pos)
        lexer = Lexer.new(checked(string), 0, end_pos)
        tokens = []
        loop do
          token = lexer.next_token
          tokens << [token.type, Location.new(buffer, token.start, token.end)]
          break if token.type == :pEOF
        end
        tokens
      end

      private

      # The checks of the arguments in their order in main.c, then one
      # parse, which raises the first error it found.
      def parse(buffer, start_pos, end_pos, variables: nil, forwarding: false, bytes: false)
        string = content(buffer)
        validate_position_range(string, start_pos, end_pos)
        engine = Engine.new(buffer, Lexer.new(checked(string), start_pos, end_pos), forwarding ? true : false, bytes: bytes)
        engine.declare_type_variables(variables) unless variables.nil?
        engine.run { yield engine }
      end

      # StringValue: the content, or what its to_str gives.
      def content(buffer)
        string = buffer.content
        String.try_convert(string) or raise TypeError, "no implicit conversion of #{type_name(string)} into String"
      end

      def type_name(value)
        case value
        when nil, true, false then value.inspect
        else value.class
        end
      end

      # StringValueCStr: the parser reads the content as a C string.
      def checked(string)
        raise ArgumentError, "string contains null byte" if string.include?("\0")

        string
      end

      def validate_position_range(string, start_pos, end_pos)
        raise ArgumentError, "negative position range: #{start_pos}...#{end_pos}" if start_pos.negative? || end_pos.negative?
        raise ArgumentError, "invalid position range: #{start_pos}...#{end_pos}" if start_pos > end_pos

        size = string.bytesize
        return unless start_pos > size

        raise ArgumentError, "position range starts past the end of the buffer: #{start_pos}...#{end_pos}, buffer is #{size} bytes"
      end
    end
  end
end
