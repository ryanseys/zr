require "erb/escape"
# The C defines an empty CGI class and does not load cgi/escape.
p defined?(CGI), CGI.constants, ERB::Escape.singleton_methods
s = "abc"
p ERB::Escape.html_escape(s).equal?(s)
p ERB::Escape.html_escape(%(<a href="x">'&'</a>))
o = Object.new
def o.to_s = 1
p (ERB::Escape.html_escape(o) rescue $!)
class Sub < String; end
p ERB::Escape.html_escape(Sub.new("<")).class, ERB::Escape.html_escape(Sub.new("a")).class
p ERB::Escape.html_escape("\xff<".b), ERB::Escape.html_escape("é<").encoding
p (ERB::Escape.html_escape("a<".encode("UTF-16LE")) rescue $!)
