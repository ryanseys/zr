# frozen_string_literal: true
# shareable_constant_value: literal

module Prism
  module Ruby
    # extension.c: the entry points of prism's C extension over the Ruby
    # parser. Each returns what the C returns, down to the encoding and
    # frozenness of each String, and raises what the C raises for a bad
    # argument.
    class << self
      # The size of pm_parse_stream_read's line buffer.
      STREAM_LINE_SIZE = 4096

      # Prism.dump
      def dump(source, **keywords)
        options = string_options(source, keywords)
        value = dump_input(source, options)
        options.freeze? ? value.freeze : value
      end

      # Prism.dump_file
      def dump_file(filepath, **keywords) = dump_input(*file_options(filepath, keywords))

      # Prism.lex
      def lex(source, **keywords) = parse_lex_input(source, string_options(source, keywords), false)

      # Prism.lex_file
      def lex_file(filepath, **keywords) = parse_lex_input(*file_options(filepath, keywords), false)

      # Prism.parse
      def parse(source, **keywords) = parse_input(source, string_options(source, keywords))

      # Prism.parse_file
      def parse_file(filepath, **keywords) = parse_input(*file_options(filepath, keywords))

      # Prism.profile: the parse alone.
      def profile(source, **keywords)
        Parser.new(source, string_options(source, keywords)).parse_program
        nil
      end

      # Prism.profile_file
      def profile_file(filepath, **keywords)
        Parser.new(*file_options(filepath, keywords)).parse_program
        nil
      end

      # Prism.parse_stream: pm_parse_stream over an object that responds to
      # gets and eof?. The lines read so far parse again while the source is
      # cut inside a string, heredoc or other lex mode.
      def parse_stream(stream, **keywords)
        options = Options.new(**keywords)
        buffer = String.new(encoding: ::Encoding::BINARY)
        eof = parse_stream_read(buffer, stream)
        parser = Parser.new(buffer, options)
        node = parse_tree(parser, options.freeze?)

        while !eof && !parser.errors.empty? && (parser.lex_mode_nested? || parser.errors.any? { |error| error.id == :heredoc_term })
          eof = parse_stream_read(buffer, stream)
          parser = Parser.new(buffer, options)
          node = parse_tree(parser, options.freeze?)
        end

        parse_result(ParseResult, parser, node, options.freeze?)
      end

      # Prism.parse_comments
      def parse_comments(source, **keywords) = parse_input_comments(source, string_options(source, keywords))

      # Prism.parse_file_comments
      def parse_file_comments(filepath, **keywords) = parse_input_comments(*file_options(filepath, keywords))

      # Prism.parse_lex
      def parse_lex(source, **keywords) = parse_lex_input(source, string_options(source, keywords), true)

      # Prism.parse_lex_file
      def parse_lex_file(filepath, **keywords) = parse_lex_input(*file_options(filepath, keywords), true)

      # Prism.parse_success?
      def parse_success?(source, **keywords) = parse_input_success?(source, string_options(source, keywords))

      # Prism.parse_failure?
      def parse_failure?(source, **keywords) = !parse_success?(source, **keywords)

      # Prism.parse_file_success?
      def parse_file_success?(filepath, **keywords) = parse_input_success?(*file_options(filepath, keywords))

      # Prism.parse_file_failure?
      def parse_file_failure?(filepath, **keywords) = !parse_file_success?(filepath, **keywords)

      # The tokens of a source as the lex callback sees them, with no parser
      # behind the lexer: `[type, start, length, lex_state]` each, the last
      # one EOF. Tokens whose kind the parser decides differ from Prism.lex's.
      def lex_tokens(source, **keywords)
        parser = Parser.new(source, Options.new(**keywords))
        tokens = []
        parser.lex_callback = ->(type, start, finish, state) { tokens << [type, start, finish - start, state] }
        parser.send(:scope_push, true)
        loop do
          parser.send(:lex)
          break if parser.instance_variable_get(:@current_type) == :EOF
        end
        tokens
      end

      private

      # string_options: the keywords are read before the source's type is
      # checked.
      def string_options(source, keywords)
        options = Options.new(**keywords)
        Options.check_type(source, String)
        options
      end

      # file_options: the source, and the options with the path as the
      # filepath. The path is read up to a NUL, as a C string.
      def file_options(filepath, keywords)
        path = encode_ospath(Options.check_type(filepath, String))
        options = Options.new(path, **keywords)
        [read_file(options.filepath), options]
      end

      # rb_str_encode_ospath: on macOS and Windows a path in an encoding
      # other than binary and UTF-8 is converted to UTF-8 when it can be.
      def encode_ospath(path)
        return path unless RUBY_PLATFORM.match?(/darwin|mswin|mingw/)
        return path if path.encoding == ::Encoding::BINARY || path.encoding == ::Encoding::UTF_8

        path.encode(::Encoding::UTF_8)
      rescue EncodingError
        path
      end

      # pm_string_file_init, with the errno of a failure raised against the
      # path.
      def read_file(path)
        File.open(path, "rb") do |file|
          raise Errno::EISDIR if file.stat.directory?

          file.read
        end
      rescue SystemCallError => e
        raise SystemCallError.new(path, e.errno)
      end

      # dump_input
      def dump_input(source, options)
        parser = Parser.new(source, options)
        node = parse_tree(parser, false)
        result = result_create(ParseResult, parser, node, parser.ruby_encoding, parser.node_source, false)
        Dump.parse(result, encoding_name: parser.encoding.name, pool: parser.constant_pool,
                           shared: parser.shared_strings, negative_zeros: parser.negative_zeros)
      end

      # parse_input
      def parse_input(source, options)
        parser = Parser.new(source, options)
        node = parse_tree(parser, options.freeze?)
        parse_result(ParseResult, parser, node, options.freeze?)
      end

      # parse_input_comments
      def parse_input_comments(source, options)
        parser = Parser.new(source, options)
        parse_tree(parser, options.freeze?)
        comments(parser, source_freeze(parser.node_source, options.freeze?), options.freeze?)
      end

      # parse_input_success_p
      def parse_input_success?(source, options)
        parser = Parser.new(source, options)
        parser.parse_program
        parser.errors.empty?
      end

      # pm_parse, and the Source pm_source_new makes after it in the
      # parser's final encoding. The nodes hold the Source as they are made,
      # so it is made first and made again when a magic comment changes the
      # encoding, which it can do only before the first node. A dump makes
      # no Source in C, so its Source never freezes.
      def parse_tree(parser, freeze)
        parser.node_source = source_new(parser, freeze)
        parser.encoding_changed_callback = -> { parser.node_source = source_new(parser, freeze) }
        node = parser.parse_program
        parser.node_source.replace_offsets(parser.newlines)
        node
      end

      # pm_source_new. Under `freeze: true` the String freezes before
      # Source.for sees it, which raises FrozenError for a binary source that
      # is not ASCII, as Source.for would make it UTF-8.
      def source_new(parser, freeze)
        string = parser.source.b.force_encoding(parser.ruby_encoding)
        Source.for(freeze ? string.freeze : string, parser.start_line, [])
      end

      # parse_lex_input: a LexResult of `[token, lex_state]` pairs, or with
      # `return_nodes` a ParseLexResult of the tree and the pairs. The
      # Source is made before the parse over the source as binary. The
      # tokens take UTF-8 until a magic comment changes the encoding, and
      # the tokens lexed before it are made again in the new one; an
      # encoding from the options is not a change.
      def parse_lex_input(source, options, return_nodes)
        parser = Parser.new(source, options)
        freeze = options.freeze?
        string = parser.source.b
        offsets = []
        ruby_source = Source.for(string, parser.start_line, offsets)
        tokens = []
        encoding = ::Encoding::UTF_8

        # parse_lex_encoding_changed_callback: the token keeps its location
        # as it was made, packed or not.
        parser.encoding_changed_callback = lambda do
          encoding = parser.ruby_encoding
          tokens.map! do |token, state|
            value = freeze_if(freeze, token.value.dup.force_encoding(encoding))
            token = freeze_if(freeze, Prism::Token.new(ruby_source, token.type, value, token.instance_variable_get(:@location)))
            freeze_if(freeze, [token, state])
          end
        end
        # parse_lex_token
        parser.lex_callback = lambda do |type, start, finish, state|
          value = freeze_if(freeze, parser.source.byteslice(start, finish - start).force_encoding(encoding))
          location = freeze ? location(ruby_source, start, finish - start, true) : (start << 32) | (finish - start)
          token = freeze_if(freeze, Prism::Token.new(ruby_source, type, value, location))
          tokens << freeze_if(freeze, [token, state])
        end
        parser.node_source = ruby_source
        node = parser.parse_program

        string.force_encoding(parser.ruby_encoding)
        offsets.concat(parser.newlines)
        [string, offsets, ruby_source, tokens].each(&:freeze) if freeze

        if return_nodes
          value = freeze_if(freeze, [AST.new(ruby_source, encoding, freeze).build(node), tokens])
          result_create(ParseLexResult, parser, value, encoding, ruby_source, freeze)
        else
          result_create(LexResult, parser, tokens, encoding, ruby_source, freeze)
        end
      end

      # A ParseResult of a parsed tree, as parse_input makes it.
      def parse_result(type, parser, node, freeze)
        encoding = parser.ruby_encoding
        source = source_freeze(parser.node_source, freeze)
        result_create(type, parser, AST.new(source, encoding, freeze).build(node), encoding, source, freeze)
      end

      # rb_class_new_instance_freeze and its kin: the value, frozen under
      # `freeze: true`.
      def freeze_if(freeze, value) = freeze ? value.freeze : value

      # The freezing of pm_source_new.
      def source_freeze(source, freeze)
        return source unless freeze

        source.source.freeze
        source.offsets.freeze
        source.freeze
      end

      # parse_result_create
      def result_create(type, parser, value, encoding, source, freeze)
        freeze_if(freeze, type.new(value, comments(parser, source, freeze), magic_comments(parser, source, freeze),
                                   data_loc(parser, source, freeze), diagnostics(parser.errors, ParseError, encoding, source, freeze),
                                   diagnostics(parser.warnings, ParseWarning, encoding, source, freeze), source))
      end

      # parser_location
      def location(source, start, length, freeze) = freeze_if(freeze, Location.new(source, start, length))

      # parser_comments
      def comments(parser, source, freeze)
        comments = parser.comments.map do |type, start, finish|
          freeze_if(freeze, (type == :inline ? InlineComment : EmbDocComment).new(location(source, start, finish - start, freeze)))
        end
        freeze_if(freeze, comments)
      end

      # parser_magic_comments
      def magic_comments(parser, source, freeze)
        magic_comments = parser.magic_comments.map do |key_start, key_length, value_start, value_length|
          freeze_if(freeze, MagicComment.new(location(source, key_start, key_length, freeze), location(source, value_start, value_length, freeze)))
        end
        freeze_if(freeze, magic_comments)
      end

      # parser_data_loc
      def data_loc(parser, source, freeze)
        start, finish = parser.data_loc
        start && location(source, start, finish - start, freeze)
      end

      # parser_errors and parser_warnings
      def diagnostics(list, type, encoding, source, freeze)
        diagnostics = list.map do |diagnostic|
          message = diagnostic.message.dup.force_encoding(encoding).freeze
          freeze_if(freeze, type.new(diagnostic.id, message, location(source, diagnostic.start, diagnostic.end - diagnostic.start, freeze), diagnostic.level))
        end
        freeze_if(freeze, diagnostics)
      end

      # pm_parse_stream_read: lines appended to the buffer until the end of
      # the stream (true) or an __END__ line (false). A line is read as
      # `gets(4095)`; a line that fills the buffer continues to be read
      # without the checks. eof? counts as true for any value but false,
      # because C tests the VALUE itself.
      def parse_stream_read(buffer, stream)
        while (line = stream.gets(STREAM_LINE_SIZE - 1))
          buffer << line.b
          next if line.bytesize == STREAM_LINE_SIZE - 1
          return false if ["__END__", "__END__\n", "__END__\r\n"].include?(line.b)
          break unless stream.eof? == false
        end
        true
      end
    end

    class AST
      using Reify

      def initialize(source, encoding, freeze)
        @source = source
        @encoding = encoding
        @freeze = freeze
        @constants = {}.compare_by_identity
      end

      def freeze? = @freeze

      # pm_ast_new: each node of the tree, parents first.
      def build(root)
        stack = [root]
        while (node = stack.pop)
          node.reify(self)
          stack.concat(node.compact_child_nodes)
        end
        root
      end

      # pm_string_new
      def string(string)
        return string if string.frozen? && string.encoding == @encoding

        string = string.dup if string.frozen?
        string.force_encoding(@encoding).freeze
      end

      # The constant pool's Symbols: a name not valid in the encoding reads
      # `:?`, as rb_str_intern refuses it.
      def constant(symbol)
        return if symbol.nil?

        @constants[symbol] ||= begin
          name = symbol.name.b.force_encoding(@encoding)
          name.valid_encoding? ? name.to_sym : :"?"
        end
      end

      def constants(symbols) = symbols.map! { |symbol| constant(symbol) }

      # pm_location_new under `freeze: true`
      def location(packed) = Location.new(@source, packed >> 32, packed & 0xFFFF_FFFF).freeze
    end
  end
end
