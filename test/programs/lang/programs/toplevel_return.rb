# frozen_string_literal: true

# A `return` written at a file's top level ends that file: ruby stops
# reading it there, and the value is dropped.

puts "start"

def helper = :helper
p helper

return if [].any?

puts "still here"

class C
  def go
    return :from_method
  end
end
p C.new.go

[1].each { p :in_block }

return if [1].any?

puts "never"
