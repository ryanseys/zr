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
    members = Primitive.zr_real_class(self).members
    missing = members - kwargs.keys
    if Primitive.zr_ary_len_m(missing) > 0
      raise ArgumentError, "missing keyword#{Primitive.zr_ary_len_m(missing) > 1 ? 's' : ''}: #{missing.map(&:inspect).join(', ')}"
    end
    unknown = kwargs.keys - members
    if Primitive.zr_ary_len_m(unknown) > 0
      raise ArgumentError, "unknown keyword#{Primitive.zr_ary_len_m(unknown) > 1 ? 's' : ''}: #{unknown.map(&:inspect).join(', ')}"
    end

    Primitive.zr_hidden_set(self, :__values__, members.map { |m| kwargs[m] }.freeze)
    freeze
  end

  # A copy stays frozen, whatever `clone` was asked.
  def initialize_copy(other)
    super
    freeze
  end

  # A member may be named `class`, so the class comes from the kernel.
  def members = Primitive.zr_real_class(self).members

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

    Primitive.zr_real_class(self).new(**to_h.merge(kwargs))
  end

  def ==(other)
    return true if equal?(other)
    return false unless Primitive.zr_real_class(other) == Primitive.zr_real_class(self)

    Primitive.zr_hidden_get(self, :__values__) == Primitive.zr_hidden_get(other, :__values__)
  end

  def eql?(other)
    return true if equal?(other)
    return false unless Primitive.zr_real_class(other) == Primitive.zr_real_class(self)

    Primitive.zr_hidden_get(self, :__values__).eql?(Primitive.zr_hidden_get(other, :__values__))
  end

  def hash = [Primitive.zr_real_class(self), Primitive.zr_hidden_get(self, :__values__)].hash

  def inspect
    name = Primitive.zr_real_class(self).name
    head = name ? "#<data #{name}" : "#<data"
    return "#{head}:...>" if Primitive.zr_recursive_enter(self, :inspect)

    begin
      pairs = members.zip(Primitive.zr_hidden_get(self, :__values__)).map { |m, v| "#{Struct.send(:plain_member?, m) ? m : m.inspect}=#{v.inspect}" }
      pairs.empty? && name ? "#{head}>" : "#{head} #{pairs.join(', ')}>"
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end
  alias to_s inspect
end
