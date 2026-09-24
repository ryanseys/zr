# frozen_string_literal: true

# The 4.8 wire format: a one-byte tag for each kind, a packed integer for
# every count, and two link tables so a graph that shares an object or a
# symbol writes it once.
module Marshal
  MAJOR_VERSION = 4
  MINOR_VERSION = 8

  def dump(obj, io = nil, limit = -1)
    io, limit = nil, io if io.is_a?(Integer)
    limit = -1 if limit.nil?
    out = Writer.new(limit).run(obj)
    return out if io.nil?

    io.write(out)
    io
  end
  module_function :dump

  # CRuby writes load in Ruby (its marshal.rb), so it returns its own
  # parameters, under CRuby's names.
  def self.load(source, proc = nil, freeze: false)
    Primitive.attr! :ruby
    # The kernel reads the kinds a dump is mostly made of at the speed
    # of a copy (runtime/kernel/marshal.rb), and gives a document it does
    # not read whole back to the reader below, which reads it from the
    # start.
    if proc.nil? && !freeze && source.instance_of?(String)
      value = Primitive.zr_marshal_load_fast(source)
      return value unless Primitive.zr_marshal_bailed_p
    end
    Reader.new(source, proc, freeze).run
  end

  class << self
    alias restore load
  end

  # Objects that contain a task, a lock, a descriptor or compiled code,
  # which no wire format can contain.
  UNDUMPABLE = %w[Proc Method UnboundMethod Binding Enumerator Fiber Dir MatchData Ractor StringIO
                  Thread Thread::Mutex Thread::Queue Thread::SizedQueue Thread::ConditionVariable].freeze
  private_constant :UNDUMPABLE

  # The packed integer: one byte for a small number, else a length byte
  # and the bytes of the number, least significant first. A `_dump` that
  # writes a count of its own uses the same spelling.
  def self.long_bytes(n)
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

  # The same, read back: the number and the bytes after it.
  def self.read_long_bytes(text)
    head = text.getbyte(0) or return [0, text]

    head -= 256 if head > 127
    return [0, text.byteslice(1..)] if head == 0
    return [head - 5, text.byteslice(1..)] if head > 4
    return [head + 5, text.byteslice(1..)] if head < -4

    count = head.abs
    value = head > 0 ? 0 : -1
    count.times do |i|
      value &= ~(0xff << (8 * i))
      value |= text.getbyte(1 + i).to_i << (8 * i)
    end
    [value, text.byteslice((1 + count)..)]
  end

  # What a `_dump` payload contains next to its bytes: the names that the
  # C API sets on the payload itself, with no `@` in front, which only the
  # `_load` of that class reads. Time writes its zone and offset this way.
  def self.extras_of(text) = Primitive.zr_hidden_get(text, :__extras__) || []

  def self.extra_set(text, name, value)
    Primitive.zr_hidden_set(text, :__extras__, extras_of(text) + [[name, value]])
    value
  end

  private_class_method :long_bytes, :read_long_bytes, :extras_of, :extra_set

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
      return set(obj, limit) if obj.is_a?(Set)

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

    # A Set writes as the pure-Ruby Set of Ruby 3 did: an object whose
    # @hash contains its members, which set.c's compat dumper is in place
    # of. Its own instance variables wrap that.
    def set(obj, limit)
      ivars = ivars_of(obj)
      @out << "I" unless ivars.empty?
      extended(obj)
      object_body(class_path(obj.class), [[:@hash, obj.send(:marshal_hash)]], limit)
      write_ivars(ivars, limit) unless ivars.empty?
    end

    # A Range writes the three parts ruby gives it, in ruby's order.
    def range_parts(range)
      [[:excl, range.exclude_end?], [:begin, range.begin], [:end, range.end]]
    end

    # Ruby keeps an exception's message, its backtrace and an errno next
    # to its instance variables, under names of its own.
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
      raise TypeError, "can't dump hash with default proc" if obj.default_proc

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

    # `e` gives each module that only the object was extended with.
    # The modules an object was extended with, as w_extended walks them:
    # those between its singleton class and its class, never one that the
    # class itself includes. An object with no singleton class has none,
    # and the walk does not make one.
    def extended(obj)
      return if obj.is_a?(Numeric) || obj.is_a?(Module)

      own = Primitive.zr_class_of(obj)
      return unless own.singleton_class?
      raise TypeError, "singleton can't be dumped" unless (own.instance_methods(false) + own.private_instance_methods(false)).empty?

      held = obj.class.ancestors
      own.ancestors.drop(1).take_while { |mod| !held.include?(mod) }.each do |mod|
        next unless mod.instance_of?(Module)
        # A module with no name cannot be named on the wire, and w_extended
        # says "class" wherever it says this.
        raise TypeError, "can't dump anonymous class #{mod.inspect}" if mod.name.nil?

        @out << "e" << symbol_bytes(mod.name.to_sym)
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
      ivars = ivars_of(text) + Marshal.send(:extras_of, text)
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

    # What an object has next to its parts: its instance variables, and
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
      # A binary name has no encoding to write, as w_symbol has it.
      return +":".b << bytes(text) if text.ascii_only? || text.encoding == Encoding::BINARY

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

    def long(n) = Marshal.send(:long_bytes, n)

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
    # The tags, as bytes: a tag is read once as a byte and compared as
    # one, since a tree of any size is a byte a value and a compare a
    # kind.
    NIL = 0x30       # "0"
    TRUE = 0x54      # "T"
    FALSE = 0x46     # "F"
    FIXNUM = 0x69    # "i"
    SYMBOL = 0x3a    # ":"
    SYMLINK = 0x3b   # ";"
    LINK = 0x40      # "@"
    IVARS = 0x49     # "I"
    EXTENDED = 0x65  # "e"
    BIGNUM = 0x6c    # "l"
    FLOAT = 0x66     # "f"
    STRING = 0x22    # '"'
    REGEXP = 0x2f    # "/"
    ARRAY = 0x5b     # "["
    HASH = 0x7b      # "{"
    HASH_DEF = 0x7d  # "}"
    CLASS = 0x63     # "c"
    MODULE = 0x6d    # "m"
    MODULE_OLD = 0x4d # "M"
    STRUCT = 0x53    # "S"
    OBJECT = 0x6f    # "o"
    UCLASS = 0x43    # "C"
    DATA = 0x64      # "d"
    USRDEF = 0x75    # "u"
    USRMARSHAL = 0x55 # "U"

    # The bytes, or a stream to take them from. A stream hands over only
    # the bytes one value asks for, so the value after it starts where
    # this one stopped.
    def initialize(source, handler, freeze)
      @io = source.respond_to?(:read) ? source : nil
      @bytes = @io ? +"".b : Primitive.zr_str_operand(source)
      @pos = 0
      @handler = handler
      @freeze = freeze
      @objects = []
      @symbols = []
      # The class or module each name resolved to: a tree of a thousand
      # nodes names its few classes a thousand times.
      @constants = {}
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

    # The kinds a tree dump is mostly made of come first: an object, a
    # symbol link, a small integer, nil, a string with its encoding.
    def read_value
      tag = byte
      if tag == OBJECT then object
      elsif tag == SYMLINK then @symbols.fetch(long)
      elsif tag == FIXNUM then long
      elsif tag == NIL then nil
      elsif tag == IVARS then with_ivars
      elsif tag == STRING then keep(text)
      elsif tag == ARRAY then array(Array)
      elsif tag == TRUE then true
      elsif tag == FALSE then false
      elsif tag == LINK then @objects.fetch(long)
      elsif tag == SYMBOL then new_symbol(text)
      elsif tag == HASH then hash(Hash, false)
      elsif tag == HASH_DEF then hash(Hash, true)
      elsif tag == FLOAT then keep(float(text))
      elsif tag == BIGNUM then keep(bignum)
      elsif tag == STRUCT then struct
      elsif tag == USRDEF then user_dump
      elsif tag == USRMARSHAL then user_marshal
      elsif tag == UCLASS then subclass
      elsif tag == EXTENDED then extended
      elsif tag == REGEXP then keep(regexp)
      elsif tag == CLASS then keep(constant(text, Class))
      elsif tag == MODULE || tag == MODULE_OLD then keep(constant(text, Module))
      elsif tag == DATA then data
      else raise ArgumentError, "dump format error(0x#{tag.to_s(16)})"
      end
    end

    # `I` names the ivars that follow the object they belong to, so the
    # object must be built before they can be read.
    def with_ivars
      need(1)
      tag = @bytes.getbyte(@pos)
      return deferred(tag) if tag == REGEXP || tag == USRDEF
      return encoded_symbol if tag == SYMBOL

      value = read_value
      each_ivar { |name, item| apply_ivar(value, name, item) }
      value
    end

    # A regexp and a `_dump` payload need their encoding before they can be
    # built, so both read their own bytes, then their own ivars.
    def deferred(tag)
      @pos += 1
      here = @objects.size
      @objects << nil
      klass = tag == USRDEF ? constant(symbol_or_link, Class) : nil
      payload = text
      options = tag == REGEXP ? byte : nil
      each_ivar { |name, item| apply_ivar(payload, name, item) }
      built = tag == REGEXP ? Regexp.new(payload, options) : loaded(klass, payload)
      @objects[here] = built
      built
    end

    # `_load`, then the loader ruby registers beside it: an Encoding's
    # `_load` hands back its name, which the load turns into the encoding.
    def loaded(klass, payload)
      built = klass.send(:_load, payload)
      klass == Encoding ? Encoding.find(built) : built
    end

    # The ivars a record lists: each name and its value, as they come.
    def each_ivar
      n = long
      while n > 0
        name = symbol_or_link
        yield name, read
        n -= 1
      end
    end

    def apply_ivar(value, name, item)
      case name
      # A Regexp keeps its encoding in the pattern it compiled, so only
      # a String takes one from a record.
      when :E then value.force_encoding(item ? Encoding::UTF_8 : Encoding::US_ASCII) if value.is_a?(String)
      when :encoding then value.force_encoding(item) if value.is_a?(String)
      # A name with no `@` is one the C API set on the payload itself,
      # which only a `_load` reads: Time writes its zone this way.
      else name.start_with?("@") ? value.instance_variable_set(name, item) : Marshal.send(:extra_set, value, name, item)
      end
    end

    def extended
      mod = constant(symbol_or_link, Module)
      value = read_value
      value.extend(mod)
      value
    end

    def subclass
      klass = constant(symbol_or_link, Class)
      value = read_value
      built = Primitive.zr_class_allocate(klass)
      case value
      when String then built.replace(value)
      when Array then built.replace(value)
      when Hash then built.replace(value)
      # A regexp husk takes the pattern from the record, never through the
      # subclass's own initialize, which CRuby does not call either.
      when Regexp then Regexp.send(:seat, built, value.source, value.options)
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
      klass = constant(symbol_or_link, Class)
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
        values.each { |member, value| built.__send__(:"#{member}=", value) }
      end
      @objects[here] = built
      built
    end

    # A plain object takes each ivar as it is read, which is the order
    # ruby sets them in; a Range or a Set is built from its parts once
    # they are all in hand.
    def object
      klass = constant(symbol_or_link, Class)
      here = @objects.size
      built = Primitive.zr_class_allocate(klass)
      @objects << built
      n = long
      if klass <= Range || klass <= Set
        parts = {}
        while n > 0
          name = symbol_or_link
          parts[name] = read
          n -= 1
        end
        if klass <= Range
          built = klass.new(parts[:begin], parts[:end], parts[:excl])
        else
          built.send(:marshal_load_hash, parts[:@hash])
        end
        @objects[here] = built
      else
        while n > 0
          name = symbol_or_link
          set_part(built, name, read)
          n -= 1
        end
      end
      built
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
      klass = constant(symbol_or_link, Class)
      keep(loaded(klass, text))
    end

    def user_marshal
      klass = constant(symbol_or_link, Class)
      built = keep(Primitive.zr_class_allocate(klass))
      built.send(:marshal_load, read)
      built
    end

    # `d`, what CRuby's `_dump_data` writes for a T_DATA object. The name
    # comes first, so an absent class raises the same error as for every
    # other tag. Then marshal.c allocates the class and refuses unless the
    # result is T_DATA.
    #
    # Only a C extension makes a T_DATA object, and this runtime has no C.
    # So that check refuses every `d` that a program can give this reader,
    # as ruby does with the same bytes: `_load_data` is unreachable in
    # both. The payload is left unread, as marshal.c leaves it.
    def data
      constant(symbol_or_link, Class)
      raise ArgumentError, "dump format error"
    end

    def symbol_or_link
      tag = byte
      return @symbols.fetch(long) if tag == SYMLINK
      return new_symbol(text) if tag == SYMBOL

      raise ArgumentError, "dump format error for symbol(0x#{tag.to_s(16)})"
    end

    # A symbol's name takes its encoding before it is interned, since a
    # Symbol is its bytes and their encoding. Its link slot comes first,
    # as r_symreal keeps it.
    def encoded_symbol
      @pos += 1
      here = @symbols.size
      @symbols << nil
      name = text
      each_ivar { |key, item| apply_ivar(name, key, item) }
      @symbols[here] = name.to_sym
    end

    def new_symbol(name)
      sym = name.to_sym
      @symbols << sym
      sym
    end

    # The class or module that `path` gives, a String or a Symbol. A name
    # that was looked up before returns the same result, kind included.
    def constant(path, kind)
      found = @constants[path]
      return found if found && found.is_a?(kind)

      value = namespace(path.to_s)
      raise ArgumentError, "#{path} does not refer to #{kind == Class ? "class" : "module"}" unless value.is_a?(kind)

      @constants[path] = value
    end

    # `rb_path_to_class` (variable.c): the path walked from Object one
    # component at a time. A component that names nothing stops with the
    # path as far as the walk read it, which takes in the separator the
    # walk had already stepped past -- so `Absent::Nested` is refused as
    # "Absent::" and `Outer::Nope` as the whole of itself. A component
    # that names something other than a class or a module is ruby's
    # TypeError, whatever kind the caller wanted.
    def namespace(path)
      raise ArgumentError, "can't retrieve anonymous class #{path.inspect}" if path.empty? || path.start_with?("#")

      found = Object
      read = 0
      while read < path.bytesize
        stop = path.index(":", read) || path.bytesize
        name = path.byteslice(read, stop - read)
        read = stop
        if read < path.bytesize
          undefined(path, read) unless path.byteslice(read, 2) == "::"
          read += 2
        end
        found = begin
          found.const_get(name, false)
        rescue NameError
          undefined(path, read)
        end
        raise TypeError, "#{path} does not refer to class/module" unless found.is_a?(Module)
      end
      found
    end

    def undefined(path, read)
      raise ArgumentError, "undefined class/module #{path.byteslice(0, read)}"
    end

    def keep(value)
      @objects << value
      value
    end

    # `count` more bytes in hand, where a stream can still give them.
    def need(count)
      return if @io.nil? || @pos + count <= @bytes.bytesize

      more = @io.read(@pos + count - @bytes.bytesize)
      @bytes << more.b if more
    end

    # A stream that runs out has reached its end; bytes that run out are
    # a dump that was cut short.
    def short!
      raise EOFError, "end of file reached" if @io

      raise ArgumentError, "marshal data too short"
    end

    def byte
      need(1) if @io
      b = @bytes.getbyte(@pos)
      short! if b.nil?
      @pos += 1
      b
    end

    def text
      size = long
      need(size)
      out = @bytes.byteslice(@pos, size)
      short! if out.nil? || out.bytesize < size

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

  private_constant :Reader, :Writer
end
