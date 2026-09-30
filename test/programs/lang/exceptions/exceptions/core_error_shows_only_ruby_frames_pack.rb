# A pack or unpack that raises shows the frame of the method the program
# called, and none of the helpers zr keeps for itself: CRuby does that
# work in C, with no frame and no constant a program can see.

def show
  yield
rescue => e
  puts "#{e.class}: #{e.message}"
  puts e.backtrace
end

show { "abc".unpack("@9") }
show { "abc".unpack1("x9") }
show { [1].pack(1) }
show { [1].pack("y") }
show { "abc".unpack("m0") }
p Object.constants.include?(:Packing)

