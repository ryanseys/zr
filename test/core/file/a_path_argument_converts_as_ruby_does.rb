# A path argument is a String, or what `to_path` or `to_str` answers,
# and it may not hold a NUL byte (CRuby's rb_get_path). The environment
# refuses NUL bytes in names and values the same way.
require "pathname"

def show(label)
  puts "#{label}: #{yield.inspect}"
rescue => e
  puts "#{label}: #{e.class}: #{e.message}"
end

show("exist? Pathname") { File.exist?(Pathname("no-such-file")) }
show("exist? nil") { File.exist?(nil) }
show("exist? Integer") { File.exist?(1) }
show("exist? NUL") { File.exist?("a\0b") }
show("file? Pathname") { File.file?(Pathname(__FILE__)) }
show("directory? to_str") { o = Object.new; def o.to_str = "."; File.directory?(o) }
show("readable? to_path") { o = Object.new; def o.to_path = __FILE__; File.readable?(o) }
show("size NUL") { File.size("a\0b") }
show("read NUL") { File.read("a\0b") }
show("new nil") { File.new(nil) }
show("stat NUL") { File.stat("a\0b") }
show("Dir.exist? Pathname") { Dir.exist?(Pathname(".")) }
show("Dir.entries NUL") { Dir.entries("a\0b") }
show("basename Pathname") { File.basename(Pathname("x/y.rb")) }
show("dirname Pathname") { File.dirname(Pathname("x/y.rb")) }
show("extname Pathname") { File.extname(Pathname("x/y.rb")) }
show("expand_path Pathname") { File.expand_path(Pathname("a"), Pathname("/tmp")) }
show("basename nil") { File.basename(nil) }
show("ENV NUL name") { ENV["a\0b"] = "1" }
show("ENV NUL value") { ENV["ZE0_NUL_CHECK"] = "a\0b" }
show("ENV NUL read") { ENV["a\0b"] }
show("ENV kept") { ENV.key?("ZE0_NUL_CHECK") }

__END__
exist? Pathname: false
exist? nil: TypeError: no implicit conversion of nil into String
exist? Integer: TypeError: no implicit conversion of Integer into String
exist? NUL: ArgumentError: path name contains null byte
file? Pathname: true
directory? to_str: true
readable? to_path: true
size NUL: ArgumentError: path name contains null byte
read NUL: ArgumentError: path name contains null byte
new nil: TypeError: no implicit conversion of nil into String
stat NUL: ArgumentError: path name contains null byte
Dir.exist? Pathname: true
Dir.entries NUL: ArgumentError: path name contains null byte
basename Pathname: "y.rb"
dirname Pathname: "x"
extname Pathname: ".rb"
expand_path Pathname: "/tmp/a"
basename nil: TypeError: no implicit conversion of nil into String
ENV NUL name: ArgumentError: bad environment variable name: contains null byte
ENV NUL value: ArgumentError: bad environment variable value: contains null byte
ENV NUL read: ArgumentError: bad environment variable name: contains null byte
ENV kept: false
