# The ISO-2022-JP family: stateful encodings, whose two-byte characters
# stand between escapes. Ruby converts one through a multibyte encoding
# that holds the same characters without a state: ISO-2022-JP through
# stateless-ISO-2022-JP and EUC-JP, CP50220 and CP50221 through CP51932.
class Encoding
  # Each stateful encoding: the multibyte encoding it converts through,
  # the stateless one between the two, and what becomes of a halfwidth
  # katakana, which ISO-2022-JP cannot hold, CP50221 holds as a set of
  # its own, and CP50220 writes as the fullwidth one.
  STATEFUL = {
    "ISO-2022-JP" => ["EUC-JP", "stateless-ISO-2022-JP", nil],
    "CP50220" => ["CP51932", nil, :fullwidth],
    "CP50221" => ["CP51932", nil, :set]
  }.freeze

  ESCAPES = { "\e(B" => :ascii, "\e(J" => :ascii, "\e$B" => :kanji, "\e$@" => :kanji, "\e(I" => :kana }.freeze
  SHIFTS = { ascii: "\e(B", kanji: "\e$B", kana: "\e(I" }.freeze

  # The halfwidth katakana from U+FF61 up, and the fullwidth ones CP50220
  # writes for them; a voiced or semi-voiced mark joins the one before it
  # where that one takes it.
  HALFWIDTH = "｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝﾞﾟ"
  FULLWIDTH = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン゛゜"
  VOICED = "カキクケコサシスセソタチツテトハヒフヘホ"
  SEMI_VOICED = "ハヒフヘホ"
  private_constant :STATEFUL, :ESCAPES, :SHIFTS, :HALFWIDTH, :FULLWIDTH, :VOICED, :SEMI_VOICED

  def self.stateful?(encoding)
    Primitive.attr! :hidden
    STATEFUL.key?(encoding.name)
  end

  # UTF-8 `text` in `target`: its characters in the multibyte encoding,
  # then each run of them behind the escape that names its set, and the
  # text back in ASCII at its end.
  def self.stateful_write(text, target, options)
    Primitive.attr! :hidden
    base_name, stateless_name, kana = STATEFUL.fetch(target.name)
    base = find(base_name)
    step = stateless_name ? find(stateless_name) : target
    path = [UTF_8, base, stateless_name && step, target].compact
    text = fullwidth(text) if kana == :fullwidth
    bytes = send(:from_utf8, text, base, path, options).b
    out = +"".b
    mode = :ascii
    shift = lambda do |to|
      out << SHIFTS.fetch(to) unless mode == to
      mode = to
    end
    at = 0
    while at < bytes.bytesize
      byte = bytes.getbyte(at)
      if byte < 0x80
        shift.call(:ascii)
        out << byte
        at += 1
      elsif byte == 0x8E && kana == :set
        shift.call(:kana)
        out << (bytes.getbyte(at + 1) & 0x7F)
        at += 2
      elsif byte == 0x8E || byte == 0x8F
        width = byte == 0x8E ? 2 : 3
        piece = bytes.byteslice(at, width)
        mark = stateful_undefined(piece, base, step, path, options)
        shift.call(:ascii)
        out << mark.b
        at += width
      else
        shift.call(:kanji)
        out << (byte & 0x7F) << (bytes.getbyte(at + 1) & 0x7F)
        at += 2
      end
    end
    shift.call(:ascii)
    out.force_encoding(target)
  end

  # A character the multibyte step wrote that the stateful encoding has
  # no set for: the replacement the caller asked for, else ruby's error.
  def self.stateful_undefined(piece, base, step, path, options)
    Primitive.attr! :hidden
    return options[:replace] || "?" if options[:undef] == :replace || options[:invalid] == :replace

    message = "#{piece.dump} to #{step.name} in conversion from #{path.map(&:name).join(' to ')}"
    raise send(:char_error, message, base, step, piece.dup.force_encoding(base))
  end

  # `text` in a stateful encoding read into UTF-8: each escape sets how
  # the bytes after it read, and they read as the multibyte encoding's.
  def self.stateful_read(text, options)
    Primitive.attr! :hidden
    from = text.encoding
    base_name, stateless_name, kana = STATEFUL.fetch(from.name)
    base = find(base_name)
    step = stateless_name ? find(stateless_name) : base
    path = [from, stateless_name && step, base, UTF_8].compact
    bytes = text.b
    out = +"".b
    mode = :ascii
    at = 0
    while at < bytes.bytesize
      byte = bytes.getbyte(at)
      if byte == 0x1B
        mode, at = escape_at(bytes, at, from, step, kana)
      elsif mode == :ascii
        # An eight-bit byte is the multibyte encoding's to read, where a
        # stateless one does not stand between.
        stateful_invalid([byte], nil, false, from, step) if byte >= 0x80 && stateless_name
        out << byte
        at += 1
      elsif mode == :kana
        stateful_invalid([byte], nil, false, from, step) unless byte.between?(0x21, 0x5F)
        out << 0x8E << (byte | 0x80)
        at += 1
      else
        stateful_invalid([byte], nil, false, from, step) unless byte.between?(0x21, 0x7E)
        second = bytes.getbyte(at + 1)
        stateful_invalid([byte], nil, true, from, step) if second.nil?
        stateful_invalid([byte], [second], false, from, step) unless second.between?(0x21, 0x7E)
        out << (byte | 0x80) << (second | 0x80)
        at += 2
      end
    end
    send(:mb_to_utf8, out.force_encoding(base), base, path, options)
  end

  # The set the escape at `at` names, and where the bytes after it start.
  def self.escape_at(bytes, at, from, step, kana)
    Primitive.attr! :hidden
    sequence = bytes.byteslice(at, 3)
    mode = ESCAPES[sequence]
    return [mode, at + 3] if mode && (mode != :kana || kana == :set)

    # The longest start of an escape the bytes make, and the byte that
    # stops it there.
    read = sequence.bytesize.downto(1).find { |n| ESCAPES.keys.any? { |escape| escape.start_with?(sequence.byteslice(0, n)) && escape.bytesize > n } } || 1
    read = 2 if mode == :kana
    head = bytes.byteslice(at, read).bytes
    after = bytes.getbyte(at + read)
    stateful_invalid(head, nil, true, from, step) if after.nil?
    stateful_invalid(head, [after], false, from, step)
  end

  def self.stateful_invalid(error, again, ended, from, step)
    Primitive.attr! :hidden
    send(:invalid, error, again, ended, from.name, step)
  end

  # CP50220's halfwidth katakana, each as its fullwidth one.
  def self.fullwidth(text)
    Primitive.attr! :hidden
    out = +""
    # Whether the last character came from a halfwidth one, which alone
    # takes a mark after it.
    joins = false
    text.each_char do |char|
      index = HALFWIDTH.index(char)
      if index.nil?
        out << char
        joins = false
        next
      end
      wide = FULLWIDTH[index]
      last = out[-1]
      if joins && wide == "゛" && VOICED.include?(last)
        out[-1] = (last.ord + 1).chr(UTF_8)
        joins = false
      elsif joins && wide == "゜" && SEMI_VOICED.include?(last)
        out[-1] = (last.ord + 2).chr(UTF_8)
        joins = false
      else
        out << wide
        joins = true
      end
    end
    out
  end
  private_class_method :stateful?, :stateful_write, :stateful_undefined, :stateful_read, :escape_at, :stateful_invalid, :fullwidth
end
