# frozen_string_literal: true

# Regexp and MatchData over Regexp::Onig (lib/zr/runtime/core/regexp/onig, the
# compiler) and the kernel's matcher (lib/zr/runtime/kernel/onig_*.rb). A match
# returns byte offsets; MatchData turns them into strings and
# character positions. The last match is in the calling method's
# frame (`$~`), which the kernel reads and writes.
class Regexp
  # What a match past `Regexp.timeout` raises.
  class TimeoutError < RegexpError; end

  IGNORECASE = 1
  EXTENDED = 2
  MULTILINE = 4
  FIXEDENCODING = 16
  NOENCODING = 32


  # `Regexp.new` is `Class#new`, as it is in CRuby: `allocate` makes the
  # husk and this seats the pattern in it. A subclass whose own
  # initialize builds the source therefore keeps the source it handed to
  # `super`.
  def initialize(source, options = nil, timeout: nil)
    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, +"already initialized regexp" unless Primitive.zr_regexp_source(self).nil?

    copied = source.is_a?(Regexp)
    if copied
      Primitive.zr_warn_here_m("flags ignored") unless options.nil?
      options = source.options
      source = source.source
    end
    # reg_init_args: StringValue of anything else.
    source = Primitive.zr_str_operand(source) unless source.is_a?(String)

    Regexp.send(:seat, self, source, Regexp.send(:option_bits, options), warns: !copied)
    Primitive.zr_regexp_limit_set(self, Regexp.send(:nanoseconds, timeout))
    self
  end

  # The option bits an `options` argument names, as CRuby's
  # reg_extract_args reads it.
  def self.option_bits(options)
    case options
    when nil, false then 0
    when true then IGNORECASE
    when Integer then options & (IGNORECASE | EXTENDED | MULTILINE | FIXEDENCODING | NOENCODING)
    when String
      bits = 0
      options.each_char do |c|
        bits |= { "i" => IGNORECASE, "x" => EXTENDED, "m" => MULTILINE }.fetch(c) { raise ArgumentError, "unknown regexp option: #{options}" }
      end
      bits
    else
      # reg_extract_args: a String spelling, else any other value is a
      # flag for ignorecase (rb_bool_expected warns under $VERBOSE).
      if (text = String.try_convert(options))
        return option_bits(text)
      end

      Primitive.zr_warn_here_m("expected true or false as ignorecase: #{options.inspect}") if $VERBOSE
      IGNORECASE
    end
  end
  private_class_method :option_bits

  # A literal's Regexp, for the kernel's literal table. A flag letter
  # that gives an encoding pins the pattern to it. The compiler printed
  # the pattern's warnings when the file started, as ruby's parser does.
  def self.literal(source, bits, pinned)
    compile_source(pinned_source(source, pinned), bits, warns: false)
  end
  private_class_method :literal

  # `/a#{b}c/u`: the same, built once each time the literal runs.
  def self.interpolated(fragments, bits, pinned)
    Primitive.attr! :hidden
    compile_source(pinned_source(joined(fragments, bits), pinned), bits).freeze
  end

  # rb_reg_preprocess_dregexp: the fragments of a dynamic pattern joined,
  # each read in its own encoding, and the whole in the one they fix.
  def self.joined(fragments, bits)
    Primitive.attr! :hidden
    fixed = nil
    out = nil
    fragments.each do |fragment|
      encoding = fragment.encoding
      if bits & NOENCODING != 0 && encoding != Encoding::BINARY
        raise RegexpError, +"/.../n has a non escaped non ASCII character in non ASCII-8BIT script" unless fragment.ascii_only?

        encoding = Encoding::BINARY
      end
      begin
        _, found = Pattern.preprocess(fragment, encoding, bits & EXTENDED != 0)
      rescue RegexpError => e
        raise ArgumentError, e.message
      end
      if found
        raise RegexpError, "encoding mismatch in dynamic regexp : #{fixed.name} and #{found.name}" if fixed && fixed != found

        fixed = found
      end
      out = out ? out << fragment : fragment.dup
    end
    raise ArgumentError, +"no arguments given" if out.nil?

    fixed ? out.force_encoding(fixed) : out
  end
  private_class_method :joined

  # reg_fragment_setenc: a flag letter's encoding is the source's.
  def self.pinned_source(source, pinned)
    Primitive.attr! :hidden
    pinned ? source.dup.force_encoding(Encoding.at(pinned).send(:load)) : source
  end
  private_class_method :pinned_source

  # `source` compiled with the option `bits`, set in the husk `re`. A
  # RegexpError gives the reason, then the pattern as written with its
  # flags. A pattern that `warns` prints the engine's warnings.
  def self.seat(re, source, bits, warns: true)
    source = source.dup.freeze unless source.frozen?
    encoding, bits, program, names, warnings = compiled(source, bits)
    # reg_set_source: the source reads in the pattern's encoding.
    source = source.dup.force_encoding(encoding).freeze unless source.encoding == encoding
    Primitive.zr_regexp_seat(re, program, source, bits, name_rows(names, encoding))
    Primitive.zr_state_set(re, :encoding, encoding)
    warn_of(warnings) if warns
    re
  end
  private_class_method :seat

  # `source` compiled with the option `bits`, as [encoding, bits, program,
  # names, warnings]: the program that the kernel's matcher reads
  # (Onig::Program), the named groups as [name, [group numbers]], and the
  # warnings as [verbose, text]. On the host, CRuby runs this same
  # compiler (`zr_regexp_host_compile`); a binary compiles here.
  def self.compiled(source, bits)
    Primitive.attr! :hidden
    if (done = Primitive.zr_regexp_host_compile(source, bits))
      index, bits, program, names, warnings = done
      return [Encoding.at(index), bits, program.freeze, names, warnings]
    end

    encoding, bits, compiled, warnings = Pattern.compile(source, bits)
    names = compiled.name_table.to_a.map { |name, entry| [name, entry.back_refs] }
    [encoding, bits, Onig::Program.pack(compiled), names, warning_rows(warnings)]
  end
  private_class_method :compiled

  # A Regexp of this class over `source`: the husk and its pattern in
  # one step, which the literal table and the copies use.
  def self.compile_source(source, bits, warns: true) = seat(allocate, source, bits, warns: warns)
  private_class_method :compile_source

  # The named groups of a compile, [[name, [group numbers]], ...] in
  # definition order, the names in the pattern's encoding.
  def self.name_rows(names, encoding)
    Primitive.attr! :hidden
    names.map { |name, refs| [name.dup.force_encoding(encoding).freeze, refs.dup.freeze].freeze }.freeze
  end
  private_class_method :name_rows

  # The warnings of a compile as [verbose, text] pairs (`warn_of`).
  def self.warning_rows(warnings)
    Primitive.attr! :hidden
    warnings.rows.map { |row| [row.verbose, row.text] }
  end
  private_class_method :warning_rows

  # What the engine warned of as it compiled the pattern (re_warn), each
  # warning naming the engine's text as Onigmo writes it. One ruby
  # gives only when verbose waits for $VERBOSE.
  def self.warn_of(warnings)
    Primitive.attr! :hidden
    warnings.each do |verbose, text|
      next if verbose && !$VERBOSE

      Primitive.zr_warn_here_m(text)
    end
  end
  private_class_method :warn_of

  # rb_reg_init_copy: what `dup` and `clone` fill a husk with (the
  # other Regexp's pattern, which the copy shares), and a refusal for
  # a Regexp that already has one.
  def initialize_copy(other)
    return self if equal?(other)

    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, +"initialize_copy should take same class object" unless other.instance_of?(self.class)
    raise TypeError, +"already initialized regexp" unless Primitive.zr_regexp_source(self).nil?

    Primitive.zr_regexp_copy_from(self, other)
    self
  end
  private :initialize_copy

  # rb_reg_prepare_re: the program that a match of `text` runs, or nil for
  # the pattern's own. The engine reads the pattern in one encoding at a
  # time, first the pattern's own. A subject that needs another encoding
  # compiles the pattern again under it, and that compile replaces the
  # engine until a subject needs another (ruby overwrites the pattern's
  # regex_t). The Regexp keeps each compile by encoding, with its
  # warnings, or with its refusal, which each match that uses it raises
  # again.
  def program_for(text)
    Primitive.attr! :hidden
    index = Primitive.zr_str_encoding_index_m(text)
    ascii = Primitive.zr_str_ascii_only_m(text)
    raise ArgumentError, "invalid byte sequence in #{Encoding.at(index)}" unless ascii || Primitive.zr_str_valid_p(text)

    # For a text like the last one (the same encoding, ASCII or not), the
    # program is the one that call kept. A change of engine below drops
    # it. A `scan` over a text calls this once per match, and the
    # selection below costs a dozen sends.
    programs = Primitive.zr_regexp_alt(self)
    last = programs && programs[:last]
    return last[2] if last && last[0] == index && last[1] == ascii

    pattern
    text_encoding = Encoding.at(index)
    Primitive.zr_regexp_alt_set(self, programs = { engine: encoding }) unless programs
    engine = programs[:engine]
    warning = nil
    unless engine == text_encoding || (ascii && engine == Encoding::US_ASCII)
      enc, warning = Pattern.prepared_encoding(engine, encoding, options, text_encoding, ascii)
      Primitive.zr_warn_here_m(warning) if warning
      unless enc == engine
        program_in(enc, warns: true)
        engine = enc
        programs[:engine] = engine
        programs.delete(:last)
      end
    end
    program = engine == encoding ? nil : programs[engine][0]
    # A program that warns is not kept: ruby warns on every match with it.
    programs[:last] = [index, ascii, program] unless warning
    program
  end

  # The program of the pattern compiled again for `enc` (nil for the
  # encoding the pattern has), printing what that compile warned of
  # when `warns`.
  def program_in(enc, warns: false)
    Primitive.attr! :hidden
    own = encoding
    programs = Primitive.zr_regexp_alt(self)
    Primitive.zr_regexp_alt_set(self, programs = { engine: own }) unless programs
    return nil if enc == own

    entry = programs[enc] ||= begin
      compiled, warnings = Pattern.recompile(pattern, options, own, enc)
      [Onig::Program.pack(compiled).freeze, Regexp.send(:warning_rows, warnings)].freeze
    rescue ArgumentError, RegexpError => e
      [nil, e.class, e.message].freeze
    end
    raise entry[1], entry[2] if entry[0].nil?

    Regexp.send(:warn_of, entry[1]) if warns
    entry[0]
  end
  private :program_for, :program_in

  def self.compile(*args, **options) = new(*args, **options)

  # String#b as it is at boot, which the C never calls on a String.
  STRING_B = String.instance_method(:b)
  private_constant :STRING_B

  # The Onigmo encoder a String in `encoding` is read with, for String's
  # own methods: Onig itself stays Regexp's.
  def self.encoder(encoding)
    Primitive.attr! :hidden
    Onig::Enc.reader(encoding)
  end

  # What rb_reg_quote writes for each metacharacter it escapes.
  QUOTED = {
    0x5B => "\\[", 0x5D => "\\]", 0x7B => "\\{", 0x7D => "\\}", 0x28 => "\\(", 0x29 => "\\)", 0x7C => "\\|", 0x2D => "\\-",
    0x2A => "\\*", 0x2E => "\\.", 0x5C => "\\\\", 0x3F => "\\?", 0x2B => "\\+", 0x5E => "\\^", 0x24 => "\\$", 0x23 => "\\#",
    0x20 => "\\ ", 0x09 => "\\t", 0x0A => "\\n", 0x0D => "\\r", 0x0C => "\\f", 0x0B => "\\v",
  }.freeze
  private_constant :QUOTED

  # rb_reg_quote: a String whose regexp meaning is its own characters,
  # read one character at a time in its own encoding and written back in
  # it. Text of plain ASCII is returned in US-ASCII.
  def self.escape(text)
    text = text.is_a?(Symbol) ? text.to_s : Primitive.zr_str_operand(text)
    enc = text.encoding
    compat = enc.ascii_compatible?
    ascii_only = compat && Primitive.zr_str_ascii_only_m(text)
    bytes = STRING_B.bind_call(text)
    onig = Onig::Enc.reader(enc)
    out = nil
    at = 0
    while at < bytes.bytesize
      c, clen = onig.ascget(bytes, at, compat)
      if c.nil?
        len = onig.mbclen(bytes, at)
        out << bytes.byteslice(at, len) if out
        at += len
        next
      end
      quoted = QUOTED[c]
      out ||= bytes.byteslice(0, at) if quoted
      if out
        piece = quoted || c.chr
        out << (compat || enc.dummy? ? piece : piece.encode(enc).b)
      end
      at += clen
    end
    out ||= bytes
    out.force_encoding(ascii_only ? Encoding::US_ASCII : enc)
  end

  def self.quote(text) = escape(text)

  # rb_reg_s_union: the patterns joined by `|`, in the one encoding they
  # agree on: an ASCII-incompatible one, else a fixed one, else binary.
  # Each `|` is written in the encoding the source has so far.
  def self.union(*patterns)
    listed = patterns.size == 1 ? Array.try_convert(patterns[0]) : nil
    patterns = listed if listed
    return new(+"(?!)") if patterns.empty?

    if patterns.size == 1
      return Regexp.try_convert(patterns[0]) || new(escape(patterns[0]))
    end

    ascii_only = false
    fixed = nil
    incompatible = nil
    agree = lambda do |held, encoding|
      raise ArgumentError, "incompatible encodings: #{held.name} and #{encoding.name}" if held && held != encoding

      encoding
    end
    source = nil
    source_encoding = nil
    patterns.each_index do |i|
      pattern = patterns[i]
      if i.positive?
        source << (source_encoding.ascii_compatible? || source_encoding.dummy? ? "|" : "|".encode(source_encoding).b)
      end
      if (regexp = Regexp.try_convert(pattern))
        encoding = regexp.encoding
        if !encoding.ascii_compatible? then incompatible = agree.call(incompatible, encoding)
        elsif regexp.fixed_encoding? then fixed = agree.call(fixed, encoding)
        else ascii_only = true
        end
        text = regexp.to_s
      else
        pattern = Primitive.zr_str_operand(pattern)
        encoding = pattern.encoding
        if !encoding.ascii_compatible? then incompatible = agree.call(incompatible, encoding)
        elsif Primitive.zr_str_ascii_only_m(pattern) then ascii_only = true
        else fixed = agree.call(fixed, encoding)
        end
        text = escape(pattern)
      end
      if incompatible
        raise ArgumentError, "ASCII incompatible encoding: #{incompatible.name}" if ascii_only
        raise ArgumentError, "incompatible encodings: #{incompatible.name} and #{fixed.name}" if fixed
      end
      if i.zero?
        source = text.b
        source_encoding = text.encoding
      else
        source << text.b
      end
    end
    new(source.force_encoding(incompatible || fixed || Encoding::BINARY))
  end

  def self.last_match(index = nil)
    match = $~
    index.nil? || match.nil? ? match : match[index]
  end

  def self.try_convert(object)
    return object if object.is_a?(Regexp)
    return nil unless object.respond_to?(:to_regexp)

    converted = object.to_regexp
    raise TypeError, "can't convert #{conversion_name(object)} to Regexp (#{conversion_name(object)}#to_regexp gives #{conversion_name(converted)})" unless converted.nil? || converted.is_a?(Regexp)

    converted
  end

  def source = pattern

  def options
    pattern
    Primitive.zr_regexp_options(self)
  end

  # `Regexp.allocate` returns an object with no pattern in it. Ruby
  # reports that here, at the first read, not at the first match.
  def pattern
    Primitive.attr! :hidden
    text = Primitive.zr_regexp_source(self)
    raise TypeError, +"uninitialized Regexp" unless text

    text
  end
  private :pattern

  def casefold? = options & IGNORECASE != 0

  # reg_names_iter: each name in the encoding the engine reads the
  # pattern in now, which a match of text in another encoding changes.
  def names = name_rows.map { |name, _| name.b.force_encoding(engine_encoding) }

  # reg_named_captures_iter writes each name as bytes.
  def named_captures = name_rows.to_h { |name, groups| [name.b, groups] }

  # The encoding the engine reads the pattern in: the pattern's own
  # until a match of text in another encoding compiles it again.
  def engine_encoding
    Primitive.attr! :hidden
    programs = Primitive.zr_regexp_alt(self)
    programs ? programs[:engine] : encoding
  end

  def timeout = Regexp.send(:seconds, Primitive.zr_regexp_limit(self))

  # `/n` or a binary source reads the pattern as bytes. A pattern that
  # contains a byte past ASCII, written out or escaped, is a binary
  # pattern. One that does not is plain ASCII that any string can match.
  # The encoding the pattern took when it was set; an allocated Regexp
  # has none and reads as binary.
  def encoding = Primitive.zr_hidden_get(self, :encoding) || Encoding::BINARY

  def fixed_encoding?
    return false unless Primitive.zr_regexp_source(self)

    options & FIXEDENCODING != 0
  end

  # rb_reg_equal: the same object, or the same pattern bytes under the
  # same options and encoding.
  def ==(other)
    return true if equal?(other)
    return false unless other.is_a?(Regexp)

    engine = IGNORECASE | EXTENDED | MULTILINE
    pattern.b == other.send(:pattern).b && options & engine == other.options & engine && fixed_encoding? == other.fixed_encoding? &&
      encoding == other.encoding
  end

  def bytewise?
    Primitive.attr! :hidden
    options & NOENCODING != 0 || pattern.encoding == Encoding::BINARY
  end
  private :bytewise?

  alias eql? ==

  # rb_reg_hash: the /n flag does not count.
  def hash = [source, options & ~NOENCODING].hash

  def to_s = Pattern.str_with_term(pattern, encoding, options, "/")

  def inspect
    return Object.instance_method(:to_s).bind_call(self) unless Primitive.zr_regexp_source(self)

    Pattern.desc(pattern, encoding, options)
  end

  # The MatchData for `text` from character `pos`, or nil; `$~` is set
  # either way.
  def match(text, pos = 0)
    result = matched(text, pos)
    return result unless block_given? && result

    yield result
  end

  # `match` with no frame of its own, for `=~` and `===`.
  def matched(text, pos = 0)
    Primitive.attr! :hidden
    if text.nil?
      Primitive.zr_backref_set(nil)
      return nil
    end
    text = text.to_s if text.is_a?(Symbol)
    raise TypeError, "no implicit conversion of #{conversion_name(text)} into String" unless text.is_a?(String)

    pos = implicit_integer(pos)
    pos += Primitive.zr_str_length_m(text) if pos < 0
    if pos < 0 || pos > Primitive.zr_str_length_m(text)
      Primitive.zr_backref_set(nil)
      return nil
    end
    result = search(text, Primitive.zr_str_char_offset_m(text, pos), false)
    Primitive.zr_backref_set(result)
    result
  end
  private :matched

  def match?(text, pos = 0)
    return false if text.nil?

    text = text.to_s if text.is_a?(Symbol)
    pos = implicit_integer(pos)
    # From the start, no character of the text needs a count.
    return !Primitive.zr_regexp_search(self, program_for(text), text, 0, false).nil? if pos == 0

    pos += Primitive.zr_str_length_m(text) if pos < 0
    return false if pos < 0 || pos > Primitive.zr_str_length_m(text)

    !Primitive.zr_regexp_search(self, program_for(text), text, Primitive.zr_str_char_offset_m(text, pos), false).nil?
  end

  # The character the search matched at (before a `\K`), or nil. Ruby
  # runs `=~` as an instruction (opt_regexpmatch2), with no frame.
  def =~(text)
    Primitive.attr! :frameless
    result = matched(text)
    result && Primitive.zr_str_byte_to_char(result.send(:text), result.send(:position))
  end

  # reg_operand: a Symbol's name, or what to_str gives.
  def ===(text)
    text = String.try_convert(text) || text unless text.is_a?(String) || text.is_a?(Symbol)
    unless text.is_a?(String) || text.is_a?(Symbol)
      Primitive.zr_backref_set(nil)
      return false
    end

    !matched(text).nil?
  end

  # `~ re`: the match against `$_`.
  def ~
    line = $_
    return match(nil) unless line.is_a?(String)

    self =~ line
  end

  # False for what memoization cannot cover: backreferences, subexp
  # calls and the absence operator.
  def self.linear_time?(regexp, options = nil, timeout: nil)
    Primitive.zr_warn_here_m("flags ignored") if regexp.is_a?(Regexp) && !options.nil?
    regexp = new(regexp, options) unless regexp.is_a?(Regexp)
    !backref?(regexp.source, Primitive.zr_regexp_captures(regexp))
  end

  # The linear matcher gives up on a backreference, a subexpression call
  # or the absent operator. Inside a `[...]` class `\1` is an octal
  # escape and `\k` is a literal k, so a class contains none of them.
  def self.backref?(source, captures)
    in_class = false
    i = 0
    while i < source.size
      c = source[i]
      if c == +"\\"
        return true if !in_class && backref_escape?(source, i + 1, captures)

        i += 1
      elsif c == +"["
        in_class = true
      elsif c == +"]"
        in_class = false
      elsif c == +"(" && !in_class && source[i, 3] == +"(?~"
        return true
      end
      i += 1
    end
    false
  end
  private_class_method :backref?

  # `\k<n>`, `\k'n'`, `\g<n>`, `\g'n'`, and a digit run that refers to a
  # group of the pattern. A run past the last group, or one that starts
  # with a zero, is an octal escape.
  def self.backref_escape?(source, i, captures)
    c = source[i]
    return (source[i + 1] == +"<" || source[i + 1] == +"'") if c == +"k" || c == +"g"
    return false unless c && c >= +"1" && c <= +"9"

    digits = source[i..].slice(/\A\d+/)
    digits.to_i <= captures
  end
  private_class_method :backref_escape?

  # The seconds that any match can take, unless its pattern sets its own.
  def self.timeout = seconds(Primitive.zr_regexp_limit(nil))

  def self.timeout=(seconds)
    Primitive.zr_regexp_limit_set(nil, nanoseconds(seconds))
    seconds
  end

  # set_timeout: nil for no limit, else a positive number of seconds,
  # kept as whole nanoseconds.
  def self.nanoseconds(seconds)
    Primitive.attr! :hidden
    return 0 if seconds.nil?

    raise TypeError, +"no implicit conversion to float from string" if seconds.is_a?(String)
    raise TypeError, "no implicit conversion to float from #{seconds}" if seconds == true || seconds == false
    raise TypeError, "can't convert #{seconds.class} into Float" unless seconds.is_a?(Numeric)
    raise ArgumentError, "invalid timeout: #{seconds}" unless seconds.to_f.positive?

    (seconds.to_f * 1e9).to_i.clamp(0, (2**62) - 1)
  end

  def self.seconds(nanoseconds)
    Primitive.attr! :hidden
    nanoseconds.zero? ? nil : nanoseconds / 1e9
  end
  private_class_method :nanoseconds, :seconds

  private

  # The named groups in definition order: [[name, [group numbers]], ...].
  def name_rows
    Primitive.attr! :hidden
    pattern
    Primitive.zr_regexp_names(self).to_a.sort { |a, b| a[1].first <=> b[1].first }
  end

  # The match at byte `from`, searching forward, or backward to it.
  # A regexp whose source contains a byte past ASCII reads only one
  # encoding, so a subject in another one is an error unless the subject
  # is plain ASCII.
  def search(text, from, backward)
    Primitive.attr! :hidden
    offsets = Primitive.zr_regexp_search(self, program_for(text), text, from, backward)
    offsets && MatchData.send(:for, self, text, offsets)
  end

  def match_at(text, from)
    Primitive.attr! :hidden
    offsets = Primitive.zr_regexp_match_at(self, program_for(text), text, from)
    offsets && MatchData.send(:for, self, text, offsets)
  end

  # StringScanner's match at byte `from`, or search from it (`search`),
  # over a text that starts `base` bytes into `text`, in place.
  def scan_in(text, base, from, search)
    Primitive.attr! :hidden
    offsets = Primitive.zr_regexp_scan_in(self, program_for(text), text, base, from, search)
    offsets && MatchData.send(:for, self, text, offsets)
  end

  # The engine is Regexp's own, as Onigmo is CRuby's C.
  private_constant :Onig
end

class MatchData
  # A MatchData a match makes, as CRuby's match_alloc does: no
  # `allocate`, which is taken away below, and no UnboundMethod a match.
  def self.for(regexp, text, offsets)
    m = Primitive.zr_class_build(self)
    m.send(:matched, regexp, text, offsets)
    m
  end
  private_class_method :for

  # The frozen text a MatchData reads. CRuby shares the text's buffer
  # with a frozen String (rb_str_new_frozen), so a match costs nothing for
  # the length of its text. The copy here is made once and kept for the
  # text while no change has reached it (FL_SNAPSHOT, which every change
  # clears): a copy for each match made a scan over a long text quadratic
  # in its length. `MatchData#string` is a String of the match's own.
  # The few texts matched most recently keep theirs, so a loop that
  # matches a second text inside the first does not copy either again.
  SNAPSHOTS = []
  private_constant :SNAPSHOTS

  def self.snapshot(text)
    return text if text.frozen?

    if Primitive.zr_str_snapshot_p(text)
      SNAPSHOTS.each { |kept, copy| return copy if kept.equal?(text) }
    end
    copy = Primitive.zr_str_new_frozen_m(text)
    SNAPSHOTS.reject! { |kept, _| kept.equal?(text) }
    SNAPSHOTS.unshift([text, copy])
    SNAPSHOTS.pop if SNAPSHOTS.size > 4
    Primitive.zr_str_snapshot_set(text)
    copy
  end
  private_class_method :snapshot

  # A MatchData comes from a match, never from a constructor, so ruby
  # takes both spellings away.
  class << self
    undef_method :allocate, :new
  end

  # A MatchData copies the match it is given, of its own kind only.
  private def initialize_copy(other)
    super
    other.string
    %i[regexp string shown offsets].each { |part| Primitive.zr_hidden_set(self, part, Primitive.zr_hidden_get(other, part)) }
    self
  end

  # A match of a String pattern keeps the String; its Regexp is made on
  # first use, as match_regexp does.
  def regexp
    @regexp = Regexp.new(Regexp.escape(@regexp)) if @regexp.is_a?(String)
    @regexp
  end

  # The text as it was, a frozen String of this match's own, as CRuby
  # gives each MatchData. It is made on first use from the copy that
  # every match of the text shares (`text`). A frozen text is used as it
  # is.
  def string
    Primitive.zr_hidden_get(self, :shown) || Primitive.zr_state_set(self, :shown, Primitive.zr_str_new_frozen_m(text))
  end

  def names = regexp.is_a?(Regexp) ? regexp.names : []

  def size = (offsets.size - 1) / 2

  alias length size

  def to_a = (0...size).map { |i| group(i) }

  def captures = (1...size).map { |i| group(i) }

  alias deconstruct captures

  def named_captures(symbolize_names: false)
    return {} unless regexp.is_a?(Regexp)

    regexp.send(:name_rows).to_h do |name, groups|
      value = groups.reverse.map { |g| group(g) }.find { |v| !v.nil? }
      name = name.b.force_encoding(regexp.send(:engine_encoding))
      [symbolize_names ? name.to_sym : name, value]
    end
  end

  # More keys than named groups return an empty Hash; a key with no
  # group ends the walk.
  def deconstruct_keys(keys)
    raise TypeError, "wrong argument type #{keys.class} (expected Array)" unless keys.nil? || keys.is_a?(Array)

    all = named_captures(symbolize_names: true)
    return all if keys.nil?
    return {} if keys.size > all.size

    out = {}
    keys.each do |key|
      raise TypeError, "wrong argument type #{conversion_name(key)} (expected Symbol)" unless key.is_a?(Symbol)
      break unless all.key?(key)

      out[key] = all[key]
    end
    out
  end

  # A group by number (a negative one counts back over the groups, never
  # reaching the whole match), by name, or a run of them.
  def [](index, length = nil)
    return to_a[index, length] if length

    case index
    when String, Symbol then group(named_group(index))
    when Range then to_a[index]
    else
      index = implicit_integer(index)
      if index < 0
        index += size
        return nil if index <= 0
      end
      index < size ? group(index) : nil
    end
  end

  def values_at(*indexes)
    out = []
    indexes.each { |i| i.is_a?(Range) ? out.concat(to_a.values_at(i)) : out << self[i] }
    out
  end

  def begin(index)
    b = byte_begin(index)
    b && Primitive.zr_str_byte_to_char(text, b)
  end

  def end(index)
    e = byte_end(index)
    e && Primitive.zr_str_byte_to_char(text, e)
  end

  def offset(index)
    [self.begin(index), self.end(index)]
  end

  def bytebegin(index) = byte_begin(index)

  def byteend(index) = byte_end(index)

  def byteoffset(index)
    [byte_begin(index), byte_end(index)]
  end

  def match(index) = self[index]

  def match_length(index)
    value = self[index]
    value && value.size
  end

  def pre_match = Primitive.zr_str_byteslice(text, 0, begin_at(0))

  def post_match = Primitive.zr_str_byteslice(text, end_at(0), Primitive.zr_str_bytesize(text) - end_at(0))

  def to_s = group(0)

  def ==(other)
    other.is_a?(MatchData) && regexp == other.regexp && text == other.send(:text) && offsets == other.send(:offsets)
  end

  alias eql? ==

  def hash = [regexp, text, offsets].hash

  def inspect
    labels = Array.new(size - 1) { |i| (i + 1).to_s }
    regexp.send(:name_rows).each { |name, groups| groups.each { |g| labels[g - 1] = name } } if regexp.is_a?(Regexp)
    parts = [group(0).inspect]
    labels.each_index { |i| parts << "#{labels[i]}:#{group(i + 1).inspect}" }
    Primitive.zr_obj_form("#<MatchData #{parts.join(' ')}>")
  end

  private

  # `offsets` is [position, begin0, end0, begin1, end1, ...]: the byte
  # the search matched at, then every group's byte span. It is kept as
  # the search made it, so a match allocates nothing but its cell; a
  # group's span is read by `begin_at` and `end_at`.
  # The fields are hidden ivars (no `@` in the runtime's own code), which
  # an ivar write sets through its site's cache. A match makes one per
  # match of scan and gsub. They are set in this order, so `string` and
  # `offsets` are rows 1 and 2, where `zr_match_nth` reads them first.
  def matched(regexp, text, offsets)
    Primitive.attr! :hidden
    @regexp = regexp
    @string = MatchData.send(:snapshot, text)
    @offsets = offsets
    @shown = text if text.frozen?
  end

  def offsets
    Primitive.attr! :hidden
    @offsets
  end

  # Group `index`'s byte span, -1 where it did not take part.
  def begin_at(index)
    Primitive.attr! :hidden
    offsets[index * 2 + 1]
  end

  def end_at(index)
    Primitive.attr! :hidden
    offsets[index * 2 + 2]
  end

  # The frozen text the match was made in, shared by every match of it.
  def text
    Primitive.attr! :hidden
    @string
  end

  # The byte the search matched at, which a `\K` may leave before the
  # match's own beginning.
  def position
    Primitive.attr! :hidden
    offsets[0]
  end

  def group(index)
    Primitive.attr! :hidden
    b = begin_at(index)
    b < 0 ? nil : Primitive.zr_str_byteslice(text, b, end_at(index) - b)
  end

  def byte_begin(index)
    Primitive.attr! :hidden
    index = backref_number(index)
    raise IndexError, "index #{index} out of matches" if index < 0 || index >= size

    b = begin_at(index)
    b < 0 ? nil : b
  end

  def byte_end(index)
    Primitive.attr! :hidden
    index = backref_number(index)
    raise IndexError, "index #{index} out of matches" if index < 0 || index >= size

    e = end_at(index)
    e < 0 ? nil : e
  end

  # match_backref_number: a group by name, else by NUM2INT.
  def backref_number(index)
    Primitive.attr! :hidden
    index.is_a?(String) || index.is_a?(Symbol) ? named_group(index) : implicit_integer(index)
  end

  def named_group(name)
    Primitive.attr! :hidden
    row = regexp.is_a?(Regexp) ? regexp.send(:name_rows).find { |n, _| n == name.to_s } : nil
    raise IndexError, "undefined group name reference: #{name}" unless row

    row[1].reverse.find { |g| begin_at(g) >= 0 } || row[1].last
  end
end

class Symbol
  def =~(pattern) = to_s =~ pattern

  def match(*args, &block) = to_s.match(*args, &block)

  def match?(*args) = to_s.match?(*args)
end
