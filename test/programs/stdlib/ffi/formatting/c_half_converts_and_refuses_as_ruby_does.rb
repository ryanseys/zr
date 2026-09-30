# The C half of the ffi gem, written in ruby: each number kind a memory
# op converts takes and refuses what ruby's C conversions take and
# refuse, in their words, and the classes refuse what ffi_c refuses.
require "ffi"
m = FFI::MemoryPointer.new(:int64, 2)
vals = [nil, "3", :a, true, 3.7, -1, 2**31, -2**31-1, 2**32, 2**63, 2**64, -2**63-1, 1r/2, Object.new, 1e30, Float::NAN]
def t; yield; rescue Exception => e; puts "#{e.class}: #{e.message.gsub(/0x\h{16}/, "ADDR")}"; else puts "ok"; end
%w[int8 uint8 int16 uint16 int32 uint32 int64 uint64 long ulong float32 float64 pointer bool].each do |t|
  row = vals.map do |v|
    m.send("put_#{t}", 0, v)
    m.send("get_#{t}", 0).inspect
  rescue => e
    "#{e.class}: #{e.message.sub(/#<Object:0x\h+>/, 'OBJ')}"
  end
  puts "#{t}: #{row.join(' | ')}"
end
def show(x) = puts(x.to_s.gsub(/0x\h{16}/, "ADDR"))
t { FFI::DynamicLibrary.open(nil, nil) }
t { FFI::StructLayout::Field.new(:a, "1", FFI::Type::INT) }
t { FFI::StructLayout::Field.new(:a, 2**70, FFI::Type::INT) }
t { FFI::MemoryPointer.new(:int).put_string(0, 1) }
t { FFI::MemoryPointer.new(:int).put_array_of_int(0, 1) }
t { FFI::ArrayType.new(:int, 3) }
t { FFI::ArrayType.new(nil, 3) }
t { FFI::Pointer.new(1).dup }
t { show [FFI::DynamicLibrary.last_error].inspect }
t { FFI::MemoryPointer.new(:int, -1) }
t { FFI::Buffer.new(:int, -1) }
t { show [FFI::Type.new(3).size, FFI::Type.new(FFI::Type::INT).inspect].inspect }
t { FFI::Type.new("x") }
t { x = FFI::Pointer.new(0); p x.read_int }
t { x = FFI::MemoryPointer.new(4); x.freeze; x.put_int(0, 1) }
t { x = FFI::MemoryPointer.new(4); x.freeze; show x.dup.inspect }
t { show [FFI::Buffer.new(4).inspect, FFI::Buffer.new(4).total].inspect }
t { FFI::MemoryPointer.new(4).free; FFI::Pointer.new(8).free }
t { show [FFI::Function.new(:int, []) { }.inspect].inspect }
t { show [FFI::Pointer.new(0).order, FFI::Pointer.new(1).order(:big).order].inspect }
t { show [FFI::MemoryPointer.new(:int, 2)[1]].inspect }
t { show [FFI::MemoryPointer.from_string("abc").size].inspect }
t { show [FFI::StructLayout.new([], 0, 1)].inspect }

