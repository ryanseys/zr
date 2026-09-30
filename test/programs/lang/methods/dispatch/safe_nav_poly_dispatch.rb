# safe navigation on a receiver of more than one class must call the method
# of the receiver's class, not drop it and return the receiver.
class Flag
  def fn? = false
  def name = "flg"
end
class Crash
  def parse(argument)
    @flags = [Flag.new]
    @flags.first&.fn?
  end
end
raise "FAIL" unless !Crash.new.parse("-qv")

arr = [Object.new, "hello", 42, nil]
p arr[1]&.upcase
p arr[2]&.to_s
p arr[3]&.length
p arr[1]&.length
flags = [Flag.new]
p flags.first&.fn?
p flags.first&.name
p [].first&.fn?
puts "OK"
