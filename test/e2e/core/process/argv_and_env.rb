# The linked binary's real `main`: argv reaches ARGV without the program name,
# and the environment block reaches ENV.
p ARGV
puts ENV.fetch("ZEO_AOT_SMOKE")
puts ENV.key?("ZEO_AOT_SMOKE_MISSING")
