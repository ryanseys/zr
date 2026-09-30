# A call's argument values stay alive while its other arguments are
# evaluated. Each case puts a fresh heap string in one argument, beside
# an argument whose evaluation makes a collection run.

def churn_gc(x)
  GC.start
  i = 0
  s = ""
  while i < 8000
    s = s + i.to_s + ","
    i += 1
  end
  x
end

def join2(a, b)
  a + "|" + b
end

class Joiner
  def join2(a, b)
    a + "|" + b
  end
end

# top-level method call
puts join2(churn_gc("A"), "B_" + 1.to_s)
# instance method call
puts Joiner.new.join2(churn_gc("C"), "D_" + 2.to_s)
# sprintf / string interpolation
label = "E"
puts "[#{churn_gc("F")}|#{label + "_" + 3.to_s}]"
