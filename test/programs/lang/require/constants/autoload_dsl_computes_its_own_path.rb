require_relative "autoload_dsl/mylib"

puts MyLib::Model.hello
puts MyLib::Model.name
puts defined?(MyLib::Model)
