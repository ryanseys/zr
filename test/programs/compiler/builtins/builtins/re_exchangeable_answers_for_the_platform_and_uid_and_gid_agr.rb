
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

# `re_exchangeable?` answers for the platform, so the golden checks that
# `re_exchange` AGREES with it rather than printing either answer.
[Process::UID, Process::GID].each do |m|
  swappable = m.re_exchangeable?
  agreed = begin
    m.re_exchange
    swappable
  rescue NotImplementedError
    !swappable
  rescue SystemCallError
    swappable
  end
  puts "#{m} re_exchange agrees: #{agreed}"
end
