# set.c, in ruby: Ruby 4.0's core Set. Its table is a Hash from each
# member to true, in insertion order, kept in a hidden slot as the C
# struct keeps its set_table, so a program sees no instance variable on
# a Set. So is the iteration level: a Set that is being walked takes no
# new member, and a frozen one is walked without counting.
class Set
  include Enumerable

  def self.[](*items)
    set = allocate
    table = set.send(:table)
    items.each { |item| table[item] = true }
    set
  end

  def initialize(enum = nil, &block)
    raise RuntimeError, "cannot reinitialize set" if Primitive.zr_hidden_get(self, :__initialized__)

    Primitive.zr_state_set(self, :__initialized__, true)
    into = table
    return self if enum.nil?

    if enum.is_a?(Array)
      enum.each { |item| into[block ? yield(item) : item] = true }
    else
      enum.__send__(Set.send(:enum_method, enum)) { |item| into[block ? yield(item) : item] = true }
    end
    self
  end

  def initialize_copy(other)
    return self if equal?(other)
    raise RuntimeError, "cannot replace set during iteration" if iterating?
    raise TypeError, "wrong argument type #{Primitive.zr_class_name_of(other)} (expected set)" unless other.is_a?(Set)

    source = other.send(:table)
    copy = source.compare_by_identity? ? {}.compare_by_identity : {}
    source.each_key { |item| copy[item] = true }
    Primitive.zr_state_set(self, :__table__, copy)
    self
  end

  def &(other)
    result = self.class.allocate
    into = result.send(:table)
    if other.is_a?(Set)
      small, large = size < other.size ? [self, other] : [other, self]
      small.send(:walk) { |item| into[item] = true if large.send(:table).key?(item) }
    else
      other.__send__(Set.send(:enum_method, other)) { |item| into[item] = true if table.key?(item) }
    end
    result
  end
  alias intersection &

  def -(other) = dup.subtract(other)
  alias difference -

  def ^(other)
    result = dup
    source = other.is_a?(Set) ? other : Set.allocate.send(:merge_from, other)
    into = result.send(:table)
    source.send(:walk) { |item| into.key?(item) ? into.delete(item) : into[item] = true }
    result
  end

  def |(other) = dup.send(:merge_from, other)
  alias + |
  alias union |

  def <=>(other)
    return nil unless other.is_a?(Set)

    if size < other.size
      -1 if within?(other)
    elsif size > other.size
      1 if other.send(:within?, self)
    elsif within?(other)
      0
    end
  end

  def ==(other)
    return false unless other.is_a?(Set)
    return true if equal?(other)
    return false unless size == other.size
    return true if empty?
    return false unless compare_by_identity? == other.compare_by_identity?

    return true if Primitive.zr_recursive_enter_paired(self, other, :==)

    begin
      within?(other)
    ensure
      Primitive.zr_recursive_leave(self, :==)
    end
  end
  alias eql? ==

  def add(item)
    check_frozen
    if iterating?
      raise RuntimeError, "can't add a new item into set during iteration" unless table.key?(item)
    else
      table[item] = true
    end
    self
  end
  alias << add

  def add?(item)
    check_frozen
    if iterating?
      raise RuntimeError, "can't add a new item into set during iteration" unless table.key?(item)

      return nil
    end
    return nil if table.key?(item)

    table[item] = true
    self
  end

  def classify
    return enum_for(:classify) { size } unless block_given?

    groups = {}
    klass = self.class
    walk do |item|
      key = yield(item)
      (groups.key?(key) ? groups[key] : (groups[key] = klass.allocate)).add(item)
    end
    groups
  end

  def clear
    check_frozen
    return self if empty?

    iterating? ? walk { |item| table.delete(item) } : table.clear
    self
  end

  def collect!
    return enum_for(:collect!) { size } unless block_given?

    check_frozen
    result = self.class.allocate
    into = result.send(:table)
    walk { |item| into[yield(item)] = true }
    initialize_copy(result)
  end
  alias map! collect!

  def compare_by_identity
    return self if compare_by_identity?
    raise RuntimeError, "compare_by_identity during iteration" if iterating?

    rebuild({}.compare_by_identity)
  end

  def compare_by_identity? = table.compare_by_identity?

  def delete(item)
    check_frozen
    table.delete(item)
    self
  end

  def delete?(item)
    check_frozen
    return nil unless table.key?(item)

    table.delete(item)
    self
  end

  def delete_if
    return enum_for(:delete_if) { size } unless block_given?

    check_frozen
    walk { |item| table.delete(item) if yield(item) }
    self
  end

  def disjoint?(other) = !intersect?(other)

  # set_i_divide: the sets a two-argument relation joins, each pair
  # joined only when it holds both ways; the classes a one-argument
  # block names otherwise.
  def divide(&block)
    return enum_for(:divide) { size } unless block
    return Set.allocate.send(:merge_from, classify(&block).values) unless block.arity == 2

    items = to_a.freeze
    parents = (0...items.size).to_a
    (0...items.size - 1).each do |i|
      (i + 1...items.size).each do |j|
        unite(parents, i, j) if yield(items[i], items[j]) && yield(items[j], items[i])
      end
    end
    answer = Set.allocate
    parts = {}
    items.each_with_index do |item, i|
      root = root_of(parents, i)
      unless parts.key?(root)
        parts[root] = self.class.allocate
        answer.add(parts[root])
      end
      parts[root].add(item)
    end
    answer
  end

  def each(&block)
    return enum_for(:each) { size } unless block

    walk(&block)
    self
  end

  def empty? = table.empty?

  def flatten
    result = self.class.allocate
    flatten_into(result, self, {})
    result
  end

  def flatten!
    return nil unless any_set?

    check_frozen
    replace(flatten)
  end

  def hash
    sum = table.size
    walk { |item| sum ^= item.hash }
    sum
  end

  def include?(item) = table.key?(item)
  alias member? include?
  alias === include?

  def inspect
    name = Primitive.zr_class_path(Primitive.zr_class_of(self))
    return "#{name}[...]".encode(Encoding::US_ASCII) if Primitive.zr_recursive_enter(self, :inspect)

    begin
      text = +"#{name}["
      first = true
      walk do |item|
        text << ", " unless first
        first = false
        text << item.inspect
      end
      text << "]"
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end
  alias to_s inspect

  def intersect?(other)
    if other.is_a?(Set)
      small, large = size < other.size ? [self, other] : [other, self]
      small.send(:walk) { |item| return true if large.send(:table).key?(item) }
      false
    elsif other.is_a?(Enumerable)
      other.any?(self)
    else
      raise ArgumentError, "value must be enumerable"
    end
  end

  def join(separator = nil) = to_a.join(separator.nil? ? "" : separator)

  def keep_if
    return enum_for(:keep_if) { size } unless block_given?

    check_frozen
    walk { |item| table.delete(item) unless yield(item) }
    self
  end

  def merge(*sets, **kwargs)
    raise ArgumentError, "no keywords accepted" unless kwargs.empty?
    raise RuntimeError, "cannot add to set during iteration" if iterating?

    check_frozen
    sets.each { |other| merge_from(other) }
    self
  end

  def proper_subset?(other)
    other = set_arg(other)
    size < other.size && within?(other)
  end
  alias < proper_subset?

  def proper_superset?(other)
    other = set_arg(other)
    size > other.size && other.send(:within?, self)
  end
  alias > proper_superset?

  def reject!
    return enum_for(:reject!) { size } unless block_given?

    check_frozen
    before = size
    walk { |item| table.delete(item) if yield(item) }
    before == size ? nil : self
  end

  def replace(other)
    check_frozen
    return initialize_copy(other) if other.is_a?(Set)
    raise RuntimeError, "cannot replace set during iteration" if iterating?

    Set.send(:enum_method, other)
    table.clear
    merge_from(other)
  end

  def reset
    raise RuntimeError, "reset during iteration" if iterating?

    rebuild(compare_by_identity? ? {}.compare_by_identity : {})
  end

  def size = table.size
  alias length size

  def select!
    return enum_for(:select!) { size } unless block_given?

    check_frozen
    before = size
    walk { |item| table.delete(item) unless yield(item) }
    before == size ? nil : self
  end
  alias filter! select!

  def subset?(other)
    other = set_arg(other)
    size <= other.size && within?(other)
  end
  alias <= subset?

  def subtract(other)
    check_frozen
    if other.is_a?(Set)
      other.send(:walk) { |item| table.delete(item) }
    else
      other.__send__(Set.send(:enum_method, other)) do |item|
        check_frozen
        table.delete(item)
      end
    end
    self
  end

  def superset?(other)
    other = set_arg(other)
    size >= other.size && other.send(:within?, self)
  end
  alias >= superset?

  def to_a = table.keys

  def to_set(*args, &block)
    klass = Set
    if args.empty?
      args = [self]
    else
      Warning.warn("#{Primitive.zr_warn_position}warning: passing arguments to Set#to_set is deprecated\n", category: :deprecated) if Warning[:deprecated]
      klass = args[0]
      args[0] = self
    end
    return self if klass.equal?(Set) && instance_of?(Set) && args.size == 1 && block.nil?

    klass.new(*args, &block)
  end

  # Ruby 4.0 keeps this subclass, which takes no compatibility layer.
  class CoreSet < Set
  end

  # lib/set/subclass_compatible.rb: the layer a direct subclass takes,
  # which keeps a subclass written for the pure-Ruby Set of Ruby 3 at
  # home. set.c loads it when the first subclass is made, so until then
  # the constant is not there.
  compatible = Module.new do
    const_set(:ClassMethods, Module.new do
      def [](*ary)
        new(ary)
      end
    end)

    def initialize(enum = nil, &block) # :yields: o
      enum.nil? and return

      if block
        do_with_enum(enum) { |o| add(block[o]) }
      else
        merge(enum)
      end
    end

    def do_with_enum(enum, &block) # :nodoc:
      if enum.respond_to?(:each_entry)
        enum.each_entry(&block) if block
      elsif enum.respond_to?(:each)
        enum.each(&block) if block
      else
        raise ArgumentError, "value must be enumerable"
      end
    end
    private :do_with_enum

    def replace(enum)
      if enum.instance_of?(self.class)
        super
      else
        do_with_enum(enum)  # make sure enum is enumerable before calling clear
        clear
        merge(enum)
      end
    end

    def to_set(*args, &block)
      klass = if args.empty?
        Set
      else
        warn "passing arguments to Enumerable#to_set is deprecated", uplevel: 1
        args.shift
      end
      return self if instance_of?(Set) && klass == Set && block.nil? && args.empty?
      klass.new(self, *args, &block)
    end

    def flatten_merge(set, seen = {}) # :nodoc:
      set.each { |e|
        if e.is_a?(Set)
          case seen[e_id = e.object_id]
          when true
            raise ArgumentError, "tried to flatten recursive Set"
          when false
            next
          end

          seen[e_id] = true
          flatten_merge(e, seen)
          seen[e_id] = false
        else
          add(e)
        end
      }

      self
    end
    protected :flatten_merge

    def flatten
      self.class.new.flatten_merge(self)
    end

    def flatten!
      replace(flatten()) if any?(Set)
    end

    def superset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size >= set.size && set.all?(self)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias >= superset?

    def proper_superset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size > set.size && set.all?(self)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias > proper_superset?

    def subset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size <= set.size && all?(set)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias <= subset?

    def proper_subset?(set)
      case
      when set.instance_of?(self.class)
        super
      when set.is_a?(Set)
        size < set.size && all?(set)
      else
        raise ArgumentError, "value must be a set"
      end
    end
    alias < proper_subset?

    def <=>(set)
      return unless set.is_a?(Set)

      case size <=> set.size
      when -1 then -1 if proper_subset?(set)
      when +1 then +1 if proper_superset?(set)
      else 0 if self.==(set)
      end
    end

    def intersect?(set)
      case set
      when Set
        if size < set.size
          any?(set)
        else
          set.any?(self)
        end
      when Enumerable
        set.any?(self)
      else
        raise ArgumentError, "value must be enumerable"
      end
    end

    def disjoint?(set)
      !intersect?(set)
    end

    def add?(o)
      add(o) unless include?(o)
    end

    def delete?(o)
      delete(o) if include?(o)
    end

    def delete_if(&block)
      block_given? or return enum_for(__method__) { size }
      select(&block).each { |o| delete(o) }
      self
    end

    def keep_if(&block)
      block_given? or return enum_for(__method__) { size }
      reject(&block).each { |o| delete(o) }
      self
    end

    def collect!
      block_given? or return enum_for(__method__) { size }
      set = self.class.new
      each { |o| set << yield(o) }
      replace(set)
    end
    alias map! collect!

    def reject!(&block)
      block_given? or return enum_for(__method__) { size }
      n = size
      delete_if(&block)
      self if size != n
    end

    def select!(&block)
      block_given? or return enum_for(__method__) { size }
      n = size
      keep_if(&block)
      self if size != n
    end

    alias filter! select!

    def merge(*enums, **nil)
      enums.each do |enum|
        if enum.instance_of?(self.class)
          super(enum)
        else
          do_with_enum(enum) { |o| add(o) }
        end
      end

      self
    end

    def subtract(enum)
      do_with_enum(enum) { |o| delete(o) }
      self
    end

    def |(enum)
      dup.merge(enum)
    end
    alias + |
    alias union |

    def -(enum)
      dup.subtract(enum)
    end
    alias difference -

    def &(enum)
      n = self.class.new
      if enum.is_a?(Set)
        if enum.size > size
          each { |o| n.add(o) if enum.include?(o) }
        else
          enum.each { |o| n.add(o) if include?(o) }
        end
      else
        do_with_enum(enum) { |o| n.add(o) if include?(o) }
      end
      n
    end
    alias intersection &

    def ^(enum)
      n = self.class.new(enum)
      each { |o| n.add(o) unless n.delete?(o) }
      n
    end

    def ==(other)
      if self.equal?(other)
        true
      elsif other.instance_of?(self.class)
        super
      elsif other.is_a?(Set) && self.size == other.size
        other.all? { |o| include?(o) }
      else
        false
      end
    end

    def eql?(o)   # :nodoc:
      return false unless o.is_a?(Set)
      super
    end

    def classify
      block_given? or return enum_for(__method__) { size }

      h = {}

      each { |i|
        (h[yield(i)] ||= self.class.new).add(i)
      }

      h
    end

    def join(separator=nil)
      to_a.join(separator)
    end

    const_set(:InspectKey, :__inspect_key__)         # :nodoc:

    def inspect
      ids = (Thread.current[Set.send(:compatible)::InspectKey] ||= [])

      if ids.include?(object_id)
        return sprintf('#<%s: {...}>', self.class.name)
      end

      ids << object_id
      begin
        return sprintf('#<%s: {%s}>', self.class, to_a.inspect[1..-2])
      ensure
        ids.pop
      end
    end

    alias to_s inspect

    def pretty_print(pp)  # :nodoc:
      pp.group(1, sprintf('#<%s:', self.class.name), '>') {
        pp.breakable
        pp.group(1, '{', '}') {
          pp.seplist(self) { |o|
            pp.pp o
          }
        }
      }
    end

    def pretty_print_cycle(pp)    # :nodoc:
      pp.text sprintf('#<%s: {%s}>', self.class.name, empty? ? '' : '...')
    end
  end
  Primitive.zr_state_set(self, :__compatible__, compatible)

  class << self
    private

    def inherited(subclass)
      return unless equal?(Set)

      unless const_defined?(:SubclassCompatible, false)
        const_set(:SubclassCompatible, compatible)
        private_constant :SubclassCompatible
      end
      subclass.include(compatible)
      subclass.extend(compatible::ClassMethods)
    end

    # Set::SubclassCompatible, before the constant names it.
    def compatible
      Primitive.attr! :hidden
      Primitive.zr_hidden_get(Set, :__compatible__)
    end

    # enum_method_id: `each_entry` where the object has one, else `each`.
    def enum_method(other)
      Primitive.attr! :hidden
      return :each_entry if other.respond_to?(:each_entry)
      return :each if other.respond_to?(:each)

      raise ArgumentError, "value must be enumerable"
    end
  end

  private

  # The table, which an allocated Set makes empty on first use.
  def table
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__table__) || Primitive.zr_state_set(self, :__table__, {})
  end

  def iterating?
    Primitive.attr! :hidden
    Primitive.zr_hidden_get(self, :__level__).to_i.positive?
  end

  # set_iter: each member, the Set counted as iterating unless frozen.
  def walk(&block)
    Primitive.attr! :hidden
    return if table.empty?
    return table.each_key(&block) if frozen?

    Primitive.zr_state_set(self, :__level__, Primitive.zr_hidden_get(self, :__level__).to_i + 1)
    begin
      table.each_key(&block)
    ensure
      Primitive.zr_state_set(self, :__level__, Primitive.zr_hidden_get(self, :__level__) - 1)
    end
  end

  # set_i_to_h: what Marshal writes a Set as, a Hash from each member to
  # true that answers false for anything else.
  def marshal_hash
    Primitive.attr! :hidden
    hash = compare_by_identity? ? {}.compare_by_identity : {}
    hash.default = false
    walk { |item| hash[item] = true }
    hash
  end

  # set_i_from_hash: the members such a Hash names.
  def marshal_load_hash(hash)
    Primitive.attr! :hidden
    raise TypeError, "wrong argument type #{hash.nil? ? 'nil' : Primitive.zr_class_name_of(hash)} (expected Hash)" unless hash.is_a?(Hash)

    compare_by_identity if hash.compare_by_identity?
    hash.each_pair do |item, value|
      raise RuntimeError, "expect true as Set value: #{Primitive.zr_class_name_of(value)}" unless value.equal?(true)

      add(item)
    end
    self
  end

  def check_frozen
    Primitive.attr! :hidden
    Primitive.zr_frozen_error(self) if frozen?
  end

  def set_arg(other)
    Primitive.attr! :hidden
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    other
  end

  # set_le: every member of this Set is one of `other`'s.
  def within?(other)
    Primitive.attr! :hidden
    into = other.send(:table)
    walk { |item| return false unless into.key?(item) }
    true
  end

  # set_merge_enum_into.
  def merge_from(other)
    Primitive.attr! :hidden
    into = table
    if other.is_a?(Set)
      other.send(:walk) { |item| into[item] = true }
    elsif other.is_a?(Array)
      other.each { |item| into[item] = true }
    else
      other.__send__(Set.send(:enum_method, other)) { |item| into[item] = true }
    end
    self
  end

  def rebuild(fresh)
    Primitive.attr! :hidden
    check_frozen
    walk { |item| fresh[item] = true }
    Primitive.zr_state_set(self, :__table__, fresh)
    self
  end

  def any_set?
    Primitive.attr! :hidden
    walk { |item| return true if item.is_a?(Set) }
    false
  end

  def flatten_into(into, from, seen)
    Primitive.attr! :hidden
    from.send(:walk) do |item|
      if item.is_a?(Set)
        case seen[item.object_id]
        when false then next
        when true then raise ArgumentError, "tried to flatten recursive Set"
        end
        seen[item.object_id] = true
        flatten_into(into, item, seen)
        seen[item.object_id] = false
      else
        into.add(item)
      end
    end
  end

  # Union-find over the members' places, with path compression.
  def root_of(parents, index)
    Primitive.attr! :hidden
    root = parents[index]
    path = []
    while root != index
      path << index
      index = root
      root = parents[index]
    end
    path.each { |at| parents[at] = root }
    root
  end

  def unite(parents, i, j)
    Primitive.attr! :hidden
    a = root_of(parents, i)
    b = root_of(parents, j)
    parents[b] = a if a != b
  end
end
