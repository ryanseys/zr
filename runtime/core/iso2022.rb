# frozen_string_literal: true

# The ISO-2022-JP family: stateful encodings, whose two-byte characters
# are between escapes. Ruby converts one through a multibyte encoding
# that has the same characters without a state: ISO-2022-JP through
# stateless-ISO-2022-JP and EUC-JP, CP50220 and CP50221 through CP51932,
# and ISO-2022-JP-KDDI through stateless-ISO-2022-JP-KDDI.
class Encoding
  # Each stateful encoding: the multibyte encoding it converts through,
  # the stateless one between the two, and what happens to a halfwidth
  # katakana (ISO-2022-JP cannot contain one, CP50221 has a set of its
  # own for it, and CP50220 writes the fullwidth one). Also whether the
  # multibyte encoding writes a lead byte that identifies the set before
  # each two-byte character, as stateless-ISO-2022-JP-KDDI does.
  STATEFUL = {
    "ISO-2022-JP" => ["EUC-JP", "stateless-ISO-2022-JP", nil, false],
    "CP50220" => ["CP51932", nil, :fullwidth, false],
    "CP50221" => ["CP51932", nil, :set, false],
    "ISO-2022-JP-KDDI" => ["stateless-ISO-2022-JP-KDDI", nil, nil, true]
  }.freeze

  ESCAPES = { "\e(B" => :ascii, "\e(J" => :ascii, "\e$B" => :kanji, "\e$@" => :old_kanji, "\e(I" => :kana }.freeze
  # The lead byte of each two-byte set, where the multibyte encoding
  # writes one: JIS X 0208, and JIS C 6226, the older one.
  LEADS = { kanji: 0x92, old_kanji: 0x90 }.freeze
  SHIFTS = { ascii: "\e(B", kanji: "\e$B", kana: "\e(I" }.freeze

  # The halfwidth katakana from U+FF61 up, and the fullwidth ones CP50220
  # writes for them; a voiced or semi-voiced mark joins the one before it
  # where that one takes it.
  HALFWIDTH = "｡｢｣､･ｦｧｨｩｪｫｬｭｮｯｰｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾖﾗﾘﾙﾚﾛﾜﾝﾞﾟ"
  FULLWIDTH = "。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン゛゜"
  VOICED = "カキクケコサシスセソタチツテトハヒフヘホ"
  SEMI_VOICED = "ハヒフヘホ"
  private_constant :STATEFUL, :ESCAPES, :LEADS, :SHIFTS, :HALFWIDTH, :FULLWIDTH, :VOICED, :SEMI_VOICED

  def self.stateful?(encoding)
    Primitive.attr! :hidden
    STATEFUL.key?(encoding.name)
  end

  # UTF-8 `text` in `target`: its characters in the multibyte encoding,
  # then each run of them behind the escape that names its set, and the
  # text back in ASCII at its end.
  def self.stateful_write(text, target, options)
    Primitive.attr! :hidden
    base_name, stateless_name, kana, led = STATEFUL.fetch(target.name)
    base = find(base_name)
    step = stateless_name ? find(stateless_name) : target
    # A carrier's JIS writes out of the carrier's own UTF-8, whose emoji
    # the text takes first.
    hub = MB_HUBS[base_name] && find(MB_HUBS[base_name])
    path = [UTF_8, hub, base, stateless_name && step, target].compact
    text = fullwidth(text) if kana == :fullwidth
    bytes = if hub
              send(:hub_write, send(:exchange, text, hub, path, options), hub, base, path, options).b
            else
              send(:from_utf8, text, base, path, options).b
            end
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
      elsif led
        shift.call(:kanji)
        out << (bytes.getbyte(at + 1) & 0x7F) << (bytes.getbyte(at + 2) & 0x7F)
        at += 3
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
    return options[:replace] || +"?" if options[:undef] == :replace || options[:invalid] == :replace

    message = "#{piece.dump} to #{step.name} in conversion from #{path.map(&:name).join(' to ')}"
    raise send(:char_error, message, base, step, piece.dup.force_encoding(base))
  end

  # `text` in a stateful encoding read into UTF-8: each escape sets how
  # the bytes after it read, and they read as the multibyte encoding's.
  def self.stateful_read(text, options)
    Primitive.attr! :hidden
    from = text.encoding
    base_name, stateless_name, kana, led = STATEFUL.fetch(from.name)
    base = find(base_name)
    step = stateless_name ? find(stateless_name) : base
    hub = MB_HUBS[base_name] && find(MB_HUBS[base_name])
    path = [from, stateless_name && step, base, hub, UTF_8].compact
    bytes = text.b
    out = +"".b
    read = +""
    mode = :ascii
    at = 0
    while at < bytes.bytesize
      byte = bytes.getbyte(at)
      begin
        if byte == 0x1B
          mode, at = escape_at(bytes, at, from, step, kana)
        elsif mode == :ascii
          # An eight-bit byte is the multibyte encoding's to read, where a
          # stateless one does not stand between.
          stateful_invalid([byte], nil, false, from, step) if byte >= 0x80 && (stateless_name || led)
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
          out << LEADS.fetch(mode) if led
          out << (byte | 0x80) << (second | 0x80)
          at += 2
        end
      rescue InvalidByteSequenceError => e
        raise unless options[:invalid] == :replace

        # What came before is read, the bytes the error names become the
        # mark, and the ones it would read again are read next.
        read << send(:mb_to_utf8, out.force_encoding(base), base, path, options) << send(:replacement, UTF_8, options)
        out = +"".b
        at += e.error_bytes.bytesize
      end
    end
    read << send(:mb_to_utf8, out.force_encoding(base), base, path, options)
    hub ? send(:exchange, read.force_encoding(hub), UTF_8, path, options) : read
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
      if joins && wide == +"゛" && VOICED.include?(last)
        out[-1] = (last.ord + 1).chr(UTF_8)
        joins = false
      elsif joins && wide == +"゜" && SEMI_VOICED.include?(last)
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
