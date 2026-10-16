# frozen_string_literal: true

# Every encoding that ruby registers is defined here. A String has one
# of the three that the runtime walks: UTF-8, ASCII-8BIT and US-ASCII.
class Encoding
  class CompatibilityError < EncodingError; end
  class ConverterNotFoundError < EncodingError; end

  # The two failures that a conversion can return give both of its ends,
  # and the character or the bytes where it stopped.
  class UndefinedConversionError < EncodingError
    def source_encoding_name = @names ? @names[0] : @source && Encoding.send(:transcoder_name, @source)

    def destination_encoding_name = @names ? @names[1] : @destination && Encoding.send(:transcoder_name, @destination)

    def source_encoding = @source

    def destination_encoding = @destination

    def error_char = @char

    def setup(source, destination, char)
      Primitive.attr! :hidden
      @source = source
      @destination = destination
      @char = char
      self
    end

    # A step whose transcoder gives its ends separately from the encodings.
    def named(source, destination)
      Primitive.attr! :hidden
      @names = [source, destination]
      self
    end
    private :setup, :named
  end

  class InvalidByteSequenceError < EncodingError
    def source_encoding_name = @names ? @names[0] : @source && Encoding.send(:transcoder_name, @source)

    def destination_encoding_name = @names ? @names[1] : @destination && Encoding.send(:transcoder_name, @destination)

    def source_encoding = @source

    def destination_encoding = @destination

    def error_bytes = @bytes

    def readagain_bytes = @again

    def incomplete_input? = @incomplete

    def setup(source, destination, bytes, again, incomplete)
      Primitive.attr! :hidden
      @source = source
      @destination = destination
      @bytes = bytes
      @again = again
      @incomplete = incomplete
      self
    end

    def named(source, destination)
      Primitive.attr! :hidden
      @names = [source, destination]
      self
    end
    private :setup, :named
  end

  # The two failures, built with all their attributes. The message is
  # binary while it is ASCII, as make_econv_exception's rb_sprintf makes
  # it.
  def self.byte_error(message, source, destination, bytes, again, incomplete)
    Primitive.attr! :hidden
    InvalidByteSequenceError.new(c_message(message)).send(:setup, source, destination, bytes.b, again&.b, incomplete)
  end

  def self.char_error(message, source, destination, char)
    Primitive.attr! :hidden
    UndefinedConversionError.new(c_message(message)).send(:setup, source, destination, char)
  end

  def self.c_message(message)
    Primitive.attr! :hidden
    message.ascii_only? ? message.b : message
  end

  # The names as the registry reads them while the core boots, before the
  # full `names` below (with "locale", "external" and the rest) exists.
  attr_reader :names

  # Every name is a frozen US-ASCII String, the same object on each
  # call.
  def initialize(index, names, dummy, ascii, loaded, bytewise)
    Primitive.attr! :hidden
    @names = names.map { |name| Primitive.zr_str_usascii(name.dup).freeze }.freeze
    # The one field CRuby shows a program.
    Primitive.zr_hidden_set(self, :@name, @names.first)
    @index = index
    @dummy = dummy
    @ascii = ascii
    Primitive.zr_state_set(self, :__loaded__, loaded)
    @bytewise = bytewise
    # An encoding is frozen, as CRuby makes each one. Reading its table
    # later is state that freeze does not lock (zr_state_set).
    freeze
  end

  # Ruby's own index for this encoding in `Encoding.list`. A String
  # stores this number.
  def index
    Primitive.attr! :hidden
    @index
  end

  # Whether one byte is always one character, which is what the runtime
  # needs to walk a String in this encoding.
  def bytewise?
    Primitive.attr! :hidden
    @bytewise
  end

  def name = @names.first

  # The names the table lists, before `names` moves the default ones.
  def listed_names
    Primitive.attr! :hidden
    @names
  end
  private :listed_names
  alias to_s name

  # Marshal writes an encoding by name, as ruby does.
  def _dump(_limit = nil) = name.dup.force_encoding(Encoding::US_ASCII)

  # CRuby's `_load` returns the name; Marshal's own loader for
  # Encoding turns it into the encoding.
  def self._load(name) = name

  # BINARY is the name that the report shows, and ASCII-8BIT is the one
  # that `name` returns. A dummy encoding says so, and so does one whose
  # table a fresh ruby has not read, in that order, as enc_inspect writes them.
  def inspect
    shown = @names[1] == +"BINARY" ? +"BINARY (ASCII-8BIT)" : name
    "#<Encoding:#{shown}#{" (dummy)" if @dummy}#{" (autoload)" unless Primitive.zr_hidden_get(self, :__loaded__)}>".force_encoding(US_ASCII)
  end

  def ascii_compatible?
    Primitive.zr_state_set(self, :__loaded__, true)
    @ascii
  end

  def dummy?
    Primitive.zr_state_set(self, :__loaded__, true)
    @dummy
  end

  # A lookup of an encoding by name reads its table.
  def load
    Primitive.attr! :hidden
    Primitive.zr_state_set(self, :__loaded__, true)
    self
  end

  # Ruby cannot make an Encoding: the runtime builds each one once.
  Primitive.zr_undef_alloc(self)

  LIST = ROWS.each_with_index.map do |(names, dummy, ascii, loaded, bytewise), index|
    encoding = Primitive.zr_class_build(self)
    encoding.send(:initialize, index, names, dummy, ascii, loaded, bytewise)
    encoding
  end.freeze
  private_constant :LIST

  BY_NAME = LIST.each_with_object({}) { |encoding, out| encoding.names.each { |name| out[name] = encoding } }.freeze
  private_constant :BY_NAME

  CONSTANTS.each { |const, name| const_set(const, BY_NAME.fetch(name)) }

  def self.at(index)
    Primitive.attr! :hidden
    LIST[index]
  end

  # Whether this encoding gives every byte from 128 up a code point of
  # its own, which is what reading its characters needs.
  def self.tabled?(encoding)
    Primitive.attr! :hidden
    HIGH.key?(encoding.name)
  end

  # Whether this encoding cases its non-ASCII characters at all.
  def self.cased?(encoding)
    Primitive.attr! :hidden
    Primitive.zr_table_member_p(CASED, encoding.name)
  end

  # A String has a byte-oriented encoding, UTF-8, or UTF-16 or UTF-32.
  # The others need byte tables that this runtime does not have.
  def self.carried(encoding)
    Primitive.attr! :hidden
    unless encoding.bytewise? || encoding.equal?(UTF_8) || wide?(encoding) || mb?(encoding) || utf8_like?(encoding)
      Primitive.zr_unimplemented("a String in the #{encoding} encoding")
    end

    encoding.send(:load).index
  end

  # Whether a String in this encoding walks by the multibyte rules in
  # lib/zr/runtime/kernel/enc_mb.rb, or by UTF-8's own rules.
  def self.mb?(encoding)
    Primitive.attr! :hidden
    MB.key?(encoding.name)
  end

  def self.utf8_like?(encoding)
    Primitive.attr! :hidden
    Primitive.zr_table_member_p(MB_UTF8, encoding.name)
  end

  # Whether a conversion out of this multibyte encoding has entries to
  # read. Ruby has no converter for some of them. A String in one of
  # those is walked and never converted.
  def self.mb_converts?(encoding)
    Primitive.attr! :hidden
    mb?(encoding) && !MB.fetch(encoding.name).empty?
  end

  # The error that a String whose bytes make no character raises. The
  # runtime calls this, because the names are here.
  def self.invalid_bytes(text)
    Primitive.attr! :hidden
    raise ArgumentError, "invalid byte sequence in #{text.encoding.name}"
  end

  # A multibyte encoding's entries, unpacked on first use. They map the
  # bytes before a character's last byte to the result of converting each
  # last byte. A code point represents itself. A String is a character
  # that needs more than one code point. `true` is a character that the
  # encoding gives no code point. `:more` starts a longer character.
  # The kernel's own rules find where a character ends, because ruby's
  # converters are narrower than its character counts.
  # MB_POOL holds mb_pool's lines once a conversion reads one.
  MB_TABLES = {}
  MB_WRITERS = {}
  MB_POOL = []
  private_constant :MB_TABLES, :MB_WRITERS, :MB_POOL

  def self.mb_table(encoding)
    Primitive.attr! :hidden
    MB_TABLES[encoding.name] ||= mb_rows(encoding.name)
  end

  def self.mb_rows(name)
    Primitive.attr! :hidden
    multi = mb_multi(name)
    pool = MB_POOL[0] ||= mb_pool.lines
    numbers = MB.fetch(name).unpack1("m").unpack("w*")
    out = {}
    at = 0
    while at < numbers.size
      size = numbers[at]
      # A walk reaches the entries with bytes.
      key = numbers[at + 1, size].pack("C*")
      byte = numbers[at + size + 1]
      id = numbers[at + size + 3]
      at += size + 4
      row = {}
      point = 0
      pool[id].unpack1("m").unpack("w*").each do |value|
        case value
        when 0 then nil
        when 1 then row[byte] = true
        when 2 then row[byte] = :more
        when 3 then row[byte] = multi.fetch(key + byte.chr).dup.force_encoding(UTF_8)
        else
          point += mb_signed(value - 4)
          row[byte] = point
        end
        byte += 1
      end
      out[key] = row
    end
    out
  end

  # The characters of an encoding that need more than one code point,
  # keyed by the bytes that a walk uses to reach them. The generated
  # table's own keys are source literals, which have the source's encoding.
  def self.mb_multi(name)
    Primitive.attr! :hidden
    rows = MB_MULTI[name]
    return nil if rows.nil?

    out = {}
    rows.each { |bytes, text| out[bytes.b] = text }
    out
  end

  # A number folded onto the positive ones, read back.
  def self.mb_signed(value)
    Primitive.attr! :hidden
    value.even? ? value / 2 : 0 - ((value + 1) / 2)
  end

  # From a code point to the bytes the encoding writes it as: the rows
  # read backwards, lowest sequence first, with the ones ruby writes
  # another way on top.
  def self.mb_writer(encoding)
    Primitive.attr! :hidden
    MB_WRITERS[encoding.name] ||= begin
      out = {}
      mb_table(encoding).each do |prefix, row|
        row.each do |byte, slot|
          next unless slot.is_a?(Integer)

          bytes = prefix + byte.chr
          # The shortest sequence represents the code point, with the
          # lowest bytes of that length, as ruby writes one.
          held = out[slot]
          if held.nil? || bytes.bytesize < held.bytesize || (bytes.bytesize == held.bytesize && bytes < held)
            out[slot] = bytes
          end
        end
      end
      packed = MB_ENCODE[encoding.name]
      if packed
        bytes = packed.unpack1("m")
        at = 0
        point = 0
        while at < bytes.bytesize
          delta, at = mb_varint(bytes, at)
          size, at = mb_varint(bytes, at)
          point += delta
          out[point] = bytes.byteslice(at, size)
          at += size
        end
      end
      out
    end
  end

  # One number of the packed rows, and where the next one starts.
  def self.mb_varint(bytes, at)
    Primitive.attr! :hidden
    value = 0
    shift = 0
    loop do
      piece = bytes.getbyte(at)
      at += 1
      value |= (piece & 0x7F) << shift
      break if piece < 0x80

      shift += 7
    end
    [value, at]
  end
  private_class_method :mb_varint
  private_class_method :mb_rows, :mb_signed

  # UTF-16 and UTF-32: the width of a code unit, and whether it is big
  # endian. The two dummy names write big endian after a byte-order
  # mark, and read the order off the mark.
  UNITS = {
    "UTF-16BE" => [2, true], "UTF-16LE" => [2, false], "UTF-32BE" => [4, true], "UTF-32LE" => [4, false],
    "UTF-16" => [2, nil], "UTF-32" => [4, nil]
  }.freeze
  private_constant :UNITS

  BOMS = { 2 => [[0xFE, 0xFF], [0xFF, 0xFE]], 4 => [[0, 0, 0xFE, 0xFF], [0xFF, 0xFE, 0, 0]] }.freeze
  private_constant :BOMS

  # Whether a String in this encoding walks by UTF-16 or UTF-32 code
  # units: the four named with a byte order.
  def self.wide?(encoding)
    Primitive.attr! :hidden
    UNITS.key?(encoding.name) && !encoding.bytewise?
  end

  # For each lead byte of a UTF-8 sequence: how many bytes follow, and
  # the range the first of them must fall in. Every later one is 80-BF.
  UTF8_LEADS = (0xC2..0xF4).to_h do |lead|
    rule = if lead < 0xE0 then [1, 0x80, 0xBF]
           elsif lead == 0xE0 then [2, 0xA0, 0xBF]
           elsif lead == 0xED then [2, 0x80, 0x9F]
           elsif lead < 0xF0 then [2, 0x80, 0xBF]
           elsif lead == 0xF0 then [3, 0x90, 0xBF]
           elsif lead == 0xF4 then [3, 0x80, 0x8F]
           else [3, 0x80, 0xBF]
           end
    [lead, rule]
  end.freeze
  private_constant :UTF8_LEADS

  # The message that a join of two encodings raises. The runtime calls
  # this because the names are here.
  def self.incompatible(a, b)
    Primitive.attr! :hidden
    raise CompatibilityError, "incompatible character encodings: #{shown(a.encoding)} and #{shown(b.encoding)}"
  end

  # BINARY shows as both its names when an error gives it.
  def self.shown(encoding)
    Primitive.attr! :hidden
    encoding.equal?(ASCII_8BIT) ? +"BINARY (ASCII-8BIT)" : encoding.name
  end

  # The code point that each byte from 128 up represents, or nil where
  # the encoding leaves the byte out. Bytes below 128 represent
  # themselves in every encoding that has a table.
  def points
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__points__) || Primitive.zr_state_set(self, :__points__, HIGH.fetch(name).scan(/..../).map { |hex| hex == +"----" ? nil : hex.to_i(16) })
  end

  # `text` written in `target`. UTF-8 is the meeting point, so a pair
  # with neither side in it converts twice, and its errors name both
  # steps.
  def self.convert(text, target, options)
    Primitive.attr! :hidden
    from = text.encoding
    target.send(:load)
    return text.dup.force_encoding(target) if from.equal?(target)
    # The stateless form of ISO-2022-JP converts on the paths of ruby's own
    # transcoders, which a converter takes one step at a time. (Its steps
    # never convert stateless text back through here.)
    return Converter.send(:transcode, text, target, options) if stateless?(from) || stateless?(target)
    if stateful?(target)
      # The multibyte encoding a stateful one is made from converts to it
      # directly; another goes through UTF-8, replacing with the target's
      # own replacement.
      direct = from.equal?(UTF_8) || from.name == STATEFUL.fetch(target.name).first
      text = convert(text, UTF_8, { **options, replace: replacement(target, options) }) unless direct
      return stateful_write(text, target, options)
    end
    if stateful?(from)
      text = stateful_read(text, options)
      return target.equal?(UTF_8) ? text : convert(text, target, options)
    end
    return ebcdic_write(from.equal?(UTF_8) ? text : convert(text, UTF_8, options), target, options) if target.name == +"IBM037"
    return convert(ebcdic_read(text), target, options) if from.name == +"IBM037"

    return jis_direct(text, from, target, options) if jis_pair?(from, target)
    return hub_convert(text, from, target, options) if MB_HUBS.key?(from.name) || MB_HUBS.key?(target.name)
    # The carriers exchange their emoji with each other in one step.
    return exchange(text, target, [from, target], options) if carrier?(from) && carrier?(target)

    path = from.equal?(UTF_8) || target.equal?(UTF_8) ? [from, target] : [from, UTF_8, target]
    # str_transcode0 opens no converter only for ASCII text between two
    # encodings that contain ASCII.
    ascii = text.ascii_only? && from.ascii_compatible? && target.ascii_compatible?
    (1...path.size).each { |i| converter(path[i - 1], path[i], path, ascii, decorators(options)) }
    text = to_utf8(text, path, options) unless from.equal?(UTF_8)
    text = from_utf8(text, target, path, options) unless target.equal?(UTF_8)
    text
  end

  def self.stateless?(encoding)
    Primitive.attr! :hidden
    encoding.name == "stateless-ISO-2022-JP"
  end
  private_class_method :stateless?

  # An encoding with no table gets past here, and so does a pair ruby
  # itself refuses to convert between. Plain ASCII crosses that second
  # one anyway, converter or none.
  def self.converter(a, b, path, ascii, decorators = [])
    Primitive.attr! :hidden
    [a, b].each do |encoding|
      next if encoding.equal?(UTF_8) || UNITS.key?(encoding.name) || mb_converts?(encoding) || utf8_like?(encoding)
      # Plain ASCII goes into an ASCII-compatible encoding with no table,
      # unless an option requests a decorator, which needs a converter.
      if ascii && !shaped?(encoding) && encoding.ascii_compatible? && !encoding.dummy?
        next if decorators.empty?

        raise ConverterNotFoundError, not_found(path, decorators)
      end
      # Ruby defines these encodings but has no converter for them.
      raise ConverterNotFoundError, not_found(path, decorators) if %w[UTF-7 ISO-2022-JP-2].include?(encoding.name)
      Primitive.zr_unimplemented("String#encode to the #{encoding} encoding") unless shaped?(encoding)
      raise ConverterNotFoundError, not_found(path, decorators) if shape_of(encoding).nil? && (!ascii || !decorators.empty?)
    end
  end

  def self.not_found(path, decorators)
    Primitive.attr! :hidden
    with = decorators.empty? ? +"" : " with #{decorators.join(",")}"
    "code converter not found (#{path.first.name} to #{path.last.name}#{with})"
  end
  private_class_method :not_found
  private_class_method :converter

  # The decorators that the options of an encode request, by ruby's names.
  def self.decorators(options)
    Primitive.attr! :hidden
    names = case options[:xml]
            when :text then [+"xml_text"]
            when :attr then %w[xml_attr_content xml_attr_quote]
            else []
            end
    names << "crlf_newline" if options[:newline] == :crlf
    names << "cr_newline" if options[:newline] == :cr
    names << "universal_newline" if options[:newline] == :universal
    names << "lf_newline" if options[:newline] == :lf
    names
  end
  private_class_method :decorators

  # How ruby words a failure for an encoding. The single-byte entries
  # and the multibyte ones give the same three facts.
  def self.shaped?(encoding)
    Primitive.attr! :hidden
    SHAPES.key?(encoding.name) || MB_SHAPES.key?(encoding.name)
  end

  def self.shape_of(encoding)
    Primitive.attr! :hidden
    SHAPES.key?(encoding.name) ? SHAPES[encoding.name] : MB_SHAPES[encoding.name]
  end

  # The name that ruby's transcoder for `encoding` declares (enc/trans),
  # which a conversion error shows since ruby takes a converter's names
  # from its transcoders (20ca4e1f64): WINDOWS-1252 for Windows-1252, and
  # SJIS-DOCOMO for a carrier's step to its UTF-8.
  def self.transcoder_name(encoding)
    Primitive.attr! :hidden
    name = encoding.name
    return HUB_NAMES[name][0] if HUB_NAMES.key?(name)

    row = SHAPES[name]
    row ? row[1] : name
  end

  # The names [source, destination] that ruby's transcoder from the
  # encoding named `a` to the one named `b` declares: a carrier's step
  # names both sides in its own way (UTF8-DOCOMO to SJIS-DOCOMO), and any
  # other step names each side as transcoder_name does.
  def self.transcoder_pair(a, b)
    Primitive.attr! :hidden
    hub = HUB_NAMES[a]
    return hub if hub && hub[1].casecmp?(b)

    hub = HUB_NAMES[b]
    return hub.reverse if hub && hub[1].casecmp?(a)

    [a, b].map { |name| (row = SHAPES[name]) ? row[1] : name }
  end
  private_class_method :shaped?, :shape_of, :transcoder_name, :transcoder_pair

  # Each byte read as the code point its encoding gives it.
  def self.to_utf8(text, path, options)
    Primitive.attr! :hidden
    from = text.encoding
    return units_to_utf8(text, from, replacement(path.last, options), options) if UNITS.key?(from.name)
    return mb_to_utf8(text, from, path, options) if mb?(from)
    return utf8_like_read(text, from, path, options) if utf8_like?(from)

    out = +""
    text.each_byte do |byte|
      if byte < 128
        out << byte
      elsif from.equal?(ASCII_8BIT)
        undefined(byte_text(byte), from, UTF_8, path, options, byte.chr.dup.force_encoding(from)) { |mark| out << mark }
      elsif from.equal?(US_ASCII)
        # US-ASCII has no byte past 127: each one is invalid.
        options[:invalid] == :replace ? out << replacement(path.last, options) : invalid([byte], nil, false, from.name)
      elsif (point = from.send(:points)[byte - 128])
        out << point
      else
        undefined(byte_text(byte), from, UTF_8, path, options, byte.chr.dup.force_encoding(from)) { |mark| out << mark }
      end
    end
    out
  end
  private_class_method :to_utf8

  # Each character written as the bytes the target gives its code point.
  def self.from_utf8(text, target, path, options)
    Primitive.attr! :hidden
    return utf8_like_write(text, target, path, options) if utf8_like?(target)

    unit, big = UNITS[target.name]
    big = true if unit && big.nil?
    writer = mb?(target) ? mb_writer(target) : nil
    points = unit || writer || target.equal?(ASCII_8BIT) || target.equal?(US_ASCII) || text.ascii_only? ? nil : target.send(:points)
    out = []
    utf8_points(text, replacement(target, options), options, target) do |point|
      bytes = point_bytes(point, unit, big, points, writer)
      bytes ||= ruled_bytes(point, target) if ruled?(target)
      if bytes
        out.concat(bytes)
      elsif options[:xml]
        out.concat("&#x#{format('%X', point)};".bytes)
      else
        undefined("U+#{point.to_s(16).upcase.rjust(4, '0')}", UTF_8, target, path, options, point.chr(UTF_8)) do |mark|
          mark.each_char { |char| out.concat(point_bytes(char.ord, unit, big, points, writer) || char.bytes) }
        end
      end
    end
    # A dummy name marks the byte order before the first character.
    out.unshift(*point_bytes(0xFEFF, unit, true, nil)) if unit && UNITS[target.name][1].nil? && !out.empty?
    out.pack("C*").force_encoding(target)
  end
  private_class_method :from_utf8

  # The bytes of code point `point` in the target: its code units, or
  # the one byte a table or ASCII gives it; nil when it has none.
  def self.point_bytes(point, unit, big, points, writer = nil)
    Primitive.attr! :hidden
    if unit
      units = unit == 4 || point < 0x10000 ? [point] : [0xD800 + ((point - 0x10000) >> 10), 0xDC00 + ((point - 0x10000) & 0x3FF)]
      units.map do |code|
        bytes = Array.new(unit) { |k| (code >> (8 * k)) & 0xFF }
        big ? bytes.reverse : bytes
      end.flatten(1)
    elsif point < 128
      [point]
    elsif writer
      writer[point]&.bytes
    elsif points && (found = points.index(point))
      [found + 128]
    end
  end
  private_class_method :point_bytes

  # econv_opts and rb_econv_prepare_options: invalid: and undef: take
  # only :replace, and a replacement is whole in its own encoding.
  def self.check_options(options)
    Primitive.attr! :hidden
    raise ArgumentError, +"unknown value for invalid character option" unless options[:invalid].nil? || options[:invalid] == :replace
    raise ArgumentError, +"unknown value for undefined character option" unless options[:undef].nil? || options[:undef] == :replace
    xml = options[:xml]
    unless xml.nil? || xml == :text || xml == :attr
      raise ArgumentError, xml.is_a?(Symbol) ? "unexpected value for xml option: #{xml}" : +"unexpected value for xml option"
    end

    replace = options[:replace]
    return if replace.nil?

    replace = Primitive.zr_convert_type(replace, String, :to_str)
    raise ArgumentError, "replacement string is broken: #{replace.dump} as #{replace.encoding}" unless replace.valid_encoding?
  end
  private_class_method :check_options

  # A converter that opens takes the replacement in its target encoding,
  # and does not open when it cannot have one. str_transcode0 opens none
  # when there is nothing to convert: the same encoding, or ASCII text
  # between two encodings that contain ASCII, with no decorator.
  def self.check_replacement(text, from, target, options)
    Primitive.attr! :hidden
    replace = options[:replace]
    return if replace.nil? || from.equal?(target)
    return if decorators(options).empty? && from.ascii_compatible? && target.ascii_compatible? && text.ascii_only?

    convert(String.try_convert(replace), target, {})
  rescue EncodingError
    raise ConverterNotFoundError, "code converter not found (#{from} to #{target})"
  end
  private_class_method :check_replacement

  # What `invalid: :replace` writes: the caller's text, else U+FFFD into
  # a Unicode encoding and "?" into any other.
  def self.replacement(target, options)
    Primitive.attr! :hidden
    options[:replace] || (target.equal?(UTF_8) || UNITS.key?(target.name) ? +"�" : +"?")
  end
  private_class_method :replacement

  # Each code point of UTF-8 `text`, on its way to `target`. Bytes UTF-8
  # does not allow raise as ruby's decoder words them, or become `mark`
  # once under `invalid: :replace`.
  def self.utf8_points(text, mark, options, target, source = UTF_8)
    Primitive.attr! :hidden
    bytes = text.bytes
    i = 0
    while i < bytes.size
      point, length, kind = utf8_step(bytes, i)
      if point
        yield point
      elsif options[:invalid] == :replace
        mark.each_char { |char| yield char.ord }
      else
        invalid(bytes[i, length], kind == :bad ? [bytes[i + length]] : nil, kind == :ended, source.name, target)
      end
      i += length
    end
  end
  private_class_method :utf8_points

  # The character at byte `i`: [code point, length], or [nil, length of
  # the bad bytes, how they went bad]. A lead byte UTF-8 never uses is
  # bad alone; a byte out of place ends the bad bytes before it, to be
  # read again; the end of the input inside a sequence leaves it
  # incomplete.
  def self.utf8_step(bytes, i)
    Primitive.attr! :hidden
    lead = bytes[i]
    return [lead, 1] if lead < 0x80

    need, low, high = UTF8_LEADS[lead]
    return [nil, 1, :lead] unless need

    point = lead & (0x3F >> need)
    (1..need).each do |k|
      byte = bytes[i + k]
      return [nil, k, :ended] if byte.nil?
      return [nil, k, :bad] unless byte.between?(k == 1 ? low : 0x80, k == 1 ? high : 0xBF)

      point = (point << 6) | (byte & 0x3F)
    end
    [point, need + 1]
  end
  private_class_method :utf8_step

  # Each code unit of a UTF-16 or UTF-32 String read as its code point,
  # written as UTF-8. A lone or unpaired surrogate, a UTF-32 unit past
  # Unicode or a short tail raises as ruby's decoder words it, or
  # becomes `mark` once under `invalid: :replace`.
  def self.units_to_utf8(text, from, mark, options)
    Primitive.attr! :hidden
    unit, big = UNITS.fetch(from.name)
    bytes = text.bytes
    points = []
    bad = lambda do |error, again, ended|
      next points.concat(mark.each_char.map(&:ord)) if options[:invalid] == :replace

      invalid(error, again, ended, from.name)
    end
    i = 0
    if big.nil?
      return +"" if bytes.empty?
      return bad.(bytes, nil, true) && points.pack("U*") if bytes.size < unit

      big = BOMS.fetch(unit).index(bytes.first(unit))&.zero?
      invalid(bytes.first(unit), nil, false, from.name) if big.nil?
      i = unit
    end
    while i < bytes.size
      kind, a, b = unit_step(bytes, i, unit, big)
      case kind
      when :char
        points << a
        i += b
      when :incomplete
        bad.(bytes[i..], nil, true)
        break
      else
        bad.(bytes[i, a], b.zero? ? nil : bytes[i + a, b], false)
        i += a
      end
    end
    points.pack("U*")
  end
  private_class_method :units_to_utf8

  # One step of the from_UTF_16LE/BE and from_UTF_32LE/BE transcoders
  # (enc/trans/utf_16_32.trans) at byte `at`: [:char, code point,
  # length], [:incomplete] where the text ends inside a character, or
  # [:invalid, error length, read-again length]. A byte the table
  # refuses inside the first unit takes the rest of that unit with it.
  def self.unit_step(bytes, at, unit, big)
    Primitive.attr! :hidden
    rest = bytes.size - at
    b = ->(k) { bytes[at + k] }
    refuse = ->(len) { len <= unit ? [:invalid, [unit, rest].min, 0] : [:invalid, ((len - 1) / unit) * unit, len - ((len - 1) / unit) * unit] }
    if unit == 2
      hi = big ? 0 : 1
      return [:incomplete] if rest < 1 + hi
      return refuse.(1 + hi) if b.(hi).between?(0xDC, 0xDF)
      return [:incomplete] if rest < 2

      code = big ? (b.(0) << 8) | b.(1) : (b.(1) << 8) | b.(0)
      return [:char, code, 2] unless b.(hi).between?(0xD8, 0xDB)
      return [:incomplete] if rest < 3 + hi
      return refuse.(3 + hi) unless b.(2 + hi).between?(0xDC, 0xDF)
      return [:incomplete] if rest < 4

      low = big ? (b.(2) << 8) | b.(3) : (b.(3) << 8) | b.(2)
      return [:char, 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00), 4]
    end
    if big
      return refuse.(1) unless b.(0) == 0
      return [:incomplete] if rest < 2
      return refuse.(2) unless b.(1) <= 0x10
      return [:incomplete] if rest < 3
      return refuse.(3) if b.(1) == 0 && b.(2).between?(0xD8, 0xDF)
      return [:incomplete] if rest < 4

      return [:char, (b.(1) << 16) | (b.(2) << 8) | b.(3), 4]
    end
    return [:incomplete] if rest < 2
    return [:incomplete] if rest < 3
    return refuse.(3) unless b.(2) <= 0x10 && (b.(2) != 0 || !b.(1).between?(0xD8, 0xDF))
    return [:incomplete] if rest < 4
    return refuse.(4) unless b.(3) == 0

    [:char, (b.(2) << 16) | (b.(1) << 8) | b.(0), 4]
  end
  private_class_method :unit_step

  # Each character of a multibyte String read as its code point, written
  # as UTF-8. The entries show where a character ends: a slot that starts
  # a longer one continues the walk. A slot with no code point is a
  # character that this pair cannot convert. No slot at all is bytes
  # that make no character.
  def self.mb_to_utf8(text, from, path, options)
    Primitive.attr! :hidden
    table = mb_table(from)
    mark = replacement(UTF_8, options)
    bytes = text.bytes
    out = +""
    i = 0
    while i < bytes.size
      if bytes[i] < 0x80
        out << bytes[i]
        i += 1
        next
      end
      if ruled?(from) && (ruled = ruled_char(bytes, i, from, path, options))
        out << ruled[0]
        i += ruled[1]
        next
      end
      prefix = +"".b
      steps = 0
      slot = nil
      while (row = table[prefix]) && (at = bytes[i + steps]) && (slot = row[at]) == :more
        prefix << at
        steps += 1
      end
      # A partial encoding's rows stop at the characters every row of
      # which was read; the walk reaches the longer ones and says so.
      if row.nil? && steps.positive? && Primitive.zr_table_member_p(MB_PARTIAL, from.name)
        Primitive.zr_unimplemented("String#encode of a #{from} character of more than two bytes")
      end
      slot = nil unless row && bytes[i + steps]
      whole = bytes[i, steps + 1]
      if slot.is_a?(Integer) || slot.is_a?(String)
        out << slot
      elsif slot == true
        undefined(whole.pack("C*").dump, from, UTF_8, path, options,
                  whole.pack("C*").dup.force_encoding(from)) { |text_mark| out << text_mark }
      elsif options[:invalid] == :replace
        out << mark
        # The byte that broke the sequence is read again, as ruby's
        # decoder reads it: it may start a character of its own.
        i -= 1 if steps.positive? && bytes[i + steps]
      elsif steps.zero?
        invalid([bytes[i]], nil, false, from.name)
      else
        invalid(bytes[i, steps], bytes[i + steps] ? [bytes[i + steps]] : nil, bytes[i + steps].nil?, from.name)
      end
      i += steps + 1
    end
    out
  end
  private_class_method :mb_to_utf8

  # An encoding that writes its characters as UTF-8 writes them: only
  # the form parts. UTF8-MAC stores each one decomposed, which ruby
  # calls NFD, and reads it back composed.
  def self.utf8_like_read(text, from, path, options)
    Primitive.attr! :hidden
    return exchange(text, UTF_8, path, options) if carrier?(from)

    text = text.dup.force_encoding(UTF_8)
    unless text.valid_encoding?
      # ruby's UTF8-MAC decoder marks a bad byte "?"; without the option
      # the bad bytes stop as UTF-8's decoder words them.
      mark = options[:replace] || +"?"
      utf8_points(text, mark, options, UTF_8, from) { nil } unless options[:invalid] == :replace
      text = text.scrub(mark)
    end
    text.unicode_normalize(:nfc)
  end

  def self.utf8_like_write(text, target, path, options)
    Primitive.attr! :hidden
    return exchange(text, target, path, options) if carrier?(target)

    text = text.unicode_normalize(:nfd)
    return text.dup.force_encoding(target) unless text.each_codepoint.any? { |point| point >= 0x100000 }

    # Ruby's UTF8-MAC table has no lead byte F4: a character of plane 16
    # is undefined in it.
    out = +""
    text.each_char do |char|
      point = char.ord
      if point < 0x100000
        out << char
      elsif options[:xml]
        out << "&#x#{format('%X', point)};"
      else
        undefined("U+#{format('%04X', point)}", UTF_8, target, path, options, char) { |mark| out << mark }
      end
    end
    out.force_encoding(target)
  end

  # `text`, in UTF-8 or a carrier's encoding, into `target`, the other
  # of the two or another carrier's: each emoji the pair exchanges
  # becomes the target's own, and every other character stays as it is.
  def self.exchange(text, target, path, options)
    Primitive.attr! :hidden
    from = text.encoding
    table = emoji(from, target)
    out = +""
    utf8_points(text, replacement(target, options), options, target, from) do |point|
      if !table.key?(point)
        out << point
      elsif (points = table[point])
        points.each { |each| out << each }
      elsif options[:xml]
        out << "&#x#{format('%X', point)};"
      else
        char = point.chr(UTF_8)
        shown = from.equal?(UTF_8) ? "U+#{format('%04X', point)}" : char.b.dump
        undefined(shown, from, target, path, options, char.force_encoding(from)) { |mark| out << mark }
      end
    end
    out.force_encoding(target)
  end
  private_class_method :utf8_like_read, :utf8_like_write, :exchange

  # The transcoders' own names for the step between a carrier's
  # Shift_JIS or JIS and the carrier's UTF-8, which ruby's failures use.
  HUB_NAMES = {
    "SJIS-DoCoMo" => %w[SJIS-DOCOMO UTF8-DOCOMO], "SJIS-KDDI" => %w[SJIS-KDDI UTF8-KDDI],
    "SJIS-SoftBank" => %w[SJIS-SoftBank UTF8-SoftBank],
    "stateless-ISO-2022-JP-KDDI" => %w[stateless-ISO-2022-JP-KDDI UTF8-KDDI]
  }.freeze
  private_constant :HUB_NAMES

  # Whether ruby converts between the two directly (japanese.trans).
  def self.jis_pair?(from, target)
    Primitive.attr! :hidden
    names = [from.name, target.name]
    names == %w[EUC-JP Shift_JIS] || names == %w[Shift_JIS EUC-JP]
  end
  private_class_method :jis_pair?

  # japanese.trans: EUC-JP and Shift_JIS convert to each other by
  # arithmetic on the JIS row and cell, not through Unicode, so a code
  # that Unicode has no character for still converts.
  def self.jis_direct(text, from, target, options)
    Primitive.attr! :hidden
    bytes = text.b
    euc = from.name == "EUC-JP"
    out = +"".b
    at = 0
    while at < bytes.bytesize
      byte = bytes.getbyte(at)
      if byte < 0x80
        out << byte
        at += 1
        next
      end
      kind, size, written, again = euc ? euc_to_sjis(bytes, at) : sjis_to_euc(bytes, at)
      case kind
      when :ok then out << written
      when :undef
        piece = bytes.byteslice(at, size)
        unless options[:undef] == :replace
          raise char_error("#{piece.dump} from #{from.name} to #{target.name}", from, target, piece.force_encoding(from))
        end

        out << (options[:replace] || +"?").encode(target).b
      else
        unless options[:invalid] == :replace
          invalid(bytes.byteslice(at, size).bytes, again && [again], kind == :incomplete, from.name, target)
        end

        out << (options[:replace] || +"?").encode(target).b
      end
      at += size
    end
    out.force_encoding(target)
  end
  private_class_method :jis_direct

  # One EUC-JP character from `at`, as fun_so_eucjp2sjis writes it:
  # [:ok, size, bytes], [:undef, size], or the error with the byte read
  # again after it.
  def self.euc_to_sjis(bytes, at)
    Primitive.attr! :hidden
    lead = bytes.getbyte(at)
    trail = ->(i) { bytes.getbyte(at + i) }
    euc_byte = ->(b) { b&.between?(0xA1, 0xFE) }
    case lead
    when 0x8E
      return [:incomplete, 1] if trail.(1).nil?
      return [:invalid, 1, nil, trail.(1)] unless euc_byte.(trail.(1))

      trail.(1) <= 0xDF ? [:ok, 2, trail.(1).chr] : [:undef, 2]
    when 0x8F
      return [:incomplete, 1] if trail.(1).nil?
      return [:invalid, 1, nil, trail.(1)] unless euc_byte.(trail.(1))
      return [:incomplete, 2] if trail.(2).nil?
      return [:invalid, 2, nil, trail.(2)] unless euc_byte.(trail.(2))

      [:undef, 3]
    when 0xA1..0xFE
      return [:incomplete, 1] if trail.(1).nil?
      return [:invalid, 1, nil, trail.(1)] unless euc_byte.(trail.(1))

      odd = lead & 1
      high = ((lead + odd) >> 1) + (lead < 0xDF ? 0x30 : 0x70)
      low = trail.(1) - (odd * 94) - 3
      low += 1 if low >= 0x7F
      [:ok, 2, [high, low].pack("C2")]
    else [:invalid, 1]
    end
  end
  private_class_method :euc_to_sjis

  # One Shift_JIS character from `at`, as fun_so_sjis2eucjp writes it.
  def self.sjis_to_euc(bytes, at)
    Primitive.attr! :hidden
    lead = bytes.getbyte(at)
    return [:ok, 1, [0x8E, lead].pack("C2")] if lead.between?(0xA1, 0xDF)
    return [:invalid, 1] unless lead.between?(0x81, 0x9F) || lead.between?(0xE0, 0xFC)

    low = bytes.getbyte(at + 1)
    return [:incomplete, 1] if low.nil?
    return [:invalid, 1, nil, low] unless low.between?(0x40, 0x7E) || low.between?(0x80, 0xFC)
    return [:undef, 2] if lead >= 0xF0

    high = lead >= 0xE0 ? lead - 64 : lead
    low += low < 0x80 ? 0x61 : 0x60
    high = (high * 2) - 0x61
    if low > 0xFE
      low -= 94
      high += 1
    end
    [:ok, 2, [high, low].pack("C2")]
  end
  private_class_method :sjis_to_euc

  # A carrier's Shift_JIS or JIS reads into the carrier's own UTF-8 and
  # writes out of it, as ruby's converters do: the carrier's emoji are
  # private-use code points there, and the exchange with Unicode or with
  # another carrier is a separate step. The path shows each hub step
  # with its transcoder's name.
  def self.hub_convert(text, from, target, options)
    Primitive.attr! :hidden
    read = MB_HUBS[from.name] && find(MB_HUBS[from.name])
    write = MB_HUBS[target.name] && find(MB_HUBS[target.name])
    start = read || from
    goal = write || target
    unicode = ->(encoding) { encoding.equal?(UTF_8) || carrier?(encoding) }
    between = if start.equal?(goal) then []
              elsif unicode[start] && unicode[goal] then [goal]
              else [UTF_8, goal]
              end
    path = [from]
    path << HUB_NAMES[from.name][1] if read
    path.concat(between)
    path << HUB_NAMES[target.name][0] if write

    text = hub_read(text, from, read, path, options) if read
    at = start
    between.each do |step|
      text = if unicode[at] && unicode[step] then exchange(text, step, path, options)
             elsif step.equal?(UTF_8) then convert(text, UTF_8, options)
             else from_utf8(text, step, path, options)
             end
      at = step
    end
    write ? hub_write(text, write, target, path, options) : text
  end

  def self.hub_read(text, from, hub, path, options)
    Primitive.attr! :hidden
    mb_to_utf8(text, from, path, options).force_encoding(hub)
  rescue InvalidByteSequenceError => e
    source, destination = HUB_NAMES[from.name]
    message = "#{e.message.delete_suffix(" on #{from.name}")} on #{source}"
    raise byte_error(message, from, hub, e.error_bytes, e.readagain_bytes, e.incomplete_input?).send(:named, source, destination)
  end

  # Each code point of the carrier's UTF-8 in the carrier's own bytes.
  def self.hub_write(text, hub, target, path, options)
    Primitive.attr! :hidden
    writer = mb_writer(target)
    source, destination = HUB_NAMES[target.name]
    out = []
    utf8_points(text, replacement(target, options), options, target, hub) do |point|
      if (bytes = point_bytes(point, nil, nil, nil, writer))
        out.concat(bytes)
        next
      end
      char = point.chr(UTF_8).force_encoding(hub)
      if options[:undef] == :replace
        out.concat(convert(options[:replace] || "?", target, {}).bytes)
      elsif (given = fallback(options[:fallback], char, options[:__source__]))
        written = begin
          given.encode(target)
        rescue EncodingError
          raise ArgumentError, +"too big fallback string"
        end
        out.concat(written.bytes)
      elsif options[:xml]
        out.concat("&#x#{format('%X', point)};".bytes)
      else
        named = path.map { |step| step.is_a?(String) ? step : transcoder_name(step) }.join(" to ")
        raise char_error("#{char.b.dump} to #{source} in conversion from #{named}", hub, target, char)
                .send(:named, destination, source)
      end
    end
    out.pack("C*").force_encoding(target)
  end
  private_class_method :hub_convert, :hub_read, :hub_write

  # Ruby's words for bytes that a decoder cannot read: `incomplete` when
  # the input ends inside them, else `followed by` the bytes it reads
  # again. The failure gives the ends of the step that read them: the
  # decoding into UTF-8, or from UTF-8 the one step to the target.
  def self.invalid(error, again, ended, name, destination = UTF_8)
    Primitive.attr! :hidden
    shown = error.pack("C*").dump
    text = if ended then "incomplete #{shown}"
           elsif again then "#{shown} followed by #{again.pack('C*').dump}"
           else shown
           end
    # The failure describes itself, as CRuby's does: it contains the
    # bytes where it stopped and the bytes it will read again.
    raise byte_error("#{text} on #{name}", find(name), destination, error.pack("C*"), again&.pack("C*"), ended)
  end
  private_class_method :invalid

  # A byte or a character the step cannot write: replaced when the
  # caller asked for that, else ruby's own error, worded for the whole
  # path.
  def self.undefined(shown, from, to, path, options, char = nil)
    Primitive.attr! :hidden
    if options[:undef] == :replace
      replacement = options[:replace] || (to.equal?(UTF_8) ? +"\uFFFD" : +"?")
      return yield(replacement)
    end
    if char && (text = fallback(options[:fallback], char, options[:__source__]))
      written = begin
        text.encode(to)
      rescue EncodingError
        raise ArgumentError, +"too big fallback string"
      end
      return yield(written.encode(UTF_8))
    end

    # The failure contains the character where it stopped, as CRuby's does.
    raise char_error(message(shown, from, to, path), from, to, char)
  end
  private_class_method :undefined

  # The text that a `fallback:` gives for a character the target cannot
  # encode, as transcode_loop calls it: a Proc or a Method is called,
  # and a Hash or any other object that responds to `[]` is indexed.
  # nil when there is no fallback, or when the option gives no usable object.
  # `watched` is the String being converted, with its size, which the
  # fallback must leave alone.
  def self.fallback(fallback, char, watched = nil)
    Primitive.attr! :hidden
    return nil if fallback.nil?

    fallback = Hash.try_convert(fallback) || fallback
    text = case fallback
           when Proc, Method then fallback.call(char)
           else
             return nil unless fallback.respond_to?(:[])

             fallback.public_send(:[], char)
           end
    raise RuntimeError, "string modified" if watched && Primitive.zr_str_bytesize(watched[0]) != watched[1]
    return nil if text.nil?

    Primitive.zr_convert_type(text, String, :to_str)
  end
  private_class_method :fallback

  # `X from A to B` for a single step that ruby words that way, else the
  # chain form, which gives every encoding on the path.
  def self.message(shown, from, to, path)
    Primitive.attr! :hidden
    other = to.equal?(UTF_8) ? from : to
    row = shape_of(other)
    return "#{shown} from #{transcoder_name(from)} to #{transcoder_name(to)}" if path.size == 2 && (to.equal?(UTF_8) ? row[2] : row[0])

    step = to.equal?(UTF_8) ? +"UTF-8" : row[1]
    # A hub step shows in the path as its transcoder's own name.
    named = path.map { |encoding| encoding.is_a?(String) ? encoding : (encoding.equal?(to) ? step : transcoder_name(encoding)) }
    "#{shown} to #{step} in conversion from #{named.join(' to ')}"
  end
  private_class_method :message

  def self.byte_text(byte)
    Primitive.attr! :hidden
    "\"\\x#{format('%02X', byte)}\""
  end
  private_class_method :byte_text

  def self.list = LIST.dup

  # Every name, and `internal` for the encoding a read converts to.
  def self.name_list
    names = LIST.flat_map(&:names)
    default_internal ? names : names << "internal"
  end

  # Every name but the first of each encoding, pointing at the first.
  # `locale`, `external` and `filesystem` name the encodings they stand
  # for now, not the ones the table lists.
  def self.aliases
    names = LIST.each_with_object({}) { |encoding, out| encoding.names.drop(1).each { |name| out[name] = encoding.name } }
    names.merge("locale" => locale_encoding.name, "external" => default_external.name, "filesystem" => default_external.name)
  end

  # The codeset of the locale that the environment named as the program
  # started, as ruby's main sets it with setlocale(LC_CTYPE, ""). WASI
  # has no locale; there it is what wasi-libc, a musl, gives: "ASCII" for
  # the C locale and "UTF-8" for any other.
  def self.locale_charmap = LOCALE[0].dup

  # The locale's encoding (rb_locale_encindex): the charmap's encoding, or
  # UTF-8 for a name that no encoding has.
  def self.locale_encoding
    Primitive.attr! :hidden
    LOCALE[1] ||= by_name[LOCALE[0].upcase(:ascii)]&.send(:load) || UTF_8
  end

  def self.read_locale
    Primitive.attr! :hidden
    charmap = Primitive.zr_os_locale_charmap
    unless charmap
      name = %w[LC_ALL LC_CTYPE LANG].map { |var| Primitive.zr_environment_get(var) }.find { |value| value && !value.empty? }
      charmap = %w[C POSIX].include?(name) ? +"ASCII" : +"UTF-8"
    end
    Primitive.zr_str_usascii(charmap).freeze
  end

  # The charmap, read as the program starts, and its encoding once asked.
  LOCALE = [read_locale, nil]
  private_constant :LOCALE

  # A path that the system gives (a directory's entries, the working
  # directory, the program's name) is in the default external encoding,
  # as rb_filesystem_encoding is on a POSIX system. The kernel tags such
  # Strings (`zr_path_str`); under a UTF-8 locale it has nothing to do.
  # core/env.rb starts it, once every encoding's methods are defined.
  def self.follow_paths
    Primitive.attr! :hidden
    Primitive.zr_path_index_set(carried(default_external))
  end

  def self.find(name)
    found = lookup(name) { |message| message }
    raise ArgumentError, found if found.is_a?(String)

    found
  end

  # The encoding that `name` names. For a name that names none, the block
  # gets the message of find's ArgumentError and gives the result, so the
  # core asks about a name without a raise (which a trace would see).
  def self.lookup(name)
    Primitive.attr! :hidden
    return name if name.is_a?(Encoding)

    text = Primitive.zr_convert_type(name, String, :to_str)
    # rb_to_encoding_index: a name must be in an ASCII-compatible encoding.
    return yield(+"invalid encoding name (non ASCII)") unless text.encoding.ascii_compatible?
    # rb_enc_find_index: a NUL ends the C string, so a name has none.
    return yield(+"invalid encoding name (NUL byte)") if text.include?("\0")

    if text.ascii_only?
      key = text.upcase(:ascii)
      # These follow the defaults: each is whatever its default is, nil too.
      return default_internal if key == +"INTERNAL"
      return default_external if key == +"EXTERNAL" || key == +"FILESYSTEM"
      return locale_encoding if key == +"LOCALE"
    end
    if (found = by_name[text])
      nil
    elsif key
      found = by_name[key]
    else
      found = LIST.find { |encoding| encoding.names.any? { |n| n.casecmp?(text) } }
    end
    return found.send(:load) if found

    yield "unknown encoding name - #{text}"
  end
  private_class_method :lookup

  # Each name of an encoding, as written and upper-cased, mapped to the
  # first encoding in the list that has it. This makes a lookup by an
  # ASCII name (every encoding name is ASCII) one step.
  def self.by_name
    Primitive.attr! :hidden
    @by_name ||= {}.tap do |index|
      LIST.each do |encoding|
        encoding.send(:listed_names).each do |name|
          index[name.upcase(:ascii)] ||= encoding
          index[name] ||= encoding
        end
      end
    end
  end

  # Both ends of a conversion, the target first, as str_transcode_enc_args
  # reads them. A name that matches no encoding is not an ArgumentError
  # here: ruby looks for a converter by the two names and finds none. Two
  # such names that are the same but for case are no conversion
  # (encoding_equal), and give BINARY at both ends.
  def self.pair(source, target)
    Primitive.attr! :hidden
    to = lookup(target) { nil }
    dname = to ? to.name : c_name(target)
    from = lookup(source) { nil }
    sname = from ? from.name : c_name(source)
    return [from, to] if from && to
    return [BINARY, BINARY] if !from && !to && sname.casecmp?(dname)

    shown = if sname.empty? then dname
            elsif dname.empty? then sname
            else "#{sname.b} to #{dname.b}"
            end
    raise ConverterNotFoundError, "code converter not found (#{shown.b})"
  end

  # An encoding name that names none, as econv reads it (StringValueCStr):
  # its bytes up to the first NUL, as BINARY. A NUL inside it is an error;
  # in a wide encoding, a NUL character is.
  def self.c_name(name)
    Primitive.attr! :hidden
    text = Primitive.zr_convert_type(name, String, :to_str)

    bytes = text.b
    if wide?(text.encoding)
      raise ArgumentError, +"string contains null char" if text.each_char.any? { |c| c.bytes.all?(0) }
    elsif bytes.include?("\0")
      raise ArgumentError, +"string contains null byte"
    end
    bytes.byteslice(0, bytes.index("\0") || bytes.bytesize)
  end
  private_class_method :c_name

  # The external and internal encodings a program set, nil for the ones
  # it did not: the locale's encoding and none.
  DEFAULTS = [nil, nil]
  private_constant :DEFAULTS

  def self.default_external = DEFAULTS[0] || locale_encoding

  def self.default_internal = DEFAULTS[1]

  # The external encoding is also the one "external" and "filesystem"
  # name, as enc_set_default_encoding moves both aliases.
  def self.default_external=(encoding)
    Warning.warn("#{Primitive.zr_warn_position}warning: setting Encoding.default_external\n") if $VERBOSE
    raise ArgumentError, +"default external can not be nil" if encoding.nil?

    store_default(0, encoding)
  end

  def self.default_internal=(encoding)
    Warning.warn("#{Primitive.zr_warn_position}warning: setting Encoding.default_internal\n") if $VERBOSE
    store_default(1, encoding)
  end

  # enc_set_default_encoding: the setters' work, which ruby's -E option
  # also does, with no warning.
  def self.store_default(slot, encoding)
    Primitive.attr! :hidden
    DEFAULTS[slot] = encoding.nil? ? nil : find(encoding)
    follow_paths if slot.zero?
    inspect_target
    encoding
  end
  private_class_method :store_default

  # Tells the kernel rb_str_inspect's result encoding: default_internal,
  # else default_external, and US-ASCII when that is not ASCII compatible.
  # A character prints as itself only when its String is in this encoding.
  def self.inspect_target
    Primitive.attr! :hidden
    target = default_internal || default_external
    Primitive.zr_inspect_index_set((target.ascii_compatible? ? target : US_ASCII).index)
  end

  # The names that follow the defaults, rather than one encoding.
  MOVING = %w[locale external filesystem internal].freeze
  private_constant :MOVING

  # The boot-time reader above stays: the registry runs before this file ends.
  def names # rubocop:disable Lint/DuplicateMethods
    moving = []
    moving << "locale" if equal?(Encoding.locale_encoding)
    moving.push("external", "filesystem") if equal?(Encoding.default_external)
    moving << "internal" if equal?(Encoding.default_internal)
    return @names if moving == @names & MOVING

    (@names - MOVING + moving.map { |name| Primitive.zr_str_usascii(name.dup).freeze }).freeze
  end

  # The encodings a conversion passes through, ruby's own converter
  # pairs being the only steps it may take: the shortest way from one
  # name to the other.
  def self.convpath_for(source, destination, shown)
    Primitive.attr! :hidden
    ends = [source, destination].map { |name| LIST.find { |encoding| encoding.names.any? { |other| other.casecmp?(name) } } }
    if ends.all?
      queue = [[ends.first]]
      seen = { ends.first.name => true }
      until queue.empty?
        path = queue.shift
        return path if path.last.equal?(ends.last)

        CONVERTERS.each do |from, to|
          next unless from == path.last.name
          next if seen[to]

          seen[to] = true
          queue << (path + [find(to)])
        end
      end
    end
    raise ConverterNotFoundError, "code converter not found (#{source} to #{destination}#{shown})"
  end

  # econv_opts' line ends, by decorator name: `newline:` names one and
  # wins over the older booleans, which can name several, and the
  # conversion then finds no converter. A nil names none.
  NEWLINE_OPTIONS = %i[universal_newline crlf_newline cr_newline lf_newline].freeze
  private_constant :NEWLINE_OPTIONS

  def self.newline_decorators(options)
    Primitive.attr! :hidden
    given = NEWLINE_OPTIONS.reject { |name| options[name].nil? }
    if options[:newline].nil?
      given.select { |name| options[name] }
    else
      Primitive.zr_warn_here_m(":newline option precedes other newline options") if $VERBOSE && !given.empty?
      [newline_decorator(options[:newline])]
    end
  end

  # The options with their line end as one `newline:`, or none. Two line
  # ends are no conversion that ruby has.
  def self.one_newline(options, from, target)
    Primitive.attr! :hidden
    lines = newline_decorators(options)
    if lines.size > 1
      ends = from.equal?(target) ? +"" : "#{from} to #{target} with "
      raise ConverterNotFoundError, "code converter not found (#{ends}#{lines.join(',')})"
    end
    options = options.except(:newline, *NEWLINE_OPTIONS)
    lines.empty? ? options : options.merge(newline: lines.first.to_s.delete_suffix("_newline").to_sym)
  end

  # The decorator a `newline:` option names. A name that is no Symbol is
  # not shown, as CRuby's own check writes it.
  def self.newline_decorator(kind)
    Primitive.attr! :hidden
    case kind
    when :universal then :universal_newline
    when :crlf then :crlf_newline
    when :cr then :cr_newline
    when :lf then :lf_newline
    else raise ArgumentError, kind.is_a?(Symbol) ? "unexpected value for newline option: #{kind}" : +"unexpected value for newline option"
    end
  end

  # What writing a code point into `target` needs: the width and order
  # of its code units, its byte table, its multibyte entries, and whether
  # it writes UTF-8 or keeps a state between characters.
  def self.writing(target)
    Primitive.attr! :hidden
    unit, big = UNITS[target.name]
    big = true if unit && big.nil?
    writer = mb?(target) ? mb_writer(target) : nil
    points = unit || writer || target.equal?(ASCII_8BIT) || target.equal?(US_ASCII) || !tabled?(target) ? nil : target.send(:points)
    [unit, big, points, writer, target.equal?(UTF_8) || utf8_like?(target), target.name.start_with?("ISO-2022-JP", "CP5022")]
  end

  # enc_compatible_p: the encoding that two objects with encodings can
  # join in, or nil. A String, a Symbol, a Regexp, an IO and an Encoding
  # have one. A String's encoding is read from its own bytes, so a
  # subclass's encoding, empty? and ascii_only? are not called.
  def self.compatible?(a, b)
    ea = encoding_of(a) or return nil
    eb = encoding_of(b) or return nil
    return ea if ea == eb

    a_string = a.is_a?(String)
    b_string = b.is_a?(String)
    return ea if b_string && Primitive.zr_str_bytesize(b) == 0
    return ea.ascii_compatible? && Primitive.zr_str_ascii_only_m(b) ? ea : eb if a_string && b_string && Primitive.zr_str_bytesize(a) == 0
    return nil unless ea.ascii_compatible? && eb.ascii_compatible?
    # An object that is not a String has no bytes to check: only its encoding counts.
    return ea if !b_string && eb == US_ASCII
    return eb if !a_string && ea == US_ASCII
    # All ASCII, a String takes the other side's encoding; two Strings
    # that both are take the first one's.
    a_ascii = a_string && Primitive.zr_str_ascii_only_m(a)
    b_ascii = b_string && Primitive.zr_str_ascii_only_m(b)
    return ea if a_string && b_ascii
    return eb if a_ascii || b_ascii

    nil
  end

  # rb_enc_get_index: the encoding of `object`, or nil for an object
  # with no encoding. is_a? rather than case: String's own boot runs
  # before Module#=== is defined.
  def self.encoding_of(object)
    Primitive.attr! :hidden
    if object.is_a?(String)
      at(Primitive.zr_str_encoding_index_m(object))
    elsif object.is_a?(Symbol) || object.is_a?(Regexp)
      object.encoding
    elsif object.is_a?(Encoding)
      object
    elsif object.is_a?(IO)
      object.internal_encoding || object.external_encoding
    end
  end
end
