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

__END__
int8: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | RangeError: integer 2147483648 too big to convert to 'int' | RangeError: integer -2147483649 too small to convert to 'int' | RangeError: integer 4294967296 too big to convert to 'int' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
uint8: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 255 | 0 | RangeError: integer -2147483649 too small to convert to 'unsigned int' | RangeError: integer 4294967296 too big to convert to 'unsigned int' | RangeError: integer 9223372036854775808 too big to convert to 'unsigned int' | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
int16: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | RangeError: integer 2147483648 too big to convert to 'int' | RangeError: integer -2147483649 too small to convert to 'int' | RangeError: integer 4294967296 too big to convert to 'int' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
uint16: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 65535 | 0 | RangeError: integer -2147483649 too small to convert to 'unsigned int' | RangeError: integer 4294967296 too big to convert to 'unsigned int' | RangeError: integer 9223372036854775808 too big to convert to 'unsigned int' | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
int32: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | RangeError: integer 2147483648 too big to convert to 'int' | RangeError: integer -2147483649 too small to convert to 'int' | RangeError: integer 4294967296 too big to convert to 'int' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
uint32: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 4294967295 | 2147483648 | RangeError: integer -2147483649 too small to convert to 'unsigned int' | RangeError: integer 4294967296 too big to convert to 'unsigned int' | RangeError: integer 9223372036854775808 too big to convert to 'unsigned int' | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
int64: TypeError: no implicit conversion from nil | TypeError: no implicit conversion from string | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion from boolean | 3 | -1 | 2147483648 | -2147483649 | 4294967296 | RangeError: bignum too big to convert into 'long long' | RangeError: bignum too big to convert into 'long long' | RangeError: bignum too big to convert into 'long long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of long long | RangeError: float NaN out of range of long long
uint64: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 18446744073709551615 | 2147483648 | 18446744071562067967 | 4294967296 | 9223372036854775808 | RangeError: bignum too big to convert into 'unsigned long long' | RangeError: bignum out of range of unsigned long long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of unsigned long long | RangeError: float NaN out of range of unsigned long long
long: TypeError: no implicit conversion from nil to integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | -1 | 2147483648 | -2147483649 | 4294967296 | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | RangeError: bignum too big to convert into 'long' | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
ulong: TypeError: no implicit conversion of nil into Integer | TypeError: no implicit conversion of String into Integer | TypeError: no implicit conversion of Symbol into Integer | TypeError: no implicit conversion of true into Integer | 3 | 18446744073709551615 | 2147483648 | 18446744071562067967 | 4294967296 | 9223372036854775808 | RangeError: bignum too big to convert into 'unsigned long' | RangeError: bignum out of range of unsigned long | 0 | TypeError: no implicit conversion of Object into Integer | RangeError: float 1e+30 out of range of integer | RangeError: float NaN out of range of integer
float32: TypeError: no implicit conversion to float from nil | TypeError: no implicit conversion to float from string | TypeError: can't convert Symbol into Float | TypeError: no implicit conversion to float from true | 3.700000047683716 | -1.0 | 2147483648.0 | -2147483648.0 | 4294967296.0 | 9.223372036854776e+18 | 1.8446744073709552e+19 | -9.223372036854776e+18 | 0.5 | TypeError: can't convert Object into Float | 1.0000000150474662e+30 | NaN
float64: TypeError: no implicit conversion to float from nil | TypeError: no implicit conversion to float from string | TypeError: can't convert Symbol into Float | TypeError: no implicit conversion to float from true | 3.7 | -1.0 | 2147483648.0 | -2147483649.0 | 4294967296.0 | 9.223372036854776e+18 | 1.8446744073709552e+19 | -9.223372036854776e+18 | 0.5 | TypeError: can't convert Object into Float | 1.0e+30 | NaN
pointer: #<FFI::Pointer address=0x0000000000000000> | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | #<FFI::Pointer address=0xffffffffffffffff> | #<FFI::Pointer address=0x0000000080000000> | #<FFI::Pointer address=0xffffffff7fffffff> | #<FFI::Pointer address=0x0000000100000000> | #<FFI::Pointer address=0x8000000000000000> | RangeError: bignum too big to convert into 'unsigned long long' | RangeError: bignum out of range of unsigned long long | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer | ArgumentError: value is not a pointer
bool: NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer | NoMethodError: undefined method 'put_bool' for an instance of FFI::MemoryPointer
TypeError: wrong argument type nil (expected Integer)
TypeError: wrong argument type String (expected Integer)
TypeError: wrong argument type Integer (expected Integer)
TypeError: wrong argument type Integer (expected String)
TypeError: wrong argument type Integer (expected Array)
TypeError: wrong argument type Symbol (expected FFI::Type)
TypeError: wrong argument type nil (expected FFI::Type)
RuntimeError: cannot duplicate unbounded memory area
["(null)"]
ok
ok
ok
[1, "#<FFI::Type::ADDR size=4 alignment=4>"]
ok
ArgumentError: wrong type
FFI::NullPointerError: invalid memory read at address=ADDR
RuntimeError: invalid memory write at address=ADDR
#<FFI::MemoryPointer address=ADDR size=4>
ok
["#<FFI:Buffer:ADDR address=ADDR size=4>", 4]
ok
ok
["#<FFI::Function address=ADDR size=48>"]
ok
[:little, :big]
ok
[#<FFI::Pointer address=ADDR size=4>]
ok
[4]
ok
RuntimeError: Struct size is zero
#@ stderr
stdlib/ffi/the_c_half_converts_and_refuses_as_ruby_does.rb:35: warning: calling free on non allocated pointer #<FFI::Pointer address=0x0000000000000008> from stdlib/ffi/the_c_half_converts_and_refuses_as_ruby_does.rb:35:in 'block in <main>'
