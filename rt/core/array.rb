# Array over the kernel's storage. CRuby writes these in C, so none
# goes through `each`: a backtrace must not show a row for it.
class Array
  include Enumerable

  def reverse
    out = []
    i = size - 1
    while i >= 0
      out << self[i]
      i -= 1
    end
    out
  end

  def last(n = nil)
    return self[-1] if n.nil?

    from = size - n
    from = 0 if from < 0
    out = []
    while from < size
      out << self[from]
      from += 1
    end
    out
  end

  def first(n = nil)
    return self[0] if n.nil?

    out = []
    i = 0
    while i < n && i < size
      out << self[i]
      i += 1
    end
    out
  end

  def <=>(other)
    return nil unless other.is_a?(Array)

    i = 0
    while i < size && i < other.size
      c = self[i] <=> other[i]
      return c if c != 0

      i += 1
    end
    size <=> other.size
  end

  def dup
    out = []
    i = 0
    while i < size
      out << self[i]
      i += 1
    end
    out
  end

  def +(other)
    out = dup
    i = 0
    while i < other.size
      out << other[i]
      i += 1
    end
    out
  end

  def join(sep = "")
    s = +""
    i = 0
    while i < size
      s << sep if i > 0
      x = self[i]
      s << (x.is_a?(Array) ? x.join(sep) : x.to_s)
      i += 1
    end
    s
  end

  def compact
    out = []
    i = 0
    while i < size
      out << self[i] unless self[i].nil?
      i += 1
    end
    out
  end

  def index(v = nil)
    i = 0
    while i < size
      return i if block_given? ? yield(self[i]) : self[i] == v

      i += 1
    end
    nil
  end

  def sum(init = 0)
    acc = init
    i = 0
    while i < size
      acc += block_given? ? yield(self[i]) : self[i]
      i += 1
    end
    acc
  end

  def min
    best = nil
    i = 0
    while i < size
      best = self[i] if i == 0 || (self[i] <=> best) < 0
      i += 1
    end
    best
  end

  def max
    best = nil
    i = 0
    while i < size
      best = self[i] if i == 0 || (self[i] <=> best) > 0
      i += 1
    end
    best
  end

  def take(n) = first(n)

  def uniq
    out = []
    i = 0
    while i < size
      out << self[i] unless out.include?(self[i])
      i += 1
    end
    out
  end

  def include?(v)
    i = 0
    while i < size
      return true if self[i] == v

      i += 1
    end
    false
  end

  def eql?(other)
    return false unless other.is_a?(Array) && size == other.size

    i = 0
    while i < size
      return false unless self[i].eql?(other[i])

      i += 1
    end
    true
  end

  def hash
    h = 7
    i = 0
    while i < size
      h = (h * 31 + self[i].hash) & 4611686018427387903
      i += 1
    end
    h
  end

  def to_a = self
  def count(*args, &block) = args.empty? && !block ? size : super
end
