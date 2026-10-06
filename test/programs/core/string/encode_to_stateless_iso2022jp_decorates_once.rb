# A conversion to or from stateless-ISO-2022-JP runs on a converter whose
# xml and newline decorators work once, as for every other target.
%w[stateless-ISO-2022-JP ISO-2022-JP EUC-JP UTF-8 US-ASCII UTF-16LE CP51932].each do |t|
  %i[attr text].each do |x|
    p [t, x, ("a\"&<あ".encode(t, xml: x) rescue $!.class).b]
  end
end
%w[stateless-ISO-2022-JP ISO-2022-JP EUC-JP UTF-16LE].each do |t|
  %i[crlf cr universal lf].each do |n|
    p [t, n, ("a\r\nb\nあ".encode(t, newline: n) rescue $!.class).b]
  end
  p [t, ("あ\n".encode(t, crlf_newline: true, xml: :text) rescue $!.class).b]
end
p "\e$B$\"\e(B\r\n".force_encoding("stateless-ISO-2022-JP").encode("UTF-8", universal_newline: true) rescue p $!
