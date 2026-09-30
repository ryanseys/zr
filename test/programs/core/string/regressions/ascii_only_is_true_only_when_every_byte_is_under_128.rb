# String#ascii_only? : true iff every byte is 7-bit ASCII.
p "hello".ascii_only?
p "héllo".ascii_only?
p "".ascii_only?
p "abc123!".ascii_only?
p "あ".ascii_only?
