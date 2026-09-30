# A method body reassigns one of its parameters to a value of a
# different type: the call sites pass Integers, and the body writes
# a String. The parameter then holds the String.

class Logger
  def report(label, hclk)
    hclk = "forever" if hclk == 4294967295
    puts label
    puts hclk
  end
end

l = Logger.new
l.report("running", 1234)
l.report("running", 4294967295)
l.report("done", 17)
