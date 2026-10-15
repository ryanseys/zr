# A match against text in an encoding the pattern cannot read raises
# Encoding::CompatibilityError from the matching method's caller, with
# no frame of zr's own, and String#match? shows only itself.
def labels(e) = e.backtrace_locations.map(&:label)
begin; /a/ =~ "a".encode("UTF-16LE"); rescue => e; p labels(e); end
begin; "a".encode("UTF-16LE").match?(/a/); rescue => e; p labels(e); end
begin; /\xff/n =~ "あ"; rescue => e; p [e.class, labels(e)]; end
