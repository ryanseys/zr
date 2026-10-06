# coding: US-ASCII
# A regexp literal whose literal fragments mix a \\u escape with a byte
# past ASCII is a SyntaxError: ruby's parser joins the fragments as it
# reads them.
[%q{/U#{%q"\x80"}/}, %q{/U#{"\x80"}/}].each do |src|
  eval("# -*- encoding: US-ASCII -*-\n#{src.sub("U", %q{\u1234})}")
rescue SyntaxError, RegexpError => e
  p e.class
end
