# frozen_string_literal: true

# The 4.8 wire format: a one-byte tag for each kind, a packed integer for
# every count, and two link tables so a graph that shares an object or a
# symbol writes it once.
module Marshal
  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  def self.dump(obj, io = nil, limit = -1)
    io, limit = nil, io if io.is_a?(Integer)
    limit = -1 if limit.nil?
    out = Writer.new(limit).run(obj)
    return out if io.nil?

    io.write(out)
    io
  end

  def self.load(source, handler = nil, freeze: false)
    bytes = source.respond_to?(:read) ? source.read : Primitive.zr_str_operand(source)
    Reader.new(bytes, handler, freeze).run
  end

  class << self
    alias restore load
  end

  # What holds a task, a lock, a descriptor or compiled code, which no
  # wire format can carry.
  UNDUMPABLE = %w[Proc Method UnboundMethod Binding Enumerator Fiber Dir MatchData Ractor StringIO
                  Thread Thread::Mutex Thread::Queue Thread::SizedQueue Thread::ConditionVariable].freeze
  private_constant :UNDUMPABLE

  # The tags, by the character each one writes.
  class Writer
    def initialize(limit)
      @limit = limit
      @out = +"".b
      @objects = {}.compare_by_identity
      @symbols = {}
      @encodings = {}
      @count = 0
    end

    def run(obj)
      @out << MAJOR_VERSION.chr << MINOR_VERSION.chr
      write(obj, @limit)
      @out
    end

    private

    def write(obj, limit)
      raise ArgumentError, "exceed depth limit" if limit == 0

      case obj
      when nil then @out << "0"
      when true then @out << "T"
      when false then @out << "F"
      when Symbol then symbol(obj)
      when Integer then integer(obj)
      else linked(obj, limit - 1)
      end
    end

    # An object the format can name twice: the second time it is a link.
    def linked(obj, limit)
      index = @objects[obj]
      return @out << "@" << long(index) if index

      return user_marshal(obj, limit) if obj.respond_to?(:marshal_dump, true)
      return user_dump(obj, limit) if obj.respond_to?(:_dump, true)


      refuse(obj)
      remember(obj)
      body(obj, limit)
    end

    def refuse(obj)
      raise TypeError, "can't dump #{obj.class}" if obj.is_a?(IO)
      return unless obj.class.ancestors.any? { |kind| UNDUMPABLE.include?(kind.name) }

      raise TypeError, "no _dump_data is defined for class #{obj.class}"
    end

    def body(obj, limit)
      ivars = ivars_of(obj)
      wrapped = !ivars.empty? && !plain_object?(obj)
      @out << "I" if wrapped
      extended(obj)
      case obj
      when Class then @out << "c" << bytes(class_path(obj))
      when Module then @out << "m" << bytes(class_path(obj))
      when Float then @out << "f" << bytes(float_text(obj))
      when Integer then @out << "l" << bignum(obj)
      when String then uclass(obj, String) << '"' << bytes(obj)
      when Regexp then uclass(obj, Regexp) << "/" << bytes(obj.source) << (obj.options & 0xff).chr
      when Array then array(obj, limit)
      when Hash then hash(obj, limit)
      when Range then object_body("Range", range_parts(obj), limit)
      when Exception then object_body(class_path(obj.class), exception_parts(obj), limit)
      when Struct, Data then struct(obj, limit)
      else object_body(class_path(obj.class), ivars, limit)
      end
      write_ivars(ivars, limit) if wrapped
    end

    # A Range writes the three parts ruby gives it, in ruby's order.
    def range_parts(range)
      [[:excl, range.exclude_end?], [:begin, range.begin], [:end, range.end]]
    end

    # Ruby holds an exception's message, its backtrace and an errno beside
    # its instance variables, under names of its own.
    def exception_parts(exception)
      parts = [[:mesg, Primitive.zr_exc_raw_message(exception)], [:bt, exception.backtrace]]
      parts << [:errno, exception.errno] if exception.is_a?(SystemCallError)
      parts + exception.instance_variables.map { |name| [name, exception.instance_variable_get(name)] }
    end

    def object_body(path, parts, limit)
      @out << "o" << symbol_bytes(path.to_sym) << long(parts.size)
      parts.each do |name, value|
        @out << symbol_bytes(name)
        write(value, limit)
      end
    end

    # A Struct and a Data value write the same record: each member's name
    # and value. A Data value has no `[]`, so its values come as it keeps
    # them.
    def struct(obj, limit)
      members = obj.class.members
      values = obj.is_a?(Data) ? obj.send(:values_store) : members.map { |name| obj[name] }
      @out << "S" << symbol_bytes(class_path(obj.class).to_sym) << long(members.size)
      members.each_with_index do |name, i|
        @out << symbol_bytes(name)
        write(values[i], limit)
      end
    end

    def array(obj, limit)
      uclass(obj, Array) << "[" << long(obj.size)
      obj.each { |item| write(item, limit) }
    end

    def hash(obj, limit)
      default = obj.default
      uclass(obj, Hash) << (default.nil? ? "{" : "}") << long(obj.size)
      obj.each_pair do |key, value|
        write(key, limit)
        write(value, limit)
      end
      write(default, limit) unless default.nil?
    end

    # `C` names the subclass a String, Array, Hash or Regexp belongs to.
    def uclass(obj, base)
      @out << "C" << symbol_bytes(class_path(obj.class).to_sym) if obj.class != base
      @out
    end

    # `e` names each module the object alone was extended with.
    def extended(obj)
      return if obj.is_a?(Numeric) || obj.is_a?(Module)

      own = obj.singleton_class
      raise TypeError, "singleton can't be dumped" unless (own.instance_methods(false) + own.private_instance_methods(false)).empty?

      own.ancestors.take_while { |mod| mod != obj.class }.each do |mod|
        @out << "e" << symbol_bytes(mod.name.to_sym) if mod.instance_of?(Module)
      end
    end

    def user_marshal(obj, limit)
      remember(obj)
      value = obj.send(:marshal_dump)
      @out << "U" << symbol_bytes(class_path(obj.class).to_sym)
      write(value, limit)
    end

    def user_dump(obj, limit)
      text = obj.send(:_dump, limit)
      ivars = ivars_of(text)
      @out << "I" unless ivars.empty?
      @out << "u" << symbol_bytes(class_path(obj.class).to_sym) << bytes(text)
      write_ivars(ivars, limit) unless ivars.empty?
      remember(obj)
    end

    def remember(obj)
      @objects[obj] = @count
      @count += 1
      obj
    end

    # What an object carries beside its parts: its instance variables, and
    # for a String, a Regexp or a Symbol the name of its encoding.
    def ivars_of(obj)
      # A class or module is written by its name alone.
      return [] if obj.is_a?(Module)

      names = obj.respond_to?(:instance_variables) ? obj.instance_variables : []
      parts = names.map { |name| [name, obj.instance_variable_get(name)] }
      obj.is_a?(String) || obj.is_a?(Regexp) ? encoding_ivar(obj.encoding) + parts : parts
    end

    # An encoding writes only its name, and the name takes a link slot of
    # its own, so a second string in the same encoding names it once.
    def encoding_name(name)
      index = @encodings[name]
      return @out << "@" << long(index) if index

      @encodings[name] = @count
      @count += 1
      @out << '"' << bytes(name)
    end

    def encoding_ivar(encoding)
      case encoding
      when Encoding::BINARY then []
      when Encoding::UTF_8 then [[:E, true]]
      when Encoding::US_ASCII then [[:E, false]]
      else [[:encoding, encoding]]
      end
    end

    def write_ivars(ivars, limit)
      @out << long(ivars.size)
      ivars.each do |name, value|
        @out << symbol_bytes(name)
        value.is_a?(Encoding) ? encoding_name(value.name) : write(value, limit)
      end
    end

    # A Range and a plain object write their parts as the object body, so
    # the wrapper must not write them twice.
    def plain_object?(obj)
      return false if obj.is_a?(Class) || obj.is_a?(Module) || obj.is_a?(Struct) || obj.is_a?(Data)

      obj.is_a?(Range) || !(obj.is_a?(String) || obj.is_a?(Regexp) || obj.is_a?(Array) ||
                            obj.is_a?(Hash) || obj.is_a?(Float) || obj.is_a?(Integer))
    end

    def class_path(mod)
      raise TypeError, "singleton class can't be dumped" if mod.singleton_class?

      name = mod.name
      raise TypeError, "can't dump anonymous #{mod.is_a?(Class) ? "class" : "module"} #{mod.inspect}" if name.nil?

      name
    end

    def symbol(sym)
      @out << symbol_bytes(sym)
    end

    # A symbol writes once; every later use is a link into the same table.
    def symbol_bytes(sym)
      index = @symbols[sym]
      return +";".b << long(index) if index

      @symbols[sym] = @symbols.size
      text = sym.to_s
      return +":".b << bytes(text) if text.ascii_only?

      +"I".b << ":" << bytes(text) << long(1) << symbol_bytes(:E) << (text.encoding == Encoding::UTF_8 ? "T" : "F")
    end

    # Ruby keeps `i` for what fits in four bytes and writes every wider
    # number as a bignum, whatever its class.
    def integer(n)
      return @out << "i" << long(n) if n >= -1073741824 && n <= 1073741823

      linked(n, 0)
    end

    def bignum(n)
      words = []
      rest = n.abs
      while rest > 0
        words << (rest & 0xffff)
        rest >>= 16
      end
      words << 0 if words.empty?
      (n < 0 ? "-" : "+") + long(words.size) + words.flat_map { |w| [w & 0xff, w >> 8] }.pack("C*")
    end

    def bytes(text)
      text = text.b
      long(text.bytesize) + text
    end

    # The packed integer: one byte for a small number, else a length byte
    # and the bytes of the number, least significant first.
    def long(n)
      return 0.chr if n == 0
      return (n + 5).chr if n > 0 && n < 123
      return ((n - 5) & 0xff).chr if n < 0 && n > -124

      out = +"".b
      rest = n
      8.times do |i|
        out << (rest & 0xff).chr
        rest >>= 8
        return ((i + 1) & 0xff).chr + out if rest == 0
        return ((-(i + 1)) & 0xff).chr + out if rest == -1
      end
      8.chr + out
    end

    def float_text(value)
      return "inf" if value == Float::INFINITY
      return "-inf" if value == -Float::INFINITY
      return "nan" if value.nan?
      return value.to_s.start_with?("-") ? "-0" : "0" if value == 0.0

      digits, point = Primitive.zr_float_shortest(value)
      (value < 0 ? "-" : "") + (point < -3 || point > digits.size ? float_exponent(digits, point) : float_plain(digits, point))
    end

    def float_exponent(digits, point)
      head = digits.size > 1 ? "#{digits[0]}.#{digits[1..]}" : digits
      "#{head}e#{point - 1}"
    end

    def float_plain(digits, point)
      return "0." + "0" * -point + digits if point <= 0
      return digits if point == digits.size

      "#{digits[0, point]}.#{digits[point..]}"
    end
  end

  # The reader, over the bytes a writer made.
  class Reader
    def initialize(bytes, handler, freeze)
      @bytes = bytes
      @pos = 0
      @handler = handler
      @freeze = freeze
      @objects = []
      @symbols = []
    end

    def run
      major = byte
      minor = byte
      if major != MAJOR_VERSION || minor > MINOR_VERSION
        raise TypeError, "incompatible marshal file format (can't be read)\n\tformat version #{MAJOR_VERSION}.#{MINOR_VERSION} required; #{major}.#{minor} given"
      end

      read
    end

    private

    # Every value the reader leaves runs the handler and takes the freeze;
    # a tag that only wraps another one does neither, so a wrapped value
    # is reported once, after its ivars.
    def read
      leave(read_value)
    end

    def leave(value)
      value.freeze if @freeze && !value.is_a?(Module)
      @handler&.call(value)
      value
    end

    def read_value
      tag = byte.chr
      case tag
      when "0" then nil
      when "T" then true
      when "F" then false
      when "i" then long
      when ":" then new_symbol(text)
      when ";" then @symbols.fetch(long)
      when "@" then @objects.fetch(long)
      when "I" then with_ivars
      when "e" then extended
      when "l" then keep(bignum)
      when "f" then keep(float(text))
      when '"' then keep(text)
      when "/" then keep(regexp)
      when "[" then array(Array)
      when "{" then hash(Hash, false)
      when "}" then hash(Hash, true)
      when "c" then keep(constant(text, Class))
      when "m" then keep(constant(text, Module))
      when "M" then keep(constant(text, Module))
      when "S" then struct
      when "o" then object
      when "C" then subclass
      when "u" then user_dump
      when "U" then user_marshal
      else raise ArgumentError, "dump format error(0x#{tag.ord.to_s(16)})"
      end
    end

    # `I` names the ivars that follow the object they belong to, so the
    # object must be built before they can be read.
    def with_ivars
      tag = @bytes.getbyte(@pos).chr
      return deferred(tag) if tag == "/" || tag == "u"

      value = read_value
      ivars.each { |name, item| apply_ivar(value, name, item) }
      value
    end

    # A regexp and a `_dump` payload need their encoding before they can be
    # built, so both read their own bytes, then their own ivars.
    def deferred(tag)
      @pos += 1
      here = @objects.size
      @objects << nil
      klass = tag == "u" ? constant(symbol_or_link.to_s, Class) : nil
      payload = text
      options = tag == "/" ? byte : nil
      ivars.each { |name, item| apply_ivar(payload, name, item) }
      built = tag == "/" ? Regexp.new(payload, options) : klass._load(payload)
      @objects[here] = built
      built
    end

    def ivars
      long.times.map { [symbol_or_link, read] }
    end

    def apply_ivar(value, name, item)
      case name
      when :E then value.force_encoding(item ? Encoding::UTF_8 : Encoding::US_ASCII)
      when :encoding then value.force_encoding(item)
      else value.instance_variable_set(name, item)
      end
    end

    def extended
      mod = constant(symbol_or_link.to_s, Module)
      value = read_value
      value.extend(mod)
      value
    end

    def subclass
      klass = constant(symbol_or_link.to_s, Class)
      value = read_value
      built = Primitive.zr_class_allocate(klass)
      case value
      when String then built.replace(value)
      when Array then built.replace(value)
      when Hash then built.replace(value)
      end
      @objects[@objects.size - 1] = built
      built
    end

    def regexp
      source = text
      Regexp.new(source, byte)
    end

    def array(klass)
      out = keep(klass == Array ? [] : Primitive.zr_class_allocate(klass))
      long.times { out << read }
      out
    end

    def hash(klass, defaulted)
      out = keep(klass == Hash ? {} : Primitive.zr_class_allocate(klass))
      long.times do
        key = read
        out[key] = read
      end
      out.default = read if defaulted
      out
    end

    def struct
      name = symbol_or_link
      klass = constant(name.to_s, Class)
      values = {}
      here = @objects.size
      @objects << nil
      long.times do
        member = symbol_or_link
        values[member] = read
      end
      built = Primitive.zr_class_allocate(klass)
      # A Data value has no writers: its values are set as they are kept,
      # and it is frozen, as `new` leaves it.
      if klass <= Data
        Primitive.zr_hidden_set(built, :__values__, klass.members.map { |member| values[member] }.freeze)
        built.freeze
      else
        values.each { |member, value| built.send(:"#{member}=", value) }
      end
      @objects[here] = built
      built
    end

    def object
      klass = constant(symbol_or_link.to_s, Class)
      here = @objects.size
      @objects << Primitive.zr_class_allocate(klass)
      parts = {}
      long.times do
        name = symbol_or_link
        parts[name] = read
      end
      built = klass <= Range ? klass.new(parts[:begin], parts[:end], parts[:excl]) : @objects[here]
      parts.each { |name, value| set_part(built, name, value) } unless klass <= Range
      @objects[here] = built
    end

    # A name without an `@` is one of the parts ruby keeps of its own.
    def set_part(built, name, value)
      case name
      when :mesg then Primitive.zr_exc_set_message(built, value)
      when :bt then built.set_backtrace(value) unless value.nil?
      when :errno then Primitive.zr_hidden_set(built, :__errno__, value)
      when :bt_locations then nil
      else built.instance_variable_set(name, value)
      end
    end

    def user_dump
      klass = constant(symbol_or_link.to_s, Class)
      keep(klass._load(text))
    end

    def user_marshal
      klass = constant(symbol_or_link.to_s, Class)
      built = keep(Primitive.zr_class_allocate(klass))
      built.send(:marshal_load, read)
      built
    end

    def symbol_or_link
      tag = byte.chr
      return @symbols.fetch(long) if tag == ";"
      return new_symbol(text) if tag == ":"

      raise ArgumentError, "dump format error for symbol(0x#{tag.ord.to_s(16)})"
    end

    def new_symbol(name)
      sym = name.to_sym
      @symbols << sym
      sym
    end

    def constant(path, kind)
      value = Object.const_get(path)
      raise ArgumentError, "#{path} does not refer to #{kind == Class ? "class" : "module"}" unless value.is_a?(kind)

      value
    rescue NameError
      raise ArgumentError, "undefined #{kind == Class ? "class" : "module"} #{path}"
    end

    def keep(value)
      @objects << value
      value
    end

    def byte
      raise ArgumentError, "marshal data too short" if @pos >= @bytes.bytesize

      b = @bytes.getbyte(@pos)
      @pos += 1
      b
    end

    def text
      size = long
      out = @bytes.byteslice(@pos, size)
      raise ArgumentError, "marshal data too short" if out.nil? || out.bytesize < size

      @pos += size
      out.dup.force_encoding(Encoding::BINARY)
    end

    def long
      head = byte
      head -= 256 if head > 127
      return 0 if head == 0
      return head - 5 if head > 4
      return head + 5 if head < -4

      value = head > 0 ? 0 : -1
      count = head.abs
      count.times do |i|
        value &= ~(0xff << (8 * i))
        value |= byte << (8 * i)
      end
      value
    end

    def bignum
      sign = byte.chr
      words = long
      value = 0
      words.times { |i| value |= (byte | (byte << 8)) << (16 * i) }
      sign == "-" ? -value : value
    end

    def float(name)
      case name
      when "inf" then Float::INFINITY
      when "-inf" then -Float::INFINITY
      when "nan" then Float::NAN
      else name.split("\0").first.to_f
      end
    end
  end
end
