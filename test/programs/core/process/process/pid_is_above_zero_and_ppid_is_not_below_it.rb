# Process.pid and Process.ppid come from getpid and
# getppid. Values vary by run; test the range. ppid is 0 on
# Windows where MinGW lacks getppid, >= 0 elsewhere.
puts Process.pid > 0
puts Process.ppid >= 0
