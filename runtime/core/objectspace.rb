# frozen_string_literal: true

# ObjectSpace: the weak maps, the finalizers, and the walk over the heap.
module ObjectSpace
  # Keys and values held weakly, compared by identity.
  class WeakMap
    include Enumerable

    def self.allocate
      Primitive.attr! :hidden
      map = Primitive.zr_class_allocate(self)
      map.send(:initialize)
      map
    end

    def initialize
      Primitive.attr! :hidden
      @table = Primitive.zr_weak_table_new_m(1, true)
    end

    def [](key) = @table[key]

    def []=(key, value)
      @table[key] = value
    end

    def key?(key) = @table.key?(key)
    alias include? key?
    alias member? key?

    def size = @table.size
    alias length size

    def keys = @table.keys
    def values = @table.values

    def delete(key)
      return @table.delete(key) if @table.key?(key)

      block_given? ? yield(key) : nil
    end

    def each(&block)
      @table.each(&block)
      self
    end
    alias each_pair each

    def each_key(&block)
      @table.each_key(&block)
      self
    end

    def each_value(&block)
      @table.each_value(&block)
      self
    end

    def inspect
      head = Primitive.zr_obj_head(self)
      return "#{head}>" if @table.empty?

      "#{head}: #{@table.map { |k, v| "#{WeakMap.show(k)} => #{WeakMap.show(v)}" }.join(', ')}>"
    end

    # A special value by `inspect`, an object by its address form.
    def self.show(value)
      Primitive.attr! :hidden
      Primitive.zr_special_p_m(value) ? value.inspect : Primitive.zr_any_to_s(value)
    end
  end

  # Keys held weakly and compared by `eql?`; values held.
  class WeakKeyMap
    # A value the collector never reclaims cannot be a weak key: the
    # immediates, and the numbers and symbols that live as long as the
    # program does.
    UNCOLLECTABLE = [Integer, Float, Symbol, NilClass, TrueClass, FalseClass].freeze
    private_constant :UNCOLLECTABLE

    def initialize
      Primitive.attr! :hidden
      @table = Primitive.zr_weak_table_new_m(2, false)
    end

    def [](key) = @table[key]

    def []=(key, value)
      raise ArgumentError, +"WeakKeyMap keys must be garbage collectable" if UNCOLLECTABLE.any? { |kind| key.is_a?(kind) }

      @table[key] = value
    end

    def key?(key) = @table.key?(key)

    def getkey(key)
      @table.each_key { |k| return k if k.eql?(key) }
      nil
    end

    def delete(key)
      return @table.delete(key) if @table.key?(key)

      block_given? ? yield(key) : nil
    end

    def clear
      @table.clear
      self
    end

    def inspect = "#{Primitive.zr_obj_head(self)} size=#{@table.size}>"
  end

  module_function

  # The proc runs with the object's id once the object is collected,
  # or when the program ends.
  def define_finalizer(obj, callable = nil, &block)
    callable ||= block
    raise ArgumentError, +"tried to create Proc object without a block" if callable.nil?
    raise ArgumentError, "wrong type argument #{callable.class} (should be callable)" unless callable.respond_to?(:call)
    raise ArgumentError, "cannot define finalizer for #{obj.class}" if Primitive.zr_special_p_m(obj)

    Primitive.zr_frozen_error(obj) if obj.frozen?
    table = Primitive.zr_finalizers_m
    row = table[obj]
    if row.nil?
      row = [obj.object_id]
      table[obj] = row
    end
    row << callable
    [0, callable]
  end

  def undefine_finalizer(obj)
    Primitive.zr_finalizers_m.delete(obj)
    obj
  end

  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true)
    Primitive.attr! :ruby
    Primitive.zr_gc_start
  end

  def each_object(mod = nil)
    return to_enum(:each_object, mod) unless block_given?
    raise TypeError, +"class or module required" unless mod.nil? || mod.is_a?(Module)

    objects = Primitive.zr_objspace_objects(mod)
    objects.each { |object| yield object }
    objects.size
  end

  # CRuby's type names for the heap's type tags. What CRuby keeps as an
  # object's own type -- an exception, a Proc -- this runtime tags apart,
  # and the census counts it under CRuby's name.
  TYPE_NAMES = {
    1 => :T_OBJECT, 2 => :T_CLASS, 3 => :T_MODULE, 4 => :T_FLOAT, 5 => :T_STRING, 31 => :T_REGEXP,
    7 => :T_ARRAY, 8 => :T_HASH, 24 => :T_OBJECT, 27 => :T_DATA, 29 => :T_DATA, 30 => :T_DATA,
    25 => :T_IMEMO, 26 => :T_IMEMO, 28 => :T_ICLASS
  }.freeze
  CENSUS_ORDER = %i[T_OBJECT T_CLASS T_MODULE T_FLOAT T_STRING T_REGEXP T_ARRAY T_HASH T_DATA T_IMEMO T_ICLASS].freeze
  # The ids of false, nil and true.
  SPECIAL_IDS = { 0 => false, 4 => nil, 20 => true }.freeze
  private_constant :TYPE_NAMES, :CENSUS_ORDER, :SPECIAL_IDS

  def count_objects(result = {})
    raise TypeError, +"non-hash given" unless result.is_a?(Hash)

    total, free, *by_type = Primitive.zr_objspace_census
    counts = Hash.new(0)
    by_type.each_with_index { |n, tag| counts[TYPE_NAMES.fetch(tag, :T_OBJECT)] += n if n.positive? }
    result.clear
    result[:TOTAL] = total
    result[:FREE] = free
    CENSUS_ORDER.each { |name| result[name] = counts[name] if counts.key?(name) }
    result
  end

  def _id2ref(id)
    id = implicit_integer(id)
    return id / 2 if id.odd?
    return SPECIAL_IDS[id] if SPECIAL_IDS.key?(id)

    found = Primitive.zr_objspace_id2ref(id)
    raise RangeError, "#{id.to_s.inspect} is not an id value" if found.nil?

    found
  end
end
