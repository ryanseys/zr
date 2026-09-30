# Under /i a class folds a character across ASCII (s and the long s, k and
# the Kelvin sign) only where the class holds it by something other than
# \w, [[:word:]], \p{ASCII} or a POSIX bracket read as ASCII.
chars = ["s", "S", "ſ", "k", "K", "K", "é", "É", "ǅ", "ß", "ss", "1", "_", " ", "µ", "Μ"]
pats = [/[\w]/i, /[\W]/i, /[^\w]/i, /[^\W]/i, /[a-z]/i, /[k]/i, /[s]/i, /[\w&&[^a-z]]/i, /[[:alpha:]]/i, /[[:^alpha:]]/i,
        /(?a)[[:alpha:]]/i, /(?a)[[:^alpha:]]/i, /(?u)[\w]/i, /[\p{ASCII}]/i, /[\P{ASCII}]/i, /[\d\w]/i, /[[:word:]]/i, /[ſ]/i,
        /[K]/i, /\w/i, /[a-z\W]/i, /[[:lower:]]/i, /(?a)[[:upper:]]/i, /[\s\w]/i, /[\w-]/i, /[-\w]/i, /[\wµ]/i,
        /[^[:^word:]]/i, /[[\w]]/i, /[a[\w]]/i, /(?i:[\w])/, /[\h]/i, /(?d)[\w]/i, /\A[\w]+\z/i]
pats.each do |re|
  puts "#{re.inspect}: #{chars.map { |c| (c =~ re) ? 1 : 0 }.join}"
end

