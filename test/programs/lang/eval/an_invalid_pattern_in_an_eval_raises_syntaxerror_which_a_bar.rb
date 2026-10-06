# A pattern the engine will not compile is a SYNTAX error, not a run-time
# one: ruby reads the literal as it compiles the string, so the eval raises
# SyntaxError and names onig's reason and the pattern. SyntaxError is a
# ScriptError, so `rescue StandardError` walks past it.
begin
  eval("/[z-a]/ =~ 'a'")
rescue SyntaxError => e
  p e.class
  p e.message[/empty range in char class: .*/]
end

begin
  eval("/a{2,1}/ =~ 'a'")
rescue SyntaxError => e
  p e.message[/upper is smaller.*/]
end

begin
  eval("/[b-a]/ =~ 'a'")
rescue StandardError
  puts "standard"
rescue SyntaxError
  puts "script"
end
