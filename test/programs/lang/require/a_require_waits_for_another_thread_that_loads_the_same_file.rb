# A require of a file that another thread is loading waits for it: it
# returns false when that load ends, and loads the file itself when that
# load raised. A require of a file that the same thread is loading
# returns false.
$rec = []
dir = File.join(Dir.pwd, "code")
p require(File.join(dir, "self_req.rb")), $rec
slow = File.join(dir, "slow.rb")
[false, true].each do |boom|
  $rec = []
  fin = false
  r1 = r2 = nil
  t2 = nil
  t1 = Thread.new do
    Thread.pass until t2
    Thread.current[:wait_for] = t2
    Thread.current[:boom] = boom
    r1 = begin
      require(slow)
    rescue => e
      e.message
    end
    Thread.pass until fin
    $rec << :t1_post
  end
  t2 = Thread.new do
    Thread.pass until t1[:in]
    begin
      r2 = require(slow)
      $rec << :t2_post
    ensure
      fin = true
    end
  end
  t1.join
  t2.join
  p [r1, r2, $rec]
  $LOADED_FEATURES.delete(slow)
end
