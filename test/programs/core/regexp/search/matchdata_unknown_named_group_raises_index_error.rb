# An unknown named-group key raises IndexError;
# a known name resolves its capture.

m = "2026-06".match(/(?<y>\d+)-(?<mo>\d+)/)
p m[:mo]
begin
  m[:nope]
rescue IndexError => e
  puts "#{e.class}: #{e.message}"
end
