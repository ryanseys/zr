require "cgi/escape"
puts CGI.escape("a b&c=d")
puts CGI.escapeHTML("<x>&'")
puts CGI.unescape("a+b%26c")
