# frozen_string_literal: true

# json's parser.c, in ruby: JSON::Ext::ParserConfig, the one-shot
# JSON::Ext::Parser.parse, and the walk both run. The walk is parser.c's
# own: an explicit stack of the containers still open, a phase for what
# the innermost one expects next, and the same error at the same byte.
require "json/common"

module JSON
  module Ext
    class ParserConfig
      # parser.c's JSON_ParserConfig, out of the program's sight as the C
      # struct is.
      Fields = Struct.new(:on_load_proc, :decimal_class, :decimal_method, :on_duplicate_key, :on_comment, :max_nesting,
                          :allow_nan, :allow_trailing_comma, :allow_control_characters, :allow_invalid_escape,
                          :symbolize_names, :freeze)
      private_constant :Fields

      def self.fields_for(opts, strict: false)
        Primitive.attr! :hidden
        fields = Fields.new(nil, nil, nil, :deprecated, :deprecated, 100, false, false, false, false, false, false)
        return fields if opts.nil?
        raise TypeError, "wrong argument type #{conversion_name(opts)} (expected Hash)" unless opts.is_a?(Hash)

        unknown = []
        Primitive.zr_hash_foreach(opts) do |key, val|
          case key
          when :max_nesting then fields.max_nesting = val ? Primitive.zr_index_operand_m(val) : 0
          when :allow_nan then fields.allow_nan = val ? true : false
          when :allow_trailing_comma then fields.allow_trailing_comma = val ? true : false
          when :allow_comments then fields.on_comment = val ? :ignore : :raise
          when :allow_control_characters then fields.allow_control_characters = val ? true : false
          when :allow_invalid_escape then fields.allow_invalid_escape = val ? true : false
          when :symbolize_names then fields.symbolize_names = val ? true : false
          when :freeze then fields.freeze = val ? true : false
          when :on_load then fields.on_load_proc = val || nil
          when :allow_duplicate_key then fields.on_duplicate_key = val ? :ignore : :raise
          when :decimal_class then decimal(fields, val) if val
          else unknown << key if strict
          end
        end
        return fields if unknown.empty?
        raise ArgumentError, "unknown keyword: #{unknown[0].inspect}" if unknown.size == 1

        raise ArgumentError, "unknown keywords: #{unknown.map(&:inspect).join(', ')}"
      end

      # A decimal class converts a number's text through try_convert, new,
      # or the method that its own name spells.
      def self.decimal(fields, val)
        Primitive.attr! :hidden
        if val.respond_to?(:try_convert)
          fields.decimal_class = val
          fields.decimal_method = :try_convert
        elsif val.respond_to?(:new)
          fields.decimal_class = val
          fields.decimal_method = :new
        elsif val.is_a?(Class)
          name = val.name
          if (at = name.rindex(":"))
            fields.decimal_class = Object.const_get(name[0, at - 1])
            fields.decimal_method = name[(at + 1)..].to_sym
          else
            fields.decimal_class = Kernel
            fields.decimal_method = name.to_sym
          end
        end
      end
      private_class_method :fields_for, :decimal

      def parse(source) = Walk.new(fields, source).run

      private

      def initialize(opts)
        Primitive.zr_frozen_error(self) if frozen?
        Primitive.zr_state_set(self, :__fields__, ParserConfig.send(:fields_for, opts))
        self
      end

      def fields
        Primitive.attr! :hidden
        Primitive.zr_hidden_get(self, :__fields__) || ParserConfig.send(:fields_for, nil)
      end
    end

    class Parser
      def self.parse(source, opts) = Walk.new(ParserConfig.send(:fields_for, opts), source).run
    end

    # cParser_parse and json_parse_any over one source: the C half's
    # work, with no method or backtrace row a program sees.
    class Walk
      Primitive.attr! :hidden

      ARRAY = 1
      OBJECT = 2
      # The phases a frame goes through. The first three equal the frame
      # types, as a completed value moves its frame to the phase its type
      # names.
      DONE = 0
      ARRAY_COMMA = 1
      OBJECT_COMMA = 2
      VALUE = 3
      OBJECT_KEY = 4
      OBJECT_COLON = 5
      MAX_DEPRECATIONS = 5
      COMMENT_DEPRECATION = "Encountered comment in JSON. This will raise an error in json 3.0 unless enabled via " \
                            "`allow_comments: true`"
      STRING_STOP = /["\\\x00-\x1f]/n
      ESCAPES = { 0x5c => "\\", 0x6e => "\n", 0x72 => "\r", 0x74 => "\t", 0x62 => "\b", 0x66 => "\f" }.freeze

      # A resumable walk starts with no source and takes it in pieces
      # (`feed`); where a piece ends inside a token, the walk stops before
      # that token and reads it again once more has come.
      def initialize(fields, source, resumable: false)
        @fields = fields
        @resumable = resumable
        @src = resumable ? +"".b : Walk.source_of(source)
        @size = @src.bytesize
        @cursor = 0
        @values = []
        @types = [DONE]
        @phases = [VALUE]
        @heads = [0]
        @starts = [0]
        @nesting = 0
        @deprecations = 0
      end

      # convert_encoding: the source as UTF-8 bytes; binary is read as
      # UTF-8, and another encoding converted.
      def self.source_of(source)
        text = Primitive.zr_str_operand(source)
        text = text.dup.force_encoding(Encoding::UTF_8) if text.encoding == Encoding::BINARY
        text = Primitive.zr_str_operand(text.encode(Encoding::UTF_8)) unless text.encoding == Encoding::UTF_8
        text = text.dup.freeze if text.equal?(source)
        text.b.freeze
      end


      def run
        unexpected_end("unexpected end of input") unless walk

        result = @values[-1]
        whitespace(true)
        syntax_error("unexpected token at end of stream %s") if @cursor < @size
        result
      end

      # --- the resumable walk: parser.c's ResumableParser -----------------

      # More source, after what the walk has not read yet.
      def feed(text)
        if @cursor.positive? && (@cursor >= @size || (@cursor > @size / 2 && @size >= 512))
          @src = @src.byteslice(@cursor, @size - @cursor)
          @cursor = 0
        end
        @src << Walk.source_of(text)
        @size = @src.bytesize
      end

      # One more document: true once one is done, false where the source
      # ends first. A document already done whose value was not taken
      # gives way to the next.
      def resume
        if @phases[-1] == DONE
          @values.pop
          @phases[-1] = VALUE
        end
        catch(:suspend) { return walk }
        false
      end

      def size_left = @size - @cursor

      def rest = @src.byteslice(@cursor, @size - @cursor).force_encoding(Encoding::UTF_8)
      def cursor = @cursor
      def eos? = @cursor >= @size

      # What is left once a document is done: the whitespace after it goes,
      # and a source read to its end is let go.
      def settle
        whitespace(false)
        return unless @cursor >= @size

        @src = +"".b
        @size = 0
        @cursor = 0
      end

      def value? = @phases[-1] == DONE && !@values.empty?
      def partial? = !@values.empty? && @phases[-1] != DONE

      # The value that is done, taken: the root has room for the next.
      def take
        raise ArgumentError, "no ready value" unless @phases[-1] == DONE && !@values.empty?

        @phases[-1] = VALUE
        @values.pop
      end

      # The document under construction at this point: each open container
      # closed on its contents, and an object's key without its value set
      # to nil.
      def partial
        return nil if @values.empty?

        values = @values.dup
        values << nil if @types[-1] == OBJECT && (@phases[-1] == VALUE || @phases[-1] == OBJECT_COLON)
        (@types.size - 1).downto(1) do |depth|
          items = values.pop(values.size - @heads[depth])
          value = if @types[depth] == ARRAY
                    items
                  else
                    items.each_slice(2).to_h
                  end
          value = @fields.on_load_proc.call(value) if @fields.on_load_proc
          values << value
        end
        values[-1]
      end

      private

      # The token at the cursor runs into the end of a resumable source: the
      # walk stops before it, to read it whole later.
      def suspend
        @cursor = @mark
        throw :suspend
      end

      def at_end? = @resumable && @cursor >= @size

      def peek = @src.getbyte(@cursor) || 0

      # json_parse_any: the frames' state machine, until the root value is
      # done. False when the source ends first.
      def walk
        phase = @phases[-1]
        loop do
          @mark = @cursor
          case phase
          when VALUE
            whitespace(true)
            if @fields.allow_trailing_comma && @types[-1] == ARRAY && peek == 0x5d
              phase = ARRAY_COMMA
              next
            end
            value = nil
            start = @cursor
            case peek
            when 0x6e then keyword("null")
            when 0x74 then value = keyword("true") && true
            when 0x66 then value = keyword("false") && false
            when 0x4e
              syntax_error("unexpected token %s") unless @fields.allow_nan
              keyword("NaN")
              value = JSON::NaN
            when 0x49
              syntax_error("unexpected token %s") unless @fields.allow_nan
              keyword("Infinity")
              value = JSON::Infinity
            when 0x2d
              @cursor += 1
              value = number(true, start)
              if value.equal?(Walk) && @fields.allow_nan && peek == 0x49
                @cursor = start
                keyword("-Infinity")
                value = JSON::MinusInfinity
              elsif value.equal?(Walk)
                syntax_error_at("invalid number: %s", start)
              end
            when 0x30..0x39
              value = number(false, start)
              syntax_error_at("invalid number: %s", start) if value.equal?(Walk)
            when 0x22
              value = string(false)
              raise_error("unexpected end of input, expected closing \"") if value.equal?(Walk)
            when 0x5b
              @cursor += 1
              whitespace(true)
              suspend if at_end?
              if peek == 0x5d
                @cursor += 1
                value = array(0)
              else
                enter(ARRAY, VALUE, 0)
                phase = VALUE
                next
              end
            when 0x7b
              @cursor += 1
              whitespace(true)
              suspend if at_end?
              if peek == 0x7d
                @cursor += 1
                value = object(0)
              else
                enter(OBJECT, OBJECT_KEY, start)
                phase = OBJECT_KEY
                next
              end
            when 0
              suspend if at_end?
              return false if @cursor >= @size

              syntax_error("unexpected NULL byte: %s")
            else
              syntax_error("unexpected character: %s")
            end
            push(value)
            phase = @phases[-1] = @types[-1]
            return true if phase == DONE
          when OBJECT_KEY
            whitespace(true)
            suspend if at_end?
            if @fields.allow_trailing_comma && peek == 0x7d
              phase = OBJECT_COMMA
              next
            end
            if peek == 0x22
              key = string(true)
              syntax_error("unexpected end of input, expected closing \"") if key.equal?(Walk)
              push(key)
              phase = @phases[-1] = OBJECT_COLON
            elsif @values.size - @heads[-1] == 0
              syntax_error("expected object key, got %s")
            else
              syntax_error("expected object key, got: %s")
            end
          when OBJECT_COLON
            whitespace(true)
            suspend if at_end?
            if peek == 0x3a
              @cursor += 1
              phase = @phases[-1] = VALUE
            elsif @values.size - @heads[-1] == 1
              syntax_error("expected ':' after object key")
            else
              syntax_error("expected ':' after object key, got: %s")
            end
          when ARRAY_COMMA
            whitespace(true)
            suspend if at_end?
            byte = peek
            if byte == 0x2c
              @cursor += 1
              phase = @phases[-1] = VALUE
            elsif byte == 0x5d
              @cursor += 1
              @nesting -= 1
              count = @values.size - @heads[-1]
              push(array(count))
              leave
              phase = @phases[-1] = @types[-1]
              return true if phase == DONE
            else
              syntax_error("expected ',' or ']' after array value")
            end
          when OBJECT_COMMA
            whitespace(true)
            suspend if at_end?
            byte = peek
            if byte == 0x2c
              @cursor += 1
              phase = @phases[-1] = OBJECT_KEY
            elsif byte == 0x7d
              @cursor += 1
              @nesting -= 1
              count = @values.size - @heads[-1]
              final = @cursor
              @cursor = @starts[-1]
              value = object(count)
              @cursor = final
              push(value)
              leave
              phase = @phases[-1] = @types[-1]
              return true if phase == DONE
            else
              syntax_error("expected ',' or '}' after object value, got: %s")
            end
          end
        end
      end

      def enter(type, phase, start)
        @nesting += 1
        max = @fields.max_nesting
        raise NestingError, "nesting of #{@nesting} is too deep" if max != 0 && max < @nesting

        @types << type
        @phases << phase
        @heads << @values.size
        @starts << start
      end

      def leave
        @types.pop
        @phases.pop
        @heads.pop
        @starts.pop
      end

      # json_push_value: each value, a key among them, through on_load.
      def push(value)
        value = @fields.on_load_proc.call(value) if @fields.on_load_proc
        @values << value
      end

      def array(count)
        array = count.zero? ? [] : @values.pop(count)
        @fields.freeze ? array.freeze : array
      end

      def object(count)
        object = {}
        pairs = count.zero? ? [] : @values.pop(count)
        i = 0
        while i < count
          object[pairs[i]] = pairs[i + 1]
          i += 2
        end
        duplicate_key(pairs) if object.size < count / 2
        @fields.freeze ? object.freeze : object
      end

      def duplicate_key(pairs)
        case @fields.on_duplicate_key
        when :deprecated
          return if @deprecations >= MAX_DEPRECATIONS

          @deprecations += 1
          warning("detected duplicate key #{duplicated(pairs).inspect} in JSON object. This will raise an error in json 3.0 unless " \
                  "enabled via `allow_duplicate_key: true`")
        when :raise
          line, column = position
          error = ParserError.new("duplicate key #{duplicated(pairs).inspect} at line #{line} column #{column}")
          error.instance_variable_set(:@line, line)
          error.instance_variable_set(:@column, column)
          raise error
        end
      end

      def duplicated(pairs)
        seen = {}
        (0...pairs.size).step(2) do |i|
          key = pairs[i]
          return key.is_a?(Symbol) ? key.name : key if seen.key?(key)

          seen[key] = true
        end
        false
      end

      def warning(message)
        return JSON.deprecation_warning(message) if @resumable

        line, column = position
        JSON.deprecation_warning("#{message} at line #{line} column #{column}")
      end

      # json_eat_whitespace, and a comment where the walk takes one.
      def whitespace(comments)
        loop do
          case @src.getbyte(@cursor)
          when 0x20, 0x0a, 0x09, 0x0d then @cursor += 1
          when 0x2f
            return unless comments

            comment
          else return
          end
        end
      end

      def comment
        syntax_error("unexpected token %s") if @fields.on_comment == :raise

        start = @cursor
        @cursor += 1
        case peek
        when 0x2f
          newline = @src.byteindex("\n", @cursor)
          # A resumable source may yet hold the newline.
          suspend if newline.nil? && @resumable
          @cursor = newline ? newline + 1 : @size
        when 0x2a
          @cursor += 1
          loop do
            star = @src.byteindex("*", @cursor)
            suspend if star.nil? && @resumable
            unexpected_end_at("unterminated comment, expected closing '*/'", start) unless star
            @cursor = star + 1
            if peek == 0x2f
              @cursor += 1
              break
            end
          end
        else
          suspend if at_end?
          syntax_error_at("unexpected token %s", start)
        end
        return unless @fields.on_comment == :deprecated && @deprecations < MAX_DEPRECATIONS

        @deprecations += 1
        warning(COMMENT_DEPRECATION)
      end

      def keyword(word)
        if @src.byteslice(@cursor, word.bytesize) == word
          @cursor += word.bytesize
          return true
        end
        suspend if @resumable && @size - @cursor < word.bytesize && word.b.start_with?(@src.byteslice(@cursor, @size - @cursor))
        syntax_error("unexpected token %s")
      end

      # json_parse_number: Walk where the text is no number.
      def number(negative, start)
        first = peek
        digits = digits_run
        suspend if at_end?
        return Walk if (first == 0x30 && digits > 1) || (negative && digits.zero?)

        integer = true
        if peek == 0x2e
          integer = false
          @cursor += 1
          suspend if at_end?
          return Walk if digits_run.zero?
        end
        if peek == 0x65 || peek == 0x45
          integer = false
          @cursor += 1
          @cursor += 1 if peek == 0x2d || peek == 0x2b
          suspend if at_end?
          return Walk if digits_run.zero?
        end
        # A number is done only once something follows it.
        suspend if at_end?
        text = @src.byteslice(start, @cursor - start)
        return text.to_i if integer
        return @fields.decimal_class.public_send(@fields.decimal_method, text) if @fields.decimal_class

        text.to_f
      end

      def digits_run
        from = @cursor
        @cursor += 1 while (byte = @src.getbyte(@cursor)) && byte >= 0x30 && byte <= 0x39
        @cursor - from
      end

      # json_parse_string: the string, a key interned, or Walk where the
      # source ends inside it.
      def string(name)
        @cursor += 1
        start = @cursor
        stop = @src.byteindex(STRING_STOP, @cursor)
        unless stop
          suspend if @resumable
          @cursor = @size
          return Walk
        end
        @cursor = stop
        if @src.getbyte(stop) == 0x22
          @cursor += 1
          return built(@src.byteslice(start, stop - start), name)
        end

        escaped_string(start, name)
      end

      def escaped_string(start, name)
        backslashes = []
        loop do
          case @src.getbyte(@cursor)
          when 0x22
            text = unescape(start, @cursor, backslashes)
            @cursor += 1
            return text.equal?(Walk) ? Walk : built(text, name)
          when 0x5c
            backslashes << @cursor
            @cursor += 1
          else
            syntax_error("invalid ASCII control character in string: %s") unless @fields.allow_control_characters
          end
          @cursor += 1
          stop = @cursor < @size && @src.byteindex(STRING_STOP, @cursor)
          unless stop
            suspend if @resumable
            @cursor = @size
            return Walk
          end
          @cursor = stop
        end
      end

      def built(bytes, name)
        text = bytes.force_encoding(Encoding::UTF_8)
        return text.to_sym if name && @fields.symbolize_names
        return -text if name || @fields.freeze

        text
      end

      # json_string_unescape over the bytes from `from` to `to`.
      def unescape(from, to, backslashes)
        out = "".b
        p = from
        backslashes.each do |at|
          next if at < p

          out << @src.byteslice(p, at - p) if at > p
          byte = @src.getbyte(at + 1)
          case byte
          when 0x22, 0x2f
            p = at + 1
          when 0x5c, 0x6e, 0x72, 0x74, 0x62, 0x66
            out << ESCAPES.fetch(byte)
            p = at + 2
          when 0x75
            code = unicode(at + 2, to)
            pe = at + 5
            if (code & 0xFC00) == 0xD800
              pe += 1
              syntax_error_at("incomplete surrogate pair at %s", p) unless pe <= to - 6 && @src.byteslice(pe, 2) == "\\u"

              low = unicode(pe + 2, to)
              syntax_error_at("invalid surrogate pair at %s", p) unless (low & 0xFC00) == 0xDC00
              code = ((code & 0x3F) << 10) | ((((code >> 6) & 0xF) + 1) << 16) | (low & 0x3FF)
              pe += 5
            end
            out << [code].pack("U").b
            p = pe + 1
          when 0, nil
            return Walk
          else
            if byte < 0x20 && !@fields.allow_control_characters
              syntax_error_at("Invalid unescaped newline character (\\n) in string: %s", at) if byte == 0x0a
              syntax_error_at("invalid ASCII control character in string: %s", at)
            end
            syntax_error_at("invalid escape character in string: %s", at) unless @fields.allow_invalid_escape

            out << byte
            p = at + 2
          end
        end
        out << @src.byteslice(p, to - p) if to > p
        out
      end

      def unicode(at, to)
        unexpected_end_at("incomplete unicode character escape sequence at %s", at - 2) if at > to - 4

        hex = @src.byteslice(at, 4)
        syntax_error_at("incomplete unicode character escape sequence at %s", at - 2) unless hex.match?(/\A\h{4}\z/n)

        hex.to_i(16)
      end

      def syntax_error(format) = raise_error(format)

      def syntax_error_at(format, at)
        @cursor = at
        raise_error(format)
      end

      def unexpected_end(format) = raise_error(format)

      def unexpected_end_at(format, at)
        @cursor = at
        raise_error(format)
      end

      # raise_parse_error: the message with up to 32 bytes of what stands
      # at the cursor, and the cursor's line and column.
      def raise_error(format)
        # parser.c keeps no lines across a resumable source's pieces.
        if @resumable
          error = ParserError.new(format.sub("%s") { fragment }.force_encoding(Encoding::UTF_8))
          error.instance_variable_set(:@line, 0)
          error.instance_variable_set(:@column, 0)
          raise error
        end
        line, column = position
        error = ParserError.new("#{format.sub('%s') { fragment }} at line #{line} column #{column}".force_encoding(Encoding::UTF_8))
        error.instance_variable_set(:@line, line)
        error.instance_variable_set(:@column, column)
        raise error
      end

      def fragment
        return "EOF" if @cursor >= @size

        len = 0
        while len < 32
          byte = @src.getbyte(@cursor + len)
          break if byte.nil? || byte == 0 || byte == 0x0a || byte == 0x20 || byte == 0x09 || byte == 0x0d

          len += 1
        end
        # Nothing to quote: the C format reads on to the next NUL byte.
        if len.zero?
          rest = @src.byteslice(@cursor, @size - @cursor)
          return rest[0, rest.index("\0") || rest.bytesize]
        end

        bytes = @src.byteslice(@cursor, len).bytes
        bytes.pop while !bytes.empty? && bytes[-1] >= 0x80 && bytes[-1] < 0xC0
        bytes.pop if !bytes.empty? && bytes[-1] >= 0xC0
        "'#{bytes.pack('C*')}'"
      end

      # cursor_position: the line counts every newline before the cursor,
      # and the column the bytes since the last one.
      def position
        newline = @src.byterindex("\n", @cursor)
        return [1, @cursor + 1] unless newline

        [2 + @src.byteslice(0, newline).count("\n"), @cursor - newline]
      end
    end
    private_constant :Walk
  end

  # parser.c's ResumableParser: a walk that takes its source in pieces
  # and hands out each document once it is whole.
  class ResumableParser
    def initialize(opts = nil)
      raise FrozenError, "can't modify frozen #{self.class}: #{inspect}" if frozen?

      @fields = Ext::ParserConfig.send(:fields_for, opts)
      clear
    end

    def <<(text)
      raise FrozenError, "can't modify frozen #{self.class}: #{inspect}" if frozen?
      raise ArgumentError, "ResumableParser can't be used recursively" if @in_use

      @walk.feed(text)
      self
    end

    def parse
      raise ArgumentError, "ResumableParser can't be used recursively" if @in_use

      if @complete
        @parsed_bytes = 0
        @incomplete_bytes = 0
      end
      @in_use = true
      from = @walk.cursor
      begin
        @complete = @walk.resume
      rescue ParserError
        @complete = true
        raise
      ensure
        @parsed_bytes += @walk.cursor - from unless @walk.cursor < from
        @incomplete_bytes = @complete ? 0 : @walk.send(:size_left)
        @walk.settle
        @in_use = false
      end
    end

    def value? = @walk.value?
    def value = @walk.take
    def partial_value = @walk.partial
    def partial_value? = @walk.partial?
    def rest = @walk.rest
    def eos? = @walk.eos?
    def parsed_bytes = @parsed_bytes + @incomplete_bytes

    def clear
      @walk = Ext.const_get(:Walk).new(@fields, nil, resumable: true)
      @complete = true
      @parsed_bytes = 0
      @incomplete_bytes = 0
      @in_use = false
      self
    end
  end
end
