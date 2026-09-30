# DATA is a File open on the main program, at the byte after the
# __END__ line. It is defined only when the main file has one.
p DATA.class
p DATA.gets
p DATA.read
p DATA.eof?
DATA.rewind
p DATA.gets
p defined?(DATA)
__END__
line one
line two
last
