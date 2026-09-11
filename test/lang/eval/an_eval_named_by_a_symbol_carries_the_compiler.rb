p send(:eval, "1 + 1")
p __send__(:eval, "2 + 2")
p "s".public_send(:instance_eval, "size")
p method(:eval).call("3 + 3")
String.send(:class_eval, "def zz = :zz")
p "q".zz

__END__
2
4
1
6
:zz
