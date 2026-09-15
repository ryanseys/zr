# One conversion, held open between the pieces of text it is given. A
# piece that ends inside a character keeps its tail until the next piece
# arrives, output that will not fit in the destination waits for room,
# and where a conversion stopped is answered in ruby's own words.
#
# The first line of this file must not spell the class's full name: ruby
# reads `coding:` inside it as a magic comment, and then looks for an
# encoding called Converter.
class Encoding
  class Converter
    CONVERTER_FLAGS.each { |name, value| const_set(name, value) }

    # The decorators in the order a description names them, and in the
    # order a conversion path lists them; a path spells two of them
    # differently. `lf_newline` writes the line ends this platform uses
    # already, so it changes nothing.
    SHOWN = %i[xml_text xml_attr_content xml_attr_quote universal_newline crlf_newline cr_newline lf_newline].freeze
    WALKED = %i[xml_text xml_attr_content xml_attr_quote crlf_newline cr_newline universal_newline lf_newline].freeze
    NAMES = {
      xml_text: "xml_text", xml_attr_content: "xml_attr_content", xml_attr_quote: "xml_attr_quote",
      universal_newline: "universal_newline", crlf_newline: "crlf_newline", cr_newline: "cr_newline",
      lf_newline: "lf_newline"
    }.freeze
    PATH_NAMES = NAMES.merge(xml_text: "xml_text_escape", xml_attr_content: "xml_attr_content_escape").freeze
    BITS = {
      xml_text: XML_TEXT_DECORATOR, xml_attr_content: XML_ATTR_CONTENT_DECORATOR,
      xml_attr_quote: XML_ATTR_QUOTE_DECORATOR, universal_newline: UNIVERSAL_NEWLINE_DECORATOR,
      crlf_newline: CRLF_NEWLINE_DECORATOR, cr_newline: CR_NEWLINE_DECORATOR, lf_newline: LF_NEWLINE_DECORATOR
    }.freeze
    MARKS = { 38 => "&amp;", 60 => "&lt;", 62 => "&gt;" }.freeze
    QUOTED = MARKS.merge(34 => "&quot;", 39 => "&apos;").freeze
    private_constant :SHOWN, :WALKED, :NAMES, :PATH_NAMES, :BITS, :MARKS, :QUOTED

    def initialize(source, destination, flags = nil, **options)
      raise TypeError, "already initialized" if defined?(@path)

      @flags = 0
      @decorators = []
      @replacement = nil
      read_options(flags, options)
      @source_name = Converter.send(:name_of, source)
      @destination_name = Converter.send(:name_of, destination)
      @path = if @source_name.empty? && @destination_name.empty?
                []
              else
                Encoding.send(:convpath_for, @source_name, @destination_name, description)
              end
      @source = @path.first
      @destination = @path.last
      # Ruby holds no converter from an encoding to itself, whatever the
      # decorators say. A decorator stands alone only where the two ends
      # are named by empty Strings, and then there is no path at all.
      if @source && @source.equal?(@destination)
        raise ConverterNotFoundError, "code converter not found (#{@source_name} to #{@destination_name}#{description})"
      end
      # A line end is one choice: ruby holds no converter that writes two
      # kinds of it.
      if (@decorators & %i[universal_newline crlf_newline cr_newline lf_newline]).size > 1
        raise ConverterNotFoundError, "code converter not found (#{@source_name} to #{@destination_name}#{description})"
      end

      @unit, @big, @points, @writer, @utf8_out, @jis = Encoding.send(:writing, @destination) if @destination
      @buffer = +"".b
      @held = +"".b
      @readagain = +"".b
      @rest = +"".b
      @errinfo = [:source_buffer_empty, nil, nil, nil, nil]
      @last_error = nil
      @finished = false
      @opened = false
      @carried_cr = false
      @jis_in = false
      # The set a stateful source reads in, which its escapes change.
      @reading = @source && Encoding.send(:stateful?, @source) ? :ascii : nil
    end

    # A name as rb_to_encoding reads it: an Encoding answers its own, and
    # anything else must be a String.
    def self.name_of(value)
      Primitive.attr! :hidden
      return value.name if value.is_a?(Encoding)

      Converter.send(:string_of, value)
    end

    def self.string_of(value)
      Primitive.attr! :hidden
      text = String.try_convert(value)
      raise TypeError, "no implicit conversion of #{conversion_name(value)} into String" if text.nil?

      text
    end
    private_class_method :name_of, :string_of

    def self.search_convpath(source, destination, flags = nil, **options)
      new(source, destination, flags, **options).convpath
    end

    # The encoding this one meets ASCII in, or nil where it is ASCII
    # compatible already, or no encoding at all.
    def self.asciicompat_encoding(name)
      found = ASCII_COMPAT[name.is_a?(Encoding) ? name.name : String.try_convert(name).to_s]
      found && Encoding.find(found)
    end

    def source_encoding = @source

    def destination_encoding = @destination

    def convpath
      @path.each_cons(2).to_a + WALKED.select { |name| @decorators.include?(name) }.map { |name| PATH_NAMES[name] }
    end

    def inspect = Primitive.zr_obj_form("#<#{self.class}: #{description(true)}>")

    def ==(other)
      return nil unless other.is_a?(Converter)

      other.source_encoding == @source && other.destination_encoding == @destination && other.send(:flags) == @flags
    end

    def primitive_errinfo = @errinfo.dup

    def last_error = @last_error

    def replacement
      @replacement ||= if @destination.nil? || @destination.name.start_with?("UTF-") then +"�"
                       else (+"?").force_encoding(Encoding::US_ASCII)
                       end
    end

    def replacement=(text)
      text = Converter.send(:string_of, text)
      begin
        written(text)
      rescue EncodingError
        raise UndefinedConversionError, "replacement character setup failed"
      end
      @replacement = text
    end

    # Every whole character of `text`, converted. What the text ends
    # inside waits for the next piece, as `:partial_input` asks.
    def convert(text)
      raise ArgumentError, "converter already finished" if @finished

      out = +"".b
      run(Converter.send(:string_of, text), out, nil, true)
      raise @last_error if @last_error && !@errinfo.first.equal?(:source_buffer_empty)

      out.force_encoding(@destination || Encoding::ASCII_8BIT)
    end

    # The last of the conversion: what the pieces left over make, and
    # whatever the destination needs at its end.
    def finish
      out = +"".b
      unless @finished
        run(nil, out, nil, false)
        @finished = true
        out << closing
        raise @last_error if @last_error && !@errinfo.first.equal?(:source_buffer_empty)
      end
      out.force_encoding(@destination || Encoding::ASCII_8BIT)
    end

    # The bytes a conversion stopped in front of, which is none until an
    # error leaves some.
    def putback(count = nil)
      taken = count.nil? ? @readagain : @readagain.byteslice(0, count)
      @readagain = @readagain.byteslice(taken.bytesize, @readagain.bytesize - taken.bytesize)
      taken.dup.force_encoding(@source || Encoding::ASCII_8BIT)
    end

    # Text written into the destination ahead of whatever comes next.
    def insert_output(text)
      @held << written(Converter.send(:string_of, text))
      nil
    end

    # One step of the conversion, with a destination the caller owns: how
    # far it got, in ruby's own words. Both Strings are changed in place,
    # as CRuby changes them.
    def primitive_convert(source, destination, offset = nil, size = nil, flags = nil, **options)
      raise ArgumentError, "negative output_byteoffset" if offset&.negative?
      raise ArgumentError, "output_byteoffset too big" if offset && offset > destination.bytesize
      raise ArgumentError, "negative output_bytesize" if size&.negative?

      destination.replace(destination.byteslice(0, offset)) if offset
      out = +"".b
      result = run(source && Converter.send(:string_of, source), out, size, bits_of(flags, options) & PARTIAL_INPUT != 0)
      source&.replace(@rest.dup.force_encoding(source.encoding))
      # The bytes join the destination as bytes: a destination already
      # tagged with the target encoding would refuse them.
      destination.force_encoding(Encoding::ASCII_8BIT)
      destination << out
      destination.force_encoding(@destination) if @destination
      result
    end

    private

    def flags
      Primitive.attr! :hidden
      @flags
    end

    def bits_of(flags, options)
      Primitive.attr! :hidden
      return flags if flags.is_a?(Integer)

      out = 0
      out |= PARTIAL_INPUT if options[:partial_input]
      out |= AFTER_OUTPUT if options[:after_output]
      out
    end

    def read_options(flags, options)
      Primitive.attr! :hidden
      options = flags.merge(options) if flags.is_a?(Hash)
      if flags.is_a?(Integer)
        @flags = flags
        BITS.each { |name, bit| @decorators << name if flags & bit != 0 }
        return
      end
      @replacement = options[:replace]
      @flags |= INVALID_REPLACE if options[:invalid] == :replace
      @flags |= UNDEF_REPLACE if options[:undef] == :replace
      case options[:xml]
      when nil then nil
      when :text then @decorators << :xml_text
      when :attr then @decorators.concat(%i[xml_attr_content xml_attr_quote])
      else raise ArgumentError, "unexpected value for xml option: #{options[:xml]}"
      end
      # An XML decorator writes a character reference where a character
      # has no place in the destination, rather than refusing it.
      @flags |= UNDEF_HEX_CHARREF if options[:xml]
      @decorators << :universal_newline if options[:universal_newline]
      @decorators << :crlf_newline if options[:crlf_newline]
      @decorators << :cr_newline if options[:cr_newline]
      @decorators << Encoding.send(:newline_decorator, options[:newline]) if options[:newline]
      @decorators.uniq!
      @decorators.each { |name| @flags |= BITS[name] }
    end

    # What `inspect`, and a failure to find a converter, call this
    # conversion: its two ends and then its decorators, or the decorators
    # alone where there is no conversion at all.
    def description(whole = false)
      Primitive.attr! :hidden
      shown = SHOWN.select { |name| @decorators.include?(name) }.map { |name| NAMES[name] }.join(",")
      return shown.empty? ? "" : " with #{shown}" unless whole
      return shown.empty? ? "no-conversion" : shown if @path.empty?

      "#{@source.name} to #{@destination.name}#{shown.empty? ? '' : " with #{shown}"}"
    end

    # The conversion itself: the pieces held over and `text`, into `out`,
    # with at most `room` bytes of it. Output made past that room waits
    # inside the converter, as CRuby's own buffer holds it.
    def run(text, out, room, partial)
      Primitive.attr! :hidden
      @rest = +"".b
      return :destination_buffer_full unless drain(out, room)

      bytes = @buffer + (text ? text.b : +"".b)
      @buffer = +"".b
      tagged = @source ? bytes.dup.force_encoding(@source) : bytes
      at = 0
      while at < bytes.bytesize
        if @reading
          width = stateful_width(bytes, at)
          return held_tail(bytes, at, partial, out, room) if width.nil?
          return broken(bytes, at, 1) if width.zero?
          if bytes.getbyte(at) == 0x1B
            at += width
            next
          end

          piece = stateful_piece(bytes, at, width)
          return broken(bytes, at, width) if piece.nil?
        else
          width = @source ? Primitive.zr_str_char_len_at_m(tagged, at) : 1
          # The piece carries the source's encoding, so its own code point
          # is what the step reads. Sliced out of the plain bytes it would
          # answer its first byte instead.
          piece = tagged.byteslice(at, width)
        end
        if @source && !@reading && !piece.valid_encoding?
          if Encoding.send(:incomplete_tail?, bytes, at, @source)
            return held_tail(bytes, at, partial, out, room)
          end

          return broken(bytes, at, width) unless @flags & INVALID_REPLACE != 0

          made = written(replacement)
        else
          made = made_of(piece)
          if made.is_a?(Symbol)
            # A character the step cannot write is read all the same, so
            # the source keeps what follows it, as CRuby leaves it.
            @rest = bytes.byteslice(at + width, bytes.bytesize - at - width) if made == :undefined_conversion
            return made
          end
        end
        at += width
        if room && out.bytesize + made.bytesize > room
          @held << made
          @rest = bytes.byteslice(at, bytes.bytesize - at)
          return :destination_buffer_full
        end
        out << made
        next unless @flags & AFTER_OUTPUT != 0 && !made.empty?

        @rest = bytes.byteslice(at, bytes.bytesize - at)
        return :after_output
      end
      @errinfo = [partial ? :source_buffer_empty : :finished, nil, nil, nil, nil]
      @errinfo.first
    end

    # How many bytes a stateful source's next piece holds: an escape,
    # which sets the set the bytes after it read in, or one character of
    # that set. nil where the text ends inside one, 0 for an escape the
    # encoding has no set for.
    def stateful_width(bytes, at)
      Primitive.attr! :hidden
      if bytes.getbyte(at) == 0x1B
        return nil if bytes.bytesize - at < 3

        mode = ESCAPES[bytes.byteslice(at, 3)]
        return 0 if mode.nil?

        @reading = mode
        return 3
      end
      width = %i[kanji old_kanji].include?(@reading) ? 2 : 1
      bytes.bytesize - at < width ? nil : width
    end

    # One character of a stateful source, as that source spells it alone:
    # behind the escape of the set it reads in.
    def stateful_piece(bytes, at, width)
      Primitive.attr! :hidden
      shift = @reading == :old_kanji ? "\e$@" : SHIFTS.fetch(@reading)
      text = (@reading == :ascii ? bytes.byteslice(at, width) : shift + bytes.byteslice(at, width)).force_encoding(@source)
      Encoding.send(:convert, text, Encoding::UTF_8, {})
    rescue InvalidByteSequenceError
      nil
    end

    # What waits inside the converter, into `out` as far as there is room
    # for it. False where some of it still waits.
    def drain(out, room)
      Primitive.attr! :hidden
      return true if @held.empty?

      taken = room ? [[room - out.bytesize, 0].max, @held.bytesize].min : @held.bytesize
      out << @held.byteslice(0, taken)
      @held = @held.byteslice(taken, @held.bytesize - taken)
      @held.empty?
    end

    # A character the text ends inside: held back where more is coming,
    # else an error, or the replacement where the caller asked for one.
    def held_tail(bytes, at, partial, out, room)
      Primitive.attr! :hidden
      tail = bytes.byteslice(at, bytes.bytesize - at)
      if partial
        @buffer = tail
        @errinfo = [:source_buffer_empty, nil, nil, nil, nil]
        return :source_buffer_empty
      end
      return stop(:incomplete_input, incomplete_error(tail), tail) unless @flags & INVALID_REPLACE != 0

      # The replacement stands for the broken tail, and reaches the
      # destination through the same buffer every other piece does.
      @held << written(replacement)
      @errinfo = [:finished, nil, nil, nil, nil]
      return :destination_buffer_full unless drain(out, room)

      :finished
    end

    def broken(bytes, at, width)
      Primitive.attr! :hidden
      error = bytes.byteslice(at, width)
      @rest = bytes.byteslice(at + width, bytes.bytesize - at - width)
      stop(:invalid_byte_sequence, invalid_error(error), error)
    end

    def incomplete_error(tail)
      Primitive.attr! :hidden
      Encoding.send(:byte_error, "incomplete #{tail.dump} on #{@source_name}", @source, @destination, tail, nil, true)
    end

    def invalid_error(error)
      Primitive.attr! :hidden
      Encoding.send(:byte_error, "#{error.dump} on #{@source_name}", @source, @destination, error, +"".b, false)
    end

    def stop(symbol, error, bytes)
      Primitive.attr! :hidden
      @errinfo = [symbol, @source_name, @destination_name, bytes.b, +"".b]
      @last_error = error
      symbol
    end

    # One character's bytes in the destination, after the decorators have
    # had their say. A Symbol answers instead where the conversion stops.
    def made_of(piece)
      Primitive.attr! :hidden
      point = code_of(piece)
      return point if point.is_a?(Symbol)

      out = +"".b
      points(point).each do |code|
        bytes = bytes_for(code)
        if bytes.nil?
          bytes = missing(code)
          return bytes if bytes.is_a?(Symbol)
        end
        out << bytes
      end
      out
    end

    # The code point of one character of the source.
    def code_of(piece)
      Primitive.attr! :hidden
      return piece.getbyte(0) if @source.nil?
      return piece.ord if @reading
      return piece.ord if @source.equal?(Encoding::UTF_8) || Encoding.send(:utf8_like?, @source)

      Encoding.send(:convert, piece, Encoding::UTF_8, {}).ord
    rescue UndefinedConversionError
      @rest = +"".b
      stop(:undefined_conversion,
           Encoding.send(:char_error, "#{piece.dump} from #{@source_name} to #{@destination_name}", @source, @destination, piece),
           piece)
    end

    # The code points one character becomes: the line ends the decorators
    # ask for, and the markup an XML decorator writes.
    def points(point)
      Primitive.attr! :hidden
      out = []
      if @carried_cr
        @carried_cr = false
        out << 10 unless point == 10
      end
      if @decorators.include?(:universal_newline) && point == 13
        @carried_cr = true
        return out
      end
      shape = if @decorators.include?(:crlf_newline) && point == 10 then [13, 10]
              elsif @decorators.include?(:cr_newline) && point == 10 then [13]
              else [point]
              end
      marks = if @decorators.include?(:xml_attr_content) then QUOTED
              elsif @decorators.include?(:xml_text) then MARKS
              end
      if @decorators.include?(:xml_attr_quote) && !@opened
        @opened = true
        out << 34
      end
      shape.each do |code|
        if marks && (text = marks[code])
          out.concat(text.each_char.map(&:ord))
        else
          out << code
        end
      end
      out
    end

    # One code point's bytes in the destination, or nil where it has none.
    def bytes_for(point)
      Primitive.attr! :hidden
      return point.chr(Encoding::UTF_8).b if @utf8_out
      return jis_bytes_for(point) if @jis

      found = Encoding.send(:point_bytes, point, @unit, @big, @points, @writer)
      found&.pack("C*")
    end

    # ISO-2022-JP holds a state: an escape says that what follows is
    # two-byte, and another says the text is back in ASCII.
    def jis_bytes_for(point)
      Primitive.attr! :hidden
      out = +"".b
      if point < 128
        out << "\e(B" if @jis_in
        @jis_in = false
        return out << point.chr
      end
      bytes = Encoding.send(:jis_bytes, point)
      return nil if bytes.nil?

      out << "\e$B" unless @jis_in
      @jis_in = true
      out << bytes
    end

    # A code point the destination has no place for: a character
    # reference where an XML decorator asked for one, the replacement
    # where the caller did, else ruby's own refusal.
    def missing(point)
      Primitive.attr! :hidden
      shown = "U+#{format('%04X', point)}"
      if @flags & UNDEF_MASK == UNDEF_HEX_CHARREF
        text = +""
        "&##{format('x%X', point)};".each_char { |char| text << char }
        return written(text)
      end
      return written(replacement) if @flags & UNDEF_REPLACE != 0

      @rest = +"".b
      stop(:undefined_conversion,
           Encoding.send(:char_error, "#{shown} from #{@source_name} to #{@destination_name}", @source, @destination,
                         point.chr(Encoding::UTF_8)),
           point.chr(Encoding::UTF_8))
    end

    # `text` in the destination's own bytes.
    def written(text)
      Primitive.attr! :hidden
      return text.b if @destination.nil?

      Encoding.send(:convert, text, @destination, {}).b
    end

    # What the destination needs once nothing more is coming.
    def closing
      Primitive.attr! :hidden
      out = +"".b
      out << 10 if @carried_cr
      @carried_cr = false
      out << written(+"\"") if @decorators.include?(:xml_attr_quote) && @opened
      if @jis_in
        out << "\e(B"
        @jis_in = false
      end
      out
    end
  end
end
