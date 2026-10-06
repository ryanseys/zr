begin
  raise SyntaxError, "m2"
rescue SyntaxError => e
  p e.message, e.full_message(highlight: false)
end
raise SyntaxError, "msg"
