# Every String method that takes a Regexp reads wide and legacy text a
# character at a time: scan, split, index and rindex, byteindex,
# partition, slice and []=, start_with?, match and match?, sub! and
# gsub! with a Hash and a block, and the offsets a MatchData answers in
# characters. UTF-16 and UTF-32 in both orders, CESU-8, GB18030, the
# JIS and Korean and Chinese encodings, and a single-byte one.
def shown(v)
  case v
  when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
  when Array then v.map { |x| shown(x) }
  when Hash then v.to_h { |k, x| [shown(k), shown(x)] }
  when MatchData then [shown(v.to_a), v.begin(0), v.end(0), v.byteoffset(0), shown(v.pre_match), shown(v.post_match)]
  else v
  end
end

def show(label)
  p [label, shown(yield)]
rescue StandardError => e
  p [label, e.class, e.message.b]
end

SAMPLES = {
  "UTF-16LE" => "Grüße, 世界! 😀 end", "UTF-16BE" => "Grüße, 世界! 😀 end",
  "UTF-32LE" => "Grüße, 世界! 😀 end", "UTF-32BE" => "Grüße, 世界! 😀 end",
  "CESU-8" => "Grüße, 世界! 😀 end", "GB18030" => "Grüße, 世界! 😀 end",
  "EUC-JP" => "カナ, 世界! ａ end", "Shift_JIS" => "カナ, 世界! ソ表 end", "Windows-31J" => "カナ, 世界! ①② end",
  "Big5" => "中文, 世界! 測試 end", "GBK" => "中文, 世界! 测试 end", "EUC-KR" => "한국, 세계! 어 end",
  "CP949" => "한국, 세계! 똠 end", "ISO-8859-7" => "Καλη, μέρα! ΑΒ end",
}.freeze

SAMPLES.each do |name, sample|
  e = ->(s) { s.encode(name) }
  r = ->(s) { Regexp.new(e.(s)) }
  text = e.(sample)
  word = sample[/\A[^,]+/]
  show(:"#{name}_scan") { text.scan(r.("\\S+")) }
  show(:"#{name}_scan_groups") { text.scan(r.("(\\S)(\\S)")) }
  show(:"#{name}_scan_empty") { e.(word).scan(r.("")).size }
  show(:"#{name}_split") { text.split(r.(",?\\s+")) }
  show(:"#{name}_split_empty") { e.(word).split(r.("")) }
  show(:"#{name}_split_limit") { text.split(r.("\\s"), 2) }
  show(:"#{name}_split_groups") { text.split(r.("(,)")) }
  show(:"#{name}_split_string") { text.split(e.(" ")) }
  show(:"#{name}_index") { [text.index(r.("!")), text.index(r.("\\s"), 5), text.rindex(r.("\\s")), text.rindex(r.("\\s"), 5)] }
  show(:"#{name}_byteindex") { [text.byteindex(r.("!")), text.byterindex(r.("\\s")), text.byteindex(e.("end"))] }
  show(:"#{name}_partition") { text.partition(r.(",\\s")) + text.rpartition(r.("\\s")) }
  show(:"#{name}_slice") { [text[r.("\\S+$")], text[r.("(\\S)(\\S)"), 2], text.slice(r.("!"))] }
  show(:"#{name}_start_with") { [text.start_with?(r.(word[0])), text.start_with?(r.("\\s")), text.end_with?(e.("end"))] }
  show(:"#{name}_match") { [text.match(r.("\\s(\\S+)\\s"), 3), text.match?(r.("!")), text =~ r.("!"), $~ && $~.begin(0)] }
  show(:"#{name}_match_at") { r.("\\S").match(text, 2) }
  show(:"#{name}_named") { m = r.("(?<a>\\S+),\\s(?<b>\\S+)").match(text); [m.named_captures, m.begin(:b), m.end(:a), m.values_at(1, 2)] }
  show(:"#{name}_sub_bang") { t = text.dup; [t.sub!(r.("\\s"), e.("_")), t.sub!(r.("zzz"), e.("_"))] }
  show(:"#{name}_gsub_hash") { text.gsub(r.("[!,]"), e.("!") => e.("?"), e.(",") => e.(";")) }
  show(:"#{name}_gsub_block") { text.gsub(r.("\\S+")) { |w| e.("<") + w + e.(">") } }
  show(:"#{name}_gsub_backref") { text.gsub(r.("(\\S)(\\S*)"), e.("\\2\\1")) }
  show(:"#{name}_aset") { t = text.dup; t[r.("\\s(\\S+)\\s"), 1] = e.("X"); t }
  show(:"#{name}_slice_bang") { t = text.dup; [t.slice!(r.("\\S+$")), t] }
  show(:"#{name}_delete_prefix") { [text.delete_prefix(e.(word)), text.delete_suffix(e.(" end"))] }
  show(:"#{name}_last_match") { text =~ r.("(\\S+)!"); [$1, $`, $', Regexp.last_match(0)] }
  show(:"#{name}_escape_union") { [Regexp.escape(e.("a.b")), Regexp.union(r.("a"), e.("."))] }
  show(:"#{name}_each_line") { e.("a\nb\n\nc").each_line.to_a + e.("a\nb\n\nc").each_line("").to_a + e.("a--b").each_line(e.("--")).to_a }
end

