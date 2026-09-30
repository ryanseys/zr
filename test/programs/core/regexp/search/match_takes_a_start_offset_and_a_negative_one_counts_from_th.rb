# Regexp#match?(str, pos) starts matching at byte offset `pos`.
puts /world/.match?("hello world", 6)
puts /hello/.match?("hello world", 6)
puts /hello/.match?("hello world")
puts /world/.match?("hello world", -5)
