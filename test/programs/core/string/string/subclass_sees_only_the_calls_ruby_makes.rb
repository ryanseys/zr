# Which of String's own methods its methods call on a subclass: every
# method String defines is wrapped to log a call made from inside another,
# and each is then called once on a fresh receiver. CRuby calls one by
# dispatch only where it means to, and zr's core, written in Ruby, has
# to call no more and no fewer. Written by `zr-dev spec dispatch`.

class Probe < String
  CALLING = []
  LOG = []
  [:%, :*, :+, :+@, :-@, :<, :<<, :<=, :<=>, :==, :===, :=~, :>, :>=, :[], :[]=, :append_as_bytes, :ascii_only?, :b, :between?, :byteindex, :byterindex, :bytes, :bytesize, :byteslice, :bytesplice, :capitalize, :capitalize!, :casecmp, :casecmp?, :center, :chars, :chomp, :chomp!, :chop, :chop!, :chr, :clamp, :clear, :codepoints, :concat, :count, :crypt, :dedup, :delete, :delete!, :delete_prefix, :delete_prefix!, :delete_suffix, :delete_suffix!, :downcase, :downcase!, :dump, :dup, :each_byte, :each_char, :each_codepoint, :each_grapheme_cluster, :each_line, :empty?, :encode, :encode!, :encoding, :end_with?, :eql?, :force_encoding, :freeze, :getbyte, :grapheme_clusters, :gsub, :gsub!, :hash, :hex, :include?, :index, :initialize_copy, :insert, :inspect, :intern, :length, :lines, :ljust, :lstrip, :lstrip!, :match, :match?, :next, :next!, :oct, :ord, :partition, :prepend, :replace, :reverse, :reverse!, :rindex, :rjust, :rpartition, :rstrip, :rstrip!, :scan, :scrub, :scrub!, :setbyte, :size, :slice, :slice!, :split, :squeeze, :squeeze!, :start_with?, :strip, :strip!, :sub, :sub!, :succ, :succ!, :sum, :swapcase, :swapcase!, :to_c, :to_f, :to_i, :to_r, :to_s, :to_str, :to_sym, :tr, :tr!, :tr_s, :tr_s!, :undump, :unicode_normalize, :unicode_normalize!, :unicode_normalized?, :unpack, :unpack1, :upcase, :upcase!, :upto, :valid_encoding?].each do |m|
    define_method(m) do |*args, &blk|
      LOG << "#{CALLING.last}->#{m}" unless CALLING.empty?
      CALLING << m
      begin
        super(*args, &blk)
      ensure
        CALLING.pop
      end
    end
    ruby2_keywords(m)
  end
end

def call(name)
  r = Probe.new(+"hello world")
  Probe::LOG.clear
  begin
    yield r
  rescue StandardError => e
    Probe::LOG << "raised #{e.class}"
  end
  puts "#{name}: #{Probe::LOG.join(" ")}" unless Probe::LOG.empty?
end

call("%") { |r| r.__send__(:%, 1) { |*x| x.first } }
call("*") { |r| r.__send__(:*, 1) { |*x| x.first } }
call("+") { |r| r.__send__(:+, "l") { |*x| x.first } }
call("+@") { |r| r.__send__(:+@) { |*x| x.first } }
call("-@") { |r| r.__send__(:-@) { |*x| x.first } }
call("<") { |r| r.__send__(:<, "l") { |*x| x.first } }
call("<<") { |r| r.__send__(:<<, 1) { |*x| x.first } }
call("<=") { |r| r.__send__(:<=, "l") { |*x| x.first } }
call("<=>") { |r| r.__send__(:<=>, 1) { |*x| x.first } }
call("==") { |r| r.__send__(:==, 1) { |*x| x.first } }
call("===") { |r| r.__send__(:===, 1) { |*x| x.first } }
call("=~") { |r| r.__send__(:=~, /l/) { |*x| x.first } }
call(">") { |r| r.__send__(:>, "l") { |*x| x.first } }
call(">=") { |r| r.__send__(:>=, "l") { |*x| x.first } }
call("[]") { |r| r.__send__(:[], 1) { |*x| x.first } }
call("[]=") { |r| r.__send__(:[]=, "l", "L") { |*x| x.first } }
call("append_as_bytes") { |r| r.append_as_bytes() { |*x| x.first } }
call("ascii_only?") { |r| r.ascii_only?() { |*x| x.first } }
call("b") { |r| r.b() { |*x| x.first } }
call("between?") { |r| r.between?("l", "L") { |*x| x.first } }
call("byteindex") { |r| r.byteindex("l") { |*x| x.first } }
call("byterindex") { |r| r.byterindex("l") { |*x| x.first } }
call("bytes") { |r| r.bytes() { |*x| x.first } }
call("bytesize") { |r| r.bytesize() { |*x| x.first } }
call("byteslice") { |r| r.byteslice(1) { |*x| x.first } }
call("capitalize") { |r| r.capitalize() { |*x| x.first } }
call("capitalize!") { |r| r.capitalize!() { |*x| x.first } }
call("casecmp") { |r| r.casecmp(1) { |*x| x.first } }
call("casecmp?") { |r| r.casecmp?(1) { |*x| x.first } }
call("center") { |r| r.center(1) { |*x| x.first } }
call("chars") { |r| r.chars() { |*x| x.first } }
call("chomp") { |r| r.chomp() { |*x| x.first } }
call("chomp!") { |r| r.chomp!() { |*x| x.first } }
call("chop") { |r| r.chop() { |*x| x.first } }
call("chop!") { |r| r.chop!() { |*x| x.first } }
call("chr") { |r| r.chr() { |*x| x.first } }
call("clear") { |r| r.clear() { |*x| x.first } }
call("codepoints") { |r| r.codepoints() { |*x| x.first } }
call("concat") { |r| r.concat() { |*x| x.first } }
call("count") { |r| r.count("l") { |*x| x.first } }
call("dedup") { |r| r.dedup() { |*x| x.first } }
call("delete") { |r| r.delete("l") { |*x| x.first } }
call("delete!") { |r| r.delete!("l") { |*x| x.first } }
call("delete_prefix") { |r| r.delete_prefix("l") { |*x| x.first } }
call("delete_prefix!") { |r| r.delete_prefix!("l") { |*x| x.first } }
call("delete_suffix") { |r| r.delete_suffix("l") { |*x| x.first } }
call("delete_suffix!") { |r| r.delete_suffix!("l") { |*x| x.first } }
call("downcase") { |r| r.downcase() { |*x| x.first } }
call("downcase!") { |r| r.downcase!() { |*x| x.first } }
call("dump") { |r| r.dump() { |*x| x.first } }
call("dup") { |r| r.dup() { |*x| x.first } }
call("each_byte") { |r| r.each_byte() { |*x| x.first } }
call("each_char") { |r| r.each_char() { |*x| x.first } }
call("each_codepoint") { |r| r.each_codepoint() { |*x| x.first } }
call("each_grapheme_cluster") { |r| r.each_grapheme_cluster() { |*x| x.first } }
call("each_line") { |r| r.each_line() { |*x| x.first } }
call("empty?") { |r| r.empty?() { |*x| x.first } }
call("encode") { |r| r.encode() { |*x| x.first } }
call("encode!") { |r| r.encode!() { |*x| x.first } }
call("encoding") { |r| r.encoding() { |*x| x.first } }
call("end_with?") { |r| r.end_with?() { |*x| x.first } }
call("eql?") { |r| r.eql?(1) { |*x| x.first } }
call("getbyte") { |r| r.getbyte(1) { |*x| x.first } }
call("grapheme_clusters") { |r| r.grapheme_clusters() { |*x| x.first } }
call("gsub") { |r| r.gsub(1) }
call("gsub!") { |r| r.gsub!(1) }
call("hash") { |r| r.hash() { |*x| x.first } }
call("hex") { |r| r.hex() { |*x| x.first } }
call("include?") { |r| r.include?("l") { |*x| x.first } }
call("index") { |r| r.index("l") { |*x| x.first } }
call("initialize_copy") { |r| r.initialize_copy("l") { |*x| x.first } }
call("inspect") { |r| r.inspect() { |*x| x.first } }
call("intern") { |r| r.intern() { |*x| x.first } }
call("length") { |r| r.length() { |*x| x.first } }
call("lines") { |r| r.lines() { |*x| x.first } }
call("ljust") { |r| r.ljust(1) { |*x| x.first } }
call("lstrip") { |r| r.lstrip() { |*x| x.first } }
call("lstrip!") { |r| r.lstrip!() { |*x| x.first } }
call("match") { |r| r.match("l") { |*x| x.first } }
call("match?") { |r| r.match?("l") { |*x| x.first } }
call("next") { |r| r.next() { |*x| x.first } }
call("next!") { |r| r.next!() { |*x| x.first } }
call("oct") { |r| r.oct() { |*x| x.first } }
call("ord") { |r| r.ord() { |*x| x.first } }
call("partition") { |r| r.partition("l") { |*x| x.first } }
call("prepend") { |r| r.prepend() { |*x| x.first } }
call("replace") { |r| r.replace("l") { |*x| x.first } }
call("reverse") { |r| r.reverse() { |*x| x.first } }
call("reverse!") { |r| r.reverse!() { |*x| x.first } }
call("rindex") { |r| r.rindex("l") { |*x| x.first } }
call("rjust") { |r| r.rjust(1) { |*x| x.first } }
call("rpartition") { |r| r.rpartition("l") { |*x| x.first } }
call("rstrip") { |r| r.rstrip() { |*x| x.first } }
call("rstrip!") { |r| r.rstrip!() { |*x| x.first } }
call("scan") { |r| r.scan("l") { |*x| x.first } }
call("scrub") { |r| r.scrub() { |*x| x.first } }
call("scrub!") { |r| r.scrub!() { |*x| x.first } }
call("setbyte") { |r| r.setbyte(0, 1) { |*x| x.first } }
call("size") { |r| r.size() { |*x| x.first } }
call("slice") { |r| r.slice(1) { |*x| x.first } }
call("slice!") { |r| r.slice!(1) { |*x| x.first } }
call("split") { |r| r.split() { |*x| x.first } }
call("squeeze") { |r| r.squeeze() { |*x| x.first } }
call("squeeze!") { |r| r.squeeze!() { |*x| x.first } }
call("start_with?") { |r| r.start_with?() { |*x| x.first } }
call("strip") { |r| r.strip() { |*x| x.first } }
call("strip!") { |r| r.strip!() { |*x| x.first } }
call("sub") { |r| r.sub("l") { |*x| x.first } }
call("sub!") { |r| r.sub!("l") { |*x| x.first } }
call("succ") { |r| r.succ() { |*x| x.first } }
call("succ!") { |r| r.succ!() { |*x| x.first } }
call("sum") { |r| r.sum() { |*x| x.first } }
call("swapcase") { |r| r.swapcase() { |*x| x.first } }
call("swapcase!") { |r| r.swapcase!() { |*x| x.first } }
call("to_c") { |r| r.to_c() { |*x| x.first } }
call("to_f") { |r| r.to_f() { |*x| x.first } }
call("to_i") { |r| r.to_i() { |*x| x.first } }
call("to_r") { |r| r.to_r() { |*x| x.first } }
call("to_s") { |r| r.to_s() { |*x| x.first } }
call("to_str") { |r| r.to_str() { |*x| x.first } }
call("to_sym") { |r| r.to_sym() { |*x| x.first } }
call("tr") { |r| r.tr("l", "L") { |*x| x.first } }
call("tr!") { |r| r.tr!("l", "L") { |*x| x.first } }
call("tr_s") { |r| r.tr_s("l", "L") { |*x| x.first } }
call("tr_s!") { |r| r.tr_s!("l", "L") { |*x| x.first } }
call("unicode_normalize") { |r| r.unicode_normalize() { |*x| x.first } }
call("unicode_normalize!") { |r| r.unicode_normalize!() { |*x| x.first } }
call("unicode_normalized?") { |r| r.unicode_normalized?() { |*x| x.first } }
call("unpack") { |r| r.unpack("l") { |*x| x.first } }
call("unpack1") { |r| r.unpack1("l") { |*x| x.first } }
call("upcase") { |r| r.upcase() { |*x| x.first } }
call("upcase!") { |r| r.upcase!() { |*x| x.first } }
call("upto") { |r| r.upto(1) }
call("valid_encoding?") { |r| r.valid_encoding?() { |*x| x.first } }

