def twice
  yield 1
  yield 2
end
twice { |i| puts "got #{i}" }
