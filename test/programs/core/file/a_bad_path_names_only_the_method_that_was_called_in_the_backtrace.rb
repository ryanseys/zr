# A path that is not a String raises from the method that was called:
# no helper of File's, and no other public method, shows in the
# backtrace, as CRuby's C functions show none.
def try(label)
  r = yield
  puts "#{label}: #{r.inspect}"
rescue Exception => e
  frames = e.backtrace_locations.map(&:label).take_while { |l| !l.start_with?("block in") }
  puts "#{label}: #{e.class}: #{e.message} #{frames.inspect}"
end

[Object.new, 1, nil, :sym, 1.5].each do |bad|
  try("File.exist?(#{bad.class})") { File.exist?(bad) }
  try("File.file?(#{bad.class})") { File.file?(bad) }
  try("File.directory?(#{bad.class})") { File.directory?(bad) }
  try("Dir.exist?(#{bad.class})") { Dir.exist?(bad) }
  try("File.extname(#{bad.class})") { File.extname(bad) }
  try("File.basename(#{bad.class})") { File.basename(bad) }
end
try("Errno as a path") do
  e = begin
    File.size("")
  rescue SystemCallError => x
    x
  end
  File.exist?(e)
end
here = __FILE__
try("File.exist?(real)") { File.exist?(here) }
try("Dir.exist?(.)") { Dir.exist?(".") }
try("Dir.exist?(file)") { Dir.exist?(here) }
try("File.extname(real)") { File.extname(here) }
try("File.extname(to_path)") { File.extname(Struct.new(:to_path).new("a/b.txt")) }
try("IO.select(false)") { IO.select(false) }
try("IO.select([], 1)") { IO.select([], 1) }
try("IO.select([1])") { IO.select([1]) }
try("IO.select([$stdout], [], [], -1)") { IO.select([$stdout], [], [], -1) }
try("IO.select([], [$stdout], [:x])") { IO.select([], [$stdout], [:x]) }
try("IO.select(nil, [$stdout], nil, 0)") { IO.select(nil, [$stdout], nil, 0).map(&:size) }
try("5.divmod(0)") { 5.divmod(0) }
try("5.div(0)") { 5.div(0) }
try("5.modulo(0)") { 5.modulo(0) }
try("5 % 0") { 5 % 0 }
try("5 / 0") { 5 / 0 }
try("(2**70).divmod(0)") { (2**70).divmod(0) }
try("(2**70).div(0)") { (2**70).div(0) }
try("(2**70).modulo(0)") { (2**70).modulo(0) }
try("5.divmod(0.0)") { 5.divmod(0.0) }
try("5.div(0.0)") { 5.div(0.0) }
try("5.modulo(0.0)") { 5.modulo(0.0) }
try("5.divmod(2)") { 5.divmod(2) }
try("-7.divmod(2)") { -7.divmod(2) }
try("-7.modulo(2)") { -7.modulo(2) }
try("-7.div(2)") { -7.div(2) }
try("7.divmod(2.5)") { 7.divmod(2.5) }
try("7.divmod(2r)") { 7.divmod(2r) }
try("7.div(0r)") { 7.div(0r) }
try("5 % 0.0") { 5 % 0.0 }
try("(2**70).divmod(0.0)") { (2**70).divmod(0.0) }
