# A corpus of `<container_op> == nil` predicates that CRuby
# answers as true. A typed array or hash can give nil for an
# out-of-range index or a missing key, even when every element
# is an Integer. Each shape below checks the Ruby condition:
#   arr[i] / arr.delete_at(i) -> (i < 0 || i >= len)
#   arr.first / arr.last / arr.pop -> (len == 0)
#   arr.find_index(x) -> !arr.include?(x)
#   hash[k] -> !hash.has_key?(k)
#   regex.match(s) -> !regex.match?(s)
#
# Plus `Array.new.instance_of?(Array)` is TRUE: every Array
# kind (of Integer, of String, etc.) is `Array`; the same holds
# for Hash kinds.

p ([1, 2, 3][99] == nil)          # 01
p Array.new.instance_of?(Array)   # 02
p ([1, 2].delete_at(3) == nil)    # 03
p ([].first == nil)               # 04
p ([].last == nil)                # 05
p ([].pop == nil)                 # 06
p ([1, 2].find_index(3) == nil)   # 07
p ({0 => 0}[5] == nil)            # 08
p (/xyz/.match("abxyc") == nil)   # 09
