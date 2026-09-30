p [1.5].pack("D").bytes
p [1.5].pack("G").bytes
p [3.14].pack("d").unpack("d")
p [1].pack("l!").bytesize
p [1].pack("i").bytesize
p [1].pack("j").bytesize
p ["hello world"].pack("M")
p ["hi there folks"].pack("u").unpack("u")
p(["hi there folks"].pack("u").unpack("u") == ["hi there folks"])
