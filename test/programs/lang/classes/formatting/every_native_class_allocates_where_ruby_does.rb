# `Class#allocate` answers a blank instance for every native class ruby
# allocates, and refuses for every one ruby refuses -- with ruby's own error
# class each time.
#
# `Marshal.load` allocates before it fills, so it needs a blank instance of
# each class it loads.
#
# The three shapes ruby uses, and zr too:
#
#   * a blank instance, for a class whose payload has an empty form;
#   * `TypeError: allocator undefined for X`, for a class with no blank;
#   * `NoMethodError: undefined method 'allocate' for class X`, for the five
#     ruby UNDEFINES the name on. The two
#     refusals are not interchangeable: `rescue TypeError` around
#     `MatchData.allocate` catches nothing.

%w[date set stringio strscan pathname time bigdecimal zlib socket monitor
   objspace digest etc].each { |f| require f }

NAMES = %w[
  Array Hash String Range Regexp MatchData Object BasicObject Rational Complex
  Struct Data Time Date DateTime Set StringIO StringScanner Pathname BigDecimal
  Dir File IO Encoding Enumerator Enumerator::Lazy Method UnboundMethod Proc
  Binding Module Class Thread Mutex Queue SizedQueue ConditionVariable
  ThreadGroup Fiber Random ObjectSpace::WeakMap Digest::MD5 Zlib::Deflate
  Zlib::Inflate Socket TCPSocket Etc::Passwd Process::Status Exception
  RuntimeError Errno::ENOENT TracePoint Symbol Integer Float
]

NAMES.each do |n|
  k = Object.const_get(n)
  row = begin
          # `BasicObject` has no `#class`, so name the class we asked rather
          # than the one the instance reports.
          k.allocate
          "ok"
        rescue ScriptError, StandardError => e
          "#{e.class}: #{e.message}"
        end
  puts "#{n}\t#{row}"
end

# The undef is INHERITED, because ruby's sits on the singleton chain.
sub = Class.new(MatchData)
begin
  sub.allocate
  puts "subclass\tallocated"
rescue NoMethodError => e
  puts "subclass\t#{e.class}"
end

# And it is a genuinely absent method, not a raising one.
puts "respond_to?\t#{[Rational, Complex, MatchData, Module].map { |k| k.respond_to?(:allocate) }.uniq.inspect}"

# A blank reports its own class, including where the payload alone could not
# say which one it is (`File` and the sockets share `IO`'s).
puts "classes\t#{[File, IO, Socket, TCPSocket, Date, DateTime, Queue, SizedQueue].map { |k| k.allocate.class }.inspect}"
