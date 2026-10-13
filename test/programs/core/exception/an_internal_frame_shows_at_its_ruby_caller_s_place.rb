# Code that an eval names `<internal:...>` (as RubyGems' Kernel#require
# is) shows in a backtrace as a C method does, at the file and line of
# the Ruby frame that called it. Of a run of such frames and C frames
# between two Ruby frames, the outermost internal frame stays, with the
# C frames outside it; the frames that it called drop out.
$stdout.sync = true
def short(rows) = rows.map { _1.sub(/\A.*\//, "") }

eval("def q = yield", nil, "<internal:fake>")
def m = q { short(caller(0)) }
p m

eval("def r = [1].each { yield }\ndef s = r { yield }", nil, "<internal:fake2>")
def t
  got = nil
  s { got = [short(caller(0)), caller_locations(0).map { [File.basename(_1.path), _1.lineno, _1.label] }] }
  got
end
p t

eval("def u = raise('boom')", nil, "<internal:fake3>")
begin
  u
rescue => e
  p short(e.backtrace)
  p e.backtrace_locations.map { [File.basename(_1.path), _1.lineno] }
end

eval("def v = [1].map { [2].each { yield } }", nil, "<internal:fake4>")
def w
  got = nil
  v { got = short(caller(0)) }
  got
end
p w

# Code that an internal eval runs shows at its caller.
p(eval("caller(0).first", nil, "<internal:top>").sub(/\A.*\//, ""))

# RubyGems' require is such a frame: the require shows at the caller's line.
dir = File.join(Dir.pwd, "tmp_internal_frames_#{$$}")
Dir.mkdir(dir)
File.write(File.join(dir, "internal_frames_lib.rb"), "LIB = [:x].map { caller_locations }[0].map { [File.basename(_1.path), _1.lineno, _1.label] }\n")
$LOAD_PATH.unshift(dir)
require "internal_frames_lib"
p LIB
File.delete(File.join(dir, "internal_frames_lib.rb"))
Dir.rmdir(dir)
