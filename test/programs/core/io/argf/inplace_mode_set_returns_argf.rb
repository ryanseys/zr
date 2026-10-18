# argf_inplace_mode_set returns ARGF, for an extension and for nil.
a = ARGF.class.new
p a.send(:inplace_mode=, ".bak").equal?(a)
p a.inplace_mode
p a.send(:inplace_mode=, nil).equal?(a)
p a.inplace_mode
p((a.inplace_mode = ".x"))
