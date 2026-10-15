# File.open and IO.new read a mode given as an argument before they
# refuse a second mode: a bad access mode raises its own error, and an
# unknown encoding warns, before "mode specified twice".
["abc", "rw", "r:bogus", "z", 0, "w"].each { |m| [{mode: ""}, {mode: "r"}, {flags: 1}, {}].each { |o| begin; File.open("/dev/null", m, **o) {}; rescue => e; p [m, o, e.class, e.message]; else p [m, o, :ok]; end } }
["abc", "r:bogus"].each { |m| begin; IO.new(1, m, mode: "w"); rescue => e; p [m, e.class, e.message]; end }
