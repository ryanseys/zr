# String#encode! checks that the receiver is not frozen before it reads
# its arguments, as str_encode_bang does.
def show(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

show("bad argument") { "x".freeze.encode!(1) }
show("unknown name") { "x".freeze.encode!("nope") }
show("unknown option value") { "x".freeze.encode!("UTF-8", invalid: :nope) }
show("thawed bad argument") { (+"x").encode!(1) }
show("thawed") { (+"x").encode!("UTF-16LE").bytes }
