%w[Shift_JIS Windows-31J SJIS-DoCoMo MacJapanese EUC-JP].each do |enc|
  p [enc, "\xA4".b.force_encoding(enc).inspect, "a\x81".b.force_encoding(enc).inspect]
end
