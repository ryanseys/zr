# A signal that comes while the scheduler changes its lists of sleepers
# runs its command after, so the lists stay whole: threads that sleep
# and are woken while another process keeps signalling all finish.
count = 0
trap(:USR1) { count += 1 }
stop = false
sleepers = Array.new(100) do
  Thread.new do
    n = 0
    until stop
      sleep 10
      n += 1
    end
    n
  end
end
Thread.pass until sleepers.all?(&:stop?)
signaller = spawn("sh", "-c", "i=0; while [ $i -lt 3000 ]; do kill -USR1 #{Process.pid}; i=$((i+1)); done")
kicker = Thread.new do
  i = 0
  until stop
    begin
      sleepers[i % 100].wakeup
    rescue ThreadError
      nil
    end
    i += 1
  end
end
Process.wait(signaller)
stop = true
kicker.join
sleepers.each do |t|
  t.wakeup
rescue ThreadError
  nil # it has ended already
end
p sleepers.map(&:value).all?(&:positive?)
p count.positive?
