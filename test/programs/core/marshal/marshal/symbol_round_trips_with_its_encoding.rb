# A Symbol is its bytes and the encoding they are in, and Marshal keeps
# both: a binary name is plain bytes, a UTF-8 one names its encoding. An
# Encoding's own _load answers the name it was handed; Marshal's loader
# turns that into the encoding.
p Marshal.restore(Marshal.dump([1, "two", :three]))
p Marshal.load(Marshal.dump(Encoding::UTF_8)), Encoding._load("UTF-8").class
p Marshal.load(Marshal.dump("é".b.to_sym)), Marshal.load(Marshal.dump("é".b.to_sym)).encoding
p Marshal.load(Marshal.dump(:"é")), Marshal.load(Marshal.dump(:"é")).encoding
p Marshal.load(Marshal.dump([:"é", :"é", "é".b.to_sym]))
p Marshal.dump(:"é").bytes, Marshal.dump("é".b.to_sym).bytes

