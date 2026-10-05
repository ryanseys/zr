# After an autoload's file runs, ruby reads the name again: a constant
# that the file made private raises, a deprecated one warns, and a file
# that does not define the name warns under $VERBOSE. Other threads that
# read the name while the file loads wait for it, and a forked child
# reads the file itself.
require "stringio"

def warnings
  $stderr = StringIO.new
  yield
  $stderr.string.gsub(__dir__, "DIR")
ensure
  $stderr = STDERR
end

class PrivateAfterLoad
  autoload :ZZZ, File.expand_path("autoload_checks/private", __dir__)
end
begin
  PrivateAfterLoad::ZZZ
  p :no_error
rescue NameError => e
  p [e.class, e.message]
end

class DeprecatedAfterLoad
  autoload :ZZZ, File.expand_path("autoload_checks/deprecated", __dir__)
end
Warning[:deprecated] = true
p(warnings { DeprecatedAfterLoad::ZZZ })

$VERBOSE = true
module Namespace
  autoload :Elsewhere, File.expand_path("autoload_checks/elsewhere", __dir__)
  p(warnings { p Elsewhere })
end
$VERBOSE = false

autoload :SlowToLoad, File.expand_path("autoload_checks/slow", __dir__)
threads = Array.new(3) { Thread.new { SlowToLoad } }
p threads.map(&:value)

# A child forked while another thread reads the file reads it again.
autoload :SlowInAFork, File.expand_path("autoload_checks/forked", __dir__)
threads = []
2.times do
  threads << Thread.new { SlowInAFork && nil }
  threads << Thread.new { fork { SlowInAFork } }
end
threads.each(&:join)
p(threads.filter_map { |t| (pid = t.value) && Process.waitpid2(pid)[1].success? })

# Two threads read two names that one file defines. The second waits for
# the first thread's require, and does not see the name as provided early.
race = File.expand_path("autoload_checks/race.rb", __dir__)
failures = 0
50.times do
  autoload :RaceFoo, race
  autoload :RaceBar, race
  t1 = Thread.new { RaceFoo }
  t2 = Thread.new { RaceBar }
  t1.join
  begin
    t2.join
  rescue NameError
    failures += 1
  end
  Object.send(:remove_const, :RaceFoo)
  Object.send(:remove_const, :RaceBar)
  $LOADED_FEATURES.delete(race)
end
p failures
