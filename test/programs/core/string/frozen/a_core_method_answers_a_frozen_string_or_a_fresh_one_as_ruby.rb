# Each answer's frozen? beside the expression that made it: the core's
# literals are frozen, so a method that answers one must answer what
# ruby's C answers, a fresh String or a frozen one.
Point = Struct.new(:x)
Pair = Data.define(:a)
answers = {
  "nil.to_s" => nil.to_s, "true.to_s" => true.to_s, "false.to_s" => false.to_s,
  "nil.inspect" => nil.inspect, "true.inspect" => true.inspect,
  "1.to_s" => 1.to_s, "12.to_s(2)" => 12.to_s(2), "(2**70).to_s" => (2**70).to_s,
  "1.5.to_s" => 1.5.to_s, "Float::INFINITY.to_s" => Float::INFINITY.to_s, "Float::NAN.inspect" => Float::NAN.inspect,
  "(0.0/-1).to_s" => (0.0 / -1).to_s,
  "Rational(1, 2).to_s" => Rational(1, 2).to_s, "Complex(1, 2).to_s" => Complex(1, 2).to_s,
  "Complex(1, 2).inspect" => Complex(1, 2).inspect,
  ":a.to_s" => :a.to_s, ":a.name" => :a.name, ":a.inspect" => :a.inspect,
  "[1].inspect" => [1].inspect, "[].inspect" => [].inspect, "[].join" => [].join, "[1, 2].join" => [1, 2].join,
  "{}.inspect" => {}.inspect, "{a: 1}.to_s" => { a: 1 }.to_s,
  "(1..2).to_s" => (1..2).to_s, "(1..2).inspect" => (1..2).inspect,
  "Point.new(1).inspect" => Point.new(1).inspect, "Pair.new(a: 1).inspect" => Pair.new(a: 1).inspect,
  "Encoding::UTF_8.name" => Encoding::UTF_8.name, "Encoding::UTF_8.to_s" => Encoding::UTF_8.to_s,
  "Encoding::UTF_8.inspect" => Encoding::UTF_8.inspect, "Encoding::UTF_8.names.first" => Encoding::UTF_8.names.first,
  "Encoding.name_list.first" => Encoding.name_list.first, "Encoding.locale_charmap" => Encoding.locale_charmap,
  "ARGF.to_s" => ARGF.to_s, "ARGF.filename" => ARGF.filename,
  "$stdout.inspect" => $stdout.inspect, "Thread.current.status" => Thread.current.status,
  "Thread.current.inspect.class" => Thread.current.inspect,
  "RuntimeError.new.message" => RuntimeError.new.message, "StandardError.new.message" => StandardError.new.message,
  "a core raise's message" => (begin; [].first(-1); rescue => e; e.message; end),
  "a ZeroDivisionError's message" => (begin; 1 / 0; rescue => e; e.message; end),
  "a KeyError's message" => (begin; {}.fetch(:k); rescue => e; e.message; end),
  "a TypeError's message" => (begin; 1 + nil; rescue => e; e.message; end),
  "File.basename" => File.basename("/a/b.rb"), "File.extname" => File.extname("a.rb"), "File.extname('a')" => File.extname("a"),
  "File.dirname" => File.dirname("a"), "File.join" => File.join("a", "b"), "File.expand_path('/')" => File.expand_path("/"),
  "File::SEPARATOR" => File::SEPARATOR, "RUBY_VERSION" => RUBY_VERSION,
  "format" => format("%d", 1), "'%s' % 1" => "%s" % 1, "[1].pack('C')" => [1].pack("C"), "[].pack('C*')" => [].pack("C*"),
  "65.chr" => 65.chr, "200.chr" => 200.chr, "'ab'.b" => "ab".b, "'abc'[0]" => "abc"[0],
  "Time.at(0).utc.zone" => Time.at(0).utc.zone, "Time.at(0).utc.to_s" => Time.at(0).utc.to_s,
  "Time.at(0).utc.inspect" => Time.at(0).utc.inspect, "strftime" => Time.at(0).utc.strftime("%Y"),
  "strftime('')" => Time.at(0).utc.strftime(""),
  "Signal.signame(2)" => Signal.signame(2), "Signal.list.keys.first" => Signal.list.keys.first,
  "Comparable.name" => Comparable.name, "Integer.to_s" => Integer.to_s, "Integer.inspect" => Integer.inspect,
  "Process.clock_gettime unit" => Process.clock_gettime(Process::CLOCK_MONOTONIC, :float_second).class.name,
  "''.center(3)" => "".center(3), "'a'.ljust(1)" => "a".ljust(1), "'a' * 0" => "a" * 0,
  "[nil].join" => [nil].join, "[[1]].to_s" => [[1]].to_s,
  "1.0.round.to_s" => 1.0.round.to_s, "Integer.sqrt(4).to_s" => Integer.sqrt(4).to_s,
  "Random.new(1).bytes(0)" => Random.new(1).bytes(0),
  "'é'.unicode_normalize" => "é".unicode_normalize, "'a'.encode('UTF-16LE')" => "a".encode("UTF-16LE"),
  "GC.stat.keys.first.to_s" => GC.stat.keys.first.to_s, "ObjectSpace.count_objects.keys.first.to_s" => ObjectSpace.count_objects.keys.first.to_s,
  "__method__.to_s" => __method__.to_s, "Set[1].inspect" => Set[1].inspect, "Set[].to_s" => Set[].to_s
}
answers.each { |name, value| puts "#{name}: #{value.is_a?(String) ? value.frozen? : value.class}" }
