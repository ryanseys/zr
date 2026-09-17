# frozen_string_literal: true

module Prism
  module Ruby
    class Parser
      # pm_parse, with the result as Prism.parse answers it and what
      # Prism.dump writes beside the tree: `[result, facts]`.
      def parse
        value = parse_program

        source = @node_source
        source.replace_start_line(@start_line)
        source.replace_offsets(@newlines)
        [ParseResult.new(value, result_comments, result_magic_comments, result_data_loc, result_errors, result_warnings, source), dump_facts]
      end

      # Dump.parse's arguments beside the result.
      def dump_facts
        { encoding_name: @encoding.name, pool: @constant_pool, shared: @shared_strings, negative_zeros: @negative_zeros }
      end

      private

      def location_object(start, finish) = Location.new(@node_source, start, finish - start)

      def result_comments
        @comments.map do |type, start, finish|
          (type == :inline ? InlineComment : EmbDocComment).new(location_object(start, finish))
        end
      end

      def result_magic_comments
        @magic_comments.map do |key_start, key_length, value_start, value_length|
          MagicComment.new(Location.new(@node_source, key_start, key_length), Location.new(@node_source, value_start, value_length))
        end
      end

      def result_data_loc = @data_loc && location_object(*@data_loc)

      def result_errors = result_diagnostics(@errors, ParseError)
      def result_warnings = result_diagnostics(@warnings, ParseWarning)

      def result_diagnostics(diagnostics, type)
        encoding = ruby_encoding
        diagnostics.map do |diagnostic|
          message = diagnostic.message.dup.force_encoding(encoding)
          type.new(diagnostic.id, message, location_object(diagnostic.start, diagnostic.end), diagnostic.level)
        end
      end
    end
  end
end
