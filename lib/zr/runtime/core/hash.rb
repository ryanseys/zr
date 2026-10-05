# frozen_string_literal: true

# Hash over the kernel's table: each, [], []=, fetch, delete, keys and
# values come from the kernel; the rest is written over them. A walk of
# a Hash's own table is Primitive.zr_hash_foreach, which a subclass's
# `each` leaves alone, as rb_hash_foreach does, and a read or a write of
# a pair inside another method is a primitive, never `self[key]`: a
# subclass sees only the calls hash.c makes by dispatch.
class Hash
  # hash.rb's: a default value or a default proc, and room for
  # `capacity` pairs.
  def initialize(ifnone = (ifnone_unset = true), capacity: 0, &block)
    Primitive.attr! :ruby
    Primitive.zr_hash_init(self, capacity, ifnone_unset ? true : false, ifnone, block)
  end

  include Enumerable

  # The flag a `ruby2_keywords` method sets on the Hash it took from
  # keywords, so a later splat passes it on as keywords again.
  def self.ruby2_keywords_hash(hash)
    raise TypeError, "no implicit conversion of #{conversion_name(hash)} into Hash" unless hash.is_a?(Hash)

    # rb_hash_dup: the class, ivars, default and compare_by_identity stay.
    Primitive.zr_ruby2_hash_mark(Kernel.instance_method(:dup).bind_call(hash))
  end

  def self.ruby2_keywords_hash?(hash)
    raise TypeError, "no implicit conversion of #{conversion_name(hash)} into Hash" unless hash.is_a?(Hash)

    Primitive.zr_ruby2_hash_p(hash)
  end

  # Always a new Hash of the receiver's class, as rb_hash_s_create
  # builds it: a Hash given alone lends its pairs, but neither its
  # default nor its compare_by_identity.
  def self.[](*args)
    if args.size == 1 && (given = Hash.try_convert(args[0]))
      out = allocate
      Primitive.zr_hash_foreach(given) { |k, v| Primitive.zr_hash_aset_m(out, k, v) }
      return out
    end
    # rb_hash_s_create: one argument that converts with to_ary is the
    # pairs, each converted the same way.
    if args.size == 1 && (list = Array.try_convert(args[0]))
      out = allocate
      list.each_with_index do |item, i|
        pair = Array.try_convert(item)
        raise ArgumentError, "wrong element type #{item.class} at #{i} (expected array)" unless pair
        raise ArgumentError, "invalid number of elements (#{pair.size} for 1..2)" unless pair.size.between?(1, 2)

        Primitive.zr_hash_aset_m(out, pair[0], pair[1])
      end
      return out
    end
    raise ArgumentError, +"odd number of arguments for Hash" if args.size.odd?

    out = allocate
    i = 0
    while i < args.size
      Primitive.zr_hash_aset_m(out, args[i], args[i + 1])
      i += 2
    end
    out
  end

  # An empty plain Hash with this one's compare_by_identity and nothing
  # else of it, as hash_dup_with_compare_by_id starts one.
  def identity_shaped
    Primitive.attr! :hidden
    out = {}
    Primitive.zr_hash_identity_p(self) ? out.compare_by_identity : out
  end

  def each_key
    return to_enum(:each_key) { size } unless block_given?

    Primitive.zr_hash_foreach(self) { |k, _| yield(k) }
    self
  end

  def each_value
    return to_enum(:each_value) { size } unless block_given?

    Primitive.zr_hash_foreach(self) { |_, v| yield(v) }
    self
  end

  def select
    return to_enum(__callee__) { size } unless block_given?

    # rb_hash_select walks a copy and deletes from it, so the block can
    # change the receiver.
    out = identity_shaped
    Primitive.zr_hash_foreach(self) { |k, v| out[k] = v }
    Primitive.zr_hash_foreach(out) { |k, v| Primitive.zr_hash_delete_m(out, k) unless yield(k, v) }
    out
  end
  alias filter select

  def reject
    return to_enum(:reject) { size } unless block_given?

    out = identity_shaped
    Primitive.zr_hash_foreach(self) { |k, v| out[k] = v }
    Primitive.zr_hash_foreach(out) { |k, v| Primitive.zr_hash_delete_m(out, k) if yield(k, v) }
    out
  end

  def select!
    return to_enum(__callee__) { size } unless block_given?

    before = Primitive.zr_hash_len_m(self)
    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hash_foreach(self) { |k, v| Primitive.zr_hash_delete_m(self, k) unless yield(k, v) }
    Primitive.zr_hash_len_m(self) == before ? nil : self
  end
  alias filter! select!

  def keep_if
    return to_enum(:keep_if) { size } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hash_foreach(self) { |k, v| Primitive.zr_hash_delete_m(self, k) unless yield(k, v) }
    self
  end

  def reject!
    return to_enum(:reject!) { size } unless block_given?

    before = Primitive.zr_hash_len_m(self)
    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hash_foreach(self) { |k, v| Primitive.zr_hash_delete_m(self, k) if yield(k, v) }
    Primitive.zr_hash_len_m(self) == before ? nil : self
  end

  def delete_if
    return to_enum(:delete_if) { size } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hash_foreach(self) { |k, v| Primitive.zr_hash_delete_m(self, k) if yield(k, v) }
    self
  end

  # A subclass returns a plain Hash with the same pairs, default and
  # compare_by_identity, as rb_hash_to_h copies them.
  def to_h
    unless block_given?
      return self if instance_of?(Hash)

      return Primitive.zr_hash_replace_m({}, self)
    end

    out = {}
    Primitive.zr_hash_foreach(self) do |k, v|
      given = yield(k, v)
      # rb_check_array_type: a pair that converts with to_ary.
      pair = Array.try_convert(given)
      raise TypeError, "wrong element type #{given.class} (expected array)" unless pair
      raise ArgumentError, "element has wrong array length (expected 2, was #{pair.size})" unless pair.size == 2

      out[pair[0]] = pair[1]
    end
    out
  end

  def to_hash = self

  def to_a
    out = []
    Primitive.zr_hash_foreach(self) { |k, v| out << [k, v] }
    out
  end

  # rb_hash_merge: a copy of the receiver as rb_hash_dup makes one, with
  # no `initialize_copy`, updated as merge! updates.
  def merge(*others, &block)
    out = Primitive.zr_hash_dup_m(self)
    others.each { |other| out.update_from(other, &block) }
    out
  end

  def merge!(*others, &block)
    Primitive.zr_frozen_error(self) if frozen?
    others.each { |other| update_from(other, &block) }
    self
  end
  alias update merge!

  # One argument of merge!: its pairs in, a block deciding a key both
  # have.
  def update_from(other)
    Primitive.attr! :hidden
    hash = Hash.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Hash"
    Primitive.zr_hash_foreach(hash) do |k, v|
      if block_given? && Primitive.zr_hash_key_p_m(self, k)
        v = yield(k, Primitive.zr_hash_fetch_m(self, k, nil), v)
      end
      Primitive.zr_hash_aset_m(self, k, v)
    end
  end

  def store(key, value) = Primitive.zr_hash_aset_m(self, key, value)

  def key(value)
    Primitive.zr_hash_foreach(self) { |k, v| return k if Primitive.zr_rb_equal(v, value) }
    nil
  end

  def value?(value)
    Primitive.zr_hash_foreach(self) { |_, v| return true if Primitive.zr_rb_equal(v, value) }
    false
  end
  alias has_value? value?

  def invert
    out = {}
    Primitive.zr_hash_foreach(self) { |k, v| out[v] = k }
    out
  end

  def transform_values
    return to_enum(:transform_values) { size } unless block_given?

    out = identity_shaped
    Primitive.zr_hash_foreach(self) { |k, v| out[k] = yield(v) }
    out
  end

  def transform_values!
    return to_enum(:transform_values!) { size } unless block_given?

    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hash_foreach(self) { |k, v| Primitive.zr_hash_store(self, k, yield(v)) }
    self
  end

  def transform_keys(mapping = nil)
    return to_enum(:transform_keys) { size } unless mapping || block_given?

    mapping = Hash.try_convert(mapping) || raise(TypeError, "no implicit conversion of #{conversion_name(mapping)} into Hash") if mapping
    out = {}
    Primitive.zr_hash_foreach(self) do |k, v|
      new_key = if mapping && Primitive.zr_hash_key_p_m(mapping, k) then Primitive.zr_hash_fetch_m(mapping, k, nil)
                elsif block_given? then yield(k)
                else k
                end
      out[new_key] = v
    end
    out
  end

  # rb_hash_transform_keys_bang: each pair taken out and put back under
  # its new key, in the order the pairs were, a key another pair has
  # already moved to left where it is.
  def transform_keys!(mapping = nil)
    return to_enum(:transform_keys!) { size } unless mapping || block_given?

    Primitive.zr_frozen_error(self) if frozen?
    mapping = Hash.try_convert(mapping) || raise(TypeError, "no implicit conversion of #{conversion_name(mapping)} into Hash") if mapping
    moved = {}
    pairs = []
    Primitive.zr_hash_foreach(self) { |k, v| pairs << [k, v] }
    pairs.each do |k, v|
      new_key = if mapping && Primitive.zr_hash_key_p_m(mapping, k) then Primitive.zr_hash_fetch_m(mapping, k, nil)
                elsif block_given? then yield(k)
                else k
                end
      Primitive.zr_hash_delete_m(self, k) unless Primitive.zr_hash_key_p_m(moved, k)
      Primitive.zr_hash_aset_m(self, new_key, v)
      Primitive.zr_hash_aset_m(moved, new_key, nil)
    end
    self
  end

  # rb_hash_replace: the other's pairs, default and compare_by_identity,
  # in CRuby's order of refusals; a Hash replaced by itself stays.
  def replace(other)
    Primitive.zr_frozen_error(self) if frozen?
    return self if equal?(other)
    raise RuntimeError, +"can't replace hash during iteration" if Primitive.zr_hash_iterating_p(self)

    hash = Hash.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Hash"
    Primitive.zr_hash_replace_m(self, hash)
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
    v = Primitive.zr_hash_aref_m(self, key)
    rest.empty? || v.nil? ? v : Primitive.zr_dig_into(v, rest)
  end

  def fetch_values(*keys, &block)
    keys.map { |k| Primitive.zr_hash_fetch_m(self, k, block) }
  end

  def values_at(*keys)
    keys.map { |k| Primitive.zr_hash_aref_m(self, k) }
  end

  def slice(*keys)
    out = identity_shaped
    keys.each { |k| out[k] = Primitive.zr_hash_fetch_m(self, k, nil) if Primitive.zr_hash_key_p_m(self, k) }
    out
  end

  # A plain Hash: the default and default proc are not copied.
  def except(*keys)
    out = identity_shaped
    Primitive.zr_hash_foreach(self) { |k, v| out[k] = v }
    keys.each { |k| out.delete(k) }
    out
  end

  # rb_hash_any_p: each pair, as one value that a two-parameter block
  # splits, against the pattern or the block. The walk is the Hash's
  # own, not a send of `each`.
  def any?(*pattern, &block)
    raise ArgumentError, "wrong number of arguments (given #{pattern.size}, expected 0..1)" if pattern.size > 1
    return false if Primitive.zr_hash_len_m(self) == 0

    Primitive.zr_warn_here_m("given block not used") if block && !pattern.empty?
    return true if pattern.empty? && !block

    Primitive.zr_hash_foreach(self) do |k, v|
      pair = [k, v]
      return true if pattern.empty? ? yield(pair) : pattern[0] === pair
    end
    false
  end

  # `default` with no argument returns the default value; with a key, the
  # value that a default proc would return for it.
  def default(*key)
    raise ArgumentError, "wrong number of arguments (given #{key.size}, expected 0..1)" if key.size > 1
    return Primitive.zr_hash_default_value(self) if key.empty?

    proc = Primitive.zr_hash_default_proc(self)
    proc ? proc.call(self, key[0]) : Primitive.zr_hash_default_value(self)
  end

  # `delete(key) { |key| }`: the block's return value for a missing key.
  def delete(key)
    Primitive.zr_frozen_error(self) if frozen?
    return Primitive.zr_hash_delete_m(self, key) if Primitive.zr_hash_key_p_m(self, key) || !block_given?

    yield key
  end

  # The whole Hash copied, as rb_hash_compact copies it, less the nils.
  def compact
    out = Primitive.zr_hash_dup_m(self)
    Primitive.zr_hash_foreach(out) { |k, v| Primitive.zr_hash_delete_m(out, k) if v.nil? }
    out
  end

  def compact!
    Primitive.zr_frozen_error(self) if frozen?
    before = Primitive.zr_hash_len_m(self)
    Primitive.zr_hash_foreach(self) { |k, v| Primitive.zr_hash_delete_m(self, k) if v.nil? }
    Primitive.zr_hash_len_m(self) == before ? nil : self
  end

  def flatten(depth = 1)
    depth = Primitive.zr_index_operand_m(depth)
    return to_a if depth.zero?

    out = []
    Primitive.zr_hash_foreach(self) { |k, v| out << k << v }
    return out if depth == 1

    # A negative depth flattens all the way down, as Array#flatten has it.
    depth.negative? ? out.flatten : out.flatten(depth - 1)
  end

  def rehash = Primitive.zr_hash_rehash(self)

  def assoc(key)
    Primitive.zr_hash_foreach(self) { |k, v| return [k, v] if k == key }
    nil
  end

  def rassoc(value)
    Primitive.zr_hash_foreach(self) { |k, v| return [k, v] if Primitive.zr_rb_equal(v, value) }
    nil
  end

  def shift
    Primitive.zr_frozen_error(self) if frozen?
    Primitive.zr_hash_foreach(self) do |k, v|
      Primitive.zr_hash_delete_m(self, k)
      return [k, v]
    end
    nil
  end

  # The same two Hashes compared again inside their own comparison is a
  # recursion, which gives equal, as rb_exec_recursive_paired does.
  def eql?(other)
    return true if equal?(other)
    return false unless other.is_a?(Hash) && Primitive.zr_hash_len_m(self) == Primitive.zr_hash_len_m(other)
    return true if Primitive.zr_recursive_enter_paired(self, other, :eql?)

    begin
      Primitive.zr_hash_foreach(self) do |k, v|
        return false unless Primitive.zr_hash_key_p_m(other, k) && Primitive.zr_rb_eql(v, Primitive.zr_hash_fetch_m(other, k, nil))
      end
      true
    ensure
      Primitive.zr_recursive_leave(self, :eql?)
    end
  end

  # Order does not matter: the pairs' hashes combine by a sum.
  # A hash that contains itself uses a fixed value for the reference
  # back, so the walk ends.
  def hash
    Kernel.send(:outer_hash, self, (Primitive.zr_hash_len_m(self) * 31) + 2) do
      total = Primitive.zr_hash_len_m(self)
      Primitive.zr_hash_foreach(self) { |k, v| total = (total + [k, v].hash) & 0x3FFFFFFFFFFFFFFF }
      total
    end
  end

  # Each comparison reads the other side as a Hash, and gives the class
  # that it got when the argument is not one.
  def <=(other) = within(hash_operand(other))

  def <(other)
    other = hash_operand(other)
    Primitive.zr_hash_len_m(self) < Primitive.zr_hash_len_m(other) && within(other)
  end

  def >=(other) = hash_operand(other).within(self)

  def >(other)
    other = hash_operand(other)
    Primitive.zr_hash_len_m(other) < Primitive.zr_hash_len_m(self) && other.within(self)
  end

  # hash_le: every pair of the receiver is a pair of `other`.
  def within(other)
    Primitive.attr! :hidden
    Primitive.zr_hash_foreach(self) do |k, v|
      return false unless Primitive.zr_hash_key_p_m(other, k) && Primitive.zr_rb_equal(Primitive.zr_hash_fetch_m(other, k, nil), v)
    end
    true
  end

  def hash_operand(other)
    Primitive.attr! :hidden
    Hash.try_convert(other) or raise TypeError, "no implicit conversion of #{conversion_name(other)} into Hash"
  end

  def to_proc
    h = self
    Primitive.zr_proc_anonymous1(lambda { |k| Primitive.zr_hash_aref_m(h, k) })
  end

  def deconstruct_keys(keys) = self

  def self.try_convert(object)
    return object if Hash === object

    converted = Primitive.zr_check_call(object, :to_hash)
    raise TypeError, "can't convert #{conversion_name(object)} to Hash (#{conversion_name(object)}#to_hash gives #{conversion_name(converted)})" unless converted.nil? || Hash === converted

    converted
  end

  def compare_by_identity = Primitive.zr_hash_compare_by_identity(self)

  def compare_by_identity? = Primitive.zr_hash_identity_p(self)

end
