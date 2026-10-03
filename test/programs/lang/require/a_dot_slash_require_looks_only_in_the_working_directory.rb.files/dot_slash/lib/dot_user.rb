begin
  require "./dot_helper"
  puts "loaded"
rescue LoadError => e
  puts e.message
end
