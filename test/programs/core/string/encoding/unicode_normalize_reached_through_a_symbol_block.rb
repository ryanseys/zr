p ["é", "Å"].map(&:unicode_normalize)
p ["é"].map(&:unicode_normalized?)
p ["é"].map { |s| s.public_send(:"unicode_#{"normalize"}", :nfd) }.map(&:length)
