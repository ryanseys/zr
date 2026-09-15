# native only: Math.expm1 has no wasm form
# The core methods a census against ruby found missing: numbers,
# reflection, Symbol, Array, Hash, Proc and %a.
p Math.expm1(1e-10), Math.log1p(1e-10), Math.log1p(-1)
begin
  Math.log1p(-2)
rescue Math::DomainError => e
  puts e.message
end
p Integer.try_convert("3"), Integer.try_convert(3), Integer.try_convert(3.7), Integer.try_convert(nil)
begin
  2.pow(3, 2.0)
rescue TypeError => e
  puts e.message
end
begin
  2.pow(3.0, 5)
rescue TypeError => e
  puts e.message
end
p 2.pow(10, 7), 5.remainder(3), (-5).remainder(3)

class Money < Numeric
  def initialize(cents) = @cents = cents
  def ==(other) = other.is_a?(Money) && other.cents == @cents
  protected def cents = @cents
end
a = Money.new(1)
p a.clone.equal?(a), a.dup.equal?(a), a.eql?(Money.new(1)), a.eql?(1), (a <=> a), (a <=> Money.new(1))
begin
  a.clone(freeze: false)
rescue ArgumentError => e
  puts e.message
end

p :abc.next, :az.succ, :abc.slice(0, 2), :abc[1], :abc.match?(/b/), (:abc =~ /b/)
p :abc.match(/(b)/)[1], Symbol.all_symbols.include?(:abc)
p [1, 2, 3].fetch_values(0, 2), [1, 2, 3].fetch_values, [1, 2, 3].fetch_values(0, 5) { |i| i * 10 }
begin
  [1, 2, 3].fetch_values(0, 5)
rescue IndexError => e
  puts e.message
end
p [1, 2, 3].rfind { |x| x.even? }, [1, 2, 3].rfind { false }, [1, 2, 3].rfind.class
p Hash.ruby2_keywords_hash({ a: 1 }), Hash.ruby2_keywords_hash?({}), Hash.ruby2_keywords_hash?(Hash.ruby2_keywords_hash({}))

square = ->(x) { x * x }
p square == square.dup, square == ->(x) { x * x }, square.hash == square.dup.hash
p square.eql?(square.dup)

p format("%a", 1.0), format("%a", 0.5), format("%a", 255.5), format("%a", 0.0), format("%a", -0.0)
p format("%A", 3.14159), format("%a", 1.0 / 0), format("%a", 0.0 / 0)
p format("%.3a", 3.14159), format("%.0a", 1.9375), format("%.0a", 1.5), format("%.1a", 1.03125)
p format("%.20a", 1.0 / 3), format("%#.0a", 3.0), format("%020a", -1.5), format("%-14a|", 1.5), format("%+a", 1.5)
p format("%a", 2.0**-1074), format("%a", 1e-310)

p (..10).bsearch { |x| x >= 4 }, (..10).bsearch { |x| x >= 20 }, (...10).bsearch { |x| x >= 4 }
p (1..).bsearch { |x| x * x >= 49 }, (1.0..).bsearch { |x| x >= 4.5 }, (..0.0).bsearch { |x| x >= -4.5 }
p (0.0..).bsearch { |x| x >= 1e300 }, (-Float::INFINITY..0.0).bsearch { |x| x >= -4.5 }
p loop.size, (1..).step(2).size

p Encoding.locale_charmap, Exception.to_tty?
t = Time.at(1_234_567_890, in: "+05:30")
p t.iso8601, t.iso8601(6), t.xmlschema(1), t.deconstruct_keys([:year, :hour])
p Time.at(0).utc.iso8601, Time.at(0).utc.deconstruct_keys(nil)[:zone]
p GC.total_time.is_a?(Integer), GC.measure_total_time, GC.auto_compact, GC.config
p GC.compact.keys, GC.stat_heap(0).keys.first, GC.verify_internal_consistency
p 12.34.display, $>.equal?($stdout)
