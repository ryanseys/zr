system("true")
p $?.class, $?.success?
Thread.new { p $?, Process.last_status }.join
p Process.last_status.equal?($?)
require "English"
p $CHILD_STATUS.class
pid = spawn("exit 3"); Process.wait(pid); p $?.exitstatus, $?.pid == pid
Thread.new { system("exit 4"); p $?.exitstatus }.join
p $?.exitstatus
p Process.waitall
