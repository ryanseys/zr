# Regexp and MatchData over Regexp::Onig (rt/core/regexp/onig, the
# compiler) and the kernel's matcher (rt/kernel/onig_*.rb). A match
# answers byte offsets; MatchData turns them into strings and
# character positions. The last match lives in the asking method's
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
    raise TypeError, "already initialized regexp" unless Primitive.zr_regexp_source(self).nil?

    copied = source.is_a?(Regexp)
    if copied
      Primitive.zr_warn_here_m("flags ignored") unless options.nil?
      options = source.options
      source = source.source
    end
    raise TypeError, "no implicit conversion of #{conversion_name(source)} into String" unless source.is_a?(String)

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
      options.each_char.reduce(0) do |acc, c|
        acc | { "i" => IGNORECASE, "x" => EXTENDED, "m" => MULTILINE }.fetch(c) { raise ArgumentError, "unknown regexp option: #{options}" }
      end
    else raise TypeError, "no implicit conversion of #{conversion_name(options)} into Integer"
    end
  end
  private_class_method :option_bits

  # A literal's Regexp, for the kernel's literal table. A flag letter
  # that names an encoding pins the pattern to it. What the pattern
  # warns of, the compiler printed as the file started, as ruby's parser
  # does.
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
        raise RegexpError, "/.../n has a non escaped non ASCII character in non ASCII-8BIT script" unless fragment.ascii_only?

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
    raise ArgumentError, "no arguments given" if out.nil?

    fixed ? out.force_encoding(fixed) : out
  end
  private_class_method :joined

  # reg_fragment_setenc: a flag letter's encoding is the source's.
  def self.pinned_source(source, pinned)
    Primitive.attr! :hidden
    pinned ? source.dup.force_encoding(Encoding.at(pinned).send(:load)) : source
  end
  private_class_method :pinned_source

  # `source` compiled with the option `bits`, seated in the husk `re`; a
  # RegexpError names the reason, then the pattern as written with its
  # flags. A pattern that `warns` prints what the engine warned of.
  def self.seat(re, source, bits, warns: true)
    source = source.dup.freeze unless source.frozen?
    encoding, bits, compiled, warnings = Pattern.compile(source, bits)
    # reg_set_source: the source reads in the pattern's encoding.
    source = source.dup.force_encoding(encoding).freeze unless source.encoding == encoding
    Primitive.zr_regexp_seat(re, Onig::Program.pack(compiled), source, bits, name_rows_of(compiled, encoding))
    Primitive.zr_state_set(re, :encoding, encoding)
    warn_of(warnings) if warns
    re
  end
  private_class_method :seat

  # A Regexp of this class over `source`: the husk and its pattern in
  # one step, which the literal table and the copies ask for.
  def self.compile_source(source, bits, warns: true) = seat(allocate, source, bits, warns: warns)
  private_class_method :compile_source

  # The named groups of a compiled pattern, [[name, [group numbers]], ...]
  # in definition order, the names in the pattern's encoding.
  def self.name_rows_of(compiled, encoding)
    Primitive.attr! :hidden
    return [].freeze unless compiled.name_table

    compiled.name_table.map { |name, entry| [name.dup.force_encoding(encoding).freeze, entry.back_refs.dup.freeze].freeze }.freeze
  end
  private_class_method :name_rows_of

  # What the engine warned of as it compiled the pattern (re_warn), each
  # warning naming the engine's text as Onigmo writes it. One ruby
  # gives only when verbose waits for $VERBOSE.
  def self.warn_of(warnings)
    Primitive.attr! :hidden
    warnings.rows.each do |row|
      next if row.verbose && !$VERBOSE

      Primitive.zr_warn_here_m(row.text)
    end
  end
  private_class_method :warn_of

  # rb_reg_init_copy: what `dup` and `clone` fill a husk with -- the
  # other Regexp's pattern, which the copy shares -- and a refusal for
  # a Regexp that already holds one.
  def initialize_copy(other)
    return self if equal?(other)

    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, "initialize_copy should take same class object" unless other.instance_of?(self.class)
    raise TypeError, "already initialized regexp" unless Primitive.zr_regexp_source(self).nil?

    Primitive.zr_regexp_copy_from(self, other)
    self
  end
  private :initialize_copy

  # rb_reg_prepare_re: the program a match of `text` runs, or nil for the
  # one the pattern has. The engine reads the pattern in one encoding at
  # a time, at first the pattern's own; a subject that asks for another
  # compiles the pattern again under it, and that compile takes the
  # engine's place until a subject asks for another (ruby overwrites
  # the pattern's regex_t). The Regexp keeps each compile by encoding,
  # with its warnings, or with the refusal it gave, which each match
  # that asks for it raises again.
  def program_for(text)
    Primitive.attr! :hidden
    pattern
    text_encoding = Encoding.at(Primitive.zr_str_encoding_index_m(text))
    ascii = Primitive.zr_str_ascii_only_m(text)
    raise ArgumentError, "invalid byte sequence in #{text_encoding}" unless ascii || Primitive.zr_str_valid_p(text)

    programs = Primitive.zr_regexp_alt(self)
    engine = programs ? programs[:engine] : encoding
    unless engine == text_encoding || (ascii && engine == Encoding::US_ASCII)
      enc, warning = Pattern.prepared_encoding(engine, encoding, options, text_encoding, ascii)
      Primitive.zr_warn_here_m(warning) if warning
      unless enc == engine
        program_in(enc, warns: true)
        engine = enc
        Primitive.zr_regexp_alt(self)[:engine] = engine
      end
    end
    engine == encoding ? nil : Primitive.zr_regexp_alt(self)[engine][0]
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
      [Onig::Program.pack(compiled).freeze, warnings].freeze
    rescue ArgumentError, RegexpError => e
      [nil, e.class, e.message].freeze
    end
    raise entry[1], entry[2] if entry[0].nil?

    Regexp.send(:warn_of, entry[1]) if warns
    entry[0]
  end
  private :program_for, :program_in

  def self.compile(*args, **options) = new(*args, **options)

  # A String whose regexp meaning is its own bytes.
  def self.escape(text)
    text = text.is_a?(Symbol) ? text.to_s : Primitive.zr_str_operand(text)
    out = +""
    text.each_char do |c|
      out << case c
             when ".", "*", "?", "+", "^", "$", "|", "(", ")", "[", "]", "{", "}", "\\", "-", "#" then "\\#{c}"
             when " " then "\\ "
             when "\t" then "\\t"
             when "\n" then "\\n"
             when "\r" then "\\r"
             when "\f" then "\\f"
             when "\v" then "\\v"
             else c
             end
    end
    out
  end

  def self.quote(text) = escape(text)

  # rb_reg_s_union: the patterns joined by `|`, in the one encoding they
  # agree on.
  def self.union(*patterns)
    listed = patterns.size == 1 ? Array.try_convert(patterns[0]) : nil
    patterns = listed if listed
    return new("(?!)") if patterns.empty?

    if patterns.size == 1
      return Regexp.try_convert(patterns[0]) || new(escape(patterns[0]))
    end

    ascii_only = false
    compatible = nil
    incompatible = nil
    agree = lambda do |held, encoding|
      raise ArgumentError, "incompatible encodings: #{held.name} and #{encoding.name}" if held && held != encoding

      encoding
    end
    source = patterns.each_with_index.map do |pattern, i|
      regexp = Regexp.try_convert(pattern)
      text = regexp ? regexp.to_s : escape(pattern = Primitive.zr_str_operand(pattern))
      encoding = regexp ? regexp.encoding : pattern.encoding
      if !encoding.ascii_compatible?
        incompatible = agree.call(incompatible, encoding)
      elsif regexp ? regexp.fixed_encoding? : !pattern.ascii_only?
        compatible = agree.call(compatible, encoding)
      else
        ascii_only = true
      end
      if incompatible
        raise ArgumentError, "ASCII incompatible encoding: #{incompatible.name}" if ascii_only
        raise ArgumentError, "incompatible encodings: #{incompatible.name} and #{compatible.name}" if compatible
      end
      i.zero? ? text.b : "|#{text}".b
    end.join
    new(source.force_encoding(incompatible || compatible || Encoding::BINARY))
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

  # `Regexp.allocate` answers an object with no pattern in it. Ruby
  # names that here, at the first read, rather than at the first match.
  def pattern
    Primitive.attr! :hidden
    text = Primitive.zr_regexp_source(self)
    raise TypeError, "uninitialized Regexp" unless text

    text
  end
  private :pattern

  def casefold? = options & IGNORECASE != 0

  def names = name_rows.map(&:first)

  def named_captures = name_rows.to_h { |name, groups| [name, groups] }

  def timeout = Regexp.send(:seconds, Primitive.zr_regexp_limit(self))

  # `/n` or a binary source reads the pattern as bytes: one that names a
  # byte past ASCII, written out or escaped, is a binary pattern, and one
  # that does not is plain ASCII that any string can match.
  # The encoding the pattern took as it was seated; an allocated Regexp
  # holds none and reads as binary.
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

  def hash = [source, options].hash

  def to_s = Pattern.str_with_term(pattern, encoding, options, "/")

  def inspect
    return Object.instance_method(:to_s).bind_call(self) unless Primitive.zr_regexp_source(self)

    Pattern.desc(pattern, encoding, options)
  end

  # The MatchData for `text` from character `pos`, or nil; `$~` is set
  # either way.
  def match(text, pos = 0)
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
    return result unless block_given? && result

    yield result
  end

  def match?(text, pos = 0)
    return false if text.nil?

    text = text.to_s if text.is_a?(Symbol)
    pos = implicit_integer(pos)
    pos += Primitive.zr_str_length_m(text) if pos < 0
    return false if pos < 0 || pos > Primitive.zr_str_length_m(text)

    !Primitive.zr_regexp_search(self, program_for(text), text, Primitive.zr_str_char_offset_m(text, pos), false).nil?
  end

  # The character the search matched at (before a `\K`), or nil.
  def =~(text)
    result = match(text)
    result && Primitive.zr_str_byte_to_char(result.send(:text), result.send(:position))
  end

  def ===(text)
    unless text.is_a?(String) || text.is_a?(Symbol)
      Primitive.zr_backref_set(nil)
      return false
    end

    !match(text).nil?
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
    regexp = new(regexp, options) unless regexp.is_a?(Regexp)
    !backref?(regexp.source, Primitive.zr_regexp_captures(regexp))
  end

  # The linear matcher gives up on a backreference, a subexpression call
  # or the absent operator. Inside a `[...]` class `\1` is an octal
  # escape and `\k` is a literal k, so a class holds none of them.
  def self.backref?(source, captures)
    in_class = false
    i = 0
    while i < source.size
      c = source[i]
      if c == "\\"
        return true if !in_class && backref_escape?(source, i + 1, captures)

        i += 1
      elsif c == "["
        in_class = true
      elsif c == "]"
        in_class = false
      elsif c == "(" && !in_class && source[i, 3] == "(?~"
        return true
      end
      i += 1
    end
    false
  end
  private_class_method :backref?

  # `\k<n>`, `\k'n'`, `\g<n>`, `\g'n'`, and a digit run that names a
  # group the pattern has. A run past the last group, or one that starts
  # with a zero, is an octal escape.
  def self.backref_escape?(source, i, captures)
    c = source[i]
    return (source[i + 1] == "<" || source[i + 1] == "'") if c == "k" || c == "g"
    return false unless c && c >= "1" && c <= "9"

    digits = source[i..].slice(/\A\d+/)
    digits.to_i <= captures
  end
  private_class_method :backref_escape?

  # The seconds any match may take, unless its pattern names its own.
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

    raise TypeError, "no implicit conversion to float from string" if seconds.is_a?(String)
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
    Primitive.zr_regexp_names(self).sort_by { |_, groups| groups.first }
  end

  # The match at byte `from`, searching forward, or backward to it.
  # A regexp whose source holds a byte past ASCII reads one encoding
  # alone, so a subject in another one is an error unless the subject
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
end

class MatchData
  def self.for(regexp, text, offsets)
    m = Class.instance_method(:allocate).bind_call(self)
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
    %i[regexp string shown position offsets].each { |part| Primitive.zr_hidden_set(self, part, Primitive.zr_hidden_get(other, part)) }
    self
  end

  def regexp = Primitive.zr_hidden_get(self, :regexp)

  # The text as it was, a frozen String of this match's own, as CRuby
  # gives each MatchData; made the first time it is asked for from the
  # copy every match of the text shares (`text`). A frozen text is its
  # own.
  def string
    Primitive.zr_hidden_get(self, :shown) || Primitive.zr_state_set(self, :shown, Primitive.zr_str_new_frozen_m(text))
  end

  def names = regexp.is_a?(Regexp) ? regexp.names : []

  def size = offsets.size / 2

  alias length size

  def to_a = (0...size).map { |i| group(i) }

  def captures = to_a.drop(1)

  alias deconstruct captures

  def named_captures(symbolize_names: false)
    return {} unless regexp.is_a?(Regexp)

    regexp.send(:name_rows).to_h do |name, groups|
      value = groups.reverse.map { |g| group(g) }.find { |v| !v.nil? }
      [symbolize_names ? name.to_sym : name, value]
    end
  end

  # More keys than named groups answer an empty Hash; a key with no
  # group ends the walk.
  def deconstruct_keys(keys)
    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.nil? || keys.is_a?(Array)

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

  def values_at(*indexes) = indexes.flat_map { |i| i.is_a?(Range) ? to_a.values_at(i) : [self[i]] }

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

  def pre_match = Primitive.zr_str_byteslice(text, 0, offsets[0])

  def post_match = Primitive.zr_str_byteslice(text, offsets[1], Primitive.zr_str_bytesize(text) - offsets[1])

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
    labels.each_with_index { |label, i| parts << "#{label}:#{group(i + 1).inspect}" }
    Primitive.zr_obj_form("#<MatchData #{parts.join(' ')}>")
  end

  private

  # `offsets` is [position, begin0, end0, begin1, end1, ...]: the byte
  # the search matched at, then every group's byte span.
  def matched(regexp, text, offsets)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :regexp, regexp)
    Primitive.zr_hidden_set(self, :string, MatchData.send(:snapshot, text))
    Primitive.zr_hidden_set(self, :shown, text) if text.frozen?
    Primitive.zr_hidden_set(self, :position, offsets[0])
    Primitive.zr_hidden_set(self, :offsets, offsets.drop(1))
  end

  def offsets
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :offsets)
  end

  # The frozen text the match was made in, shared by every match of it.
  def text
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :string)
  end

  # The byte the search matched at, which a `\K` may leave before the
  # match's own beginning.
  def position
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :position)
  end

  def group(index)
    Primitive.attr! :hidden
    b = offsets[index * 2]
    b < 0 ? nil : Primitive.zr_str_byteslice(text, b, offsets[index * 2 + 1] - b)
  end

  def byte_begin(index)
    Primitive.attr! :hidden
    index = backref_number(index)
    raise IndexError, "index #{index} out of matches" if index < 0 || index >= size

    b = offsets[index * 2]
    b < 0 ? nil : b
  end

  def byte_end(index)
    Primitive.attr! :hidden
    index = backref_number(index)
    raise IndexError, "index #{index} out of matches" if index < 0 || index >= size

    e = offsets[index * 2 + 1]
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

    row[1].reverse.find { |g| offsets[g * 2] >= 0 } || row[1].last
  end
end

class Symbol
  def =~(pattern) = to_s =~ pattern

  def match(*args, &block) = to_s.match(*args, &block)

  def match?(*args) = to_s.match?(*args)
end
