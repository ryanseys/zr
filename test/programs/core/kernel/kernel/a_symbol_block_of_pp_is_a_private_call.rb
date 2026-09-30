begin
  [[1] * 3].each(&:pp)
rescue NoMethodError => e
  p [e.class, e.message]
end
p [1].respond_to?(:pp)
