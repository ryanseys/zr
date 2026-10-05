# frozen_string_literal: true

# One conversion, kept open between the pieces of text it is given. A
# piece that ends inside a character keeps its tail until the next piece
# arrives. Output that does not fit in the destination waits for room.
# Where a conversion stopped is reported in ruby's own words.
#
# The first line of this file must not spell the class's full name: ruby
# reads `coding:` inside it as a magic comment, and then looks for an
# encoding called Converter.
class Encoding
  class Converter
    CONVERTER_FLAGS.each { |name, value| const_set(name, value) }

    # The decorators in the order that a description gives them, and in
    # the order that a conversion path lists them; a path spells two of
    # them differently. `lf_newline` writes the line ends that this
    # platform already uses, so it changes nothing.
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
      raise TypeError, +"already initialized" if defined?(@path)

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
      # Ruby has no converter from an encoding to itself, whatever the
      # decorators say. A decorator is used alone only when the two ends
      # are empty Strings, and then there is no path at all.
      if @source && @source.equal?(@destination)
        raise ConverterNotFoundError, "code converter not found (#{@source_name} to #{@destination_name}#{description})"
      end
      # A line end is one choice: ruby has no converter that writes two
      # kinds of it.
      if (@decorators & %i[universal_newline crlf_newline cr_newline lf_newline]).size > 1
        raise ConverterNotFoundError, "code converter not found (#{@source_name} to #{@destination_name}#{description})"
      end

      @unit, @big, @points, @writer, @utf8_out, @jis = Encoding.send(:writing, @destination) if @destination
      # UTF-16 and UTF-32 write big-endian after a byte order mark, which
      # comes once, before the first character.
      @bom = @destination && %w[UTF-16 UTF-32].include?(@destination.name)
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

    # A name as rb_to_encoding reads it: an Encoding gives its own name,
    # and any other object must be a String.
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
      Array.new([@path.size - 1, 0].max) { |i| [@path[i], @path[i + 1]] } + WALKED.select { |name| @decorators.include?(name) }.map { |name| PATH_NAMES[name] }
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
        raise UndefinedConversionError, +"replacement character setup failed"
      end
      @replacement = text
    end

    # Every whole character of `text`, converted. A character that the
    # text ends inside waits for the next piece, as `:partial_input` requests.
    def convert(text)
      raise ArgumentError, +"converter already finished" if @finished

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
      # econv_primitive_convert: the offset and the size are C longs.
      offset = Primitive.zr_index_operand_m(offset) unless offset.nil?
      size = Primitive.zr_index_operand_m(size) unless size.nil?
      raise ArgumentError, +"negative output_byteoffset" if offset&.negative?
      raise ArgumentError, +"output_byteoffset too big" if offset && offset > destination.bytesize
      raise ArgumentError, +"negative output_bytesize" if size&.negative?

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
      # econv_opts: the replacement converts with to_str, once, before the
      # options are checked.
      options = options.merge(replace: Primitive.zr_str_operand(options[:replace])) unless options[:replace].nil? || options[:replace].is_a?(String)
      Encoding.send(:check_options, options)
      @replacement = options[:replace]
      @flags |= INVALID_REPLACE if options[:invalid] == :replace
      @flags |= UNDEF_REPLACE if options[:undef] == :replace
      case options[:xml]
      when :text then @decorators << :xml_text
      when :attr then @decorators.concat(%i[xml_attr_content xml_attr_quote])
      end
      # An XML decorator writes a character reference where a character
      # has no place in the destination, rather than refusing it.
      @flags |= UNDEF_HEX_CHARREF if options[:xml]
      @decorators.concat(Encoding.send(:newline_decorators, options))
      @decorators.uniq!
      @decorators.each { |name| @flags |= BITS[name] }
    end

    # What `inspect`, and a failure to find a converter, call this
    # conversion: its two ends and then its decorators, or the decorators
    # alone where there is no conversion at all.
    def description(whole = false)
      Primitive.attr! :hidden
      shown = SHOWN.select { |name| @decorators.include?(name) }.map { |name| NAMES[name] }.join(",")
      return shown.empty? ? +"" : " with #{shown}" unless whole
      return shown.empty? ? +"no-conversion" : shown if @path.empty?

      "#{@source.name} to #{@destination.name}#{shown.empty? ? '' : " with #{shown}"}"
    end

    # The conversion itself: the kept pieces and `text`, into `out`,
    # with at most `room` bytes of it. Output made past that room waits
    # inside the converter, as in CRuby's own buffer.
    def run(text, out, room, partial)
      Primitive.attr! :hidden
      @rest = +"".b
      # Each step reports its own end: a step that ends well clears the
      # error of the one before it, as ruby keeps only the last result.
      @last_error = nil
      @errinfo = [:destination_buffer_full, nil, nil, nil, nil]
      return :destination_buffer_full unless drain(out, room)

      # The bytes that an error left to read again come first.
      bytes = @buffer + @readagain + (text ? text.b : +"".b)
      @buffer = +"".b
      @readagain = +"".b
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
          # The piece has the source's encoding, so the step reads its own
          # code point. If it were sliced out of the plain bytes, it would
          # give its first byte instead.
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
        @errinfo = [:after_output, nil, nil, nil, nil]
        return :after_output
      end
      @errinfo = [partial ? :source_buffer_empty : :finished, nil, nil, nil, nil]
      @errinfo.first
    end

    # How many bytes are in a stateful source's next piece: an escape,
    # which selects the set for the bytes after it, or one character of
    # that set. nil when the text ends inside one, 0 for an escape that
    # the encoding has no set for.
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

    # A character that the text ends inside: kept back when more is
    # coming, else an error, or the replacement if the caller asked for one.
    def held_tail(bytes, at, partial, out, room)
      Primitive.attr! :hidden
      tail = bytes.byteslice(at, bytes.bytesize - at)
      if partial
        @buffer = tail
        @errinfo = [:source_buffer_empty, nil, nil, nil, nil]
        return :source_buffer_empty
      end
      return stop(:incomplete_input, incomplete_error(tail), tail) unless @flags & INVALID_REPLACE != 0

      # The replacement is in place of the broken tail, and goes to the
      # destination through the same buffer as every other piece.
      @held << written(replacement)
      @errinfo = [:finished, nil, nil, nil, nil]
      return :destination_buffer_full unless drain(out, room)

      :finished
    end

    # A character that is broken where it stands: the transcoder takes
    # the bytes that still began one, and the code unit that broke them
    # is read again after, as its readagain bytes.
    def broken(bytes, at, width)
      Primitive.attr! :hidden
      error, again = @reading ? [bytes.byteslice(at, width), +"".b] : broken_split(bytes, at)
      @readagain = again
      stop_at = at + error.bytesize + again.bytesize
      @rest = bytes.byteslice(stop_at, bytes.bytesize - stop_at)
      stop(:invalid_byte_sequence, invalid_error(error, again), error, again)
    end

    # The longest head from `at` that is still an incomplete character,
    # and the unit after it that no character continues with.
    def broken_split(bytes, at)
      Primitive.attr! :hidden
      onig = Regexp.encoder(@source)
      unit = onig.min_len
      k = unit
      k += unit while at + k < bytes.bytesize && onig.precise_mbclen(bytes.byteslice(at, k), 0) < -1
      return [bytes.byteslice(at, [unit, bytes.bytesize - at].min), +"".b] if k == unit

      [bytes.byteslice(at, k - unit), bytes.byteslice(at + k - unit, unit)]
    end

    # The stage of the path where an error happens, as the transcoder that
    # found it names its two ends: a broken source byte in the first
    # stage, a character the destination lacks in the last.
    def stage(undefined)
      Primitive.attr! :hidden
      return [@source, @destination] if @path.size < 2

      undefined ? [@path[-2], @path[-1]] : [@path[0], @path[1]]
    end

    def stage_names(undefined)
      Primitive.attr! :hidden
      from, to = stage(undefined)
      [from&.name || @source_name, to&.name || @destination_name]
    end

    def incomplete_error(tail)
      Primitive.attr! :hidden
      from, to = stage(false)
      Encoding.send(:byte_error, "incomplete #{tail.dump} on #{stage_names(false)[0]}", from, to, tail, nil, true)
    end

    def invalid_error(error, again = +"".b)
      Primitive.attr! :hidden
      followed = again.empty? ? +"" : " followed by #{again.dump}"
      from, to = stage(false)
      Encoding.send(:byte_error, "#{error.dump}#{followed} on #{stage_names(false)[0]}", from, to, error, again.empty? ? nil : again, false)
    end

    def stop(symbol, error, bytes, again = +"".b)
      Primitive.attr! :hidden
      @errinfo = [symbol, *stage_names(symbol == :undefined_conversion), bytes.b, again.b]
      @last_error = error
      symbol
    end

    # One character's bytes in the destination, after the decorators
    # apply. A Symbol is returned in their place where the conversion stops.
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
      from, to = stage(false)
      names = stage_names(false)
      stop(:undefined_conversion,
           Encoding.send(:char_error, "#{piece.dump} from #{names[0]} to #{names[1]}", from, to, piece),
           piece)
    end

    # The code points that one character becomes: the line ends that the
    # decorators request, and the markup that an XML decorator writes.
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
      return cesu_bytes_for(point) if @destination&.name == +"CESU-8"

      found = Encoding.send(:point_bytes, point, @unit, @big, @points, @writer)
      return nil if found.nil?

      if @bom
        @bom = false
        found = (@unit == 2 ? [0xFE, 0xFF] : [0, 0, 0xFE, 0xFF]) + found
      end
      found.pack("C*")
    end

    # CESU-8 writes a character past U+FFFF as its two UTF-16 surrogates,
    # each in the three bytes UTF-8 gives a code point of that size.
    def cesu_bytes_for(point)
      Primitive.attr! :hidden
      return point.chr(Encoding::UTF_8).b if point < 0x10000

      units = [0xD800 + ((point - 0x10000) >> 10), 0xDC00 + ((point - 0x10000) & 0x3FF)]
      units.map { |u| [0xE0 | (u >> 12), 0x80 | ((u >> 6) & 0x3F), 0x80 | (u & 0x3F)].pack("C*") }.join.b
    end

    # ISO-2022-JP keeps a state: an escape says that the next bytes are
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

    # A code point that the destination cannot encode: a character
    # reference when an XML decorator requests one, the replacement when
    # the caller does, else ruby's own refusal.
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
      # A path of several stages names them all, as rb_econv_open_exc does.
      from, to = stage(true)
      names = stage_names(true)
      message = if @path.size > 2
                  "#{shown} to #{names[1]} in conversion from #{@path.map(&:name).join(' to ')}"
                else
                  "#{shown} from #{names[0]} to #{names[1]}"
                end
      stop(:undefined_conversion, Encoding.send(:char_error, message, from, to, point.chr(Encoding::UTF_8)), point.chr(Encoding::UTF_8))
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
