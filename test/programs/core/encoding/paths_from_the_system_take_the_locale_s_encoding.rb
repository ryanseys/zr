# Under an EUC-JP locale, a path that the system gives is in the locale's
# encoding: the main file's name ($0, __FILE__, __dir__, its backtrace
# lines and caller paths) and a directory's entries. The working
# directory too, and File.expand_path stays UTF-8, as ruby gives it on
# darwin.

def encoding_of(value) = value.encoding.to_s

p [encoding_of($0), encoding_of(__FILE__), encoding_of(__dir__)]
p Dir.children(__dir__).map(&:encoding).uniq.map(&:to_s)
p [encoding_of(Dir.pwd), encoding_of(File.expand_path("x"))]
p encoding_of(caller_locations(0).first.path)
p encoding_of((raise "x" rescue $!.backtrace.first))
