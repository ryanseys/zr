# frozen_string_literal: true

# Struct: `Struct.new` makes a class whose instances hold one value
# per member. The members sit in a hidden instance variable of the
# class and the values in one of the instance, as CRuby keeps them, so
# neither shows in `instance_variables`.
class Struct
  include Enumerable
  Primitive.zr_undef_alloc(self)

  class << self
    def new(*members, keyword_init: nil, &body)
      name = class_name(members.shift) unless members.empty? || members.first.is_a?(Symbol)
      members = members.map { |m| member_name(m) }
      dup = members.find { |m| members.count(m) > 1 }
      raise ArgumentError, "duplicate member: #{dup}" if dup

      klass = Class.new(self)
      Primitive.zr_define_alloc(klass)
      # The members come first, where the kernel looks first
      # (zr_struct_row).
      Primitive.zr_hidden_set(klass, :__members__, members.freeze)
      Primitive.zr_hidden_set(klass, :__keyword_init__, keyword_init)
      Struct.const_set(name, klass) if name
      klass.define_singleton_method(:new, Class.instance_method(:new))
      klass.define_singleton_method(:[], Class.instance_method(:new))
      klass.define_singleton_method(:members) { Primitive.zr_struct_members(self).dup }
      klass.define_singleton_method(:keyword_init?) { Primitive.zr_struct_keyword_init(self) }
      klass.define_singleton_method(:inspect) { keyword_init? ? "#{self}(keyword_init: true)" : to_s }
      # The accessors are entries of the kernel's (runtime/kernel/struct.rb).
      Primitive.zr_struct_readers(klass, members)
      Primitive.zr_struct_writers(klass, members)
      klass.class_eval(&body) if body
      klass
    end

    # A member that inspects as a bare name: letters, digits and
    # underscores, not starting with a digit.
    def plain_member?(name)
      text = name.to_s
      return false if text.empty? || text.getbyte(0) >= 48 && text.getbyte(0) <= 57

      text.each_byte.all? { |b| (b >= 48 && b <= 57) || (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || b == 95 }
    end

    private :plain_member?

    private

    # The first argument when it is not a member: nil, or a String
    # that is the name of a constant under Struct.
    def class_name(arg)
      return nil if arg.nil?
      raise TypeError, "no implicit conversion of #{conversion_name(arg)} into String" unless arg.is_a?(String)
      raise NameError, "identifier #{arg} needs to be constant" unless arg.getbyte(0).between?(65, 90)

      arg
    end

    def member_name(m)
      return m if m.is_a?(Symbol)
      return m.to_sym if m.is_a?(String)

      raise TypeError, "#{m.inspect} is not a symbol nor a string"
    end
  end

  # The values come from the kernel (zr_struct_values), which makes them
  # for an allocated struct at the first read, so a member returns nil
  # before any initialize runs.
  #
  # `initialize` is an entry of the kernel's (runtime/kernel/struct.rb,
  # zr_struct_initialize). It makes the values of a call by position
  # itself, and sends all other calls here.
  Primitive.zr_struct_builtins(self)

  # Sizes come from the kernel: a program that patches Array#size or
  # Hash#empty? cannot reach inside the constructor, as it cannot in
  # CRuby's C. `members`, and not the class's, which returns a copy:
  # nothing here changes the entry, and rb_struct_initialize also reads
  # the class's own. The values bind by index rather than by each_with_index, which
  # would cost an Array and a Proc per call.
  def initialize_members(*args, **keywords)
    Primitive.attr! :hidden
    members = member_names
    count = Primitive.zr_ary_len_m(members)
    values = Array.new(count)
    Primitive.zr_hidden_set(self, :__values__, values)
    keyword_init = Primitive.zr_struct_keyword_init(Primitive.zr_real_class(self))
    given = Primitive.zr_ary_len_m(args)
    # Keywords are a value by position when keyword_init says so, and
    # when it says nothing but values came by position too.
    if (keyword_init == false || (keyword_init.nil? && given > 0)) && Primitive.zr_hash_len_m(keywords) > 0
      args << keywords
      keywords = {}
      given += 1
    end
    if keyword_init || (given == 0 && Primitive.zr_hash_len_m(keywords) > 0)
      raise ArgumentError, "wrong number of arguments (given #{given}, expected 0)" unless given == 0

      unknown = keywords.keys - members
      raise ArgumentError, "unknown keywords: #{unknown.join(', ')}" if Primitive.zr_ary_len_m(unknown) > 0

      keywords.each { |k, v| values[members.index(k)] = v }
    else
      raise ArgumentError, +"struct size differs" if given > count

      i = 0
      while i < given
        values[i] = Primitive.zr_ary_at_m(args, i)
        i += 1
      end
    end
  end

  private :initialize_members

  # `initialize_copy` is an entry of the kernel's too
  # (zr_struct_initialize_copy), which sends all but a copy from a struct
  # of the same class here.
  def initialize_copy_members(other)
    Primitive.attr! :hidden
    Kernel.instance_method(:initialize_copy).bind_call(self, other)
    Primitive.zr_hidden_set(self, :__values__, Primitive.zr_struct_values(other).dup)
    self
  end
  private :initialize_copy_members

  # A member may be named `class`, so the class comes from the kernel.
  def members = member_names.dup

  # The names as the class stores them, which rb_struct_members reads: a
  # subclass's own `members`, instance or class, is not called.
  def member_names
    Primitive.attr! :hidden
    Primitive.zr_struct_members(Primitive.zr_real_class(self))
  end
  private :member_names

  # `to_a`, `deconstruct` and `values` are entries of the kernel's
  # (zr_struct_to_a).

  def size = Primitive.zr_ary_len_m(member_names)
  alias length size

  def [](key)
    Primitive.zr_struct_values(self)[member_index(key)]
  end

  def []=(key, value)
    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_struct_values(self)[member_index(key)] = value
  end

  def each(&block)
    return to_enum(:each) { size } unless block

    Primitive.zr_struct_values(self).each(&block)
    self
  end

  def each_pair
    return to_enum(:each_pair) { size } unless block_given?

    values = Primitive.zr_struct_values(self)
    names = member_names
    names.each_index { |i| yield [names[i], values[i]] }
    self
  end

  def to_h(&block)
    pairs = member_names.zip(Primitive.zr_struct_values(self))
    block ? pairs.to_h(&block) : pairs.to_h
  end

  def deconstruct_keys(keys)
    return to_h if keys.nil?
    raise TypeError, "wrong argument type #{keys.class} (expected Array or nil)" unless keys.is_a?(Array)
    names = member_names
    return {} if keys.size > names.size

    values = Primitive.zr_struct_values(self)
    out = {}
    keys.each do |k|
      i = k.is_a?(Symbol) ? names.index(k) : nil
      break unless i

      out[k] = values[i]
    end
    out
  end

  # rb_get_values_at with struct_entry: a Range reads as Array's does, and
  # an index outside the members raises.
  def values_at(*indexes)
    values = Primitive.zr_struct_values(self)
    size = Primitive.zr_ary_len_m(values)
    out = []
    indexes.each do |i|
      if i.is_a?(Range)
        out.concat(values.values_at(i))
        next
      end
      n = Primitive.zr_index_operand_m(i)
      raise IndexError, "offset #{n} too small for struct(size:#{size})" if n < -size
      raise IndexError, "offset #{n} too large for struct(size:#{size})" if n >= size

      out << values[n]
    end
    out
  end

  def dig(key, *rest)
    # A member this struct does not hold is a miss, not an error, which
    # is what makes `dig` safe to chain.
    v = if key.is_a?(Integer) then at_or_nil(key)
        elsif (i = member_names.index(key.to_sym)) then Primitive.zr_struct_values(self)[i]
        end
    return v if rest.empty? || v.nil?

    Primitive.zr_dig_into(v, rest)
  end

  def select(*args, &block)
    raise ArgumentError, "wrong number of arguments (given #{args.size}, expected 0)" unless args.empty?
    return to_enum(:select) { size } unless block

    Primitive.zr_struct_values(self).select(&block)
  end
  alias filter select

  def ==(other)
    return true if equal?(other)
    return false unless Primitive.zr_real_class(other) == Primitive.zr_real_class(self)

    Primitive.zr_struct_values(self) == Primitive.zr_struct_values(other)
  end

  def eql?(other)
    return true if equal?(other)
    return false unless Primitive.zr_real_class(other) == Primitive.zr_real_class(self)

    Primitive.zr_struct_values(self).eql?(Primitive.zr_struct_values(other))
  end

  def hash = [Primitive.zr_real_class(self), Primitive.zr_struct_values(self)].hash

  # The class shows by its path, as rb_struct_inspect writes it: always
  # in the marker of a struct reached again inside its own inspect, and
  # otherwise only when it is a name, not a #<Class:0x...>.
  def inspect
    path = Primitive.zr_class_path(Primitive.zr_real_class(self))
    return Primitive.zr_obj_form("#<struct #{path}:...>") if Primitive.zr_recursive_enter(self, :inspect)

    name = path unless path.start_with?("#")
    head = name ? "#<struct #{name}" : +"#<struct"

    begin
      pairs = member_names.zip(Primitive.zr_struct_values(self)).map { |m, v| "#{Struct.send(:plain_member?, m) ? m : m.inspect}=#{v.inspect}" }
      Primitive.zr_obj_form(pairs.empty? && name ? "#{head}>" : "#{head} #{pairs.join(', ')}>")
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end
  alias to_s inspect

  private

  # The index a member name or position names, or the error CRuby
  # raises for one that is out of range.
  # The value at `index`, counted from the end when negative, or nil
  # where the struct is shorter.
  def at_or_nil(index)
    Primitive.attr! :hidden
    count = Primitive.zr_ary_len_m(member_names)
    index += count if index.negative?
    index.between?(0, count - 1) ? Primitive.zr_struct_values(self)[index] : nil
  end
  private :at_or_nil

  def member_index(key)
    Primitive.attr! :hidden
    members = member_names
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
