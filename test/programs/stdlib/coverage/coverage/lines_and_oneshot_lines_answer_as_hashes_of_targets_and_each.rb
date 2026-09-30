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

