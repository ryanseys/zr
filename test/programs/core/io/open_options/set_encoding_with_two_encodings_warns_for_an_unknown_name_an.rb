# set_encoding with two arguments warns for a name that matches nothing,
# converts nothing between one encoding and itself or from binary, and
# takes the conversion options.
File.write("/tmp/zr_spec_set_encoding.txt", "x")
File.open("/tmp/zr_spec_set_encoding.txt") do |f|
  [["iso-8859-1", "-"], ["binary", "utf-8"], [Encoding::UTF_8, Encoding::UTF_8], ["euc-jp", "utf-8"], ["bogus", "bogus2"], ["utf-8", "bogus"], [Encoding::EUC_JP, "utf-8"], ["euc-jp", nil], [nil, nil], [Encoding::BINARY]].each do |args|
    r = (f.set_encoding(*args) rescue $!)
    p [args, r.is_a?(Exception) ? r : [f.external_encoding, f.internal_encoding]]
  end
  f.set_encoding("iso-8859-1", "utf-8", invalid: :replace)
  p [f.external_encoding, f.internal_encoding]
  p((f.set_encoding("utf-8", invalid: :bogus) rescue $!))
end
File.delete("/tmp/zr_spec_set_encoding.txt")
