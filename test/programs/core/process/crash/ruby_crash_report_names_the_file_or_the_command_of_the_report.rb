# RUBY_CRASH_REPORT names where the bug report goes. %p is the pid, %t
# the time, %f the main script's base name and %F its path with each
# slash as `!`, %% a percent sign, and %NNN the byte of an octal code.
# The file is made, or emptied first. A template that starts with `|`
# runs a command that reads the report: its first word is a path, which
# ruby does not search for. When the file cannot be made, or the command
# does not start, the report goes to stderr.
require "tmpdir"

def crash(template)
  r, w = IO.pipe
  pid = fork do
    r.close
    $stderr.reopen(w)
    $stdout.reopen(File::NULL)
    ENV["RUBY_CRASH_REPORT"] = template
    Process.kill(:SEGV, $$)
  end
  w.close
  text = r.read
  Process.wait(pid)
  [pid, text]
end

Dir.mktmpdir do |dir|
  Dir.chdir(dir) do
    pid, err = crash("%%crash.%p.%101.log")
    p err
    p File.exist?("%crash.#{pid}.A.log")
    report = File.read("%crash.#{pid}.A.log")
    p report.lines[1] == "#{RUBY_DESCRIPTION}\n", report.include?("-- Ruby level backtrace information")

    _, err = crash("time.%t.log")
    p err, Dir["time.*.log"].map { it.match?(/\Atime\.\d+\.log\z/) }

    script = File.basename(__FILE__)
    _, err = crash("by.%f.log")
    p err, File.exist?("by.#{script}.log")

    File.write("old.log", "x" * 100_000)
    _, err = crash("old.log")
    p err, File.read("old.log").start_with?("x"), File.read("old.log").include?("[BUG] Segmentation fault")

    # An octal code of zero ends the name.
    _, err = crash("cut.log%0rest")
    p err, File.exist?("cut.log")

    _, err = crash("|/usr/bin/tee  -a piped.log")
    p err
    p File.read("piped.log").include?("[BUG] Segmentation fault")

    _, err = crash("|tee x.log")
    p err.lines.first, err.include?("[BUG] Segmentation fault"), File.exist?("x.log")

    _, err = crash("no/such/dir/x.log")
    p err.include?("[BUG] Segmentation fault")

    _, err = crash("")
    p err.include?("[BUG] Segmentation fault")
  end
end
