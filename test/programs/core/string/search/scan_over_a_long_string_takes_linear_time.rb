# Each match's MatchData holds the text it matched. CRuby shares the
# text's buffer with a frozen copy, so a match costs nothing for the
# length of the text; here each match copies the whole of it, and a scan
# over a long text is quadratic in its length.
text = "ab " * 300_000
p text.scan(/a/).size
p text.gsub(/b/, "c").bytesize
p text.split(/ /).size

