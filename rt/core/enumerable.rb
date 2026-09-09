# Enumerable over `each`, in the shape CRuby's C implementation has: a
# block passed on to `each`, with the value taken as the element.
module Enumerable
  def map
    out = []
    each { |x| out << yield(x) }
    out
  end

  def select
    out = []
    each { |x| out << x if yield(x) }
    out
  end

  def reject
    out = []
    each { |x| out << x unless yield(x) }
    out
  end

  def filter_map
    out = []
    each do |x|
      v = yield(x)
      out << v if v
    end
    out
  end

  def find
    each { |x| return x if yield(x) }
    nil
  end

  def any?
    if block_given?
      each { |x| return true if yield(x) }
    else
      each { |x| return true if x }
    end
    false
  end

  def all?
    if block_given?
      each { |x| return false unless yield(x) }
    else
      each { |x| return false unless x }
    end
    true
  end

  def none?
    if block_given?
      each { |x| return false if yield(x) }
    else
      each { |x| return false if x }
    end
    true
  end

  def count
    n = 0
    if block_given?
      each { |x| n += 1 if yield(x) }
    else
      each { |x| n += 1 }
    end
    n
  end

  def first
    each { |x| return x }
    nil
  end

  def to_a
    out = []
    each { |x| out << x }
    out
  end

  def include?(target)
    each { |x| return true if x == target }
    false
  end

  def each_with_index
    i = 0
    each do |x|
      yield(x, i)
      i += 1
    end
    self
  end

  def inject(*args)
    acc = args.empty? ? nil : args.first
    op = args.size == 2 ? args.last : (args.size == 1 && !block_given? ? args.first : nil)
    if op
      acc = args.size == 2 ? args.first : nil
      first = args.size != 2
      each do |x|
        if first
          acc = x
          first = false
        else
          acc = acc.send(op, x)
        end
      end
      return acc
    end
    first = args.empty?
    each do |x|
      if first
        acc = x
        first = false
      else
        acc = yield(acc, x)
      end
    end
    acc
  end

  def reduce(*args, &block) = inject(*args, &block)

  def sum
    acc = 0
    if block_given?
      each { |x| acc += yield(x) }
    else
      each { |x| acc += x }
    end
    acc
  end
end
