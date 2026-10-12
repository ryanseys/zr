require "etc"
p Etc::VERSION.match?(/\A\d+\.\d+\.\d+/), Etc.const_defined?(:VERSION, false)
