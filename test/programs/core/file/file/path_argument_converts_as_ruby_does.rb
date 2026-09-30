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
show("ENV NUL value") { ENV["ZR_NUL_CHECK"] = "a\0b" }
show("ENV NUL read") { ENV["a\0b"] }
show("ENV kept") { ENV.key?("ZR_NUL_CHECK") }

