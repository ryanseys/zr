# ObjectSpace: the weak maps and the finalizers; walking the heap is
# refused by name.
module ObjectSpace
  # Keys and values held weakly, compared by identity.
  class WeakMap
    include Enumerable

    def initialize
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
    def initialize
      @table = Primitive.zr_weak_table_new_m(2, false)
    end

    def [](key) = @table[key]

    def []=(key, value)
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
    raise ArgumentError, "tried to create Proc object without a block" if callable.nil?
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

  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true) = Primitive.zr_gc_start

  def each_object(mod = nil) = Primitive.zr_unimplemented("ObjectSpace.each_object")
  def count_objects(result = {}) = Primitive.zr_unimplemented("ObjectSpace.count_objects")
  def _id2ref(id) = Primitive.zr_unimplemented("ObjectSpace._id2ref")
end
