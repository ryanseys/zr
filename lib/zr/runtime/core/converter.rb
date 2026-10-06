# frozen_string_literal: true

# One conversion, kept open between the pieces of text it is given, as
# transcode.c's rb_econv_t: a chain of steps, one per transcoder, from the
# source through the encodings between to the destination. Each step
# keeps its own state, and each inner step writes into a buffer of its
# own that the next step reads. Decorators (line ends and XML escapes)
# are steps too. Where a conversion stopped is reported in ruby's words.
#
# The first line of this file must not spell the class's full name: ruby
# reads `coding:` inside it as a magic comment, and then looks for an
# encoding called Converter.
class Encoding
  class Converter
    CONVERTER_FLAGS.each { |name, value| const_set(name, value) }

    NEWLINE_MASK = UNIVERSAL_NEWLINE_DECORATOR | CRLF_NEWLINE_DECORATOR | CR_NEWLINE_DECORATOR | LF_NEWLINE_DECORATOR
    # decorator_names: the decorators that a flag word asks for, in the
    # order that rb_econv_open adds them.
    DECORATIONS = [
      [XML_TEXT_DECORATOR, "xml_text_escape"], [XML_ATTR_CONTENT_DECORATOR, "xml_attr_content_escape"],
      [XML_ATTR_QUOTE_DECORATOR, "xml_attr_quote"], [CRLF_NEWLINE_DECORATOR, "crlf_newline"],
      [CR_NEWLINE_DECORATOR, "cr_newline"], [LF_NEWLINE_DECORATOR, "lf_newline"],
      [UNIVERSAL_NEWLINE_DECORATOR, "universal_newline"]
    ].freeze
    # econv_description: the decorators in the order and words that a
    # description gives them.
    DESCRIBED = [
      [UNIVERSAL_NEWLINE_DECORATOR, "universal_newline"], [CRLF_NEWLINE_DECORATOR, "crlf_newline"],
      [CR_NEWLINE_DECORATOR, "cr_newline"], [LF_NEWLINE_DECORATOR, "lf_newline"], [XML_TEXT_DECORATOR, "xml_text"],
      [XML_ATTR_CONTENT_DECORATOR, "xml_attr_content"], [XML_ATTR_QUOTE_DECORATOR, "xml_attr_quote"]
    ].freeze
    DESCRIBED_MASK = NEWLINE_MASK | XML_TEXT_DECORATOR | XML_ATTR_CONTENT_DECORATOR | XML_ATTR_QUOTE_DECORATOR
    # The results that a step reports at once (trans_sweep).
    REPORTED = %i[invalid_byte_sequence incomplete_input undefined_conversion after_output].freeze
    # The size of an inner step's buffer (rb_econv_add_transcoder_at).
    BUFFER = 4096
    private_constant :NEWLINE_MASK, :DECORATIONS, :DESCRIBED, :DESCRIBED_MASK, :REPORTED, :BUFFER

    # Bytes that one side writes at the end and the other side reads from
    # the front: the source, or the buffer after a step.
    class Feed
      Primitive.attr! :hidden

      attr_reader :bytes

      def initialize(bytes = +"".b)
        @bytes = bytes
        @pos = 0
      end

      def size = @bytes.bytesize - @pos

      def empty? = @pos >= @bytes.bytesize

      def take
        byte = @bytes.getbyte(@pos)
        @pos += 1
        byte
      end

      def read(count)
        piece = @bytes.byteslice(@pos, count)
        @pos += piece.bytesize
        piece
      end

      def rest = @bytes.byteslice(@pos, size)

      # Drops the bytes read, as trans_sweep moves a buffer's data to its start.
      def compact
        return if @pos.zero?

        @bytes = rest
        @pos = 0
      end

      def <<(piece)
        @bytes << piece
        self
      end
    end

    # One transcoder at work (rb_transcoding). It reads the bytes of one
    # character and then writes what they become, and it can stop at any
    # byte of either and go on from there on the next call
    # (transcode_restartable). `@at` is where it goes on.
    class Step
      Primitive.attr! :hidden

      attr_reader :source, :target, :error, :again
      attr_accessor :readagain, :result

      def initialize(source, target)
        @source = source
        @target = target
        @recognized = +"".b
        @readagain = +"".b
        @write = +"".b
        @at = :start
        @result = :source_buffer_empty
        @error = nil
        @again = nil
        prepare
      end

      # What a kind of step sets up for itself.
      def prepare; end

      def decorator? = @source.empty?

      # asciicompat_type: a decoder reads an encoding that is not ASCII
      # compatible into one that is, and an encoder does the reverse.
      def kind
        if ASCII_COMPAT[@source] == @target then :decoder
        elsif ASCII_COMPAT[@target] == @source then :encoder
        else :converter
        end
      end

      # input_unit_length: the bytes that an invalid character takes at
      # least.
      def unit = 1

      # Whether the transcoder writes something once its input ends.
      def finishes? = false

      # The bytes that an error left are read before the input.
      def convert(input, out, stop, flags)
        unless @readagain.empty?
          again = Feed.new(@readagain)
          @readagain = +"".b
          result = run(again, out, stop, flags | PARTIAL_INPUT)
          unless result == :source_buffer_empty
            @readagain << again.rest
            return result
          end
        end
        run(input, out, stop, flags)
      end

      # rb_econv_putback: the last `count` bytes to read again.
      def put_back(count)
        kept = @readagain.bytesize - count
        taken = @readagain.byteslice(kept, count)
        @readagain = @readagain.byteslice(0, kept)
        taken
      end

      private

      # transcode_restartable0. A step stops (returns) where CRuby's
      # SUSPEND does, and `@at` names the point it goes on from.
      def run(input, out, stop, flags)
        start = out.bytesize
        partial = flags & PARTIAL_INPUT != 0
        after = flags & AFTER_OUTPUT != 0
        loop do
          case @at
          when :start
            @recognized = +"".b
            return :after_output if after && out.bytesize != start
            if input.empty?
              return :source_buffer_empty if partial

              @at = finishes? ? :closing : :finished
              next
            end
            @recognized << input.take
            @at = verdict
          when :more
            return :after_output if after && out.bytesize != start
            if input.empty?
              return :source_buffer_empty if partial

              @at = :start
              return failure(:incomplete_input, @recognized, +"".b)
            end
            @recognized << input.take
            @at = verdict
          when :room
            return :destination_buffer_full if full?(out, stop)

            made = emit(@recognized)
            if made == :invalid
              @at = :invalid
            elsif made.nil?
              @at = :start
              return failure(:undefined_conversion, @recognized, +"".b)
            else
              @write = made
              @at = :write
            end
          when :write
            return :destination_buffer_full unless flush(out, stop)

            @at = :start
          when :invalid
            count = @recognized.bytesize
            if count > unit
              # The whole units before the byte that broke the character
              # are the error, and the rest is read again.
              kept = ((count - 1) / unit) * unit
              @readagain = @recognized.byteslice(kept, count - kept)
              @at = :start
              return failure(:invalid_byte_sequence, @recognized.byteslice(0, kept), @readagain.dup)
            end
            @at = :unit
            return :after_output if count < unit && after && out.bytesize != start
          when :unit
            # An invalid character shorter than a unit takes the unit.
            if partial && @recognized.bytesize + input.size < unit
              @recognized << input.read(input.size)
              return :source_buffer_empty
            end
            @recognized << input.read([unit - @recognized.bytesize, input.size].min)
            @at = :start
            return failure(:invalid_byte_sequence, @recognized, +"".b)
          when :closing
            return :destination_buffer_full if full?(out, stop)

            @write = finish
            @at = :closed
          when :closed
            return :destination_buffer_full unless flush(out, stop)

            @at = :finished
          when :finished
            return :finished
          end
        end
      end

      # Where the character read so far goes: more bytes, an error, or
      # output once there is room for it.
      def verdict
        case classify(@recognized)
        when :more then :more
        when :invalid then :invalid
        else :room
        end
      end

      def failure(result, error, again)
        @error = error.dup
        @again = again
        result
      end

      def full?(out, stop) = !stop.nil? && out.bytesize >= stop

      # Writes what waits, as far as there is room. True when all of it is out.
      def flush(out, stop)
        room = stop.nil? ? @write.bytesize : [stop - out.bytesize, 0].max
        if room < @write.bytesize
          out << @write.byteslice(0, room)
          @write = @write.byteslice(room, @write.bytesize - room)
          return false
        end
        out << @write
        @write = +"".b
        true
      end
    end

    # A transcoder between two encodings that its tables convert one
    # character at a time.
    class Table < Step
      Primitive.attr! :hidden

      # The code units that a Unicode encoding reads, and whether the high
      # byte comes first.
      UNITS = { "UTF-16BE" => [2, true], "UTF-16LE" => [2, false], "UTF-32BE" => [4, true], "UTF-32LE" => [4, false] }.freeze
      # The encodings that write a byte order mark, and the order they write in.
      MARKED = { "UTF-16" => "UTF-16BE", "UTF-32" => "UTF-32BE" }.freeze
      MARKS = { "UTF-16" => "\xFE\xFF".b, "UTF-32" => "\x00\x00\xFE\xFF".b }.freeze

      def prepare
        @to = Encoding.find(MARKED.fetch(@target, @target))
        @mark = MARKS[@target]
        # A source with a byte order mark reads in the order its mark gives.
        @order = MARKED.key?(@source) ? nil : @source
        @from = @order && Encoding.find(@order)
      end

      def unit = (UNITS[@order || MARKED.fetch(@source, @source)] || [1])[0]

      def classify(bytes)
        return marked(bytes) if @order.nil?

        if (size, big = UNITS[@order])
          return size == 2 ? utf16(bytes, big) : utf32(bytes, big)
        end
        return stateless(bytes) if @order.start_with?("stateless-ISO-2022-JP")

        found = Regexp.encoder(@from).precise_mbclen(bytes, 0)
        if found.positive? then :char
        elsif found < -1 then :more
        else :invalid
        end
      end

      def emit(bytes)
        if @order.nil?
          @order = bytes.getbyte(0) == 0xFE || (bytes.bytesize == 4 && bytes.getbyte(2) == 0xFE) ? "#{@source}BE" : "#{@source}LE"
          @from = Encoding.find(@order)
          return +"".b
        end
        made = Encoding.send(:convert, bytes.dup.force_encoding(@from), @to, {}).b
        if @mark
          made = @mark + made
          @mark = nil
        end
        made
      rescue UndefinedConversionError
        nil
      rescue InvalidByteSequenceError
        :invalid
      end

      private

      # A byte order mark: the first unit must be one.
      def marked(bytes)
        size = @source == "UTF-16" ? 2 : 4
        return :more if bytes.bytesize < size

        bom = size == 2 ? ["\xFE\xFF".b, "\xFF\xFE".b] : ["\x00\x00\xFE\xFF".b, "\xFF\xFE\x00\x00".b]
        bom.include?(bytes) ? :char : :invalid
      end

      # A UTF-16 character breaks at the first byte that no character
      # continues with: a low surrogate first, or a high one followed by
      # anything but a low one. `big` puts the high byte of a unit first.
      def utf16(bytes, big)
        high = ->(at) { bytes.getbyte(big ? at : at + 1) }
        case bytes.bytesize
        when 1 then :more
        when 2
          if high.call(0).between?(0xD8, 0xDB) then :more
          elsif high.call(0).between?(0xDC, 0xDF) then :invalid
          else :char
          end
        when 3 then !big || high.call(2).between?(0xDC, 0xDF) ? :more : :invalid
        else high.call(2).between?(0xDC, 0xDF) ? :char : :invalid
        end
      end

      # A UTF-32 character is one code point up to U+10FFFF and outside the
      # surrogates. The bytes are known high first when `big`, low first
      # otherwise.
      def utf32(bytes, big)
        count = bytes.bytesize
        byte = ->(rank) { bytes.getbyte(big ? rank : 3 - rank) }
        known = ->(rank) { big ? rank < count : 3 - rank < count }
        return :invalid if known.call(0) && byte.call(0) != 0
        return :invalid if known.call(1) && byte.call(1) > 0x10
        return :invalid if known.call(1) && known.call(2) && byte.call(1).zero? && byte.call(2).between?(0xD8, 0xDF)

        count < 4 ? :more : :char
      end

      # stateless-ISO-2022-JP: ASCII, or 0x90 or 0x92 and two bytes of the set.
      def stateless(bytes)
        first = bytes.getbyte(0)
        return :char if bytes.bytesize == 1 && first < 0x80
        return :invalid unless first == 0x90 || first == 0x92
        return :invalid if bytes.bytesize > 1 && !bytes.getbyte(bytes.bytesize - 1).between?(0xA1, 0xFE)

        bytes.bytesize == 3 ? :char : :more
      end
    end

    # A decorator: a step from no encoding, which reads one byte at a time.
    class Decorator < Step
      Primitive.attr! :hidden

      NAMES = %w[amp_escape xml_text_escape xml_attr_content_escape xml_attr_quote universal_newline crlf_newline cr_newline lf_newline].freeze
      ESCAPES = {
        "amp_escape" => { 0x26 => "&amp;" },
        "xml_text_escape" => { 0x26 => "&amp;", 0x3C => "&lt;", 0x3E => "&gt;" },
        "xml_attr_content_escape" => { 0x22 => "&quot;", 0x26 => "&amp;", 0x27 => "&apos;", 0x3C => "&lt;", 0x3E => "&gt;" },
        "crlf_newline" => { 0x0A => "\r\n" },
        "cr_newline" => { 0x0A => "\r" }
      }.freeze

      def prepare
        # universal_newline: just after a CR. xml_attr_quote: the opening
        # quote is out.
        @state = false
      end

      def kind = @target == "xml_attr_quote" ? :encoder : :converter

      def finishes? = %w[universal_newline lf_newline xml_attr_quote].include?(@target)

      def classify(_bytes) = :char

      def emit(bytes)
        byte = bytes.getbyte(0)
        case @target
        when "universal_newline", "lf_newline" then newline(byte)
        when "xml_attr_quote"
          out = @state ? +"".b : +"\"".b
          @state = true
          out << byte
        else
          (ESCAPES.fetch(@target)[byte] || bytes).b
        end
      end

      # fun_so_universal_newline: a CR becomes LF when the next byte
      # comes, and a CR LF one LF.
      def newline(byte)
        out = +"".b
        if byte == 0x0A
          out << 0x0A
          @state = false
        else
          out << 0x0A if @state
          @state = byte == 0x0D
          out << byte unless @state
        end
        out
      end

      def finish
        if @target == "xml_attr_quote"
          out = @state ? +"\"".b : +"\"\"".b
          @state = false
          return out
        end
        out = @state ? +"\n".b : +"".b
        @state = false
        out
      end
    end

    # The ISO-2022-JP family read into its stateless form
    # (fun_si_iso2022jp_decoder, fun_si_cp50221_decoder): escapes choose
    # the set that the next bytes read in.
    class JisDecoder < Step
      Primitive.attr! :hidden

      DESIGNATIONS = { "\e(B" => :ascii, "\e(J" => :ascii, "\e$@" => :old_kanji, "\e$B" => :kanji }.freeze
      KATAKANA = { "\e(I" => :katakana, "\x0E" => :katakana, "\x0F" => :ascii }.freeze

      def prepare
        @set = :ascii
        @cp = @source.start_with?("CP5022")
        @designations = @cp ? DESIGNATIONS.merge(KATAKANA) : DESIGNATIONS
      end

      def classify(bytes)
        first = bytes.getbyte(0)
        if first == 0x1B
          return :more if bytes.bytesize < 3 && @designations.keys.any? { |escape| escape.start_with?(bytes) }

          return @designations.key?(bytes) ? :char : :invalid
        end
        return :char if @cp && (first == 0x0E || first == 0x0F)
        return bytes.getbyte(1).between?(0x21, 0x7E) ? :char : :invalid if bytes.bytesize == 2

        case @set
        when :ascii
          return :char if first <= 0x7F && first != 0x0E && first != 0x0F
          # CP50221 reads the bytes up to 0x92 as they are, and a halfwidth
          # katakana from 0xA1 to 0xDF.
          @cp && (first <= 0x92 || first.between?(0xA1, 0xDF)) ? :char : :invalid
        when :katakana then (first & 0x7F).between?(0x21, 0x5F) && (first <= 0x92 || first.between?(0xA1, 0xDF)) ? :char : :invalid
        else lead?(first) ? :more : :invalid
        end
      end

      def emit(bytes)
        if (set = @designations[bytes])
          @set = set
          return +"".b
        end
        first = bytes.getbyte(0)
        return bytes.b if bytes.bytesize == 1 && @set == :ascii && !(@cp && first.between?(0xA1, 0xDF))
        return [0x8E, first | 0x80].pack("C*") if bytes.bytesize == 1
        return [(bytes.getbyte(0) | 0x80), (bytes.getbyte(1) | 0x80)].pack("C*") if @cp

        [@set == :old_kanji ? 0x90 : 0x92, bytes.getbyte(0) | 0x80, bytes.getbyte(1) | 0x80].pack("C*")
      end

      private

      # The first byte of a two-byte character of the set in use.
      def lead?(byte)
        case @set
        when :kanji
          return byte.between?(0x21, 0x7E) unless @cp

          byte.between?(0x21, 0x28) || byte == 0x2D || byte.between?(0x30, 0x74) || byte.between?(0x79, 0x7C)
        when :old_kanji
          @cp ? byte.between?(0x21, 0x28) || byte.between?(0x30, 0x74) : byte.between?(0x21, 0x7E)
        else false
        end
      end
    end

    # A stateless form written as ISO-2022-JP (fun_so_iso2022jp_encoder,
    # fun_so_cp5022x_encoder, fun_so_cp50220_encoder): an escape before
    # each change of set, and ASCII again at the end.
    class JisEncoder < Step
      Primitive.attr! :hidden

      SHIFTS = { ascii: "\e(B", kanji: "\e$B", old_kanji: "\e$@", katakana: "\e(I" }.freeze
      # tbl0208: each halfwidth katakana from 0xA1 as its JIS X 0208 one.
      FULLWIDTH = [
        "!#", "!V", "!W", "!\"", "!&", "%r", "%!", "%#", "%%", "%'", "%)", "%c", "%e", "%g", "%C", "!<",
        "%\"", "%$", "%&", "%(", "%*", "%+", "%-", "%/", "%1", "%3", "%5", "%7", "%9", "%;", "%=", "%?",
        "%A", "%D", "%F", "%H", "%J", "%K", "%L", "%M", "%N", "%O", "%R", "%U", "%X", "%[", "%^", "%_",
        "%`", "%a", "%b", "%d", "%f", "%h", "%i", "%j", "%k", "%l", "%m", "%o", "%s", "!+", "!,"
      ].freeze

      def prepare
        @set = :ascii
        @cp = @source == "CP51932"
        @fullwidth = @target == "CP50220"
        # CP50220: a halfwidth katakana that a sound mark may join, and
        # the set before it.
        @held = nil
        @before = :ascii
      end

      def finishes? = true

      # The stateless form: ASCII but the shifts (which CP51932 leaves
      # undefined), and two-byte characters after 0x90 or 0x92, or in CP51932
      # from 0xA1, or 0x8E and a halfwidth katakana.
      def classify(bytes)
        first = bytes.getbyte(0)
        if bytes.bytesize == 1
          return @cp || ![0x0E, 0x0F, 0x1B].include?(first) ? :char : :invalid if first < 0x80
          lead = @cp ? first == 0x8E || first.between?(0xA1, 0xFE) : first == 0x90 || first == 0x92
          return lead ? :more : :invalid
        end
        return :invalid unless bytes.getbyte(bytes.bytesize - 1).between?(0xA1, 0xFE)

        width = @cp ? 2 : 3
        bytes.bytesize == width ? :char : :more
      end

      def emit(bytes)
        first = bytes.getbyte(0)
        return nil if @cp && [0x0E, 0x0F, 0x1B].include?(first)
        return cp50220(bytes) if @fullwidth

        written(bytes)
      end

      def finish
        out = +"".b
        if @held
          out << shift(:kanji, @before) << FULLWIDTH[@held - 0xA1]
          @held = nil
        end
        out << shift(:ascii)
      end

      private

      def shift(set, from = @set)
        @set = set
        set == from ? +"".b : SHIFTS.fetch(set).b
      end

      def written(bytes)
        if bytes.bytesize == 1
          shift(:ascii) << (bytes.getbyte(0) & 0x7F)
        elsif @cp && bytes.getbyte(0) == 0x8E
          shift(:katakana) << (bytes.getbyte(1) & 0x7F)
        elsif @cp
          shift(:kanji) << (bytes.getbyte(0) & 0x7F) << (bytes.getbyte(1) & 0x7F)
        else
          shift(bytes.getbyte(0) == 0x90 ? :old_kanji : :kanji) << (bytes.getbyte(1) & 0x7F) << (bytes.getbyte(2) & 0x7F)
        end
      end

      # CP50220 writes each halfwidth katakana as its fullwidth one, and a
      # sound mark after it joins it.
      def cp50220(bytes)
        out = +"".b
        if @held
          code = FULLWIDTH[@held - 0xA1]
          c = @held & 0x7F
          @held = nil
          out << shift(:kanji, @before) << code.getbyte(0)
          if bytes.bytesize == 2 && bytes.getbyte(0) == 0x8E
            return out << (code.getbyte(1) + 1) if bytes.getbyte(1) == 0xDE
            return out << (code.getbyte(1) + 2) if bytes.getbyte(1) == 0xDF && c.between?(0x4A, 0x4E)
          end
          out << code.getbyte(1)
        end
        if bytes.bytesize == 2 && bytes.getbyte(0) == 0x8E
          kana = bytes.getbyte(1)
          return out << shift(:kanji) << FULLWIDTH[kana - 0xA1] if kana.between?(0xA1, 0xB5) || kana.between?(0xC5, 0xC9) || kana.between?(0xCF, 0xDF)
          return out << shift(:katakana) << (kana & 0x7F) if kana > 0xDF

          @held = kana
          @before = @set
          @set = :katakana
          return out
        end
        out << written(bytes)
      end
    end

    # EUC-JP and stateless-ISO-2022-JP, each into the other
    # (fun_so_eucjp_to_stateless_iso2022jp and its reverse).
    class Stateless < Step
      Primitive.attr! :hidden

      def classify(bytes)
        first = bytes.getbyte(0)
        if bytes.bytesize == 1
          return @source != "EUC-JP" && [0x0E, 0x0F, 0x1B].include?(first) ? :invalid : :char if first < 0x80
          return :more if @source == "EUC-JP" ? first == 0x8E || first == 0x8F || first.between?(0xA1, 0xFE) : first == 0x90 || first == 0x92

          return :invalid
        end
        return :invalid unless bytes.getbyte(bytes.bytesize - 1).between?(0xA1, 0xFE)

        width = if @source == "EUC-JP"
                  first == 0x8F ? 3 : 2
                else
                  3
                end
        bytes.bytesize == width ? :char : :more
      end

      def emit(bytes)
        first = bytes.getbyte(0)
        if bytes.bytesize == 1
          return nil if @source == "EUC-JP" && [0x0E, 0x0F, 0x1B].include?(first)

          return bytes.b
        end
        return bytes.byteslice(1, 2).b if @source != "EUC-JP"
        return nil if first == 0x8E || first == 0x8F

        "\x92".b + bytes.b
      end
    end

    private_constant :Feed, :Step, :Table, :Decorator, :JisDecoder, :JisEncoder, :Stateless

    # The step that converts `source` into `target` in one transcoder.
    def self.step(source, target)
      Primitive.attr! :hidden
      return Decorator.new(source, target) if source.empty?
      return JisDecoder.new(source, target) if ASCII_COMPAT[source] == target && Encoding.send(:stateful?, Encoding.find(source))
      return JisEncoder.new(source, target) if ASCII_COMPAT[target] == source && Encoding.send(:stateful?, Encoding.find(target))
      return Stateless.new(source, target) if [source, target].sort == ["EUC-JP", "stateless-ISO-2022-JP"]

      Table.new(source, target)
    end

    # transcode_search_path: the pairs of ruby's transcoders that lead
    # from one name to the other, nil when none does. A decorator is a
    # transcoder from no encoding.
    def self.search(source, target)
      Primitive.attr! :hidden
      return [["", target]] if source.empty? && Decorator::NAMES.include?(target)
      return nil if source.casecmp?(target)

      path = Encoding.send(:convpath_for, source, target, "")
      path.each_cons(2).map { |a, b| [a.name, b.name] }
    rescue ConverterNotFoundError
      nil
    end

    # The canonical name of an encoding argument, or the String as given
    # (enc_arg).
    def self.name_of(value)
      Primitive.attr! :hidden
      return value.name if value.is_a?(Encoding)

      text = Converter.send(:string_of, value)
      Encoding.find(text).name
    rescue ArgumentError
      text
    end

    def self.string_of(value)
      Primitive.attr! :hidden
      text = String.try_convert(value)
      raise TypeError, "no implicit conversion of #{conversion_name(value)} into String" if text.nil?

      text
    end

    # The encoding called `name`, or nil (make_encobj).
    def self.encoding_named(name)
      Primitive.attr! :hidden
      Encoding.find(name)
    rescue ArgumentError
      nil
    end

    # econv_description.
    def self.describe(source, target, flags)
      Primitive.attr! :hidden
      out = +""
      described = !source.empty? || !target.empty?
      if described
        out << if source.empty? then target
               elsif target.empty? then source
               else "#{source} to #{target}"
               end
      end
      if flags & DESCRIBED_MASK != 0
        out << " with " if described
        out << DESCRIBED.filter_map { |bit, name| name if flags & bit != 0 }.join(",")
        described = true
      end
      described ? out : out << "no-conversion"
    end

    # econv_opts: the flag word that an option Hash gives.
    def self.flags_of(options)
      Primitive.attr! :hidden
      Encoding.send(:check_options, options)
      flags = 0
      flags |= INVALID_REPLACE if options[:invalid] == :replace
      flags |= UNDEF_REPLACE if options[:undef] == :replace
      flags |= UNDEF_REPLACE if !options[:replace].nil? && flags & INVALID_REPLACE == 0
      case options[:xml]
      when :text then flags |= XML_TEXT_DECORATOR | UNDEF_HEX_CHARREF
      when :attr then flags |= XML_ATTR_CONTENT_DECORATOR | XML_ATTR_QUOTE_DECORATOR | UNDEF_HEX_CHARREF
      end
      Encoding.send(:newline_decorators, options).each { |name| flags |= const_get(:"#{name.to_s.upcase}_DECORATOR") }
      flags
    end

    # decorator_names: nil for a flag word that asks for two line ends, or
    # for both XML forms.
    def self.decorators_of(flags)
      Primitive.attr! :hidden
      newline = flags & NEWLINE_MASK
      # One line end at most: the mask holds one bit or none.
      return nil unless (newline & (newline - 1)).zero?
      return nil if flags & XML_TEXT_DECORATOR != 0 && flags & XML_ATTR_CONTENT_DECORATOR != 0

      DECORATIONS.filter_map { |bit, name| name if flags & bit != 0 }
    end

    # A path with the decorators of `flags` added, as decorate_convpath
    # adds them: before the last step when it is an encoder.
    def self.decorated(path, flags)
      Primitive.attr! :hidden
      names = decorators_of(flags) or return nil
      last = path.last
      at = path.size
      at -= 1 if last.is_a?(Array) && step(last[0].name, last[1].name).kind == :encoder
      path[0...at] + names + path[at..]
    end
    private_class_method :step, :search, :name_of, :string_of, :encoding_named, :describe, :flags_of, :decorators_of, :decorated

    def self.search_convpath(source, destination, flags = nil, **options)
      sname, dname, flags = arguments(source, destination, flags, options)
      pairs = search(sname, dname)
      raise ConverterNotFoundError, "code converter not found (#{describe(sname, dname, flags)})" if pairs.nil?

      path = pairs.map { |a, b| a.empty? ? b : [encoding_named(a), encoding_named(b)] }
      decorated(path, flags) || raise(ConverterNotFoundError, "code converter not found (#{describe(sname, dname, flags)})")
    end

    # econv_args: the two names, and the flag word that an Integer or an
    # option Hash gives.
    def self.arguments(source, destination, flags, options)
      Primitive.attr! :hidden
      if !flags.nil?
        raise ArgumentError, +"wrong number of arguments (given 4, expected 2..3)" unless options.empty?

        flags = Primitive.zr_index_operand_m(flags)
      elsif flags.nil? && !options.empty?
        flags = flags_of(options)
      else
        flags = 0
      end
      [name_of(source), name_of(destination), flags]
    end
    private_class_method :arguments

    # transcode_loop: `text` converted whole into `target`, with the
    # options of String#encode; the error that stops it is raised.
    def self.transcode(text, target, options)
      Primitive.attr! :hidden
      converter = new(text.encoding, target, **options.except(:fallback))
      out = +""
      result = converter.primitive_convert(text.b, out, nil, nil, 0)
      raise converter.last_error unless result == :finished

      out.force_encoding(target)
    end
    private_class_method :transcode

    # The encoding this one meets ASCII in, or nil where it is ASCII
    # compatible already, or no encoding at all.
    def self.asciicompat_encoding(name)
      found = ASCII_COMPAT[name.is_a?(Encoding) ? name.name : String.try_convert(name).to_s]
      found && Encoding.find(found)
    end

    def initialize(*args, **options)
      raise TypeError, +"already initialized" if defined?(@steps)

      @steps = []
      @buffers = []
      @flags = 0
      @finished = 0
      @started = false
      @input = nil
      @replacement = nil
      @last = [:source_buffer_empty]
      if args.size == 1 && options.empty? && (path = Array.try_convert(args[0]))
        by_path(path)
      else
        raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 2..3)" unless args.size.between?(2, 3)

        # rb_econv_prepare_options: the replacement converts with to_str once.
        options = options.merge(replace: Primitive.zr_str_operand(options[:replace])) unless options[:replace].nil? || options[:replace].is_a?(String)
        @source_name, @destination_name, flags = Converter.send(:arguments, args[0], args[1], args[2], options)
        open(@source_name, @destination_name, flags) or
          raise ConverterNotFoundError, "code converter not found (#{Converter.send(:describe, @source_name, @destination_name, flags)})"
        begin
          self.replacement = options[:replace] unless options[:replace].nil?
        rescue UndefinedConversionError
          raise ConverterNotFoundError, "code converter not found (#{Converter.send(:describe, @source_name, @destination_name, flags)})"
        end
      end
      unless @source_name.empty? && Decorator::NAMES.include?(@destination_name) || (@source_name.empty? && @destination_name.empty?)
        @source = Converter.send(:encoding_named, @source_name)
        @destination = Converter.send(:encoding_named, @destination_name)
      end
    end

    def source_encoding = @source

    def destination_encoding = @destination

    def convpath
      @steps.map do |step|
        step.decorator? ? step.target.dup : [Converter.send(:encoding_named, step.source), Converter.send(:encoding_named, step.target)]
      end
    end

    def inspect = Primitive.zr_obj_form("#<#{self.class}: #{Converter.send(:describe, @source_name, @destination_name, @flags)}>")

    def ==(other)
      return nil unless other.is_a?(Converter)

      mine = [@source_name, @destination_name, @flags, replacement_pair, @steps.map { |s| [s.source, s.target] }]
      mine == other.send(:identity)
    end

    def primitive_errinfo
      result, step, error, again = @last
      return [result, nil, nil, nil, nil] if step.nil?

      [result, step.source.dup, step.target.dup, error.b, again.b]
    end

    def last_error = error_of(@last)

    def replacement
      replace = make_replacement
      bytes, name = replace
      encoding = Converter.send(:encoding_named, name) || Encoding::ASCII_8BIT
      bytes.dup.force_encoding(encoding)
    end

    # rb_econv_set_replacement: the text in the encoding that output is
    # inserted in.
    def replacement=(text)
      text = Converter.send(:string_of, text)
      into = insert_encoding
      bytes = text.b
      name = text.encoding.name
      unless into.empty? || name.casecmp?(into)
        bytes = converted(name, into, bytes)
        raise UndefinedConversionError, +"replacement character setup failed" if bytes.nil?

        name = into
      end
      @replacement = [bytes, name]
      text
    end

    # econv_convert: every whole character of `text`, converted.
    def convert(text)
      text = Converter.send(:string_of, text)
      out = +""
      result = primitive_convert(text.dup, out, nil, nil, PARTIAL_INPUT)
      raise last_error if %i[invalid_byte_sequence undefined_conversion incomplete_input].include?(result)
      raise ArgumentError, +"converter already finished" if result == :finished

      out
    end

    # econv_finish: the last of the conversion.
    def finish
      out = +""
      result = primitive_convert(nil, out, nil, nil, 0)
      raise last_error if %i[invalid_byte_sequence undefined_conversion incomplete_input].include?(result)

      out
    end

    # econv_putback: the bytes that the first step reads again, the last
    # of them first.
    def putback(count = nil)
      held = @steps.empty? ? 0 : @steps[0].readagain.bytesize
      count = count.nil? ? held : [Primitive.zr_index_operand_m(count), held].min
      taken = count.positive? ? @steps[0].put_back(count) : +"".b
      taken.force_encoding(@source || Encoding::ASCII_8BIT)
    end

    # econv_insert_output: `text`, in the encoding that output is inserted in.
    def insert_output(text)
      text = Converter.send(:string_of, text)
      into = insert_encoding
      bytes = into.empty? || text.encoding.name.casecmp?(into) ? text.b : encoded(text, into)
      insert(bytes, into)
      nil
    end

    # econv_primitive_convert. Both Strings change in place.
    def primitive_convert(source, destination, offset = nil, size = nil, flags = nil, **options)
      if flags.nil?
        flags = 0
        flags |= PARTIAL_INPUT if options[:partial_input]
        flags |= AFTER_OUTPUT if options[:after_output]
      else
        raise ArgumentError, +"wrong number of arguments (given 6, expected 2..5)" unless options.empty?

        flags = Primitive.zr_index_operand_m(flags)
      end
      destination = Converter.send(:string_of, destination)
      source = Converter.send(:string_of, source) unless source.nil?
      offset = Primitive.zr_index_operand_m(offset) unless offset.nil?
      size = Primitive.zr_index_operand_m(size) unless size.nil?
      raise FrozenError, "can't modify frozen String: #{destination.inspect}" if destination.frozen?
      raise ArgumentError, +"negative output_byteoffset" if offset&.negative?
      raise ArgumentError, +"output_byteoffset too big" if offset && offset > destination.bytesize
      raise ArgumentError, +"negative output_bytesize" if size&.negative?

      destination.replace(destination.byteslice(0, offset)) if offset
      input = source && Feed.new(source.b)
      out = +"".b
      result = econv_convert(input, out, size, flags)
      source&.replace(input.rest.force_encoding(source.encoding))
      # The bytes join the destination as bytes: a destination already
      # tagged with the target encoding would refuse them.
      destination.force_encoding(Encoding::ASCII_8BIT)
      destination << out
      destination.force_encoding(@destination) if @destination
      result
    end

    private

    def identity
      Primitive.attr! :hidden
      [@source_name, @destination_name, @flags, replacement_pair, @steps.map { |s| [s.source, s.target] }]
    end

    def replacement_pair
      Primitive.attr! :hidden
      @replacement
    end

    # rb_econv_open: the steps of the path, then the decorators.
    def open(source, target, flags)
      Primitive.attr! :hidden
      names = Converter.send(:decorators_of, flags) or return false
      unless source.empty? && target.empty?
        pairs = Converter.send(:search, source, target) or return false
        pairs.each { |a, b| add(Converter.send(:step, a, b), @steps.size) }
      end
      names.each { |name| decorate_at_last(name) }
      @source_name = source
      @destination_name = target
      @flags = flags
      true
    end

    # rb_econv_init_by_convpath.
    def by_path(path)
      Primitive.attr! :hidden
      first = true
      @source_name = +""
      @destination_name = +""
      path.each do |element|
        if (pair = Array.try_convert(element))
          raise ArgumentError, +"not a 2-element array in convpath" unless pair.size == 2

          a = Converter.send(:name_of, pair[0])
          b = Converter.send(:name_of, pair[1])
        else
          a = +""
          b = Converter.send(:string_of, element)
        end
        if a.empty? && Decorator::NAMES.include?(b)
          add(Decorator.new(a, b), @steps.size)
          next
        end
        raise ArgumentError, "decoration failed: #{b}" if a.empty?

        pairs = Converter.send(:search, a, b) or raise ArgumentError, "adding conversion failed: #{a} to #{b}"
        at = @steps.size
        pairs.each { |x, y| add(Converter.send(:step, x, y), @steps.size) }
        if first
          first = false
          @source_name = @steps[at].source
        end
        @destination_name = @steps.last.target
      end
    end

    # rb_econv_add_transcoder_at: the step and its buffer.
    def add(step, at)
      Primitive.attr! :hidden
      @steps.insert(at, step)
      @buffers.insert(at, Feed.new)
    end

    # rb_econv_decorate_at_last: a decorator goes before a last step that
    # writes an encoding that is not ASCII compatible.
    def decorate_at_last(name)
      Primitive.attr! :hidden
      last = @steps.last
      at = @steps.size
      at -= 1 if last && !last.decorator? && last.kind == :encoder
      add(Decorator.new(+"", name), at)
    end

    # The last step that is not a decorator (ec->last_tc).
    def last_step
      Primitive.attr! :hidden
      @steps.reverse_each.find { |step| !step.decorator? }
    end

    # rb_econv_encoding_to_insert_output.
    def insert_encoding
      Primitive.attr! :hidden
      step = last_step
      return +"" if step.nil?

      step.kind == :encoder ? step.source : step.target
    end

    # rb_econv_convert: errors that the flags replace are replaced, and
    # the conversion goes on.
    def econv_convert(input, out, stop, flags)
      Primitive.attr! :hidden
      @started = true
      loop do
        result = convert0(input, out, stop, flags)
        if %i[invalid_byte_sequence incomplete_input].include?(result) && @flags & INVALID_MASK == INVALID_REPLACE
          next if output_replacement
        end
        if result == :undefined_conversion
          case @flags & UNDEF_MASK
          when UNDEF_REPLACE then next if output_replacement
          when UNDEF_HEX_CHARREF then next if output_hex_charref
          end
        end
        return result
      end
    end

    # rb_econv_convert0.
    def convert0(input, out, stop, flags)
      Primitive.attr! :hidden
      input ||= Feed.new
      @last = [:source_buffer_empty]
      result, at = no_conversion(input, out, stop, flags) if @steps.empty?
      unless result
        tail = @buffers.last
        has_output = false
        unless tail.empty?
          room = stop.nil? ? tail.size : stop - out.bytesize
          if room < tail.size
            out << tail.read(room)
            result = :destination_buffer_full
          else
            out << tail.read(tail.size)
            tail.compact
            has_output = true
          end
        end
      end
      if result.nil? && @input && !@input.empty?
        result, at = trans_conv(@input, out, stop, (flags & ~AFTER_OUTPUT) | PARTIAL_INPUT)
        result = nil if result == :source_buffer_empty
      end
      if result.nil?
        if has_output && flags & AFTER_OUTPUT != 0 && !input.empty?
          result, at = trans_conv(Feed.new, out, stop, flags)
          result = :after_output if result == :source_buffer_empty
        elsif flags & AFTER_OUTPUT != 0 || @steps.size == 1
          result, at = trans_conv(input, out, stop, flags)
        else
          flags |= AFTER_OUTPUT
          loop do
            result, at = trans_conv(input, out, stop, flags)
            break unless result == :after_output
          end
        end
      end
      @last = if %i[invalid_byte_sequence incomplete_input undefined_conversion].include?(result)
                step = @steps[at]
                [result, step, step.error, step.again]
              else
                [result]
              end
      result
    end

    # A conversion with no step copies its input (the num_trans == 0 part
    # of rb_econv_convert0).
    def no_conversion(input, out, stop, flags)
      Primitive.attr! :hidden
      room = -> { stop.nil? ? Float::INFINITY : stop - out.bytesize }
      if @input && !@input.empty?
        if room.call < @input.size
          out << @input.read(room.call)
          return [:destination_buffer_full]
        end
        out << @input.rest
        @input = nil
        return [:after_output] if flags & AFTER_OUTPUT != 0
      end
      count = [room.call, input.size].min
      if count.positive? && flags & AFTER_OUTPUT != 0
        out << input.read(1)
        return [:after_output]
      end
      out << input.read(count)
      return [:destination_buffer_full] unless input.empty?

      [flags & PARTIAL_INPUT != 0 ? :source_buffer_empty : :finished]
    end

    # rb_trans_conv: sweeps the steps until one has something to report,
    # and returns [the result, the step's index].
    def trans_conv(input, out, stop, flags)
      Primitive.attr! :hidden
      input ||= Feed.new
      count = @steps.size
      @steps[0].result = :source_buffer_empty if @steps[0].result == :after_output
      start = (count - 1).downto(0).find { |i| [*REPORTED, :finished].include?(@steps[i].result) }
      if start
        start += 1
      else
        if @steps[count - 1].result == :destination_buffer_full && flags & AFTER_OUTPUT != 0
          result, at = trans_conv(nil, out, stop, (flags & ~AFTER_OUTPUT) | PARTIAL_INPUT)
          return [result == :source_buffer_empty ? :after_output : result, at]
        end
        start = 0
      end
      loop do
        report = sweep(input, out, stop, flags, start)
        start = report + 1
        break if report == -1 || report == count - 1
      end
      (count - 1).downto(0) do |i|
        result = @steps[i].result
        next if result == :source_buffer_empty

        @steps[i].result = :source_buffer_empty if REPORTED.include?(result)
        return [result, i]
      end
      [:source_buffer_empty, -1]
    end

    # trans_sweep: each step from `start` converts what the one before it
    # wrote, until none moves; the index of a step that has something to
    # report, or -1.
    def sweep(input, out, stop, flags, start)
      Primitive.attr! :hidden
      count = @steps.size
      loop do
        moved = false
        i = start
        while i < count
          step = @steps[i]
          from = i.zero? ? input : @buffers[i - 1]
          if i == count - 1
            into = out
            limit = stop
          else
            @buffers[i].compact
            into = @buffers[i].bytes
            limit = BUFFER
          end
          f = flags
          f |= PARTIAL_INPUT if @finished != i
          if i.zero? && flags & AFTER_OUTPUT != 0
            start = 1
            flags &= ~AFTER_OUTPUT
          end
          f &= ~AFTER_OUTPUT unless i.zero?
          before = [from.size, into.bytesize]
          result = step.result = step.convert(from, into, limit, f)
          moved = true if before != [from.size, into.bytesize]
          return i if REPORTED.include?(result)

          @finished = i + 1 if result == :finished
          i += 1
        end
        break unless moved
      end
      -1
    end

    # make_replacement: U+FFFD into UTF-8 and "?" into any other.
    def make_replacement
      Primitive.attr! :hidden
      @replacement ||= begin
        into = insert_encoding
        if into.empty? then [+"?".b, +""]
        elsif into.casecmp?("UTF-8") then ["\xEF\xBF\xBD".b, +"UTF-8"]
        else [+"?".b, +"US-ASCII"]
        end
      end
    end

    def output_replacement
      Primitive.attr! :hidden
      bytes, name = make_replacement
      insert(bytes, name)
    end

    # output_hex_charref: each code point of the broken character as
    # &#xHH;.
    def output_hex_charref
      Primitive.attr! :hidden
      _, step, error = @last
      units = step.source.casecmp?("UTF-32BE") ? error : converted(step.source, "UTF-32BE", error)
      return false if units.nil? || units.bytesize % 4 != 0

      units.unpack("N*").each { |point| return false unless insert(format("&#x%X;", point).b, "US-ASCII") }
      true
    end

    # rb_econv_insert_output: the bytes go where the next output comes
    # from, ahead of a last step that encodes them, or after the last
    # step.
    def insert(bytes, name)
      Primitive.attr! :hidden
      @started = true
      return true if bytes.empty?

      into = insert_encoding
      unless name.casecmp?(into)
        bytes = converted(name, into, bytes)
        return false if bytes.nil?
      end
      last = @steps.size - 1
      if @steps.empty?
        feed = (@input ||= Feed.new)
      elsif @steps[last].kind == :encoder
        step = @steps[last]
        feed = last.zero? ? (@input ||= Feed.new) : @buffers[last - 1]
      else
        feed = @buffers[last]
      end
      feed << bytes
      if step
        feed << step.readagain
        step.readagain = +"".b
      end
      true
    end

    # allocate_converted_string: `bytes` converted whole, or nil.
    def converted(source, target, bytes)
      Primitive.attr! :hidden
      out = +"".b
      converter = Converter.new(source, target)
      converter.send(:econv_convert, Feed.new(bytes.b), out, nil, 0) == :finished ? out : nil
    rescue ConverterNotFoundError
      nil
    end

    # `text` in the encoding `name`, or the error that its conversion
    # stopped at.
    def encoded(text, name)
      Primitive.attr! :hidden
      converter = Converter.new(text.encoding, name)
      out = +"".b
      result = converter.send(:econv_convert, Feed.new(text.b), out, nil, 0)
      raise converter.last_error unless result == :finished

      out
    end

    # make_econv_exception.
    def error_of(last)
      Primitive.attr! :hidden
      result, step, error, again = last
      return nil if step.nil?

      from = Converter.send(:encoding_named, step.source)
      to = Converter.send(:encoding_named, step.target)
      if result == :undefined_conversion
        shown = error.dump
        if step.source == "UTF-8"
          char = error.dup.force_encoding(Encoding::UTF_8)
          shown = format("U+%04X", char.ord) if char.valid_encoding? && char.length == 1
        end
        message = if step.source == @source_name && step.target == @destination_name
                    "#{shown} from #{step.source} to #{step.target}"
                  else
                    names = @steps.reject(&:decorator?).map(&:target)
                    "#{shown} to #{step.target} in conversion from #{@source_name}#{names.map { |n| " to #{n}" }.join}"
                  end
        char = error.dup.force_encoding(from || Encoding::ASCII_8BIT)
        return Encoding.send(:char_error, message, from, to, char).send(:named, step.source.dup, step.target.dup)
      end
      message = if result == :incomplete_input
                  "incomplete #{error.dump} on #{step.source}"
                elsif again.empty?
                  "#{error.dump} on #{step.source}"
                else
                  "#{error.dump} followed by #{again.dump} on #{step.source}"
                end
      Encoding.send(:byte_error, message, from, to, error, again.empty? ? nil : again, result == :incomplete_input)
              .send(:named, step.source.dup, step.target.dup)
    end
  end
end
