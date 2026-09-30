# The P-B core classes: File, Dir, Time, Process, ENV.
#
# Everything here is zone- and machine-independent on purpose: Time uses a
# fixed epoch read in UTC, paths are built under a scratch directory this
# script creates, and nothing prints a real pid/clock/environment value --
# only facts about them. That is what lets the output be diffed against real
# ruby at all.

# --- Errors: the Errno family, with CRuby's message shape ------------------
begin
  File.read("/definitely/not/here")
rescue Errno::ENOENT => e
  puts "#{e.class}: #{e.message}"
end
p Errno::ENOENT.superclass
p Errno::ENOENT.ancestors.include?(StandardError)

begin
  Dir.entries("/definitely/not/here")
rescue SystemCallError => e     # caught by the PARENT class
  puts e.class
end

