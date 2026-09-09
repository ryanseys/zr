# Hash over the kernel's table.
class Hash
  include Enumerable

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

  def reject
    return to_enum(:reject) { size } unless block_given?

    out = {}
    each { |k, v| out[k] = v unless yield(k, v) }
    out
  end

  def to_h
    self
  end

  def merge(other)
    out = {}
    each { |k, v| out[k] = v }
    other.each { |k, v| out[k] = v }
    out
  end

  def key(value)
    each { |k, v| return k if v == value }
    nil
  end

  def value?(value)
    each { |_, v| return true if v == value }
    false
  end

  def invert
    out = {}
    each { |k, v| out[v] = k }
    out
  end

  def filter
    out = {}
    each { |k, v| out[k] = v if yield(k, v) }
    out
  end

  def has_value?(value)
    value?(value)
  end

  def transform_values
    return to_enum(:transform_values) { size } unless block_given?

    out = {}
    each { |k, v| out[k] = yield(v) }
    out
  end
end
