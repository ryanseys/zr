# ruby reports a program that does not parse, and exits 1 without
# running any of it.
puts "never printed"
class O; def s=(v) = @s = v; end
# The two lines after the error are in the report, so the recording
# below never is.
