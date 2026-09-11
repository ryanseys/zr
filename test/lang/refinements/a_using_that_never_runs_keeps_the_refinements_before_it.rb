module A
  refine(String) { def shout = "A:#{upcase}" }
end
module B
  refine(String) { def shout = "B:#{upcase}" }
end
module C
  refine(String) { def whisper = "C:#{downcase}" }
end

using A
using B if false
p "x".shout

flag = true
using C if flag
p "Y".whisper, "x".shout

if flag
  using B
else
  using C
end
p "x".shout, "Y".whisper

using B unless flag
p "x".shout

__END__
"A:X"
"C:y"
"A:X"
"B:X"
"C:y"
"B:X"
