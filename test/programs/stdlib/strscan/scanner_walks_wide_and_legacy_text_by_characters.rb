# A StringScanner over UTF-16, UTF-32 or a legacy multibyte text scans
# with patterns of the text's encoding, steps a character at a time
# with getch, and reports byte positions and character positions apart.
require "strscan"

def shown(v)
  case v
  when String then v.valid_encoding? && v.encoding != Encoding::BINARY ? [v.encoding.name, v.encode("UTF-8")] : [v.encoding.name, v.b]
  when Array then v.map { |x| shown(x) }
  else v
  end
end

def show(label)
  p [label, shown(yield)]
rescue StandardError => e
  p [label, e.class, e.message.b]
end

%w[UTF-16LE UTF-16BE UTF-32LE UTF-32BE GB18030 EUC-JP Shift_JIS Big5 EUC-KR CESU-8].each do |name|
  e = ->(s) { s.encode(name) }
  r = ->(s) { Regexp.new(e.(s)) }
  sample = name.start_with?("EUC-JP", "Shift") ? "カナ 表示 end" : (name == "Big5" ? "中文 測試 end" : (name == "EUC-KR" ? "한국 세계 end" : "Grüße 世界😀 end"))
  show(:"#{name}_scan") do
    s = StringScanner.new(e.(sample))
    [s.scan(r.("\\S+")), s.pos, s.charpos, s.matched, s.matched_size, s.pre_match, s.skip(r.("\\s+")), s.check(r.("\\S")), s.rest_size]
  end
  show(:"#{name}_getch") do
    s = StringScanner.new(e.(sample))
    [s.getch, s.getch, s.get_byte, s.pos, s.charpos, s.peek(2).bytesize, s.rest.encoding]
  end
  show(:"#{name}_until") do
    s = StringScanner.new(e.(sample))
    [s.scan_until(r.("\\s")), s.pos, s.charpos, s.search_full(r.("e"), false, false), s.exist?(r.("d")), s.check_until(r.("d$")), s.eos?]
  end
  show(:"#{name}_groups") do
    s = StringScanner.new(e.(sample))
    s.scan(r.("(?<a>\\S)(\\S)"))
    [s[1], s[:a], s.captures, s.values_at(0, 2), s.size, s.named_captures]
  end
  show(:"#{name}_string_pattern") do
    s = StringScanner.new(e.(sample))
    [s.scan(e.(sample[0, 2])), s.pos, s.skip_until(e.("e")), s.charpos, s.scan_until(e.("d")), s.pos]
  end
  show(:"#{name}_unscan") do
    s = StringScanner.new(e.(sample))
    s.scan(r.("\\S+"))
    s.unscan
    s.pos = 2 * e.("a").bytesize
    [s.pos, s.charpos, s.getch, s.inspect.b]
  end
end

