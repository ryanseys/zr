# Four threads that never block share the CPU through the timer
# Tests: Thread, preemption at safe points, Thread#value

threads = Array.new(4) do |k|
  Thread.new do
    x = k
    i = 0
    while i < 3_000_000
      x = ((x * 31) + i) & 0xffff
      i += 1
    end
    x
  end
end
p threads.map(&:value)
