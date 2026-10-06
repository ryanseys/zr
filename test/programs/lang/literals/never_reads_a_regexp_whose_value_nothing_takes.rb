# ruby compiles nothing for an expression whose value nothing
# takes, so it never reads a regexp written there -- and a
# pattern the engine refuses is a SyntaxError only where the
# program could have taken it. Each line below holds one the
# engine refuses, and ruby runs every one of them.
puts 1
/[z-a]/
def m
  /[z-a]/
  2
end
puts m
[3].each { /[z-a]/; nil }
while false do /[z-a]/ end
true && /[z-a]/
if true then /[z-a]/ end
(/[z-a]/)
begin
  /[z-a]/
ensure
  /[z-a]/
end
case 3
when 3 then /[z-a]/
else /[z-a]/
end
case [3]
in [x] then /[z-a]/
end
# A condition written as a literal chooses its branch as the
# program is built, and the branch it never chooses is never read.
if false then /[q-a]/ end
unless true then /[q-a]/ end
if true then puts 4 else /[q-a]/ end
# An interpolated regexp is not a literal, and its parts still run.
/#{puts 5}/
puts 6
