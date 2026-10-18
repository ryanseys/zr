# A command with no word in it -- `system("")` or `system(" ")` -- still names
# a program: the empty name, which no directory holds. ruby's exec answers
# ENOENT, so `system` reports 127 and `exception: true` raises it.
#
# zr split the command into NO words and handed the spawn an empty list, so
# the kernel read a program name that was not there: signal 11.

def refusal(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

refusal("system('')") { [system(""), $?&.exitstatus, $?&.success?] }
refusal("system(' ')") { [system(" "), $?&.exitstatus] }
refusal("system('', exception: true)") { system("", exception: true) }
refusal("spawn('')") { Process.spawn("") }
refusal("backtick('')") { `` }

# The neighbouring argument guards, which the same helper decides.
refusal("system(nil)") { system(nil) }
refusal("system('true', 1)") { system("true", 1) }
refusal("system()") { system }

# A command that is only a shell word still reaches the shell, whose
# syntax error each shell words its own way.
refusal("system(';')") { [system(";", err: File::NULL), $?&.exitstatus] }

