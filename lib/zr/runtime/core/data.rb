# frozen_string_literal: true

# Data: `Data.define` makes a class of immutable values, one per member,
# made with keywords or positionally. Members live in a hidden variable
# of the class and values in one of the instance, as Struct's do.
class Data
  Primitive.zr_undef_alloc(self)

  class << self
    undef_method :new

    def define(*members, &body)
      members = members.map do |m|
        name = m.is_a?(String) ? m.to_sym : m
        raise TypeError, "#{m.inspect} is not a symbol nor a string" unless name.is_a?(Symbol)
        # rb_is_attrset_sym: a setter's name (`x=`), not an operator (`==`).
        raise ArgumentError, "invalid data member: #{name}" if name.end_with?("=") && Struct.send(:plain_member?, name.name.delete_suffix("="))

        name
      end
      dup = members.find { |m| members.count(m) > 1 }
      raise ArgumentError, "duplicate member: #{dup}" if dup

      klass = Class.new(self)
      Primitive.zr_define_alloc(klass)
      # setup_data: a defined class does not define again.
      klass.singleton_class.undef_method(:define)
      Primitive.zr_hidden_set(klass, :__members__, members.freeze)
      Primitive.zr_data_constructors(klass)
      klass.define_singleton_method(:members) { Primitive.zr_struct_members(self).dup }
      klass.define_singleton_method(:inspect) { to_s }
      Primitive.zr_struct_readers(klass, members)
      Primitive.zr_mod_eval_block(klass, body) if body
      klass
    end
  end


  # `initialize` is an entry of the kernel's (lib/zr/runtime/kernel/data.rb,
  # zr_data_initialize). It fills the values of a call that names each
  # member once, and sends all other calls here.
  Primitive.zr_data_builtins(self)

  # The values in the members' order, filled in one walk over them.
  # `missing` and `unknown` are built only when the call was wrong and the
  # message needs them, which is where rb_data_initialize_m builds its own.
  def initialize_members(**kwargs)
    Primitive.attr! :hidden
    members = member_names
    count = Primitive.zr_ary_len_m(members)
    values = Array.new(count)
    seen = Array.new(count, false)
    named = 0
    unknown = nil
    # rb_data_initialize_m: a String key names a member as its Symbol
    # does, and so does a key that converts with to_str; any other key is
    # a TypeError. Missing members raise before unknown keys.
    kwargs.each do |key, value|
      name = case key
             when Symbol then key
             when String then key.to_sym
             else (key = String.try_convert(key) || raise(TypeError, "#{key.inspect} is not a symbol nor a string")).to_sym
             end
      i = members.index(name)
      if i
        named += 1 unless seen[i]
        values[i] = value
        seen[i] = true
      else
        (unknown ||= []) << key
      end
    end
    if named < count
      missing = members.reject.with_index { |_, i| seen[i] }
      raise ArgumentError, "missing keyword#{Primitive.zr_ary_len_m(missing) > 1 ? 's' : ''}: #{missing.map(&:inspect).join(', ')}"
    end
    if unknown
      raise ArgumentError, "unknown keyword#{Primitive.zr_ary_len_m(unknown) > 1 ? 's' : ''}: #{unknown.map(&:inspect).join(', ')}"
    end

    Primitive.zr_hidden_set(self, :__values__, values.freeze)
    freeze
  end

  private :initialize_members

  # A copy stays frozen, whatever `clone` was told.
  def initialize_copy(other)
    super
    freeze
  end

  # A member may be named `class`, so the class comes from the kernel.
  def members = member_names.dup

  # The names as the class stores them, which rb_data_members reads: a
  # subclass's own `members`, instance or class, is not called.
  def member_names
    Primitive.attr! :hidden
    Primitive.zr_struct_members(Primitive.zr_real_class(self))
  end
  private :member_names

  # The values, one per member: nil for each until `initialize` runs, as
  # an allocated Data reads in CRuby.
  def values_store
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__values__) || Array.new(Primitive.zr_ary_len_m(member_names))
  end
  private :values_store

  def to_h(&block)
    pairs = member_names.zip(values_store)
    return pairs.to_h unless block

    # rb_hash_set_pair names a bad pair without its index.
    out = {}
    pairs.each do |k, v|
      pair = yield(k, v)
      a = Array.try_convert(pair) or raise TypeError, "wrong element type #{conversion_name(pair)} (expected array)"
      raise ArgumentError, "element has wrong array length (expected 2, was #{a.size})" unless a.size == 2

      out[a[0]] = a[1]
    end
    out
  end

  def deconstruct_keys(keys)
    return to_h if keys.nil?
    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.is_a?(Array)
    names = member_names
    return {} if keys.size > names.size

    values = values_store
    out = {}
    keys.each do |k|
      # A key that converts with to_str is its String (rb_data_deconstruct_keys).
      k = String.try_convert(k) || raise(TypeError, "#{k.inspect} is not a symbol nor a string") unless k.is_a?(Symbol) || k.is_a?(String)

      i = names.index(k.to_sym)
      break unless i

      out[k] = values[i]
    end
    out
  end

  def deconstruct = values_store.dup

  def with(**kwargs)
    return self if kwargs.empty?

    # rb_data_with: a new object of the class gets `initialize`, and the
    # class's own `new` is not called.
    copy = Primitive.zr_class_allocate(Primitive.zr_real_class(self))
    copy.send(:initialize, **to_h.merge(kwargs))
    copy
  end

  def ==(other)
    return true if equal?(other)
    return false unless Primitive.zr_real_class(other) == Primitive.zr_real_class(self)

    values_store == other.send(:values_store)
  end

  def eql?(other)
    return true if equal?(other)
    return false unless Primitive.zr_real_class(other) == Primitive.zr_real_class(self)

    values_store.eql?(other.send(:values_store))
  end

  def hash = [Primitive.zr_real_class(self), values_store].hash

  def inspect
    # rb_data_inspect: the class path, unless it is a temporary one;
    # the class's own `name` is not called.
    path = Primitive.zr_class_path(Primitive.zr_real_class(self))
    name = path unless path.start_with?("#")
    head = name ? "#<data #{name}" : +"#<data"
    # The marker of a recursion always names the class, as Struct's does.
    return Primitive.zr_obj_form("#<data #{path}:...>") if Primitive.zr_recursive_enter(self, :inspect)

    begin
      pairs = member_names.zip(values_store).map { |m, v| "#{Struct.send(:plain_member?, m) ? m.own_text : m.inspect}=#{v.inspect}" }
      Primitive.zr_obj_form(pairs.empty? ? "#{head}>" : "#{head} #{pairs.join(', ')}>")
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end
  alias to_s inspect
end
