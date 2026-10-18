# digest/bubblebabble defines bubblebabble with rb_define_module_function:
# a private instance method of Digest too, also when a file compiled at
# run time requires it.
require "digest"
require ["digest", "bubblebabble"].join("/")
p Digest.bubblebabble("_b_")
p Class.new.include(Digest).new.send(:bubblebabble, "_b_")
p Digest.private_instance_methods.sort
p Digest::SHA256.bubblebabble("x")[0, 11]
