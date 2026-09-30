# `in x => y` writes the SAME scrutinee into two different locals, and
# both locals read back the value.

case 5
in x => y
  puts x
  puts y
end
