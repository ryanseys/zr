
# `Process::Sys`, `Process::UID` and `Process::GID` -- the identity surface.
#
# Every id printed here is compared against one the process already knows,
# never printed raw, so the output is the same on any machine. Nothing in
# this file can change an id: an unprivileged process may only re-assert the
# ids it already holds, and every other request is refused.

uid = Process.uid
euid = Process.euid
gid = Process.gid
egid = Process.egid

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue Exception => e # rubocop:disable Lint/RescueException
  puts "#{label}: #{e.class}: #{e.message}"
end

# The shape: all three are modules, and every name but the two `eid=`
# writers is a `module_function` -- a singleton method AND a private
# instance method, so `include Process::Sys` carries them too.
[Process::Sys, Process::UID, Process::GID].each do |m|
  puts "#{m} class: #{m.class}"
  puts "#{m} singleton: #{m.singleton_methods(false).sort.inspect}"
  puts "#{m} private: #{m.private_instance_methods(false).sort.inspect}"
  puts "#{m} public instance: #{m.instance_methods(false).inspect}"
end
puts "Sys respond_to?: #{Process::Sys.respond_to?(:setuid)}"
puts "Sys included: #{Class.new { include Process::Sys }.new.send(:getuid) == uid}"

