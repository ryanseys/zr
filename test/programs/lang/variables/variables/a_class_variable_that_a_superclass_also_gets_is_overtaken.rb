class Pa; end
class Ch < Pa
  @@s = 1
  def self.r = @@s
end
class Pa
  @@s = 2
end
begin
  Ch.r
rescue RuntimeError => e
  p e.message
end
p Pa.class_variable_get(:@@s)
