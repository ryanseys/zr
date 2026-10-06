begin; Enumerator::Yielder.new; rescue => e; p e.class, e.message; end
p Enumerator.new { |y| y << 1 << 2; y.yield 3 }.to_a
