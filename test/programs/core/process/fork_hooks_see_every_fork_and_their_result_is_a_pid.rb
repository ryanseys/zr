# Process._fork is the one hook that fork, Process.fork and
# IO.popen("-") call; a hook that wraps it sees each fork, its result
# must be a pid, and the child knows its own pid as $$.
module Hook
  class << self
    attr_accessor :mode, :log
  end

  def _fork
    case Hook.mode
    when :wrong then "BOO"
    else
      Hook.log << :before
      pid = super
      Hook.log << (pid.zero? ? :child : :parent)
      raise "raised in the child" if Hook.mode == :raise && pid.zero?

      pid
    end
  end
end
Process.singleton_class.prepend(Hook)

def forked(label)
  Hook.log = []
  r, w = IO.pipe
  pid = yield(w)
  w.close
  child = r.read
  Process.waitpid(pid) if pid
  puts "#{label}: parent #{Hook.log.inspect}, child #{child}"
end

forked("fork") { |w| fork { w.print Hook.log.inspect, " ", $$ == Process.pid; exit!(0) } }
forked("Process.fork") { |w| Process.fork { w.print Hook.log.inspect; exit!(0) } }
forked("fork no block") do |w|
  pid = fork
  unless pid
    w.print Hook.log.inspect, " ", $$ == Process.pid && $$ != Process.ppid
    exit!(0)
  end
  pid
end
forked("Process._fork") do |w|
  pid = Process._fork
  if pid.zero?
    w.print $$ == Process.pid
    exit!(0)
  end
  pid
end
Hook.log = []
IO.popen("-") do |io|
  if io
    puts "popen: #{io.read} #{Hook.log.inspect}"
  else
    print Hook.log.inspect
  end
end

Hook.mode = :wrong
begin
  fork
rescue TypeError => e
  p [e.class, e.message]
end

# A hook that raises in the child ends the child with the error, past
# the rescue around fork; the parent goes on.
Hook.mode = :raise
Hook.log = []
begin
  pid = fork { puts "child block" }
  Process.waitpid(pid)
  puts "parent #{$?.exitstatus} #{Hook.log.inspect}"
rescue RuntimeError
  puts "rescued"
end
