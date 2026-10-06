# Under $DEBUG an exception that ends a thread goes on in the main
# thread; and as the program ends, the main thread is done before the
# other threads' ensure clauses run.
$stdout.sync = true
t = Thread.new do
  Thread.current.report_on_exception = false
  Thread.stop
  raise "in thread"
end
Thread.pass until t.stop?
begin
  $DEBUG = true
  t.run
  Thread.pass while t.alive?
  sleep 0.1
  p 1
rescue => e
  $DEBUG = false
  p [2, e.message]
end
$DEBUG = false

q = Thread::Queue.new
Thread.new(Thread.current) do |main|
  q.push nil
  main.run
  Thread.pass until main.stop?
  p :main_stopped
ensure
  puts "#{main.alive?} #{main.status.inspect} #{main.stop?} #{Thread.current.status}"
end
q.pop
