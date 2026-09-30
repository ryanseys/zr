p Integer.sqrt(0)
p Integer.sqrt(8)
p Integer.sqrt(9)
p Integer.sqrt(10**20)
p Integer.sqrt(2**100)
begin
  Integer.sqrt(-4)
rescue Math::DomainError => e
  puts e.message
end
