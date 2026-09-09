# Hash over the kernel's table: each, [], []=, fetch, delete, keys and
# values come from the kernel; the rest is written over them.
class Hash
  include Enumerable

  def self.[](*args)
    return args[0].to_h if args.size == 1 && args[0].respond_to?(:to_hash)
    if args.size == 1 && args[0].is_a?(Array)
      out = {}
      args[0].each do |pair|
        raise ArgumentError, "wrong element type #{pair.class} (expected array)" unless pair.is_a?(Array)
        raise ArgumentError, "invalid number of elements (#{pair.size} for 1..2)" unless pair.size.between?(1, 2)

        out[pair[0]] = pair[1]
      end
      return out
    end
    raise ArgumentError, "odd number of arguments for Hash" if args.size.odd?

    out = {}
    args.each_slice(2) { |k, v| out[k] = v }
    out
  end

  def each_key
    return to_enum(:each_key) { size } unless block_given?

    each { |k, _| yield(k) }
    self
  end

  def each_value
    return to_enum(:each_value) { size } unless block_given?

    each { |_, v| yield(v) }
    self
  end

  def select
    return to_enum(:select) { size } unless block_given?

    out = {}
    each { |k, v| out[k] = v if yield(k, v) }
    out
  end
  alias filter select

  def reject
    return to_enum(:reject) { size } unless block_given?

    out = {}
    each { |k, v| out[k] = v unless yield(k, v) }
    out
  end

  def select!
    return to_enum(:select!) { size } unless block_given?

    before = size
    keys.each { |k| delete(k) unless yield(k, self[k]) }
    size == before ? nil : self
  end
  alias filter! select!

  def keep_if(&block)
    return to_enum(:keep_if) { size } unless block

    select!(&block)
    self
  end

  def reject!
    return to_enum(:reject!) { size } unless block_given?

    before = size
    keys.each { |k| delete(k) if yield(k, self[k]) }
    size == before ? nil : self
  end

  def delete_if(&block)
    return to_enum(:delete_if) { size } unless block

    reject!(&block)
    self
  end

  # A subclass answers a plain Hash with the same default.
  def to_h
    unless block_given?
      return self if instance_of?(Hash)

      out = {}
      each { |k, v| out[k] = v }
      out.default_proc = default_proc if default_proc
      out.default = default unless default_proc
      return out
    end

    out = {}
    each do |k, v|
      pair = yield(k, v)
      raise TypeError, "wrong element type #{pair.class} (expected array)" unless pair.is_a?(Array)
      raise ArgumentError, "element has wrong array length (expected 2, was #{pair.size})" unless pair.size == 2

      out[pair[0]] = pair[1]
    end
    out
  end

  def to_hash = self

  def to_a
    out = []
    each { |k, v| out << [k, v] }
    out
  end
  alias entries to_a

  def merge(*others, &block)
    out = dup
    others.each { |other| out.merge!(other, &block) }
    out
  end

  def merge!(*others)
    others.each do |other|
      other.each do |k, v|
        self[k] = block_given? && key?(k) ? yield(k, self[k], v) : v
      end
    end
    self
  end
  alias update merge!

  def store(key, value) = self[key] = value

  def key(value)
    each { |k, v| return k if v == value }
    nil
  end

  def value?(value)
    each { |_, v| return true if v == value }
    false
  end
  alias has_value? value?

  def invert
    out = {}
    each { |k, v| out[v] = k }
    out
  end

  def transform_values
    return to_enum(:transform_values) { size } unless block_given?

    out = {}
    each { |k, v| out[k] = yield(v) }
    out
  end

  def transform_values!
    return to_enum(:transform_values!) { size } unless block_given?

    keys.each { |k| self[k] = yield(self[k]) }
    self
  end

  def transform_keys(mapping = nil)
    return to_enum(:transform_keys) { size } unless mapping || block_given?

    out = {}
    each do |k, v|
      new_key = if mapping&.key?(k) then mapping[k]
                elsif block_given? then yield(k)
                else k
                end
      out[new_key] = v
    end
    out
  end

  def transform_keys!(mapping = nil, &block)
    return to_enum(:transform_keys!) { size } unless mapping || block

    replace(transform_keys(mapping, &block))
  end

  def replace(other)
    clear
    other.each { |k, v| self[k] = v }
    self
  end

  def clear = Primitive.zr_hash_clear(self)

  def default=(value)
    Primitive.zr_hash_set_default(self, value)
  end

  def default_proc = Primitive.zr_hash_default_proc(self)

  def default_proc=(pr)
    pr = pr.to_proc if !pr.nil? && !pr.is_a?(Proc) && pr.respond_to?(:to_proc)
    unless pr.nil? || pr.is_a?(Proc)
      raise TypeError, "wrong default_proc type #{pr.class} (expected Proc)"
    end
    if pr&.lambda? && pr.arity != 2 && (pr.arity >= 0 || pr.arity < -3)
      raise TypeError, "default_proc takes two arguments (2 for #{pr.arity})"
    end

    Primitive.zr_hash_set_default_proc(self, pr)
  end

  def dig(key, *rest)
    v = self[key]
    rest.empty? || v.nil? ? v : Primitive.zr_dig_into(v, rest)
  end

  def fetch_values(*keys, &block)
    keys.map { |k| fetch(k, &block) }
  end

  def values_at(*keys)
    keys.map { |k| self[k] }
  end

  def slice(*keys)
    out = {}
    keys.each { |k| out[k] = self[k] if key?(k) }
    out
  end

  # A plain Hash: the default and default proc do not carry over.
  def except(*keys)
    out = {}
    each { |k, v| out[k] = v }
    keys.each { |k| out.delete(k) }
    out
  end

  # The block sees each pair as one value, which a two-parameter block
  # takes apart.
  def any?(*args)
    return super if args.size == 1
    return !empty? unless block_given?

    each { |k, v| return true if yield([k, v]) }
    false
  end

  # `default` alone answers the default value; with a key, what a
  # default proc would answer for it.
  def default(*key)
    raise ArgumentError, "wrong number of arguments (given #{key.size}, expected 0..1)" if key.size > 1
    return Primitive.zr_hash_default_value(self) if key.empty?

    proc = default_proc
    proc ? proc.call(self, key[0]) : Primitive.zr_hash_default_value(self)
  end

  # `delete(key) { |key| }`: the block's answer for a missing key.
  def delete(key)
    Primitive.zr_frozen_error(self) if frozen?
    return Primitive.zr_hash_delete_m(self, key) if key?(key) || !block_given?

    yield key
  end

  def compact
    out = {}
    each { |k, v| out[k] = v unless v.nil? }
    out.default = default
    out.default_proc = default_proc if default_proc
    out
  end

  def compact!
    before = size
    keys.each { |k| delete(k) if self[k].nil? }
    size == before ? nil : self
  end

  def flatten(depth = 1)
    depth = Primitive.zr_index_operand_m(depth)
    return to_a if depth <= 0

    out = []
    each { |k, v| out << k << v }
    depth > 1 ? out.flatten(depth - 1) : out
  end

  def rehash = Primitive.zr_hash_rehash(self)

  def assoc(key)
    each { |k, v| return [k, v] if k == key }
    nil
  end

  def rassoc(value)
    each { |k, v| return [k, v] if v == value }
    nil
  end

  def shift
    each do |k, v|
      delete(k)
      return [k, v]
    end
    nil
  end

  def eql?(other)
    return false unless other.is_a?(Hash) && size == other.size

    each { |k, v| return false unless other.key?(k) && v.eql?(other[k]) }
    true
  end

  # Order does not matter: the pairs' hashes combine by a sum.
  def hash
    total = size
    each { |k, v| total = (total + [k, v].hash) & 0x3FFFFFFFFFFFFFFF }
    total
  end

  def <=(other) = all? { |k, v| other.key?(k) && other[k] == v }

  def <(other) = size < other.size && self <= other

  def >=(other) = other <= self

  def >(other) = other < self

  def to_proc
    h = self
    Primitive.zr_proc_anonymous(lambda { |k| h[k] })
  end

  def deconstruct_keys(keys) = self

  def self.try_convert(object)
    return object if object.is_a?(Hash)
    return nil unless object.respond_to?(:to_hash)

    converted = object.to_hash
    raise TypeError, "can't convert #{object.class} to Hash (#{object.class}#to_hash gives #{converted.class})" unless converted.nil? || converted.is_a?(Hash)

    converted
  end

  def compare_by_identity = Primitive.zr_hash_compare_by_identity(self)

  def compare_by_identity? = Primitive.zr_hash_identity_p(self)

end
