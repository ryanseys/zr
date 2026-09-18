# The vendored stdlib over the runtime's own extension halves.
require "strscan"
require "cgi/escape"
require "digest"
require "erb"
require "English"

s = StringScanner.new("This is an example string")
p s.scan(/\w+/), s.scan(/\s+/), s.scan_until(/exam/), s.pos, s.charpos
p s.pre_match, s.post_match, s.matched, s.matched_size, s.rest_size
p s.check(/ple/), s.skip(/ple/), s.getch, s.peek(6), s.bol?, s.eos?
s.reset
p s.scan(/(\w+) (is)/), s[1], s[2], s.captures, s.inspect
p s.exist?(/string/), s.skip_until(/string/), s.eos?

p CGI.escapeHTML(%q{<a href="x">&'})
p CGI.escape("a b+c/d"), CGI.escapeURIComponent("a b+c/d")
p CGI.unescape("a+b%2Fc"), CGI.unescapeHTML("&lt;a&gt;&amp;&#x41;")

p Digest::SHA256.hexdigest("abc")
p Digest::SHA1.hexdigest("abc"), Digest::MD5.hexdigest("abc")
p Digest::SHA256.new.tap { |d| d << "a"; d << "bc" }.hexdigest

name = "world"
puts ERB.new("Hello <%= name %>! <% 2.times do |i| %>[<%= i %>]<% end %>").result(binding)
p ERB::Util.html_escape("<b>"), ERB::Util.url_encode("a b")

"hello world" =~ /o (w\w+)/
p $MATCH, $PREMATCH, $POSTMATCH, $LAST_PAREN_MATCH, $LAST_MATCH_INFO[1]
