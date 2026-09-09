# Hash over the kernel's table.
class Hash
  include Enumerable

  def each_key
    each { |k, _| yield(k) }
    self
  end

  def each_value
    each { |_, v| yield(v) }
    self
  end

  def select
    out = {}
    each { |k, v| out[k] = v if yield(k, v) }
    out
  end

  def reject
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
    out = {}
    each { |k, v| out[k] = yield(v) }
    out
  end
end
