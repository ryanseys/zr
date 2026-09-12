# A command with no word in it -- `system("")` or `system(" ")` -- still names
# a program: the empty name, which no directory holds. ruby's exec answers
# ENOENT, so `system` reports 127 and `exception: true` raises it.
#
# ze0 split the command into NO words and handed the spawn an empty list, so
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

# A command that is only a shell word still reaches the shell.
refusal("system(';')") { [system(";"), $?&.exitstatus] }

__END__
system(''): [nil, 127, false]
system(' '): [nil, 127]
system('', exception: true): Errno::ENOENT: No such file or directory - 
spawn(''): Errno::ENOENT: No such file or directory - 
backtick(''): Errno::ENOENT: No such file or directory - 
system(nil): TypeError: no implicit conversion of nil into String
system('true', 1): TypeError: no implicit conversion of Integer into String
system(): ArgumentError: wrong number of arguments (given 0, expected 1+)
system(';'): [false, 2]
#@ stderr
sh: -c: line 0: syntax error near unexpected token `;'
sh: -c: line 0: `;'
