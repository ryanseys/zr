# A gets limit that falls inside a character reads on to that
# character's end, so a line never ends in half a character.
path = "/tmp/ze0_a_gets_limit_keeps_a_whole_character.txt"
File.write(path, "alpha\nbéta\n日本語\n")
File.open(path) { |f| p f.gets(nil, 8), f.gets(3), f.gets(1), f.gets(4), f.gets }
File.open(path) { |f| p f.gets("\n", 7), f.gets(2), f.gets(5) }
File.delete(path)
__END__
"alpha\nbé"
"ta\n"
"日"
"本語"
"\n"
"alpha\n"
"bé"
"ta\n"
