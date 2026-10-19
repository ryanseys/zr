# A thread that inflates in a loop is woken and killed many times, as in
# CRuby's TestZlib#test_thread_wakeup_interrupt. zlib's own C inflates
# without the GVL, and the kill must wait for it.
require "zlib"
require "stringio"

gz = Zlib.gzip("a" * 100_000)
200.times do
  t = Thread.new { loop { Zlib::GzipReader.new(StringIO.new(gz)).read } }
  10.times { t.wakeup }
  sleep 0.001
  t.kill
  t.join
end
GC.start
p Zlib::GzipReader.new(StringIO.new(gz)).read.size
