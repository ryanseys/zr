# Set: a Hash whose keys are the members, in insertion order. The
# Enumerable methods that build a new collection answer Arrays, as
# CRuby's core Set does; the set algebra answers Sets.
class Set
  include Enumerable

  # Ruby 4.0's core Set keeps this subclass, with nothing of its own.
  class CoreSet < Set
  end

  def self.[](*items) = new(items)

  def initialize(items = nil, &block)
    @hash = {}
    @iterating = 0
    return if items.nil?

    raise ArgumentError, "value must be enumerable" unless items.respond_to?(:each)

    items.each { |x| add(block ? yield(x) : x) }
  end

  def size = @hash.size
  alias length size

  def empty? = @hash.empty?

  def include?(item) = @hash.key?(item)
  alias member? include?
  alias === include?

  def add(item)
    check_frozen
    raise RuntimeError, "can't add a new item into set during iteration" if @iterating > 0 && !@hash.key?(item)

    @hash[item] = true
    self
  end

  alias << add

  def add?(item)
    return nil if @hash.key?(item)

    add(item)
  end

  def delete(item)
    check_frozen
    @hash.delete(item)
    self
  end

  def delete?(item)
    return nil unless @hash.key?(item)

    delete(item)
  end

  def each(&block)
    return to_enum(:each) { size } unless block

    @iterating += 1
    begin
      @hash.each_key(&block)
    ensure
      @iterating -= 1
    end
    self
  end

  def to_a = @hash.keys

  def to_set = self

  def dup
    copy = self.class.new
    copy.send(:take_hash, @hash.dup)
    copy
  end

  alias clone dup

  def freeze
    @hash.freeze
    super
  end

  def merge(*others)
    others.each do |other|
      raise ArgumentError, "value must be enumerable" unless other.respond_to?(:each)

      other.each { |x| add(x) }
    end
    self
  end

  def subtract(other)
    enumerable(other).each { |x| delete(x) }
    self
  end

  def |(other) = dup.merge(enumerable(other))
  alias union |
  alias + |

  def -(other) = dup.subtract(enumerable(other))
  alias difference -

  def &(other)
    other = enumerable(other)
    result = self.class.new
    other.each { |x| result.add(x) if include?(x) }
    result
  end

  alias intersection &

  def ^(other)
    result = dup
    enumerable(other).each { |x| result.include?(x) ? result.delete(x) : result.add(x) }
    result
  end

  def subset?(other)
    other = set_arg(other)
    size <= other.size && all? { |x| other.include?(x) }
  end

  alias <= subset?

  def proper_subset?(other)
    other = set_arg(other)
    size < other.size && all? { |x| other.include?(x) }
  end

  alias < proper_subset?

  def superset?(other) = set_arg(other).subset?(self)
  alias >= superset?

  def proper_superset?(other) = set_arg(other).proper_subset?(self)
  alias > proper_superset?

  def disjoint?(other) = !intersect?(other)

  def intersect?(other)
    other = enumerable(other)
    other.any? { |x| include?(x) }
  end

  def <=>(other)
    return nil unless other.is_a?(Set)
    return 0 if self == other
    return -1 if proper_subset?(other)
    return 1 if proper_superset?(other)

    nil
  end

  def ==(other)
    return true if equal?(other)
    return false unless other.is_a?(Set) && size == other.size

    all? { |x| other.include?(x) }
  end

  def eql?(other) = other.is_a?(Set) && @hash.eql?(other.instance_variable_get(:@hash))

  def hash = @hash.hash

  def inspect
    return "Set[...]" if Primitive.zr_recursive_enter(self, :inspect)

    begin
      "Set[#{to_a.map(&:inspect).join(', ')}]"
    ensure
      Primitive.zr_recursive_leave(self, :inspect)
    end
  end

  alias to_s inspect

  def join(separator = nil) = to_a.join(separator)

  def clear
    check_frozen
    @hash.clear
    self
  end

  def replace(other)
    check_frozen
    other = enumerable(other)
    @hash.clear
    other.each { |x| add(x) }
    self
  end

  def delete_if
    return to_enum(:delete_if) { size } unless block_given?

    check_frozen
    to_a.each { |x| @hash.delete(x) if yield(x) }
    self
  end

  def keep_if
    return to_enum(:keep_if) { size } unless block_given?

    check_frozen
    to_a.each { |x| @hash.delete(x) unless yield(x) }
    self
  end

  def select!(&block)
    return to_enum(:select!) { size } unless block

    before = size
    keep_if(&block)
    size == before ? nil : self
  end

  alias filter! select!

  def reject!(&block)
    return to_enum(:reject!) { size } unless block

    before = size
    delete_if(&block)
    size == before ? nil : self
  end

  def map!
    return to_enum(:map!) { size } unless block_given?

    check_frozen
    items = to_a
    @hash.clear
    items.each { |x| @hash[yield(x)] = true }
    self
  end

  alias collect! map!

  def flatten
    result = self.class.new
    each { |x| x.is_a?(Set) ? result.merge(x.flatten) : result.add(x) }
    result
  end

  def flatten!
    return nil if none? { |x| x.is_a?(Set) }

    replace(flatten)
  end

  def classify
    return to_enum(:classify) { size } unless block_given?

    groups = {}
    each { |x| (groups[yield(x)] ||= self.class.new).add(x) }
    groups
  end

  # The sets of members the block's relation joins, or the classes
  # its one-argument form names. A relation of two members joins them
  # only when it holds both ways, and what it joins travels: CRuby walks
  # the pairs into a union-find and answers one set per root.
  def divide(&block)
    return to_enum(:divide) { size } unless block
    return Set.new(classify(&block).values) if block.arity != 2

    items = to_a
    roots = (0...items.size).to_a
    i = 0
    while i < items.size - 1
      j = i + 1
      while j < items.size
        share_root(roots, i, j) if yield(items[i], items[j]) && yield(items[j], items[i])
        j += 1
      end
      i += 1
    end
    parts = {}
    answer = Set.new
    items.each_with_index do |item, at|
      root = root_of(roots, at)
      unless parts.key?(root)
        parts[root] = self.class.new
        answer.add(parts[root])
      end
      parts[root].add(item)
    end
    answer
  end

  def compare_by_identity
    @hash.compare_by_identity
    self
  end

  def compare_by_identity? = @hash.compare_by_identity?

  def reset
    @hash.rehash
    self
  end

  def first(n = nil) = n.nil? ? to_a.first : to_a.first(n)

  private

  def take_hash(hash)
    Primitive.attr! :hidden
    @hash = hash
    @iterating = 0
  end

  # Union-find over the members' places: where a place leads, and the
  # two places a joined pair share afterwards.
  def root_of(roots, at)
    Primitive.attr! :hidden
    at = roots[at] while roots[at] != at
    at
  end

  def share_root(roots, i, j)
    Primitive.attr! :hidden
    a = root_of(roots, i)
    b = root_of(roots, j)
    roots[b] = a if a != b
  end

  def check_frozen
    Primitive.attr! :hidden
    raise FrozenError.new("can't modify frozen Set: #{inspect}", receiver: self) if frozen?
  end

  def enumerable(other)
    Primitive.attr! :hidden
    raise ArgumentError, "value must be enumerable" unless other.respond_to?(:each)

    other
  end

  def set_arg(other)
    Primitive.attr! :hidden
    raise ArgumentError, "value must be a set" unless other.is_a?(Set)

    other
  end
end
