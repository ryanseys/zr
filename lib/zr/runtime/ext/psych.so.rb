# frozen_string_literal: true

Object.send(:native_module, :Psych)

# psych's C extension, in Ruby: the libyaml 0.2.5 parser and emitter
# (a port under psych/libyaml) and the glue psych puts around them
# (psych_parser.c, psych_emitter.c, psych_to_ruby.c and psych.c). The
# gem's own Ruby half (psych/, vendored in vendor/ruby) reaches these classes the
# way it reaches CRuby's, so everything above this file is the gem as
# written.
#
# The emitter is a handler, which is the one thing this file needs
# from the gem's Ruby half before the gem requires it.
require "psych/handler"
# The parser raises Psych::SyntaxError, so the class must exist before
# the gem's own part loads, which is also where CRuby's psych.so defines it.
require "psych/syntax_error"

require_relative "psych/libyaml/yaml"
require_relative "psych/libyaml/yaml_private"
require_relative "psych/libyaml/reader"
require_relative "psych/libyaml/scanner"
require_relative "psych/libyaml/parser"
require_relative "psych/libyaml/writer"
require_relative "psych/libyaml/emitter"
require_relative "psych/libyaml/api"

module Psych
  # psych.c
  def self.libyaml_version = LibYAML::VERSION.dup

  # The parser and emitter in use: libyaml, as a build without libfyaml has.
  BACKEND = (+"libyaml").force_encoding(Encoding::US_ASCII)

  # psych_to_ruby.c's two methods.
  class ClassLoader
    private

    # rb_path_to_class: each segment is a constant that the module before
    # it defines itself, from Object on. The refusal gives the path as far
    # as it read.
    def path2class(path)
      raise ArgumentError, "invalid class path encoding (non ASCII)" unless path.encoding.ascii_compatible?
      raise ArgumentError, "can't retrieve anonymous class #{path}" if path.empty? || path.start_with?("#")

      mod = Object
      read = 0
      until read >= path.bytesize
        colon = path.byteindex(":", read) || path.bytesize
        name = path.byteslice(read, colon - read)
        read = colon
        if read < path.bytesize
          raise ArgumentError, "undefined class/module #{path.byteslice(0, read)}" unless path.byteslice(read, 2) == "::"

          read += 2
        end
        unless /\A[A-Z]\w*\z/.match?(name) && mod.const_defined?(name, false)
          raise ArgumentError, "undefined class/module #{path.byteslice(0, read)}"
        end

        mod = mod.const_get(name, false)
        raise TypeError, "#{path} does not refer to class/module" unless mod.is_a?(Module)
      end
      mod
    end
  end

  module Visitors
    class Visitor; end

    class ToRuby < Visitor
      private

      # An exception of `klass` that no initialize ran for, holding
      # `message`.
      def build_exception(klass, message)
        exception = klass.allocate
        Primitive.zr_exc_set_message(exception, message)
        exception
      end
    end
  end

  module LibYAML
    # What the C glue does with Ruby values: the type checks and the
    # conversions of the Ruby C API that psych_parser.c and
    # psych_emitter.c call, with CRuby's messages.
    module Glue
      module_function

      FIXNUM_RANGE = (-(2**62)..((2**62) - 1))
      INT_RANGE = (-(2**31)..((2**31) - 1))

      # Check_Type(value, T_STRING)
      def check_string(value)
        return value if value.is_a?(String)

        raise TypeError, "wrong argument type #{conversion_name(value)} (expected String)"
      end

      # Check_Type(value, T_ARRAY)
      def check_array(value)
        return value if value.is_a?(Array)

        raise TypeError, "wrong argument type #{conversion_name(value)} (expected Array)"
      end

      # Check_Type(value, T_FIXNUM)
      def check_fixnum(value)
        return value if value.is_a?(Integer) && FIXNUM_RANGE.cover?(value)

        raise TypeError, "wrong argument type #{conversion_name(value)} (expected Integer)"
      end

      # StringValue
      def string_value(value)
        return value if value.is_a?(String)

        raise TypeError, no_implicit_conversion(value, "String") unless value.respond_to?(:to_str)

        converted = value.to_str
        return converted if converted.is_a?(String)

        raise TypeError, cant_convert_gives(value, "String", :to_str, converted)
      end

      # StringValueCStr: the bytes of a string with no NUL in it.
      def c_string_value(value)
        value = string_value(value)
        raise ArgumentError, "string contains null byte" if value.include?("\0")

        value
      end

      # NUM2INT
      def num2int(value)
        case value
        when Integer
          raise RangeError, "integer #{value} too big to convert to 'int'" if value > INT_RANGE.max
          raise RangeError, "integer #{value} too small to convert to 'int'" if value < INT_RANGE.min

          value
        when Float
          truncated = value.truncate
          raise RangeError, "float #{value} out of range of integer" unless INT_RANGE.cover?(truncated)

          truncated
        when nil, true, false
          raise TypeError, no_implicit_conversion(value, "Integer")
        else
          unless value.respond_to?(:to_int)
            raise TypeError, no_implicit_conversion(value, "Integer")
          end

          num2int(value.to_int)
        end
      end

      # The glue tests a VALUE as a C int, where only false is 0: nil
      # counts as true there.
      def c_truth(value) = !value.equal?(false)

      # rb_str_export_to_enc: the string in `encoding`, or the string
      # itself when it cannot convert.
      def export_to_encoding(string, encoding)
        return string if string.encoding == encoding

        if string.ascii_only? && string.encoding.ascii_compatible? && encoding.ascii_compatible?
          return string.dup.force_encoding(encoding)
        end

        string.encode(encoding)
      rescue EncodingError
        string
      end

      # PSYCH_TRANSCODE over rb_str_new: libyaml's bytes as a UTF-8 string,
      # exported to Encoding.default_internal when one is set.
      def ruby_string(bytes, internal)
        string = bytes.dup.force_encoding(Encoding::UTF_8)
        internal ? export_to_encoding(string, internal) : string
      end

      # rb_protect: run the block and return the exception it raises, or
      # nil.
      def protect
        yield
        nil
      rescue ::Exception => e
        e
      end

      # transcode_string: which encoding libyaml reads a string as.
      def transcode_string(string)
        case string.encoding
        when Encoding::UTF_8 then [string, UTF8_ENCODING]
        when Encoding::UTF_16LE then [string, UTF16LE_ENCODING]
        when Encoding::UTF_16BE then [string, UTF16BE_ENCODING]
        else [export_to_encoding(string, Encoding::UTF_8), UTF8_ENCODING]
        end
      end

      # transcode_io: which encoding libyaml reads an IO as.
      def transcode_io(io)
        encoding = io.external_encoding
        encoding = Encoding.find(encoding.to_s) unless encoding.nil? || encoding.is_a?(Encoding)

        case encoding
        when Encoding::US_ASCII, Encoding::UTF_8 then UTF8_ENCODING
        when Encoding::UTF_16LE then UTF16LE_ENCODING
        when Encoding::UTF_16BE then UTF16BE_ENCODING
        else ANY_ENCODING
        end
      end

      # io_reader: IO#read(size), cut back to a character boundary when
      # the IO returns more than the limit.
      def read_io(io, size)
        string = io.read(size)
        return String.new(encoding: Encoding::BINARY) if string.nil?

        string = string_value(string)
        if string.bytesize > size
          cut = 0
          string.each_char do |char|
            break if cut + char.bytesize > size

            cut += char.bytesize
          end
          return string.byteslice(0, cut).force_encoding(Encoding::BINARY)
        end
        string.b
      end

      # make_exception
      def make_exception(parser, path)
        return NoMemoryError if parser.error == MEMORY_ERROR

        line = parser.context_mark.line + 1
        column = parser.context_mark.column + 1

        Psych.const_get(:SyntaxError).new(
          path, line, column, parser.problem_offset,
          parser.problem && parser.problem.dup.force_encoding(Encoding::US_ASCII),
          parser.context && parser.context.dup.force_encoding(Encoding::US_ASCII)
        )
      end
    end
  end

  # Reads a YAML stream and calls the handler for every event in it.
  class Parser
    # Any encoding: let the parser choose the encoding
    ANY = LibYAML::ANY_ENCODING
    # UTF-8 encoding
    UTF8 = LibYAML::UTF8_ENCODING
    # UTF-16-LE encoding with BOM
    UTF16LE = LibYAML::UTF16LE_ENCODING
    # UTF-16-BE encoding with BOM
    UTF16BE = LibYAML::UTF16BE_ENCODING

    # Returns a Psych::Parser::Mark object that contains line, column, and
    # index information.
    def mark
      mark = LibYAML::Glue.native_parser(self).current_mark
      Psych::Parser.const_get(:Mark, false).new(mark.index, mark.line, mark.column)
    end

    private

    # psych_parser.c's parse: run libyaml over `yaml` and call `handler`
    # with every event, each one after an event_location call. A handler
    # cannot parse again with the same parser while it runs.
    def _native_parse(handler, yaml, path)
      if Primitive.zr_hidden_get(self, :__parsing__)
        raise Psych::Exception, "parser is already parsing, it cannot be reused from a handler callback"
      end

      Primitive.zr_state_set(self, :__parsing__, true)
      begin
        parse_events(handler, yaml, path)
      ensure
        Primitive.zr_state_set(self, :__parsing__, nil)
      end
    end

    def parse_events(handler, yaml, path)
      glue = LibYAML::Glue
      parser = glue.reset_native_parser(self)
      internal = Encoding.default_internal

      if yaml.respond_to?(:read)
        encoding = glue.transcode_io(yaml)
        parser.set_encoding(encoding)
        parser.set_input { |size| glue.read_io(yaml, size) }
      else
        yaml = glue.string_value(yaml)
        yaml, encoding = glue.transcode_string(yaml)
        parser.set_encoding(encoding)
        parser.set_input_string(yaml)
      end

      loop do
        event = parser.error == LibYAML::NO_ERROR ? parser.parse : nil
        if event.nil?
          exception = glue.make_exception(parser, path)
          glue.reset_native_parser(self)
          raise exception
        end

        state = glue.protect do
          handler.event_location(event.start_mark.line, event.start_mark.column,
                                 event.end_mark.line, event.end_mark.column)
        end
        raise state if state

        done = false
        case event.type
        when LibYAML::STREAM_START_EVENT
          state = glue.protect { handler.start_stream(event.encoding) }
        when LibYAML::DOCUMENT_START_EVENT
          version = event.version_directive ? [event.version_directive.major, event.version_directive.minor] : []
          tag_directives = event.tag_directives.map do |tag_directive|
            [glue.ruby_string(tag_directive.handle, internal), glue.ruby_string(tag_directive.prefix, internal)]
          end
          state = glue.protect { handler.start_document(version, tag_directives, event.implicit) }
        when LibYAML::DOCUMENT_END_EVENT
          state = glue.protect { handler.end_document(event.implicit) }
        when LibYAML::ALIAS_EVENT
          anchor = event.anchor && glue.ruby_string(event.anchor, internal)
          state = glue.protect { handler.alias(anchor) }
        when LibYAML::SCALAR_EVENT
          value = glue.ruby_string(event.value, internal)
          anchor = event.anchor && glue.ruby_string(event.anchor, internal)
          tag = event.tag && glue.ruby_string(event.tag, internal)
          state = glue.protect do
            handler.scalar(value, anchor, tag, event.plain_implicit, event.quoted_implicit, event.style)
          end
        when LibYAML::SEQUENCE_START_EVENT
          anchor = event.anchor && glue.ruby_string(event.anchor, internal)
          tag = event.tag && glue.ruby_string(event.tag, internal)
          state = glue.protect { handler.start_sequence(anchor, tag, event.implicit, event.style) }
        when LibYAML::SEQUENCE_END_EVENT
          state = glue.protect { handler.end_sequence }
        when LibYAML::MAPPING_START_EVENT
          anchor = event.anchor && glue.ruby_string(event.anchor, internal)
          tag = event.tag && glue.ruby_string(event.tag, internal)
          state = glue.protect { handler.start_mapping(anchor, tag, event.implicit, event.style) }
        when LibYAML::MAPPING_END_EVENT
          state = glue.protect { handler.end_mapping }
        when LibYAML::NO_EVENT
          # Past the stream's end, libyaml gives no event: the parse stops.
          state = glue.protect { handler.empty }
          done = true
        when LibYAML::STREAM_END_EVENT
          state = glue.protect { handler.end_stream }
          done = true
        end
        raise state if state
        break if done
      end

      self
    end
  end

  # Writes the events a handler is given back out as YAML text, through
  # libyaml's emitter.
  class Emitter < Handler
    # Create a new Psych::Emitter that writes to +io+.
    def initialize(*args)
      unless args.size.between?(1, 2)
        raise ArgumentError, wrong_arity(args.size, 1..2)
      end

      glue = LibYAML::Glue
      emitter = glue.native_emitter(self)
      io, options = args

      if args.size == 2
        line_width = options.line_width
        indent = options.indentation
        canonical = options.canonical

        emitter.set_width(glue.num2int(line_width))
        emitter.set_indent(glue.num2int(indent))
        emitter.set_canonical(canonical == true)
      end

      emitter.set_output do |buffer|
        wrote = io.write(buffer.dup.force_encoding(Encoding::UTF_8))
        glue.num2int(wrote) != 0
      end

      self
    end

    # Start a stream emission with +encoding+
    def start_stream(encoding)
      glue = LibYAML::Glue
      emitter = glue.native_emitter(self)
      glue.check_fixnum(encoding)

      glue.emit(emitter, LibYAML::Events.stream_start(glue.num2int(encoding)))

      self
    end

    # End a stream emission
    def end_stream
      glue = LibYAML::Glue
      glue.emit(glue.native_emitter(self), LibYAML::Events.stream_end)

      self
    end

    # Start a document emission with YAML +version+, +tags+, and an
    # +implicit+ start.
    def start_document(version, tags, imp)
      glue = LibYAML::Glue
      emitter = glue.native_emitter(self)

      glue.check_array(version)

      version_directive = nil
      unless version.empty?
        version_directive = LibYAML::VersionDirective.new(glue.num2int(version[0]), glue.num2int(version[1]))
      end

      tag_directives = []
      if tags
        glue.check_array(tags)

        tags.each do |tuple|
          glue.check_array(tuple)

          raise RuntimeError, "tag tuple must be of length 2" if tuple.size < 2

          name = glue.string_value(tuple[0])
          value = glue.string_value(tuple[1])
          name = glue.export_to_encoding(name, Encoding::UTF_8)
          value = glue.export_to_encoding(value, Encoding::UTF_8)

          tag_directives.push(LibYAML::TagDirective.new(glue.c_string_value(name).b, glue.c_string_value(value).b))
        end
      end

      event = LibYAML::Events.document_start(version_directive, tag_directives, glue.c_truth(imp))
      glue.emit(emitter, event)

      self
    end

    # End a document emission with an +implicit+ ending.
    def end_document(imp)
      glue = LibYAML::Glue
      glue.emit(glue.native_emitter(self), LibYAML::Events.document_end(glue.c_truth(imp)))

      self
    end

    # Emit a scalar with +value+, +anchor+, +tag+, and a +plain+ or
    # +quoted+ string type with +style+.
    def scalar(value, anchor, tag, plain, quoted, style)
      glue = LibYAML::Glue
      emitter = glue.native_emitter(self)

      glue.check_string(value)

      value = glue.export_to_encoding(value, Encoding::UTF_8)

      unless anchor.nil?
        glue.check_string(anchor)
        anchor = glue.export_to_encoding(anchor, Encoding::UTF_8)
      end

      unless tag.nil?
        glue.check_string(tag)
        tag = glue.export_to_encoding(tag, Encoding::UTF_8)
      end

      event = LibYAML::Events.scalar(
        anchor.nil? ? nil : glue.c_string_value(anchor).b,
        tag.nil? ? nil : glue.c_string_value(tag).b,
        value.b,
        glue.c_truth(plain),
        glue.c_truth(quoted),
        glue.num2int(style)
      )
      glue.emit(emitter, event)

      self
    end

    # Start emitting a sequence with +anchor+, a +tag+, +implicit+
    # sequence start and end, along with +style+.
    def start_sequence(anchor, tag, implicit, style)
      glue = LibYAML::Glue
      anchor, tag = glue.anchor_and_tag(anchor, tag)
      emitter = glue.native_emitter(self)

      event = LibYAML::Events.sequence_start(anchor, tag, glue.c_truth(implicit), glue.num2int(style))
      glue.emit(emitter, event)

      self
    end

    # End sequence emission.
    def end_sequence
      glue = LibYAML::Glue
      glue.emit(glue.native_emitter(self), LibYAML::Events.sequence_end)

      self
    end

    # Start emitting a YAML map with +anchor+, +tag+, an +implicit+ start
    # and end, and +style+.
    def start_mapping(anchor, tag, implicit, style)
      glue = LibYAML::Glue
      emitter = glue.native_emitter(self)
      anchor, tag = glue.anchor_and_tag(anchor, tag)

      event = LibYAML::Events.mapping_start(anchor, tag, glue.c_truth(implicit), glue.num2int(style))
      glue.emit(emitter, event)

      self
    end

    # Emit the end of a mapping.
    def end_mapping
      glue = LibYAML::Glue
      glue.emit(glue.native_emitter(self), LibYAML::Events.mapping_end)

      self
    end

    # Emit an alias with +anchor+.
    def alias(anchor)
      glue = LibYAML::Glue
      emitter = glue.native_emitter(self)

      unless anchor.nil?
        glue.check_string(anchor)
        anchor = glue.export_to_encoding(anchor, Encoding::UTF_8)
      end

      event = anchor.nil? ? nil : LibYAML::Events.alias(glue.c_string_value(anchor).b)
      glue.emit(emitter, event)

      self
    end

    # Set the output style to canonical, or not.
    def canonical=(style)
      LibYAML::Glue.native_emitter(self).set_canonical(style == true)
      style
    end

    # Get the output style, canonical or not.
    def canonical = LibYAML::Glue.native_emitter(self).canonical

    # Set the indentation level to +level+. The level must be less than 10
    # and greater than 1.
    def indentation=(level)
      LibYAML::Glue.native_emitter(self).set_indent(LibYAML::Glue.num2int(level))
      level
    end

    # Get the indentation level.
    def indentation = LibYAML::Glue.native_emitter(self).best_indent

    # Get the preferred line width.
    def line_width = LibYAML::Glue.native_emitter(self).best_width

    # Set the preferred line with to +width+.
    def line_width=(width)
      LibYAML::Glue.native_emitter(self).set_width(LibYAML::Glue.num2int(width))
      width
    end
  end

  module LibYAML
    module Glue
      module_function

      # The libyaml parser behind a Psych::Parser. CRuby keeps it in the
      # object's typed data; here it lives in an instance variable, which
      # these two methods alone touch.
      def native_parser(owner)
        Primitive.zr_hidden_get(owner, :__libyaml_parser) || reset_native_parser(owner)
      end

      # yaml_parser_delete and yaml_parser_initialize
      def reset_native_parser(owner)
        Primitive.zr_hidden_set(owner, :__libyaml_parser, Parser.new)
      end

      # The libyaml emitter behind a Psych::Emitter, set up as psych's
      # allocator sets it up: unicode on, an indentation of 2.
      def native_emitter(owner)
        emitter = Primitive.zr_hidden_get(owner, :__libyaml_emitter)
        return emitter if emitter

        emitter = Emitter.new
        emitter.set_unicode(true)
        emitter.set_indent(2)
        Primitive.zr_hidden_set(owner, :__libyaml_emitter, emitter)
      end

      # psych_emitter.c's emit. An event that libyaml refused to build
      # (its strings were not UTF-8) reaches the emitter zeroed, as the
      # uninitialized event does in C.
      def emit(emitter, event)
        return if emitter.emit(event || Event.new(NO_EVENT, ZERO_MARK, ZERO_MARK))

        raise RuntimeError, emitter.problem.to_s
      end

      # The anchor and tag checks of start_sequence and start_mapping.
      def anchor_and_tag(anchor, tag)
        unless anchor.nil?
          check_string(anchor)
          anchor = export_to_encoding(anchor, Encoding::UTF_8)
        end

        unless tag.nil?
          check_string(tag)
          tag = export_to_encoding(tag, Encoding::UTF_8)
        end

        [anchor.nil? ? nil : c_string_value(anchor).b, tag.nil? ? nil : c_string_value(tag).b]
      end
    end
  end

  private_constant :LibYAML
end
