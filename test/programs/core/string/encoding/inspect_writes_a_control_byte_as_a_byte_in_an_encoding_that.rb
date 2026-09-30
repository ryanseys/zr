# In an encoding that is not Unicode, inspect writes a control byte as a
# byte, not as a Unicode escape.
%w[EUC-JP Shift_JIS GBK CESU-8].each do |e|
  p "\x00\x07\x1b\x7f\n\\u0000a".dup.force_encoding(e).inspect
end
