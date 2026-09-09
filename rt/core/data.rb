# Data: `Data.define` makes a class of immutable values, one per member,
# made with keywords or positionally. Members live in a hidden variable
# of the class and values in one of the instance, as Struct's do.
class Data
  class << self
    undef_method :new

    def define(*members, &body)
      members = members.map do |m|
        name = m.is_a?(String) ? m.to_sym : m
        raise TypeError, "#{m.inspect} is not a symbol nor a string" unless name.is_a?(Symbol)
        raise ArgumentError, "invalid data member: #{name}" if name.end_with?("=")

        name
      end
      dup = members.find { |m| members.count(m) > 1 }
      raise ArgumentError, "duplicate member: #{dup}" if dup

      klass = Class.new(self)
      Primitive.zr_hidden_set(klass, :__members__, members.freeze)
      Primitive.zr_data_constructors(klass)
      klass.define_singleton_method(:members) do
        k = self
        k = k.superclass until Primitive.zr_hidden_get(k, :__members__)
        Primitive.zr_hidden_get(k, :__members__).dup
      end
      klass.define_singleton_method(:inspect) { to_s }
      members.each_with_index do |member, i|
        klass.define_method(member) { Primitive.zr_hidden_get(self, :__values__)[i] }
      end
      klass.class_eval(&body) if body
      klass
    end

  end


  def initialize(**kwargs)
    members = self.class.members
    missing = members - kwargs.keys
    unless missing.empty?
      raise ArgumentError, "missing keyword#{missing.size > 1 ? 's' : ''}: #{missing.map(&:inspect).join(', ')}"
    end
    unknown = kwargs.keys - members
    unless unknown.empty?
      raise ArgumentError, "unknown keyword#{unknown.size > 1 ? 's' : ''}: #{unknown.map(&:inspect).join(', ')}"
    end

    Primitive.zr_hidden_set(self, :__values__, members.map { |m| kwargs[m] }.freeze)
    freeze
  end

  def members = self.class.members

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

  def deconstruct = Primitive.zr_hidden_get(self, :__values__).dup

  def with(**kwargs)
    return self if kwargs.empty?

    self.class.new(**to_h.merge(kwargs))
  end

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
    head = name ? "#<data #{name}" : "#<data"
    return "#{head}:...>" if Primitive.zr_recursive_enter(self, :inspect)

    begin
      pairs = members.zip(Primitive.zr_hidden_get(self, :__values__)).map { |m, v| "#{m}=#{v.inspect}" }
      pairs.empty? ? "#{head}>" : "#{head} #{pairs.join(', ')}>"
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end
  alias to_s inspect
end
