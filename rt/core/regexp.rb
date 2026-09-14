# Regexp and MatchData over the kernel's oniguruma binding. A match
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

  ERRORS = {
    -5 => "fail to memory allocation", -6 => "undefined type (bug)", -11 => "internal parser error (bug)",
    -12 => "stack error (bug)", -13 => "undefined bytecode (bug)", -14 => "unexpected bytecode (bug)",
    -15 => "match-stack limit over", -16 => "parse depth limit over", -17 => "retry-limit-in-match over",
    -18 => "retry-limit-in-search over", -19 => "subexp-call-limit-in-search over",
    -21 => "default multibyte-encoding is not set",
    -22 => "can't convert to wide-char on specified multibyte-encoding", -23 => "fail to initialize",
    -30 => "invalid argument", -100 => "end pattern at left brace", -101 => "end pattern at left bracket",
    -102 => "empty char-class", -103 => "premature end of char-class", -104 => "end pattern at escape",
    -105 => "end pattern at meta", -106 => "end pattern at control", -108 => "invalid meta-code syntax",
    -109 => "invalid control-code syntax", -110 => "char-class value at end of range",
    -111 => "char-class value at start of range", -112 => "unmatched range specifier in char-class",
    -113 => "target of repeat operator is not specified", -114 => "target of repeat operator is invalid",
    -115 => "nested repeat operator", -116 => "unmatched close parenthesis",
    -117 => "end pattern with unmatched parenthesis", -118 => "end pattern in group",
    -119 => "undefined group option", -120 => "invalid group option", -121 => "invalid POSIX bracket type",
    -122 => "invalid pattern in look-behind", -123 => "invalid repeat range {lower,upper}", -200 => "too big number",
    -201 => "too big number for repeat range", -202 => "upper is smaller than lower in repeat range",
    -203 => "empty range in char class", -204 => "mismatch multibyte code length in char-class range",
    -205 => "too many multibyte code ranges are specified", -206 => "too short multibyte code string",
    -207 => "too big backref number", -208 => "invalid backref number/name",
    -209 => "numbered backref/call is not allowed. (use name)", -210 => "too many captures",
    -212 => "too long wide-char value", -213 => "undefined operator", -214 => "group name is empty",
    -215 => "invalid group name <%n>", -216 => "invalid char in group name <%n>",
    -217 => "undefined name <%n> reference", -218 => "undefined group <%n> reference",
    -219 => "multiplex defined name <%n>", -220 => "multiplex definition name <%n> call",
    -221 => "never ending recursion", -222 => "group number is too big for capture history",
    -223 => "invalid character property name {%n}", -224 => "invalid if-else syntax",
    -225 => "invalid absent group pattern", -226 => "invalid absent group generator pattern",
    -227 => "invalid callout pattern", -228 => "invalid callout name", -229 => "undefined callout name",
    -230 => "invalid callout body", -231 => "invalid callout tag name", -232 => "invalid callout arg",
    -400 => "invalid code point value", -401 => "too big wide-char value",
    -402 => "not supported encoding combination", -403 => "invalid combination of options",
    -406 => "very inefficient pattern", -500 => "library is not initialized"
  }.freeze
  private_constant :ERRORS

  # `Regexp.new` is `Class#new`, as it is in CRuby: `allocate` makes the
  # husk and this seats the pattern in it. A subclass whose own
  # initialize builds the source therefore keeps the source it handed to
  # `super`.
  def initialize(source, options = nil, timeout: nil)
    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, "already initialized regexp" unless Primitive.zr_regexp_source(self).nil?

    if source.is_a?(Regexp)
      Primitive.zr_warn_here_m("flags ignored") unless options.nil?
      options = source.options
      source = source.source
    end
    raise TypeError, "no implicit conversion of #{conversion_name(source)} into String" unless source.is_a?(String)

    Regexp.send(:seat, self, source, Regexp.send(:option_bits, options))
    Primitive.zr_regexp_limit_set(self, Regexp.send(:nanoseconds, timeout))
    self
  end

  # The option bits an `options` argument names, as CRuby's
  # reg_extract_args reads it.
  def self.option_bits(options)
    case options
    when nil, false then 0
    when true then IGNORECASE
    when Integer then options & 7
    when String
      options.each_char.reduce(0) do |acc, c|
        acc | { "i" => IGNORECASE, "x" => EXTENDED, "m" => MULTILINE }.fetch(c) { raise ArgumentError, "unknown regexp option: #{options}" }
      end
    else raise TypeError, "no implicit conversion of #{conversion_name(options)} into Integer"
    end
  end
  private_class_method :option_bits

  # A literal's Regexp, for the kernel's literal table. A flag letter
  # that names an encoding pins the pattern to it.
  def self.literal(source, bits, pinned)
    pin(compile_source(source, bits), pinned)
  end
  private_class_method :literal

  # `/a#{b}c/u`: the same, built once each time the literal runs.
  def self.interpolated(source, bits, pinned)
    Primitive.attr! :hidden
    pin(compile_source(source, bits), pinned).freeze
  end

  def self.pin(made, pinned)
    Primitive.attr! :hidden
    made.instance_variable_set(:@pinned, Encoding.at(pinned).send(:load)) if pinned
    made
  end
  private_class_method :pin

  # `source` compiled with the option `bits`, seated in the husk `re`; a
  # RegexpError names the reason, then the pattern as written with its
  # flags.
  def self.seat(re, source, bits)
    source = source.dup.freeze unless source.frozen?
    written = "/#{source}/#{(bits & MULTILINE != 0 ? 'm' : '')}#{(bits & IGNORECASE != 0 ? 'i' : '')}#{(bits & EXTENDED != 0 ? 'x' : '')}"
    raise RegexpError, "upper is smaller than lower in repeat range: #{written}" if inverted_interval?(source)

    begin
      text = Pattern.engine_text(source, bits & EXTENDED != 0, binary_pattern?(source, bits))
    rescue RegexpError => e
      raise RegexpError, "#{e.message}: #{written}"
    end
    result = Primitive.zr_regexp_seat(re, text.frozen? ? text : text.dup.freeze, source, bits)
    if result.is_a?(Array)
      code, at = result
      reason = (ERRORS[code] || "regexp error #{code}").sub("%n", at.to_s)
      raise RegexpError, "#{reason}: #{written}"
    end
    result
  end
  private_class_method :seat

  # A Regexp of this class over `source`: the husk and its pattern in
  # one step, which the literal table and the copies ask for.
  def self.compile_source(source, bits) = seat(allocate, source, bits)
  private_class_method :compile_source

  # Whether the engine reads the pattern as bytes: its own encoding says
  # so, or `/n` and a byte past ASCII in it.
  def self.binary_pattern?(source, bits)
    Primitive.attr! :hidden
    source.encoding == Encoding::BINARY || (bits & NOENCODING != 0 && Pattern.past_ascii?(source))
  end

  # A dup or clone compiles its own pattern from the same source.
  # rb_reg_init_copy: what `dup` and `clone` fill a husk with -- the
  # other Regexp's pattern, compiled for the copy -- and a refusal for a
  # Regexp that already holds one.
  def initialize_copy(other)
    return self if equal?(other)

    Primitive.zr_frozen_error(self) if frozen?
    raise TypeError, "initialize_copy should take same class object" unless other.instance_of?(self.class)
    raise TypeError, "already initialized regexp" unless Primitive.zr_regexp_source(self).nil?

    Primitive.zr_regexp_copy_from(self, other)
    self
  end
  private :initialize_copy

  def recompile
    Primitive.attr! :hidden
    text = Pattern.engine_text(source, options & EXTENDED != 0, Regexp.binary_pattern?(source, options))
    Primitive.zr_regexp_recompile(self, text.frozen? ? text : text.dup.freeze)
  end
  private :recompile

  # `a{2,1}`: an interval whose upper bound is below its lower one, which
  # Ruby refuses where oniguruma would read it as possessive.
  def self.inverted_interval?(source)
    in_class = false
    i = 0
    while i < source.size
      c = source[i]
      if c == "\\"
        i += 1
      elsif c == "["
        in_class = true
      elsif c == "]"
        in_class = false
      elsif c == "{" && !in_class && (stop = source.index("}", i))
        low, high = source[(i + 1)...stop].split(",", 2)
        return true if high && low.match?(/\A\d+\z/) && high.match?(/\A\d+\z/) && low.to_i > high.to_i

        i = stop
      end
      i += 1
    end
    false
  end
  private_class_method :inverted_interval?

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

  def self.union(*patterns)
    patterns = patterns[0] if patterns.size == 1 && patterns[0].is_a?(Array)
    return new("(?!)") if patterns.empty?
    return patterns[0] if patterns.size == 1 && patterns[0].is_a?(Regexp)

    new(patterns.map { |pattern| pattern.is_a?(Regexp) ? pattern.to_s : escape(pattern) }.join("|"))
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

  # `/n` on an ASCII-only pattern reads it as plain ASCII, which is what
  # the source shows too.
  def source
    text = pattern
    options & NOENCODING != 0 && text.ascii_only? ? text.dup.force_encoding(Encoding::US_ASCII).freeze : text
  end

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

  # `/n` reads the pattern as bytes: one that names a byte past ASCII,
  # written out or escaped, is a binary pattern, and one that does not is
  # plain ASCII that any string can match.
  def encoding
    return Encoding::BINARY unless Primitive.zr_regexp_source(self)
    return @pinned if @pinned
    return Encoding::BINARY if options & NOENCODING != 0 && Pattern.past_ascii?(source)

    source.ascii_only? ? Encoding::US_ASCII : source.encoding
  end

  def fixed_encoding?
    return false unless Primitive.zr_regexp_source(self)
    return true unless @pinned.nil?
    return Pattern.past_ascii?(source) if options & NOENCODING != 0

    !source.ascii_only?
  end

  def ==(other) = other.is_a?(Regexp) && source == other.source && options == other.options

  alias eql? ==

  def hash = [source, options].hash

  def to_s
    on = +""
    off = +""
    { "m" => MULTILINE, "i" => IGNORECASE, "x" => EXTENDED }.each { |letter, bit| (options & bit != 0 ? on : off) << letter }
    "(?#{on}#{off.empty? ? '' : "-#{off}"}:#{shown_source})"
  end

  def inspect
    return Object.instance_method(:to_s).bind_call(self) unless Primitive.zr_regexp_source(self)

    text = "/#{shown_source}/"
    text << "m" if options & MULTILINE != 0
    text << "i" if options & IGNORECASE != 0
    text << "x" if options & EXTENDED != 0
    text << "n" if options & NOENCODING != 0
    text
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
    pos += text.size if pos < 0
    if pos < 0 || pos > text.size
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
    pos += text.size if pos < 0
    return false if pos < 0 || pos > text.size

    check_subject(text)
    !Primitive.zr_regexp_search(self, text, Primitive.zr_str_char_offset_m(text, pos), false).nil?
  end

  # The character the search matched at (before a `\K`), or nil.
  def =~(text)
    result = match(text)
    result && Primitive.zr_str_byte_to_char(result.string, result.send(:position))
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

  # The source as inspect and to_s show it: a bare `/` escaped, a
  # control character as `\xHH`, whitespace as itself.
  def shown_source
    Primitive.attr! :hidden
    text = +""
    escaped = false
    source.each_char do |c|
      code = c.ord
      if c == "/" && !escaped
        text << "\\/"
      elsif code < 0x20 && !" \t\n\v\f\r".include?(c) || code == 0x7f
        text << format("\\x%02X", code)
      else
        text << c
      end
      escaped = c == "\\" && !escaped
    end
    text
  end

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
  def check_subject(text)
    Primitive.attr! :hidden
    raise ArgumentError, "invalid byte sequence in #{text.encoding}" unless text.valid_encoding?
    # UTF-16 and UTF-32 match no pattern: their ASCII is not ASCII bytes.
    return unless !text.encoding.ascii_compatible? || (fixed_encoding? && text.encoding != encoding && !text.ascii_only?)

    raise Encoding::CompatibilityError,
          "incompatible encoding regexp match (#{Encoding.shown(encoding)} regexp with #{Encoding.shown(text.encoding)} string)"
  end
  private :check_subject

  def search(text, from, backward)
    Primitive.attr! :hidden
    pattern
    check_subject(text)

    offsets = Primitive.zr_regexp_search(self, text, from, backward)
    offsets && MatchData.send(:for, self, text, offsets)
  end

  def match_at(text, from)
    Primitive.attr! :hidden
    pattern
    check_subject(text)

    offsets = Primitive.zr_regexp_match_at(self, text, from)
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

  # A MatchData comes from a match, never from a constructor, so ruby
  # takes both spellings away.
  class << self
    undef_method :allocate, :new
  end

  # A MatchData copies the match it is given, of its own kind only.
  private def initialize_copy(other)
    super
    %i[regexp string position offsets].each { |part| Primitive.zr_hidden_set(self, part, Primitive.zr_hidden_get(other, part)) }
    self
  end

  def regexp = Primitive.zr_hidden_get(self, :regexp)

  def string = Primitive.zr_hidden_get(self, :string)

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
    b && Primitive.zr_str_byte_to_char(string, b)
  end

  def end(index)
    e = byte_end(index)
    e && Primitive.zr_str_byte_to_char(string, e)
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

  def pre_match = string.byteslice(0, offsets[0])

  def post_match = string.byteslice(offsets[1], string.bytesize - offsets[1])

  def to_s = group(0)

  def ==(other)
    other.is_a?(MatchData) && regexp == other.regexp && string == other.string && offsets == other.send(:offsets)
  end

  alias eql? ==

  def hash = [regexp, string, offsets].hash

  def inspect
    labels = Array.new(size - 1) { |i| (i + 1).to_s }
    regexp.send(:name_rows).each { |name, groups| groups.each { |g| labels[g - 1] = name } } if regexp.is_a?(Regexp)
    parts = [group(0).inspect]
    labels.each_with_index { |label, i| parts << "#{label}:#{group(i + 1).inspect}" }
    "#<MatchData #{parts.join(' ')}>"
  end

  private

  # `offsets` is [position, begin0, end0, begin1, end1, ...]: the byte
  # the search matched at, then every group's byte span.
  def matched(regexp, text, offsets)
    Primitive.attr! :hidden
    Primitive.zr_hidden_set(self, :regexp, regexp)
    Primitive.zr_hidden_set(self, :string, text.frozen? ? text : text.dup.freeze)
    Primitive.zr_hidden_set(self, :position, offsets[0])
    Primitive.zr_hidden_set(self, :offsets, offsets.drop(1))
  end

  def offsets
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :offsets)
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
    b < 0 ? nil : string.byteslice(b, offsets[index * 2 + 1] - b)
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
