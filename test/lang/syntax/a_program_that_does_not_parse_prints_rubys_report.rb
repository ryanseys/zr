# ruby reports a program that does not parse, and exits 1 without
# running any of it.
puts "never printed"
class O; def s=(v) = @s = v; end
# The two lines after the error are in the report, so the recording
# below never is.
__END__
#@ stderr
lang/syntax/a_program_that_does_not_parse_prints_rubys_report.rb: --> lang/syntax/a_program_that_does_not_parse_prints_rubys_report.rb

invalid method name; a setter method cannot be defined in an endless method definition

> 3  puts "never printed"
> 4  class O; def s=(v) = @s = v; end

lang/syntax/a_program_that_does_not_parse_prints_rubys_report.rb:4: syntax error found (SyntaxError)
  2 | # running any of it.
  3 | puts "never printed"
> 4 | class O; def s=(v) = @s = v; end
    |              ^~ invalid method name; a setter method cannot be defined in an endless method definition
  5 | # The two lines after the error are in the report, so the recording
  6 | # below never is.

#@ exit 1
