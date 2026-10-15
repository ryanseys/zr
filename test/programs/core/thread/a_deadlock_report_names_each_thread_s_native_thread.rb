# The fatal deadlock error lists each live thread with its native
# thread's address, as debug_deadlock_check prints it.
queue = Queue.new
begin
  queue.pop
rescue Exception => e
  puts e.message.gsub(/0x\h+/, "0xADDR")
end
