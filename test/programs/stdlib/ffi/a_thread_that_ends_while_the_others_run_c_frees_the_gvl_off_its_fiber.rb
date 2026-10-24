# A thread that ends while every other thread runs C without the GVL
# frees the GVL only once its OS thread is off the fiber's stack: the
# thread that takes the GVL next can collect that fiber. Each thread
# here naps in a blocking Fiddle call, runs the collection and ends; no
# object refers to a thread that ended.
require "fiddle"

nap = Fiddle::Function.new(Fiddle::Handle::DEFAULT["usleep"], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
40.times do
  ended = 0
  32.times { |i| Thread.new { nap.call(50 + (i * 37 % 400)); GC.start; ended += 1 } }
  nap.call(1_000) until ended == 32
end
p :ok
