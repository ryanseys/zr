# A `return` in an eval leaves the innermost lambda around the eval, also
# when the method that made the lambda has returned. In a Proc whose
# method has returned, there is nothing to leave.
def orphan_lambda = lambda { eval("return :ok") }

def orphan_proc = proc { eval("return :ng") }

p orphan_lambda.call
p((orphan_proc.call rescue $!.class))

def inside
  l = lambda do
    eval("return :from_lambda")
    :not_here
  end
  [l.call, :after]
end
p inside

def nested
  l = lambda do
    [1, 2].each { |i| eval("return i * 10") }
    :not_here
  end
  l.call
end
p nested

def through_a_proc
  pr = proc { eval("return :from_method") }
  pr.call
  :not_here
end
p through_a_proc
