# A local initialized from `.dup` of a Hash with String values, where
# later writes put values of other types into it. Reads of the copied
# String values must give those values, not 0 or nil. The test reads
# the values, not only `.length`.

class Match
  attr_reader :path_params
  def initialize(pp); @path_params = pp; end
end

m = Match.new({ "article_id" => "1", "format" => "html" })
merged = m.path_params.dup
merged["x"] = 1        # int value forces analyzer-side widening to str_poly_hash
puts merged["article_id"]   # round-trips the original str value
puts merged["format"]
puts merged["x"]
puts merged.length
