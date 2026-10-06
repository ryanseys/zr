begin
  Object.new.puts
rescue NoMethodError => e
  puts e.detailed_message(highlight: false)
end
begin
  Object.new.prinf
rescue NoMethodError => e
  puts e.detailed_message(highlight: false)
end
def self.helpr = 1
begin
  helper
rescue NameError => e
  puts e.detailed_message(highlight: false)
end
