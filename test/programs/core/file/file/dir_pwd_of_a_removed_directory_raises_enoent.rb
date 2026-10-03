require "tmpdir"

home = Dir.pwd
dir = Dir.mktmpdir
Dir.chdir(dir)
Dir.rmdir(dir)
[-> { Dir.pwd }, -> { Dir.getwd }, -> { File.expand_path("x") }, -> { File.absolute_path("x") }].each do |call|
  call.call
  puts "no error"
rescue SystemCallError => e
  puts "#{e.class}: #{e.message}"
end
begin
  raise "boom"
rescue => e
  puts e.message
end
Dir.chdir(home)
puts Dir.pwd == home
