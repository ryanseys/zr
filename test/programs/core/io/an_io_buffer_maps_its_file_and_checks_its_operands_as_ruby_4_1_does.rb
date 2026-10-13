# IO::Buffer.map maps the file itself: a forked child's write reaches the
# parent's buffer and the file unless the mapping is private, the child
# shows the same address, and a file open only for reading cannot take a
# writable mapping. Offsets, lengths and sizes take only Integers. A block
# that froze the buffer of IO::Buffer.for still lets it go. .string checks
# its size and needs its block.
$VERBOSE = nil
$stdout.sync = true
def try(label)
  p [label, yield]
rescue => e
  p [label, e.class, e.message]
end

path = File.join(Dir.pwd, "io_buffer_map_#{$$}.txt")
[0, IO::Buffer::PRIVATE].each do |flags|
  File.write(path, "I'm private")
  file = File.open(path, "r+")
  buffer = IO::Buffer.map(file, nil, 0, flags)
  shown = IO.popen("-") do |child|
    if child
      child.read.chomp
    else
      buffer.set_string("I'm shared!")
      puts buffer.to_s
      exit!(0)
    end
  end
  p [flags, shown == buffer.to_s, buffer.get_string, File.read(path)]
  buffer.free
  file.close
end

File.write(path, "read only text")
File.open(path, "rb") do |file|
  try(:read_only_file) { IO::Buffer.map(file) }
  try(:read_only_flag) { IO::Buffer.map(file, nil, 0, IO::Buffer::READONLY).get_string }
  try(:size_string) { IO::Buffer.map(file, "4") }
  try(:size_float) { IO::Buffer.map(file, 4.0) }
  try(:offset_float) { IO::Buffer.map(file, 4, 0.0, IO::Buffer::READONLY).get_string }
end
File.delete(path)

b = IO::Buffer.new(8)
try(:get_value_float) { b.get_value(:U8, 1.0) }
try(:slice_float) { b.slice(1.0, 2) }
try(:slice_length_float) { b.slice(1, 2.0) }
try(:get_string_float) { b.get_string(1.5) }
try(:clear_float) { b.clear(0, 1.0) }
try(:set_string_string) { b.set_string("x", "1") }
try(:negative_offset) { b.get_value(:U8, -1) }
try(:bignum_offset) { b.get_value(:U8, 2**70) }

string = +"test"
buffer = IO::Buffer.for(string, &:freeze)
p [buffer.null?, string << "!"]
try(:string_negative) { IO::Buffer.string(-1) {} }
try(:string_no_block) { IO::Buffer.string(1) }
try(:string_float) { IO::Buffer.string(1.9) { |io| io.size } }
try(:string_value) { IO::Buffer.string(3) { |io| io.set_string("abc") } }
