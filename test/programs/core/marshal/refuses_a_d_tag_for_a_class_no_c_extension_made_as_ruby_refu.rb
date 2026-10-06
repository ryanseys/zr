# `d` is what CRuby's `_dump_data` writes for a T_DATA object, and
# only a C extension makes one. marshal.c reads the class name,
# allocates the class, and refuses unless what it made is T_DATA --
# so a `d` naming a class a Ruby program can define is refused
# there too, whether or not that class answers `_load_data`.
class Plain; end
class Loader
  def _load_data(v) = @v = v
end
payload = Marshal.dump("payload")[2..]
%w[Plain Loader Absent].each do |name|
  bytes = "\x04\bd:#{(name.bytesize + 5).chr}#{name}#{payload}".b
  begin
    p Marshal.load(bytes)
  rescue ArgumentError => e
    p [name, e.class, e.message]
  end
end
