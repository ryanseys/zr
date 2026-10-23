# zlib inflates without the GVL (zstream_run_once_begin), so a thread that
# waits takes its turn at each zlib call: a Thread.pass to an inflating
# thread comes back at once, not after its time slice.
require "zlib"
require "stringio"
t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
gzipped = Zlib.gzip("abc" * 2000)
50.times do
  thr = Thread.new { loop { Zlib::GzipReader.new(StringIO.new(gzipped)).read } }
  10.times { thr.wakeup; Thread.pass }
  sleep 0.001
  thr.kill
  thr.join
end
el = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
# Time slices would take 50 s; a busy host takes a few.
puts el < 20 ? "fast" : "slow #{el}"
