s = "a\x00\x00\x00\xFF\xFF\xFF\xFFb\x00\x00".b.force_encoding("UTF-32LE")
p [s.valid_encoding?, (s.scrub("?") rescue [$!.class, $!.message])]
p s.scrub.b
p s.grapheme_clusters.size
p s.chars.size
