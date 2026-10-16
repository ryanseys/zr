require "coverage"

# CRuby records both branches of a safe call at the call without its
# block literal: to the closing parenthesis, or to the method's name.
Coverage.start(branches: true)
require_relative "safe_calls"
built = File.expand_path("safe_calls.rb", __dir__)
late = File.join(Dir.pwd, "late_safe_calls.rb")
File.write(late, File.read(built))
require late

result = Coverage.result
[built, late].each do |path|
  result.fetch(path)[:branches].each { |root, sides| p [root, sides] }
end
