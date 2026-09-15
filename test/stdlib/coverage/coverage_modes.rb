# Coverage's modes: lines and oneshot_lines as hashes of targets, the
# counts a suspend leaves out, a result that keeps measuring, and the
# errors each state refuses with.
require "coverage"

Coverage.setup(lines: true)
p Coverage.state
require_relative "coverage_modes/lib_a"
twice(1)
Coverage.resume
twice(2)
pick(true)
Coverage.suspend
pick(false)
p((Coverage.suspend rescue $!))
Coverage.resume
p((Coverage.resume rescue $!))
p((Coverage.setup rescue $!))
kept = Coverage.result(stop: false, clear: true)
kept.each { |path, value| p [File.basename(path), value] }
p Coverage.state
twice(3)
p Coverage.peek_result.transform_keys { |path| File.basename(path) }
Coverage.result
p Coverage.state

Coverage.start(oneshot_lines: true)
require_relative "coverage_modes/lib_b"
tally = Tally.new
3.times { tally.add }
Coverage.result.each { |path, value| p [File.basename(path), value] }

p((Coverage.start(lines: true, oneshot_lines: true) rescue $!))
p Coverage.state
p((Coverage.resume rescue $!))
p [Coverage.supported?(:branches), Coverage.supported?(:all)]

__END__
:suspended
#<RuntimeError: coverage measurement is not running>
#<RuntimeError: coverage measurement is already running>
#<RuntimeError: coverage measurement is already setup>
["lib_a.rb", {lines: [0, 1, nil, nil, 0, 1, 1, nil, 0, nil, nil]}]
:running
{"lib_a.rb" => {lines: [0, 1, nil, nil, 0, 0, 0, nil, 0, nil, nil]}}
:idle
["lib_b.rb", {oneshot_lines: [1, 2, 4, 5]}]
#<RuntimeError: cannot enable lines and oneshot_lines simultaneously>
:idle
#<RuntimeError: coverage measurement is not set up yet>
[true, false]
