# frozen_string_literal: true

# The parser and the generator json ships as a C extension, in ruby. The
# gem's own ruby half (vendor/ext/json/lib/json.rb) reaches them the way
# it reaches CRuby's, so everything above this file is the gem as
# written.
module JSON
  # What `pretty_generate` sets, and what a plain `generate` leaves off.
  PRETTY = { indent: "  ", space: " ", object_nl: "\n", array_nl: "\n" }.freeze

  class << self
    def generate(obj, opts = nil) = Writer.new(opts).run(obj)

    def pretty_generate(obj, opts = nil) = Writer.new(PRETTY.merge(options(opts))).run(obj)

    def parse(source, opts = nil) = Reader.new(source, options(opts)).run

    alias parse! parse
    alias unsafe_load parse

    # A State, a Hash, or nothing, as a Hash of symbol keys.
    def options(opts)
      return {} if opts.nil?
      return opts.to_h.transform_keys(&:to_sym) if opts.respond_to?(:to_h)

      {}
    end
  end

  # Ruby to JSON text. Only the types json encodes itself are written
  # here; anything else answers `to_json`, which is where the gem's own
  # additions come in.
  class Writer
    ESCAPES = {
      '"' => '\\"', "\\" => "\\\\", "\b" => "\\b", "\f" => "\\f",
      "\n" => "\\n", "\r" => "\\r", "\t" => "\\t"
    }.freeze
    SCRIPT_SAFE = { "/" => "\\/", " " => "\\u2028", " " => "\\u2029" }.freeze

    def initialize(opts)
      opts = JSON.options(opts)
      @indent = opts.fetch(:indent, "")
      @space = opts.fetch(:space, "")
      @space_before = opts.fetch(:space_before, "")
      @object_nl = opts.fetch(:object_nl, "")
      @array_nl = opts.fetch(:array_nl, "")
      @allow_nan = opts.fetch(:allow_nan, false)
      @ascii_only = opts.fetch(:ascii_only, false)
      @script_safe = opts[:script_safe] || opts[:escape_slash] || false
      @strict = opts.fetch(:strict, false)
      @max_nesting = opts.fetch(:max_nesting, 100)
      @max_nesting = nil if @max_nesting == false || @max_nesting == 0
    end

    def run(obj) = value(obj, 0)

    private

    def value(obj, depth)
      case obj
      when nil then "null"
      when true then "true"
      when false then "false"
      when String then string(obj)
      when Integer then obj.to_s
      when Float then float(obj)
      when Array then array(obj, depth)
      when Hash then object(obj, depth)
      else other(obj, depth)
      end
    end

    def other(obj, _depth)
      raise GeneratorError, "#{obj.class} not allowed in JSON" if @strict
      return obj.to_json(self) if obj.respond_to?(:to_json)

      string(obj.to_s)
    end

    def float(obj)
      return obj.to_s if obj.finite?
      raise GeneratorError, "#{obj.nan? ? "NaN" : (obj.positive? ? "Infinity" : "-Infinity")} not allowed in JSON" unless @allow_nan

      obj.nan? ? "NaN" : (obj.positive? ? "Infinity" : "-Infinity")
    end

    def array(obj, depth)
      deeper = nest(depth)
      return "[]" if obj.empty?

      pad = @indent * deeper
      rows = obj.map { |v| "#{pad}#{value(v, deeper)}" }
      "[#{@array_nl}#{rows.join(",#{@array_nl.empty? ? "" : @array_nl}#{@array_nl.empty? ? "" : ""}")}#{@array_nl}#{@indent * depth}]"
    end

    def object(obj, depth)
      deeper = nest(depth)
      return "{}" if obj.empty?

      pad = @indent * deeper
      rows = obj.map { |k, v| "#{pad}#{string(key(k))}#{@space_before}:#{@space}#{value(v, deeper)}" }
      "{#{@object_nl}#{rows.join(",#{@object_nl}")}#{@object_nl}#{@indent * depth}}"
    end

    def key(k)
      return k if k.is_a?(String)
      return k.to_s if k.is_a?(Symbol) || k.is_a?(Integer)
      raise GeneratorError, "#{k.class} not allowed as a JSON object key" if @strict

      k.to_s
    end

    def nest(depth)
      deeper = depth + 1
      if @max_nesting && deeper > @max_nesting
        raise NestingError, "nesting of #{deeper - 1} is too deep. Did you try to serialize objects with circular references?"
      end

      deeper
    end

    def string(text)
      text = text.to_s
      text = text.encode(Encoding::UTF_8) unless text.encoding == Encoding::UTF_8
      out = +'"'
      text.each_char { |c| out << escaped(c) }
      out << '"'
    end

    def escaped(c)
      return ESCAPES[c] if ESCAPES.key?(c)
      return SCRIPT_SAFE[c] if @script_safe && SCRIPT_SAFE.key?(c)

      code = c.ord
      return format("\\u%04x", code) if code < 0x20
      return c unless @ascii_only && code > 0x7f
      return format("\\u%04x", code) if code <= 0xffff

      high = 0xd800 + ((code - 0x10000) >> 10)
      format("\\u%04x\\u%04x", high, 0xdc00 + ((code - 0x10000) & 0x3ff))
    end
  end

  # JSON text to ruby, read left to right. Every stop names the line and
  # the column it stands on, as the C parser does.
  class Reader
    WORDS = { "true" => true, "false" => false, "null" => nil }.freeze
    NAN = { "NaN" => Float::NAN, "Infinity" => Float::INFINITY, "-Infinity" => -Float::INFINITY }.freeze
    UNESCAPE = { '"' => '"', "\\" => "\\", "/" => "/", "b" => "\b", "f" => "\f", "n" => "\n", "r" => "\r", "t" => "\t" }.freeze

    def initialize(source, opts)
      source = source.to_str
      @text = source.encoding == Encoding::UTF_8 ? source : source.dup.force_encoding(Encoding::UTF_8)
      @chars = @text.chars
      @i = 0
      @symbolize = opts.fetch(:symbolize_names, false)
      @freeze = opts.fetch(:freeze, false)
      @allow_nan = opts.fetch(:allow_nan, false)
      @trailing = opts.fetch(:allow_trailing_comma, false)
      @object_class = opts.fetch(:object_class, nil) || Hash
      @array_class = opts.fetch(:array_class, nil) || Array
      @decimal_class = opts[:decimal_class]
      @max_nesting = opts.fetch(:max_nesting, 100)
      @max_nesting = nil if @max_nesting == false || @max_nesting == 0
    end

    def run
      skip_space
      stop("unexpected end of input") if done?

      out = value(0)
      skip_space
      stop("unexpected token at end of stream #{rest}") unless done?
      out
    end

    private

    def done? = @i >= @chars.size

    def here = @chars[@i]

    def rest = "'#{@chars[@i..].join}'"

    def skip_space
      @i += 1 while !done? && " \t\n\r".include?(@chars[@i])
    end

    # `line column` counted from the start, which is what every message
    # names.
    def stop(what, at = @i)
      before = @chars[0, at]
      line = before.count("\n") + 1
      column = at - (before.rindex("\n") || -1)
      raise ParserError, "#{what} at line #{line} column #{column}"
    end

    def value(depth)
      case here
      when "{" then object(nest(depth))
      when "[" then array(nest(depth))
      when '"' then string
      when "0".."9" then number
      when "-" then @chars[@i + 1] == "I" ? word(depth) : number
      else word(depth)
      end
    end

    def nest(depth)
      deeper = depth + 1
      raise NestingError, "nesting of #{deeper} is too deep" if @max_nesting && deeper > @max_nesting

      deeper
    end

    # A word is `true`, `false`, `null`, or one of the three non-finite
    # numbers. Anything else starts nothing: the message shows the rest
    # of the input, and nothing at all at the top level, as ruby's does.
    def word(depth)
      at = @i
      run = @chars[@i..].take_while { |c| /[A-Za-z\-]/.match?(c) }.join
      stop("unexpected character: #{depth.zero? ? "''" : rest}", at) if run.empty?

      if WORDS.key?(run)
        @i += run.size
        return WORDS[run]
      end
      if @allow_nan && NAN.key?(run)
        @i += run.size
        return NAN[run]
      end
      stop("unexpected token #{rest}", at)
    end

    def number
      at = @i
      text = @chars[@i..].take_while { |c| /[0-9eE+\-.]/.match?(c) }.join
      m = /\A-?(?:0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?\z/.match(text)
      stop("invalid number: #{rest}", at) unless m

      @i += text.size
      return m[1] || m[2] ? text.to_f : text.to_i unless @decimal_class && (m[1] || m[2])

      @decimal_class.public_send(@decimal_class.respond_to?(:new) ? :new : :call, text)
    end

    def string
      at = @i
      @i += 1
      out = +""
      until done? && stop("unexpected end of input, expected closing \"", @chars.size)
        c = @chars[@i]
        if c == '"'
          @i += 1
          out = out.force_encoding(Encoding::UTF_8)
          return @freeze ? -out : out
        end
        c == "\\" ? unescape(out) : (out << c and @i += 1)
      end
      stop("unexpected end of input, expected closing \"", at)
    end

    def unescape(out)
      at = @i
      c = @chars[@i + 1]
      if UNESCAPE.key?(c)
        out << UNESCAPE[c]
        @i += 2
      elsif c == "u"
        out << codepoint
      else
        stop("invalid escape character in string: #{rest}", at)
      end
    end

    # `\uHHHH`, and the pair a character past the basic plane is written as.
    def codepoint
      code = hex4
      return code.chr(Encoding::UTF_8) unless code >= 0xd800 && code < 0xdc00 && @chars[@i] == "\\" && @chars[@i + 1] == "u"

      low = hex4
      (0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00)).chr(Encoding::UTF_8)
    end

    def hex4
      digits = @chars[@i + 2, 4].join
      stop("incomplete unicode character escape sequence: #{rest}") unless /\A\h{4}\z/.match?(digits)

      @i += 6
      digits.to_i(16)
    end

    def array(depth)
      out = @array_class.new
      @i += 1
      skip_space
      if here == "]"
        @i += 1
        return out
      end
      loop do
        skip_space
        stop("unexpected end of input") if done?
        stop("unexpected character: #{rest}") if here == "]" || here == ","

        out << value(depth)
        skip_space
        stop("unexpected end of input") if done?
        break if here == "]"
        stop("expected ',' or ']' after array value") unless here == ","

        @i += 1
        skip_space
        break if @trailing && here == "]"
      end
      @i += 1
      out
    end

    def object(depth)
      out = @object_class.new
      @i += 1
      first = true
      loop do
        skip_space
        stop("expected object key, got EOF") if done?
        break if here == "}" && (first || @trailing)
        stop("expected object key, got#{first ? "" : ":"} #{rest}") unless here == '"'

        key = string
        key = @symbolize ? key.to_sym : key
        skip_space
        stop("expected ':' after object key") unless here == ":"

        @i += 1
        skip_space
        stop("unexpected end of input") if done?
        out[key] = value(depth)
        skip_space
        stop("unexpected end of input") if done?
        break if here == "}"
        stop("expected ',' or '}' after object value") unless here == ","

        @i += 1
        first = false
      end
      @i += 1
      out
    end
  end
end
