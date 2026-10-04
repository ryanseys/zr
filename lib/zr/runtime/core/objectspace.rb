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
      raise LocalJumpError, +"no block given" unless block

      @table.each(&block)
      self
    end
    alias each_pair each

    def each_key(&block)
      raise LocalJumpError, +"no block given" unless block

      @table.each_key(&block)
      self
    end

    def each_value(&block)
      raise LocalJumpError, +"no block given" unless block

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

  # CRuby's type names for the heap's type tags. This runtime gives a
  # separate tag to some objects that CRuby keeps as an object's own
  # type (an exception, a Proc), and the census counts them under CRuby's name.
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
    by_type.each_index { |tag| counts[TYPE_NAMES.fetch(tag, :T_OBJECT)] += by_type[tag] if by_type[tag].positive? }
    result.clear
    result[:TOTAL] = total
    result[:FREE] = free
    CENSUS_ORDER.each { |name| result[name] = counts[name] if counts.key?(name) }
    result
  end

  # id2ref: an id that is a special constant's own word gives that
  # constant; any other names a cell. With more than one ractor, only a
  # shareable object comes back.
  def _id2ref(id)
    id = to_integer(id)
    # NUM2PTR: an id of eight bytes or fewer must fit a pointer.
    raise RangeError, "bignum out of range of unsigned long" if id < -(2**63) && id > -(2**64)

    found = id.between?(-(2**63), (2**64) - 1) ? immediate_of(id) : false
    if found.equal?(false)
      found = Primitive.zr_objspace_id2ref(id)
      raise RangeError, "#{id} is #{id >= Primitive.zr_objspace_next_id ? 'not an id value' : 'a recycled object'}" if found.nil?
    else
      found = found.first
    end
    if Ractor.send(:multi?) && !Ractor.shareable?(found)
      raise RangeError, "#{id} is the id of an unshareable object on multi-ractor"
    end

    found
  end

  # The constant whose word `id` is, in a one-item Array, or false for a
  # word that names a cell.
  def immediate_of(id)
    Primitive.attr! :hidden
    word = id & ((2**64) - 1)
    return [SPECIAL_IDS[word]] if SPECIAL_IDS.key?(word)
    return [(word >= 2**63 ? word - (2**64) : word) >> 1] if word.odd?

    high = word >> 32
    low = word & 0xFFFF_FFFF
    return [Primitive.zr_objspace_word_value(high, low)] if (word & 3) == 2
    if (word & 0xFF) == 0x0C
      raise RangeError, "0x#{format('%016x', word)} is not a symbol id value" unless Primitive.zr_objspace_symbol_word_p(high, low)

      return [Primitive.zr_objspace_word_value(high, low)]
    end
    raise RangeError, "#{id} is not an id value" unless (word & 7).zero?

    false
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
