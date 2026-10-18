# With an OS thread for each thread (ZR_THREADS=native in the .env), a
# blocking FFI call and a Fiddle call run without the GVL: the other
# threads run meanwhile, a callback takes the GVL back, and a kill ends
# the call's sleep. A call that keeps the GVL stops the others.
require "ffi"
require "fiddle"

module C
  extend FFI::Library
  ffi_lib FFI::Library::LIBC
  attach_function :usleep, [:uint], :int, blocking: true
  attach_function :usleep_held, :usleep, [:uint], :int
  callback :compare, [:pointer, :pointer], :int
  attach_function :qsort, [:pointer, :size_t, :size_t, :compare], :void, blocking: true
end

ticks = 0
ticker = Thread.new do
  loop do
    ticks += 1
    sleep 0.005
  end
end
sleep 0.02

before = ticks
C.usleep(200_000)
p ticks - before >= 3

before = ticks
C.usleep_held(100_000)
p ticks - before <= 1

nap = Fiddle::Function.new(Fiddle::Handle::DEFAULT["usleep"], [Fiddle::TYPE_INT], Fiddle::TYPE_INT)
before = ticks
nap.call(200_000)
p ticks - before >= 3

numbers = [5, 3, 9, 1, 7, 2]
buffer = FFI::MemoryPointer.new(:int, numbers.size)
buffer.write_array_of_int(numbers)
order = proc { |a, b| a.read_int <=> b.read_int }
C.qsort(buffer, numbers.size, 4, order)
p buffer.read_array_of_int(numbers.size)

sleeper = Thread.new { C.usleep(5_000_000) }
sleep 0.1
started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
sleeper.kill
sleeper.join
p sleeper.status, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 2

ticker.kill
ticker.join
