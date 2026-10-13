# frozen_string_literal: true

# ObjectSpace: the weak maps, the finalizers, and the walk over the heap.
module ObjectSpace
  # Keys and values kept weakly, compared by identity.
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

    # wmap_each and its kin yield with no enumerator: no block is a
    # LocalJumpError.
    def each(&block)
      raise LocalJumpError, +"no block given" unless block || @table.empty?
      return self unless block

      @table.each(&block)
      self
    end
    alias each_pair each

    def each_key(&block)
      raise LocalJumpError, +"no block given" unless block || @table.empty?
      return self unless block

      @table.each_key(&block)
      self
    end

    def each_value(&block)
      raise LocalJumpError, +"no block given" unless block || @table.empty?
      return self unless block

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

  # Keys kept weakly and compared by `eql?`; values kept strongly.
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
      # wkmap_aset hashes the key first (rb_any_hash, which a private hash
      # answers), which a BasicObject cannot.
      key.__send__(:hash)
      raise ArgumentError, +"WeakKeyMap keys must be garbage collectable" if UNCOLLECTABLE.any? { |kind| kind === key }

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
    raise ArgumentError, "wrong type argument #{callable.class} (should be callable)" unless callable.respond_to?(:call, true)
    raise ArgumentError, "cannot define finalizer for #{obj.class}" if Primitive.zr_special_p_m(obj)

    Primitive.zr_frozen_error(obj) if obj.frozen?
    # rb_callable_receiver: a finalizer that holds the object keeps it
    # alive, which ruby warns about.
    receiver = if Proc === callable then Primitive.zr_proc_self_m(callable)
               elsif Method === callable then callable.receiver
               end
    Primitive.zr_warn_here_m("finalizer references object to be finalized") if receiver.equal?(obj)
    table = Primitive.zr_finalizers_m
    row = table[obj]
    if row.nil?
      row = [obj.object_id]
      table[obj] = row
    end
    # A finalizer equal to one already defined is not added again, and
    # the call returns the one already there.
    i = 1
    while i < row.size
      return [0, row[i]] if row[i] == callable

      i += 1
    end
    row << callable
    [0, callable]
  end

  def undefine_finalizer(obj)
    Primitive.zr_frozen_error(obj) if obj.frozen?
    table = Primitive.zr_finalizers_m
    row = table.delete(obj)
    # A stream's Closer is the stream's own, not one that the program
    # defined, so it stays.
    closer = IO.const_get(:Closer, false)
    kept = row&.drop(1)&.select { |callable| closer === callable }
    table[obj] = [row.first, *kept] unless kept.nil? || kept.empty?
    obj
  end

  def garbage_collect(full_mark: true, immediate_mark: true, immediate_sweep: true)
    Primitive.attr! :ruby
    Primitive.zr_gc_start_m(full_mark, immediate_sweep)
    nil
  end

  def each_object(mod = nil)
    return to_enum(:each_object, mod) unless block_given?
    raise TypeError, +"class or module required" unless mod.nil? || mod.is_a?(Module)

    objects = Primitive.zr_objspace_objects(mod)
    objects.each { |object| yield object }
    objects.size
  end

  # The kernel fills the Hash and makes no object while it counts
  # (zr_objspace_count_into), as CRuby's C makes none.
  def count_objects(result = {})
    raise TypeError, +"non-hash given" unless result.is_a?(Hash)

    # Each key that it already has counts 0, as set_zero leaves it.
    result.each_key { |key| result[key] = 0 }
    Primitive.zr_objspace_count_into(result)
  end
end

# The core library's own helper classes, and every class under them,
# where ruby has C. No program sees them through ObjectSpace.
conceal = lambda do |mod|
  Primitive.zr_class_conceal_m(mod)
  mod.constants(false).each do |name|
    inner = mod.const_get(name, false)
    conceal.(inner) if inner.is_a?(Module) && inner.name&.start_with?("#{mod.name}::")
  end
end
[[Dir, :Glob], [File, :FnMatch], [Enumerator::Lazy, :Step], [Fiber, :Blocked], [Kernel, :Formatter],
 [Marshal, :Reader], [Marshal, :Writer], [Object, :Packing], [Process, :Redirects], [Regexp, :Onig],
 [Regexp, :Pattern]].each { |scope, name| conceal.(scope.const_get(name, false)) }
