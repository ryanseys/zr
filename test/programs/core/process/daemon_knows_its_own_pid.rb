# After Process.daemon the process is the forked daemon: $$ is its pid,
# and its parent is no longer the process that called it.
caller_pid = $$
IO.popen("-", "r+") do |io|
  if io
    Process.wait(io.pid)
    daemon, pid, parent = 3.times.map { Integer(io.gets) }
    p daemon == pid
    p parent != caller_pid
    p(begin
      Process.wait(daemon)
    rescue Errno::ECHILD => e
      e.class
    end)
    io.puts "go"
  else
    Process.daemon(false, true)
    puts $$, Process.pid, Process.ppid
    $stdout.flush
    $stdin.gets
  end
end
