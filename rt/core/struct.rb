# Struct: `Struct.new` makes a class whose instances hold one value
# per member. The members sit in a hidden instance variable of the
# class and the values in one of the instance, as CRuby keeps them, so
# neither shows in `instance_variables`.
class Struct
  include Enumerable

  class << self
    def new(*members, keyword_init: nil, &body)
      name = class_name(members.shift) unless members.empty? || members.first.is_a?(Symbol)
      members = members.map { |m| member_name(m) }
      dup = members.find { |m| members.count(m) > 1 }
      raise ArgumentError, "duplicate member: #{dup}" if dup

      klass = Class.new(self)
      Struct.const_set(name, klass) if name
      Primitive.zr_hidden_set(klass, :__members__, members.freeze)
      Primitive.zr_hidden_set(klass, :__keyword_init__, keyword_init)
      klass.define_singleton_method(:new, Class.instance_method(:new))
      klass.define_singleton_method(:[], Class.instance_method(:new))
      klass.define_singleton_method(:members) do
        k = self
        k = k.superclass until Primitive.zr_hidden_get(k, :__members__)
        Primitive.zr_hidden_get(k, :__members__).dup
      end
      klass.define_singleton_method(:keyword_init?) do
        k = self
        k = k.superclass until Primitive.zr_hidden_get(k, :__members__)
        Primitive.zr_hidden_get(k, :__keyword_init__)
      end
      klass.define_singleton_method(:inspect) { to_s }
      members.each_with_index do |member, i|
        klass.define_method(member) { Primitive.zr_hidden_get(self, :__values__)[i] }
        klass.define_method(:"#{member}=") do |value|
          Primitive.zr_frozen_error(self) if frozen?
          Primitive.zr_hidden_get(self, :__values__)[i] = value
        end
      end
      klass.class_eval(&body) if body
      klass
    end

    private

    # The first argument when it is not a member: nil, or a String
    # that names a constant under Struct.
    def class_name(arg)
      return nil if arg.nil?
      raise TypeError, "no implicit conversion of #{arg.class} into String" unless arg.is_a?(String)
      raise NameError, "identifier #{arg} needs to be constant" unless arg.getbyte(0).between?(65, 90)

      arg
    end

    def member_name(m)
      return m if m.is_a?(Symbol)
      return m.to_sym if m.is_a?(String)

      raise TypeError, "#{m.inspect} is not a symbol nor a string"
    end
  end

  def initialize(*args, **keywords)
    members = self.class.members
    values = Array.new(members.size)
    Primitive.zr_hidden_set(self, :__values__, values)
    keyword_init = self.class.keyword_init?
    if keyword_init == false && !keywords.empty?
      args << keywords
      keywords = {}
    end
    if keyword_init || (args.empty? && !keywords.empty?)
      raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0)" unless args.empty?

      unknown = keywords.keys - members
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" unless unknown.empty?

      keywords.each { |k, v| values[members.index(k)] = v }
    else
      raise ArgumentError, "struct size differs" if args.size > members.size

      args.each_with_index { |v, i| values[i] = v }
    end
  end

  def initialize_copy(other)
    super
    Primitive.zr_hidden_set(self, :__values__, Primitive.zr_hidden_get(other, :__values__).dup)
  end

  def members = self.class.members

  def to_a = Primitive.zr_hidden_get(self, :__values__).dup
  alias deconstruct to_a
  alias values to_a

  def size = members.size
  alias length size

  def [](key)
    Primitive.zr_hidden_get(self, :__values__)[member_index(key)]
  end

  def []=(key, value)
    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hidden_get(self, :__values__)[member_index(key)] = value
  end

  def each(&block)
    return to_enum(:each) { size } unless block

    Primitive.zr_hidden_get(self, :__values__).each(&block)
    self
  end

  def each_pair
    return to_enum(:each_pair) { size } unless block_given?

    values = Primitive.zr_hidden_get(self, :__values__)
    members.each_with_index { |m, i| yield m, values[i] }
    self
  end

  def to_h(&block)
    pairs = members.zip(Primitive.zr_hidden_get(self, :__values__))
    block ? pairs.to_h(&block) : pairs.to_h
  end

  def deconstruct_keys(keys)
    return to_h if keys.nil?
    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.is_a?(Array)
    return {} if keys.size > members.size

    values = Primitive.zr_hidden_get(self, :__values__)
    out = {}
    keys.each do |k|
      i = k.is_a?(Symbol) ? members.index(k) : nil
      break unless i

      out[k] = values[i]
    end
    out
  end

  def values_at(*indexes) = to_a.values_at(*indexes)

  def dig(key, *rest)
    v = self[key]
    rest.empty? || v.nil? ? v : v.dig(*rest)
  end

  def select(&block)
    return to_enum(:select) { size } unless block

    to_a.select(&block)
  end
  alias filter select

  def ==(other)
    return true if equal?(other)
    return false unless other.class == self.class

    Primitive.zr_hidden_get(self, :__values__) == Primitive.zr_hidden_get(other, :__values__)
  end

  def eql?(other)
    return true if equal?(other)
    return false unless other.class == self.class

    Primitive.zr_hidden_get(self, :__values__).eql?(Primitive.zr_hidden_get(other, :__values__))
  end

  def hash = [self.class, Primitive.zr_hidden_get(self, :__values__)].hash

  def inspect
    name = self.class.name
    head = name ? "#<struct #{name}" : "#<struct"
    return "#{head}:...>" if Primitive.zr_recursive_enter(self, :inspect)

    begin
      pairs = members.zip(Primitive.zr_hidden_get(self, :__values__)).map { |m, v| "#{plain_member?(m) ? m : m.inspect}=#{v.inspect}" }
      "#{head} #{pairs.join(', ')}>"
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end
  alias to_s inspect

  private

  # A member that inspects as a bare name: letters, digits and
  # underscores, not starting with a digit.
  def plain_member?(name)
    text = name.to_s
    return false if text.empty? || text.getbyte(0) >= 48 && text.getbyte(0) <= 57

    text.each_byte.all? { |b| (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 }
  end

  # The index a member name or position names, or the error CRuby
  # raises for one that is out of range.
  def member_index(key)
    members = self.members
    case key
    when Symbol, String
      i = members.index(key.to_sym)
      raise NameError.new("no member '#{key}' in struct", key.to_sym) unless i

      i
    else
      i = Integer(key)
      raise IndexError, "offset #{i} too small for struct(size:#{members.size})" if i < -members.size
      raise IndexError, "offset #{i} too large for struct(size:#{members.size})" if i >= members.size

      i % members.size
    end
  end
end
