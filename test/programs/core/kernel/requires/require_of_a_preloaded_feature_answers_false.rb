# ruby loads these features before the program starts, so a require of
# one answers false, by any of its names. Only pathname's C half is
# loaded; a require of pathname still runs its Ruby half.
p [require("thread"), require("enumerator"), require("rational"), require("complex"), require("fiber")]
p [require("ruby2_keywords"), require("set"), require("monitor"), require("thread.rb"), require("enumerator.so")]
p require("pathname")
