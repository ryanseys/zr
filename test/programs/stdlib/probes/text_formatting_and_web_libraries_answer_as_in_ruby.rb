# A probe of many methods, each line one call and its answer or its error,
# compared with ruby's.
def t(label)
  r = begin
    yield.inspect
  rescue Exception => e
    "#{e.class}: #{e.message}"
  end
  puts "#{label}: #{r}"
end

require "shellwords"; require "abbrev" rescue nil
require "erb"; require "cgi"; require "cgi/escape"; require "uri"; require "base64"; require "securerandom"
t("erb") { ERB.new("<%= 1+2 %> <%- if true -%>y<% end %>", trim_mode: "-").result }
t("erb h") { ERB::Util.html_escape("<a href='x'>&</a>") }
t("erb url") { ERB::Util.url_encode("a b&c/ü") }
t("cgi esc") { CGI.escapeHTML("<\"'&>") }
t("cgi unesc") { CGI.unescapeHTML("&lt;&#39;&#x41;&amp;&quot;") }
t("cgi escape") { CGI.escape("a b+c/ü") }
t("uri parse") { u = URI.parse("http://user@ex.com:8080/p/a?q=1#f"); [u.scheme, u.userinfo, u.host, u.port, u.path, u.query, u.fragment] }
t("uri join") { URI.join("http://a/b/c/d;p?q", "../g").to_s }
t("uri www") { URI.encode_www_form(a: 1, b: ["x y", "z"]) }
t("uri decode") { URI.decode_www_form("a=1&b=x+y&b=%7A") }
t("uri regexp") { "see http://x.com and https://y.org/a" .scan(URI.regexp(%w[http https])).size }
t("uri gen") { URI::HTTP.build(host: "h", path: "/p", query: "a=1").to_s }
t("uri mailto") { URI("mailto:a@b.c?subject=hi").to }
t("base64") { [Base64.strict_encode64("\xff\x00ab"), Base64.urlsafe_encode64("??>>", padding: false), Base64.decode64("YWJj\n")] }
t("base64 err") { Base64.strict_decode64("YWJj=") }
t("secure") { [SecureRandom.hex(4).size, SecureRandom.uuid =~ /\A\h{8}-\h{4}-4\h{3}-[89ab]\h{3}-\h{12}\z/, SecureRandom.alphanumeric(5).size] }
t("shellwords") { ["a 'b c' \"d\\\"e\" f\\ g".shellsplit, Shellwords.escape("it's here"), %w[a b\ c].shelljoin] }
t("shell err") { Shellwords.split("a 'b") }
t("format") { format("%-5s|%05.1f|%+x|%o|%e|%10.4s|%%|%c|%b", "ab", 3.14159, 255, 8, 12345.678, "abcdefg", 65, 5) }
t("format2") { format("%<a>s-%{b}", a: 1, b: 2) }
t("format3") { format("%#x %#o %#b % d %.3g %g %G", 255, 8, 5, 3, 1234567.0, 0.0001, 1e20) }
t("unpack") { "abc\x01\x02".unpack("a2 C* ") }
t("pack") { [1, 2, 3].pack("s>l<q") .bytes }
t("tr") { "hello".tr("el", "ip").tr_s("l", "r").squeeze.delete("o") }
t("succ") { ["az", "zz", "a9", "Zz", "1.9", ""].map(&:succ) }
t("center") { ["ab".center(7, "*"), "ab".ljust(5, "12"), "ab".rjust(1)] }
t("scan") { "a1b22c333".scan(/[a-z](\d+)/) }
t("sub") { "John Smith".sub(/(\w+) (\w+)/, '\2, \1') + "a-b".gsub("-") { $&.ord.to_s } }
t("encode") { "héllo".encode("ISO-8859-1").bytes + "xあ".encode("Shift_JIS", undef: :replace).bytes }
t("unicode") { ["Straße".upcase, "ǅ".downcase, "ﬀ".upcase, "İ".downcase.bytes, "ÀÉ".unicode_normalize(:nfd).size] }
t("casecmp") { ["Ä".casecmp?("ä"), "a".casecmp("B"), "ß".casecmp?("SS")] }
t("each_grapheme") { "🇯🇵é".grapheme_clusters.size }
t("string fmt") { 1234567.89.to_s + " " + 1e100.to_s + " " + (0.1 + 0.2).to_s + " " + 1.23e-5.to_s }
t("int fmt") { [255.to_s(2), (-255).to_s(16), 10.digits, 1234.pow(5, 7), Integer.sqrt(99), 10.bit_length] }
t("float round") { [2.5.round, 3.5.round, 2.675.round(2), 1.15.round(1), 10.0.floor(-1), 1.23456.ceil(3), -0.0.to_s] }
t("rational") { [Rational("1/3") + 0.5r, 3.14.rationalize(Rational(1, 100)), 1.5.to_r, Rational(7, 2).round(half: :even)] }
t("complex") { [Complex(1, 2) * Complex(3, 4), Complex("1+2i").abs2, Complex(3, 4).polar.map { _1.round(3) }] }
