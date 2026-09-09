# super_method, included_modules, Module.nesting, __method__,
# source_location, the main object's verbs, and Hash and Integer
# methods written in Ruby.
module Greet
  def hi = "Greet#hi"
end

class Base
  def hi = "Base#hi"
  def who = __method__
  def in_block = [1].map { __method__ }
end

class Kid < Base
  include Greet
  def hi = "Kid#hi"
end

m = Kid.new.method(:hi)
p m.super_method.owner, m.super_method.call, m.super_method.super_method.owner, m.super_method.super_method.super_method
p Kid.instance_method(:hi).super_method.class, Kid.instance_method(:hi).super_method.owner
p Base.new.method(:hi).super_method
p Kid.included_modules, Base.included_modules, Comparable.included_modules, Enumerable.included_modules
p Base.new.who, Base.new.in_block, __method__

module Outer
  module Inner
    p Module.nesting
    class << self
      p Module.nesting
    end
  end
  p Module.nesting
end
p Module.nesting

pr = proc { 1 }
p pr.source_location, ->(x) { x }.source_location[1], :sym.to_proc.source_location, method(:p).source_location

module Top
  def top_helper = "helped"
end
include Top
p top_helper, Object.include?(Top)

def util = "util"
private def hidden = "hidden"
public
def shown = "shown"
p [Object.private_method_defined?(:util), Object.private_method_defined?(:hidden), Object.public_method_defined?(:shown)]

h = { a: 1, b: 2, c: nil }
p h.fetch_values(:a, :b), h.values_at(:a, :z), h.slice(:a, :z), h.except(:a), h.compact, h.dig(:a), h.any? { |k, v| v == 2 }, h.count { |k, v| v }, h.find { |k, v| v == 2 }
p h.map { |k, v| [k, v] }, h.flat_map { |k, v| [k] }, h.filter_map { |k, v| k if v }, h.partition { |k, v| v }, h.group_by { |k, v| v.nil? }
p h.sort_by { |k, v| v.to_i }, h.min_by { |k, v| v.to_i }, h.sum { |k, v| v.to_i }, h.each_with_object([]) { |(k, v), a| a << k }, h.each_with_index.to_a, h.reduce(0) { |s, (k, v)| s + v.to_i }
p h.transform_keys(&:to_s), h.transform_keys(a: :x), h.transform_values { |v| v.to_i * 2 }, h.invert, h.key(2), h.rassoc(2), h.assoc(:b), h.first, h.first(2), h.to_a, h.sort, h.min, h.max
p h.merge({ d: 4 }, { e: 5 }), h.merge(a: 9) { |k, old, new| old + new }, h.select { |k, v| v }, h.reject { |k, v| v }, h.select! { |k, v| v }, h, h.reject! { |k, v| false }, h.keep_if { true }, h.delete_if { |k, v| k == :b }
p h.store(:z, 26), h, h.shift, h, h.clear, h, h.default, h.default_proc
d = Hash.new(5)
p d[:x], d.default, d.fetch(:x, 7)
d.default = 6
p d[:y]
e = Hash.new { |hash, key| hash[key] = key.to_s }
p e[:q], e, e.default_proc.class, e.default
e.default_proc = nil
p e[:zz], e.default_proc
p Hash[[[:a, 1], [:b, 2]]], Hash[:a, 1, :b, 2], Hash[{ x: 1 }]
begin; Hash[:a]; rescue => e; puts "#{e.class}: #{e.message}"; end
p({ a: 1 }.to_h { |k, v| [v, k] }, { a: 1 } <= { a: 1, b: 2 }, { a: 1 } < { a: 1 }, { a: 1, b: 2 } > { a: 1 }, { a: 1 }.to_proc.call(:a), { a: 1 }.eql?({ a: 1 }), { a: 1 }.hash == { a: 1 }.hash)
p({ a: 1, b: 2 }.transform_values!(&:succ), { a: 1 }.transform_keys!(&:to_s), { a: 1 }.replace({ b: 2 }), { a: 1 }.compact!, { a: nil }.compact!, { a: 1 }.update(b: 2))

p 2**10, 2**0, (-2)**3, 3.pow(4), 3.pow(4, 5), 5[0], 5[1], 5[2], 5[-1], 65.chr, 7.divmod(2), -7.divmod(2), 7.remainder(-2), -7.remainder(2), 7.div(2), 7.modulo(-2)
p 12.gcd(18), 12.lcm(18), 0.lcm(5), 255.bit_length, -1.bit_length, 0.bit_length, 1234.digits, 1234.digits(16), 0.digits, 15.ceil(-1), 15.floor(-1), 15.round(-1), 14.round(-1), -15.round(-1), 15.ceil, 15.to_i, 15.to_int, 15.truncate, 15.integer?, 15.ord, 15.abs2, 5.size, 5.coerce(2)
p 1.step(10, 3).to_a, 10.step(1, -4).to_a, 1.step(3).to_a, 1.step(10, 3).size, Integer.sqrt(24), Integer.sqrt(25), Integer.sqrt(0), 1.step(3).class
begin; 1.step(2, 0) { }; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; 256.chr; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; -1.digits; rescue => e; puts "#{e.class}: #{e.message}"; end
begin; Integer.sqrt(-1); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; 3.pow(2, 0); rescue => e; puts "#{e.class}: #{e.message}"; end
a = [1, 2, 3]
p a.fetch(1), a.fetch(-1), a.fetch(5, :d), a.fetch(5) { |i| i * 2 }
begin; a.fetch(5); rescue => e; puts "#{e.class}: #{e.message}"; end
begin; a.fetch(-5); rescue => e; puts "#{e.class}: #{e.message}"; end
p (1..10).step(3), (1..10).step(3).to_a, (1...10).step(3).to_a, ((1..10) % 3).to_a, (1..10).step(3).size, (1..).step(2).first(3), (1..10).step(3) { |x| print x }, 1.step(10, 3).first(2), 1.step(10, 3).last, 1.step(10, 3).size, 1.step(3) == 1.step(3), 1.step(nil, 2).inspect
p (1..10).step(-1), (1..10).step(-1).to_a, (1..10).step(-2).size
begin; (1..10).step(0); rescue => e; puts "#{e.class}: #{e.message}"; end
