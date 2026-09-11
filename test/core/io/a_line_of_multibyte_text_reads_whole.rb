# gets and each_line find the separator by bytes, so a line of
# multibyte characters comes back whole, newline and all.
path = "/tmp/ze0_a_line_of_multibyte_text_reads_whole.txt"
File.write(path, "héllo\nwörld ünïcode\n日本語\nplain\n")
File.open(path) { |f| f.each_line { |l| p l } }
File.open(path) { |f| p f.gets, f.gets("ö"), f.gets(nil) }
File.open(path) { |f| p f.readlines(chomp: true) }
File.delete(path)
__END__
"héllo\n"
"wörld ünïcode\n"
"日本語\n"
"plain\n"
"héllo\n"
"wö"
"rld ünïcode\n日本語\nplain\n"
["héllo", "wörld ünïcode", "日本語", "plain"]
