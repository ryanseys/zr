# A conversion error names true, false and nil by their inspect, as
# rb_no_implicit_conversion does, never by their class (TrueClass).
require "coverage"
require "ripper"
require "nkf"
require "date"

def show
  yield
rescue StandardError => e
  puts "#{e.class}: #{e.message}"
else
  puts "no error"
end

[true, false, nil].each do |v|
  show { ENV[v] }
  show { ENV.fetch(v) }
  show { File.exist?(v) }
  show { File.open(__FILE__, v) {} }
  show { IO.read(__FILE__, open_args: v) }
  show { "é".encode("US-ASCII", fallback: { "é" => v }) }
  show { Ripper.dedent_string(v, 1) }
  show { Ripper.new(v) }
  show { NKF.nkf("-w", v) }
end
[true, false].each { |v| show { Coverage.setup(v) } }
Coverage.setup
[true, false].each { |v| show { Coverage.result(v) } }
[true, false].each do |v|
  rand_gives = Object.new.tap { |o| o.define_singleton_method(:rand) { |*| v } }
  show { "a".scrub(v) }
  show { Date._parse(v) }
  show { [1, 2].shuffle(random: rand_gives) }
  show { Process.spawn({ v => "x" }, "true") }
end
