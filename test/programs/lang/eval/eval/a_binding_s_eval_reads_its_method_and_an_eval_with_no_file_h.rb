def bm = binding
p bm.eval("__method__")
p eval("__dir__"), binding.eval("__dir__"), eval("__dir__", nil, "/tmp/x/y.rb")
