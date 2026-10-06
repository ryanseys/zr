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
    # marshal_dump: a port must write, and is put in binmode first.
    unless io.nil?
      raise TypeError, +"instance of IO needed" unless io.respond_to?(:write)

      io.binmode if io.respond_to?(:binmode)
    end
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
    # of a copy (lib/zr/runtime/kernel/marshal.rb), and gives a document it does
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

  # The classes whose objects CRuby keeps as T_DATA: a task, a lock, a
  # descriptor, compiled code or C state. Only a `_dump_data` writes one
  # (`d`), and only a `_load_data` reads one.
  DATA_KINDS = %w[ARGF.class Proc Method UnboundMethod Binding Enumerator Fiber Dir Ractor StringIO Thread Thread::Mutex
                  Thread::Queue Thread::SizedQueue Thread::ConditionVariable Time Random Encoding::Converter
                  ObjectSpace::WeakMap ObjectSpace::WeakKeyMap].freeze
  private_constant :DATA_KINDS

  # Whether CRuby keeps the objects of `klass` as T_DATA.
  def self.data_kind?(klass)
    klass.ancestors.any? { |kind| Primitive.zr_table_member_p(DATA_KINDS, MODULE_NAME.bind_call(kind)) }
  end

  # Module#name, as CRuby's class2path reads a class's name: a `name`
  # that the program wrote for a class does not change what is dumped.
  MODULE_NAME = Module.instance_method(:name)
  private_constant :MODULE_NAME

  FREEZE = Kernel.instance_method(:freeze)
  private_constant :FREEZE

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

  private_class_method :long_bytes, :read_long_bytes, :extras_of, :extra_set, :data_kind?

  # The tags, by the character each one writes.
  class Writer
    def initialize(limit)
      @limit = limit
      @out = +"".b
      @objects = {}.compare_by_identity
      @symbols = {}
      @encodings = {}
      @count = 0
      # The objects whose `_dump` is still being written.
      @dumping = {}.compare_by_identity
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


      data = data?(obj)
      remember(obj)
      data ? data_dump(obj, limit) : body(obj, limit)
    end

    # Whether `obj` is written as T_DATA, which takes a `_dump_data`. An
    # IO and a MatchData have no form on the wire at all.
    def data?(obj)
      raise TypeError, "can't dump #{Primitive.zr_real_class(obj)}" if IO === obj || MatchData === obj
      return false unless Marshal.send(:data_kind?, Primitive.zr_real_class(obj))
      return true if obj.respond_to?(:_dump_data, true)

      raise TypeError, "no _dump_data is defined for class #{Primitive.zr_real_class(obj)}"
    end

    # w_object's T_DATA: the extended modules, `d`, the class, then what
    # `_dump_data` returns.
    def data_dump(obj, limit)
      payload = obj.__send__(:_dump_data)
      extended(obj)
      @out << "d" << symbol_bytes(class_path(Primitive.zr_real_class(obj)).to_sym)
      write(payload, limit)
    end

    def body(obj, limit)
      return set(obj, limit) if Set === obj

      ivars = ivars_of(obj)
      wrapped = !ivars.empty? && !plain_object?(obj)
      @out << "I" if wrapped
      extended(obj)
      # A String, Regexp, Array or Hash writes by its builtin type, which an
      # instance of a copy of one of them (`String.clone`) keeps.
      builtin = Primitive.zr_builtin_class_m(obj)
      if builtin.equal?(String) then uclass(obj, String) << '"' << bytes(obj)
      elsif builtin.equal?(Regexp) then uclass(obj, Regexp) << "/" << bytes(obj.source) << (obj.options & 0xff).chr
      elsif builtin.equal?(Array) then array(obj, limit)
      elsif builtin.equal?(Hash) then hash(obj, limit)
      else typed_body(obj, ivars, limit)
      end
      write_ivars(ivars, limit) if wrapped
    end

    def typed_body(obj, ivars, limit)
      case obj
      when Class then @out << "c" << bytes(class_path(obj))
      when Module then @out << "m" << bytes(class_path(obj))
      when Float then @out << "f" << bytes(float_text(obj))
      when Integer then @out << "l" << bignum(obj)
      when Range then object_body(class_path(Primitive.zr_real_class(obj)), range_parts(obj), limit)
      when Exception then object_body(class_path(Primitive.zr_real_class(obj)), exception_parts(obj), limit)
      when Struct, Data then struct(obj, limit)
      else object_body(class_path(Primitive.zr_real_class(obj)), ivars, limit)
      end
    end

    # A Set writes as the pure-Ruby Set of Ruby 3 did: an object whose
    # @hash contains its members, which set.c's compat dumper is in place
    # of. Its own instance variables wrap that.
    def set(obj, limit)
      ivars = ivars_of(obj)
      @out << "I" unless ivars.empty?
      extended(obj)
      object_body(class_path(Primitive.zr_real_class(obj)), [[:@hash, obj.send(:marshal_hash)]], limit)
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
      parts.concat(exception.send(:marshal_parts))
      parts << [:cause, exception.cause] if Primitive.zr_exc_cause_set_p(exception)
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
      members = Primitive.zr_real_class(obj).members
      values = Data === obj ? obj.send(:values_store) : members.map { |name| obj[name] }
      @out << "S" << symbol_bytes(class_path(Primitive.zr_real_class(obj)).to_sym) << long(members.size)
      members.each_index do |i|
        @out << symbol_bytes(members[i])
        write(values[i], limit)
      end
    end

    # w_object's T_ARRAY: an element whose dump changes the Array's size
    # stops the dump.
    def array(obj, limit)
      size = obj.size
      uclass(obj, Array) << "[" << long(size)
      obj.each do |item|
        write(item, limit)
        raise RuntimeError, +"array modified during dump" unless obj.size == size
      end
    end

    def hash(obj, limit)
      raise TypeError, "can't dump hash with default proc" if obj.default_proc

      default = obj.default
      uclass(obj, Hash)
      # An identity hash names Hash itself as its user class, as w_object
      # marks it.
      @out << "C" << symbol_bytes(:Hash) if obj.compare_by_identity?
      @out << (default.nil? ? "{" : "}") << long(obj.size)
      obj.each_pair do |key, value|
        write(key, limit)
        write(value, limit)
      end
      write(default, limit) unless default.nil?
    end

    # `C` gives the subclass of a String, Array, Hash or Regexp.
    def uclass(obj, base)
      @out << "C" << symbol_bytes(class_path(Primitive.zr_real_class(obj)).to_sym) if Primitive.zr_real_class(obj) != base
      @out
    end

    # `e` gives each module that only the object was extended with.
    # The modules an object was extended with, as w_extended walks them:
    # those between its singleton class and its class, never one that the
    # class itself includes. An object with no singleton class has none,
    # and the walk does not make one.
    def extended(obj)
      return if Numeric === obj || Module === obj

      own = Primitive.zr_class_of(obj)
      return unless own.singleton_class?
      # w_extended: a singleton class with methods or instance variables
      # of its own has no form on the wire.
      raise TypeError, "singleton can't be dumped" unless (own.instance_methods(false) + own.private_instance_methods(false)).empty? && own.instance_variables.empty?

      real = Primitive.zr_real_class(obj)
      held = real.ancestors
      chain = own.ancestors.take_while { |mod| !held.include?(mod) }
      chain.each do |mod|
        # A singleton class with prepended modules writes the object's
        # class after them, where its origin is in the chain.
        if mod.equal?(own)
          @out << "e" << symbol_bytes(class_path(real).to_sym) unless chain.first.equal?(own)
          next
        end
        next unless mod.instance_of?(Module)
        # A module with no name cannot be named on the wire, and w_extended
        # says "class" wherever it says this.
        name = MODULE_NAME.bind_call(mod)
        raise TypeError, "can't dump anonymous class #{mod.inspect}" if name.nil?

        @out << "e" << symbol_bytes(name.to_sym)
      end
    end

    def user_marshal(obj, limit)
      remember(obj)
      value = obj.send(:marshal_dump)
      # A value of the same class would dump itself again without end.
      klass = Primitive.zr_real_class(obj)
      raise RuntimeError, "#{klass}#marshal_dump returned same class instance" if Primitive.zr_real_class(value).equal?(klass)

      @out << "U" << symbol_bytes(class_path(Primitive.zr_real_class(obj)).to_sym)
      write(value, limit)
    end

    # The object is remembered only after its instance variables, so one
    # that holds itself would be dumped again without end.
    def user_dump(obj, limit)
      raise RuntimeError, +"can't dump recursive object using _dump()" if @dumping.key?(obj)

      @dumping[obj] = true
      text = obj.send(:_dump, limit)
      raise TypeError, +"_dump() must return string" unless text.is_a?(String)
      ivars = ivars_of(text) + Marshal.send(:extras_of, text)
      @out << "I" unless ivars.empty?
      @out << "u" << symbol_bytes(class_path(Primitive.zr_real_class(obj)).to_sym) << bytes(text)
      write_ivars(ivars, limit) unless ivars.empty?
      remember(obj)
    ensure
      @dumping.delete(obj)
    end

    def remember(obj)
      @objects[obj] = @count
      @count += 1
      obj
    end

    # What an object has next to its parts: its instance variables, and
    # for a String, a Regexp or a Symbol the name of its encoding.
    def ivars_of(obj)
      # A class or module is written by its name alone, with the name's
      # encoding when it is not ASCII.
      if Module === obj
        path = class_path(obj)
        return path.ascii_only? ? [] : encoding_ivar(path.encoding)
      end

      names = obj.respond_to?(:instance_variables) ? obj.instance_variables : []
      parts = names.map { |name| [name, obj.instance_variable_get(name)] }
      builtin = Primitive.zr_builtin_class_m(obj)
      return encoding_ivar(obj.encoding) + parts if builtin.equal?(String) || builtin.equal?(Regexp)
      # w_ivar: a Hash that a ruby2_keywords method took writes the flag K.
      return [[:K, true]] + parts if builtin.equal?(Hash) && Hash.ruby2_keywords_hash?(obj)

      parts
    end

    # An encoding writes only its name, and the name takes a link slot of
    # its own, so a second string in the same encoding writes it once.
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

    # w_encoding and w_ivar: the encoding (`E`) and the ruby2_keywords flag
    # (`K`) are one level deeper than the depth limit allows for the value
    # they belong to.
    def write_ivars(ivars, limit)
      @out << long(ivars.size)
      ivars.each do |name, value|
        @out << symbol_bytes(name)
        if value.is_a?(Encoding) then encoding_name(value.name)
        elsif name == :E || name == :K then write(value, limit.negative? ? limit : limit + 1)
        else write(value, limit)
        end
      end
    end

    # A plain object writes its ivars as the object body, so the wrapper
    # must not write them twice. A Range writes its own parts there, and
    # its ivars in the wrapper.
    def plain_object?(obj)
      return false if Class === obj || Module === obj || Struct === obj || Data === obj || Range === obj

      Primitive.zr_builtin_class_m(obj).nil? && !(Float === obj || Integer === obj)
    end

    def class_path(mod)
      raise TypeError, "singleton class can't be dumped" if mod.singleton_class?

      # The class's own name: a `name` that the program wrote does not count.
      name = MODULE_NAME.bind_call(mod)
      # must_not_be_anonymous: a temporary name starts with `#`.
      raise TypeError, "can't dump anonymous #{mod.is_a?(Class) ? "class" : "module"} #{name || mod.inspect}" if name.nil? || name.start_with?("#")

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

      if text.encoding == Encoding::UTF_8 || text.encoding == Encoding::US_ASCII
        return +"I".b << ":" << bytes(text) << long(1) << symbol_bytes(:E) << (text.encoding == Encoding::UTF_8 ? "T" : "F")
      end

      # w_encoding: any other encoding is named by a String, which takes an
      # object's place in the links.
      head = +"I".b << ":" << bytes(text) << long(1) << symbol_bytes(:encoding)
      @count += 1
      head << "\"" << bytes(text.encoding.name.b)
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
      (n < 0 ? "-" : "+") + long(words.size) + words.pack("v*")
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

    # The bytes, or a stream to take them from. A stream gives only the
    # bytes that one value needs, so the next value starts where this one
    # stopped.
    def initialize(source, handler, freeze)
      @io = source.respond_to?(:read) ? source : nil
      # rb_marshal_load_with_proc: a port is put in binmode first.
      @io.__send__(:binmode) if @io.respond_to?(:binmode, true)
      @bytes = @io ? +"".b : Primitive.zr_str_operand(source)
      @pos = 0
      @handler = handler
      @freeze = freeze
      # The values that the proc saw whole, for a link to one of them.
      @whole = {}.compare_by_identity
      @partial = {}.compare_by_identity
      @objects = []
      @symbols = []
      # How many more bytes the counts read so far promise, which a stream
      # may read ahead (arg->readable).
      @readable = 0
      # The class or module that each name resolved to: a tree of a
      # thousand nodes refers to its few classes a thousand times.
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
      # r_symlink: a symbol named again is no new value, so neither the
      # proc nor the freeze sees it.
      need(1)
      if @bytes.getbyte(@pos) == SYMLINK
        @pos += 1
        return @symbols.fetch(long)
      end
      # r_object's TYPE_LINK: an object already read takes no freeze, and
      # the proc sees it only once it is whole.
      if @bytes.getbyte(@pos) == LINK
        @pos += 1
        value = link
        return @handler && @whole.key?(value) ? @handler.call(value) : value
      end
      leave(read_value)
    end

    # r_leave: with freeze, a String is the interned one, so equal Strings
    # are one object, and any other value freezes without a `freeze` that
    # the program wrote.
    def leave(value)
      if @freeze && !value.is_a?(Module)
        # rb_fstring: only a bare String, with no ivars and no singleton
        # class, is interned; any other is frozen in place.
        if value.instance_of?(String) && value.instance_variables.empty? && !Primitive.zr_class_of(value).singleton_class?
          # A link to the String reads the interned one too.
          interned = -value
          at = @objects.rindex { |o| o.equal?(value) }
          @objects[at] = interned if at
          value = interned
        else
          FREEZE.bind_call(value)
        end
      end
      @whole[value] = true if @handler && !@partial.key?(value)
      # r_post_proc: what the proc returns takes the place of the value.
      @handler ? @handler.call(value) : value
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
      elsif tag == LINK then link
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
      elsif tag == MODULE then keep(constant(text, Module))
      # The old `M` takes a class or a module (rb_path_to_class).
      elsif tag == MODULE_OLD then keep(namespace(text))
      elsif tag == DATA then data
      else raise ArgumentError, "dump format error(0x#{tag.to_s(16)})"
      end
    end

    # `I` marks the ivars that follow the object they belong to, so the
    # object must be built before they can be read.
    def with_ivars
      need(1)
      tag = @bytes.getbyte(@pos)
      return deferred(tag) if tag == REGEXP || tag == USRDEF
      return encoded_symbol if tag == SYMBOL
      return named_module(tag) if tag == CLASS || tag == MODULE || tag == MODULE_OLD

      value = read_value
      each_ivar(value) { |name, item| apply_ivar(value, name, item) }
      value
    end

    # `c`, `m` or `M` with ivars: the first may give the encoding of the
    # name (r_encname); a class or a module takes no other.
    def named_module(tag)
      @pos += 1
      path = text
      n = long
      if n > 0
        name = symbol_or_link
        item = read
        if name == :E || name == :encoding
          apply_ivar(path, name, item)
          n -= 1
        end
      end
      found = tag == MODULE_OLD ? namespace(path) : constant(path, tag == CLASS ? Class : Module)
      if n > 0
        kind = { CLASS => "class", MODULE => "module", MODULE_OLD => "class/module" }.fetch(tag)
        raise TypeError, "can't override instance variable of #{kind} '#{path}'"
      end
      keep(found)
    end

    # r_object's TYPE_LINK: an object whose record is still being read (a
    # regexp before its ivars) has no value to link to yet.
    def link
      value = @objects.fetch(long) { raise ArgumentError, +"dump format error (unlinked)" }
      raise ArgumentError, +"dump format error (bad link)" if value.equal?(self)

      value
    end

    # A regexp and a `_dump` payload need their encoding before they can be
    # built, so both read their own bytes, then their own ivars. A regexp
    # takes its place in the links first (r_prepare); what `_load` builds
    # takes the next place after the ivars (r_entry).
    def deferred(tag)
      @pos += 1
      here = @objects.size
      # The reader itself holds a regexp's place until it is built.
      @objects << self if tag == REGEXP
      klass = tag == USRDEF ? loader(constant(symbol_or_link, Class)) : nil
      payload = text
      options = tag == REGEXP ? byte : nil
      encoded = false
      each_ivar do |name, item|
        encoded ||= name == :E || name == :encoding
        apply_ivar(payload, name, item)
      end
      built = tag == REGEXP ? Regexp.new(encoded ? payload : old_escapes(payload), options) : loaded(klass, payload)
      # A Regexp takes the ivars that were dumped with it.
      payload.instance_variables.each { |name| built.instance_variable_set(name, payload.instance_variable_get(name)) } if tag == REGEXP
      return keep(built) unless tag == REGEXP

      @objects[here] = built
      built
    end

    # `_load`, then the loader that ruby registers next to it: an
    # Encoding's `_load` returns its name, which the load turns into the encoding.
    def loaded(klass, payload)
      built = klass.send(:_load, payload)
      klass == Encoding ? Encoding.find(built) : built
    end

    # A class whose `_load` reads a `u` record.
    def loader(klass)
      raise TypeError, "class #{klass.name} needs to have method '_load'" unless klass.respond_to?(:_load, true)

      klass
    end

    # The ivars a record lists: each name and its value, as they come. A
    # class or a module takes none (r_ivar).
    def each_ivar(owner = nil)
      n = long
      if n > 0 && owner.is_a?(Module)
        kind = owner.is_a?(Class) ? "class" : "module"
        raise TypeError, "can't override instance variable of #{kind} '#{MODULE_NAME.bind_call(owner)}'"
      end
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
      # The flag that a ruby2_keywords method set on the Hash it took.
      when :K
        raise ArgumentError, "ruby2_keywords flag is given but #{value.inspect} is not a Hash" unless value.is_a?(Hash)

        Primitive.zr_ruby2_hash_mark(value)
      # A name with no `@` is one the C API set on the payload itself,
      # which only a `_load` reads: Time writes its zone this way.
      else name.to_s.getbyte(0) == 0x40 ? value.instance_variable_set(name, item) : Marshal.send(:extra_set, value, name, item)
      end
    end

    # `e`: a module that the next value was extended with, or the value's
    # own class, which w_extended writes after the modules prepended to
    # its singleton class. The modules of one value come one after the
    # other, so they pass down to the next `e`.
    def extended(modules = [])
      path = symbol_or_link
      found = namespace(path.to_s)
      if found.is_a?(Class)
        value = read_value
        klass = Primitive.zr_class_of(value)
        raise ArgumentError, "prepended class #{path} differs from class #{klass.name}" unless klass.equal?(found)

        single = value.singleton_class
        single.prepend(modules.pop) until modules.empty?
        return value
      end
      raise ArgumentError, "#{path} does not refer to module" unless found.instance_of?(Module)

      modules << found
      need(1)
      value = if @bytes.getbyte(@pos) == EXTENDED
        @pos += 1
        extended(modules)
      else
        read_value
      end
      value.extend(modules.pop) until modules.empty?
      value
    end

    def subclass
      klass = constant(symbol_or_link, Class)
      # r_object_for: Hash as its own user class marks an identity hash.
      if klass == Hash
        need(1)
        tag = @bytes.getbyte(@pos)
        if tag == HASH || tag == HASH_DEF
          @pos += 1
          return hash(Hash, tag == HASH_DEF, identity: true)
        end
      end
      value = read_value
      built = Primitive.zr_class_allocate(klass)
      # The user class must make a value of the same type as the record.
      base = [String, Array, Hash, Regexp].find { |type| value.is_a?(type) }
      raise ArgumentError, "dump format error (user class)" unless base && Primitive.zr_builtin_class_m(built).equal?(base)

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

    # A regexp with no ivars has no encoding of its own.
    def regexp
      source = text
      Regexp.new(old_escapes(source), byte)
    end

    # The escapes that ruby 1.8 did not have.
    OLD_ESCAPES = "ghijklmopquyEFHIJKLNOPQRSTUVXY"

    # r_object's TYPE_REGEXP, for 1.8 compatibility: a pattern dumped with
    # no encoding drops the backslash of an escape that 1.8 did not have,
    # so `\u` reads as `u`. An escaped backslash stays.
    def old_escapes(source)
      out = source.byteslice(0, 0)
      backslashes = 0
      source.each_char do |char|
        if char == "\\"
          backslashes += 1
        else
          out.chop! if backslashes.odd? && OLD_ESCAPES.include?(char)
          backslashes = 0
        end
        out << char
      end
      out
    end

    # A count of values, which no record writes negative.
    def length
      n = long
      raise ArgumentError, +"negative length" if n.negative?

      n
    end

    def array(klass)
      size = length
      out = keep(klass == Array ? [] : Primitive.zr_class_allocate(klass))
      @readable += size - 1
      size.times do
        out << read
        @readable -= 1
      end
      @readable += 1
      out
    end

    def hash(klass, defaulted, identity: false)
      size = length
      out = keep(klass == Hash ? {} : Primitive.zr_class_allocate(klass))
      out.compare_by_identity if identity
      @readable += (size - 1) * 2
      size.times do
        key = read
        out[key] = read
        @readable -= 2
      end
      @readable += 2
      out.default = read if defaulted
      out
    end

    # r_object's TYPE_STRUCT: the class must make a Struct, a Data value or
    # a Range, whose members are the record's, in the same order. The
    # values are kept as they come, without the member writers.
    def struct
      # r_prepare: the link slot comes before the class's name.
      here = @objects.size
      @objects << self
      klass = constant(symbol_or_link, Class)
      size = length
      built = Primitive.zr_class_allocate(klass)
      members = struct_members(klass)
      raise TypeError, "class #{klass.name} not a struct" if members.nil?
      raise TypeError, "struct #{klass.name} not compatible (struct size differs)" unless members.size == size

      @objects[here] = built
      values = Array.new(size)
      Primitive.zr_hidden_set(built, :__values__, values) unless klass <= Range
      @readable += (size - 1) * 2
      members.each_with_index do |member, i|
        slot = symbol_or_link
        raise TypeError, "struct #{klass.name} not compatible (:#{slot} for :#{member})" unless slot == member

        values[i] = read
        @readable -= 2
      end
      @readable += 2
      if klass <= Range
        Range.instance_method(:initialize).bind_call(built, *values)
      elsif klass <= Data
        # A Data value is frozen, as `new` leaves it.
        values.freeze
        built.freeze
      end
      built
    end

    # The members of a class that CRuby keeps as T_STRUCT, or nil.
    def struct_members(klass)
      return %i[begin end excl] if klass <= Range
      return nil unless klass <= Struct || klass <= Data

      klass.members
    end

    # A plain object takes each ivar as it is read, which is the order
    # in which ruby sets them. A Range or a Set is built from its parts
    # after all of them are read.
    def object
      # r_prepare: the object's link slot comes before its class's name,
      # whose encoding may take a slot of its own.
      here = @objects.size
      @objects << self
      klass = constant(symbol_or_link, Class)
      # r_object: an `o` must allocate a plain object, not a core kind.
      raise ArgumentError, "dump format error" if [IO, String, Array, Hash, Regexp, Struct, Proc, Method, Thread, MatchData].any? { |kind| klass <= kind }

      built = Primitive.zr_class_allocate(klass)
      @objects[here] = built
      n = long
      # An old Complex or Rational dump is an object with two ivars, which
      # the compat loaders read: @real and @image (nucomp_loader), and
      # @numerator and @denominator (nurat_loader).
      if klass <= Range || klass <= Set || klass <= Complex || klass <= Rational
        parts = {}
        while n > 0
          name = symbol_or_link
          parts[name] = read
          n -= 1
        end
        # range_loader: the bounds are set on the object already linked,
        # without the subclass's initialize.
        if klass <= Range
          Range.instance_method(:initialize).bind_call(built, parts[:begin], parts[:end], parts[:excl])
        elsif klass <= Complex
          built.send(:marshal_load, [parts[:@real], parts[:@image]])
        elsif klass <= Rational
          built.send(:marshal_load, [parts[:@numerator], parts[:@denominator]])
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
      when :cause then cause!(built, value)
      else
        if name.to_s.getbyte(0) == 0x40 then built.instance_variable_set(name, value)
        elsif built.is_a?(Exception) then built.send(:marshal_part_set, name, value)
        end
      end
    end

    # A loaded cause that leads back to the exception, itself included,
    # is refused, as rb_exc_check_circular_cause refuses it.
    def cause!(built, cause)
      Primitive.zr_exc_cause_set(built, cause)
      seen = {}.compare_by_identity
      link = cause
      while link.is_a?(Exception)
        raise ArgumentError, "circular causes" if link.equal?(built) || seen.key?(link)

        seen[link] = true
        link = link.cause
      end
    end

    # What `_load` or `marshal_load` builds with no ivars around it stays
    # partial, as r_leave leaves it: a link to it does not call the proc.
    def user_dump
      klass = loader(constant(symbol_or_link, Class))
      built = keep(loaded(klass, text))
      @partial[built] = true
      built
    end

    # r_object's TYPE_USRMARSHAL: after marshal_load, the object takes the
    # ivars of its data that it did not set itself (r_copy_ivar).
    def user_marshal
      klass = constant(symbol_or_link, Class)
      built = keep(Primitive.zr_class_allocate(klass))
      # rb_marshal_define_compat: Complex and Rational load through a
      # loader that reflection does not show.
      unless built.respond_to?(:marshal_load, true) || built.is_a?(Complex) || built.is_a?(Rational)
        raise TypeError, "instance of #{klass.name} needs to have method 'marshal_load'"
      end

      data = read
      built.send(:marshal_load, data)
      data.instance_variables.each do |name|
        built.instance_variable_set(name, data.instance_variable_get(name)) unless built.instance_variable_defined?(name)
      end
      @partial[built] = true
      built
    end

    # `d`, what `_dump_data` writes for a T_DATA object. marshal.c
    # allocates the class, refuses one that is not T_DATA, takes the link
    # slot, and gives the payload to `_load_data`.
    def data
      name = symbol_or_link
      klass = constant(name, Class)
      built = Primitive.zr_class_allocate(klass)
      raise ArgumentError, +"dump format error" unless Marshal.send(:data_kind?, Primitive.zr_real_class(built))

      keep(built)
      raise TypeError, "class #{name} needs to have instance method '_load_data'" unless built.respond_to?(:_load_data, true)

      built.__send__(:_load_data, read)
      built
    end

    def symbol_or_link
      tag = byte
      return @symbols.fetch(long) if tag == SYMLINK
      return new_symbol(text) if tag == SYMBOL
      # r_symbol: an encoded name comes with its ivars.
      need(1) if tag == IVARS
      if tag == IVARS && @bytes.getbyte(@pos) == SYMBOL
        return encoded_symbol
      end

      raise ArgumentError, "dump format error for symbol(0x#{tag.to_s(16)})"
    end

    # A symbol's name takes its encoding before it is interned, since a
    # Symbol is its bytes and their encoding. Its link slot comes first,
    # as r_symreal keeps it.
    def encoded_symbol
      @pos += 1
      here = @symbols.size
      name = text
      # The name takes its link slot before its ivars, which may name it.
      @symbols << name.to_sym
      each_ivar { |key, item| apply_ivar(name, key, item) if key == :E || key == :encoding }
      raise ArgumentError, "invalid byte sequence in #{name.encoding}: #{name.inspect}" unless name.valid_encoding?

      @symbols[here] = name.to_sym
    end

    def new_symbol(name)
      sym = name.to_sym
      @symbols << sym
      sym
    end

    # The class or module that `path` gives, a String or a Symbol. A name
    # that was looked up before returns the same result, kind included.
    # A module (`m`, `e`) is a Module that is not a Class, as path2module
    # requires.
    def constant(path, kind)
      found = @constants[path]
      return found if found && module_kind?(found, kind)

      value = namespace(path.to_s)
      raise ArgumentError, "#{path} does not refer to #{kind == Class ? "class" : "module"}" unless module_kind?(value, kind)

      @constants[path] = value
    end

    def module_kind?(value, kind) = kind == Module ? value.instance_of?(Module) : value.is_a?(kind)

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

    # `count` more bytes available, when a stream can still give them.
    # A stream gives one byte with getbyte while the counts read so far
    # promise no more (r_byte), and else reads as many as they promise,
    # so it never reads past the value.
    def need(count)
      return if @io.nil? || @pos + count <= @bytes.bytesize

      missing = @pos + count - @bytes.bytesize
      if missing == 1 && @readable <= 0 && @io.respond_to?(:getbyte)
        b = @io.getbyte
        @bytes << b.chr if b
      else
        more = @io.read([missing, @readable].max)
        @bytes << more.b if more
      end
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
      words = length
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
