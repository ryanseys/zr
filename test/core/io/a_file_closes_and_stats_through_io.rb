# File#close, File#stat and File#to_path are IO's rows: a File has no
# rows of its own for them. IO has no p and no codepoints.

File.open(__FILE__) { |f| p [f.stat.size > 0, f.to_path == __FILE__] }
f = File.new(__FILE__)
p f.close, f.closed?, f.close
begin
  f.stat
rescue IOError => e
  p e
end
p File.instance_method(:close).owner, File.instance_method(:stat).owner, File.instance_method(:to_path).owner
p $stdout.respond_to?(:p), $stdin.respond_to?(:codepoints)

__END__
[true, true]
nil
true
nil
#<IOError: closed stream>
IO
IO
IO
false
false
