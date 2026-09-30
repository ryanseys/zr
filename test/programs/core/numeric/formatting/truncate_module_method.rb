# A user-defined module method named `truncate` is a different method
# from Float#truncate(n). `ViewHelpers.truncate(s, length: 100)` returns
# the String that its body makes, not a Float.
#
# Roundhouse's blog views have this shape, in
# `app/views/articles/_article.rb`:
# `io << ViewHelpers.html_escape(ViewHelpers.truncate(article.body,
# length: 100))`.

module M
  def self.html_escape(s)
    return "" if s.nil?
    s.to_s
  end

  def self.truncate(s, length: 30, omission: "...")
    return "" if s.nil?
    str = s.to_s
    return str if str.length <= length
    cutoff = length - omission.length
    cutoff = 0 if cutoff < 0
    "#{str[0, cutoff]}#{omission}"
  end
end

# html_escape gets an Integer and Strings, so its param has more than
# one type.
puts M.html_escape(42)                                   # 42
puts M.html_escape("hello")                              # hello
puts M.html_escape(M.truncate("short text", length: 100)) # short text
puts M.html_escape(M.truncate("a very long text indeed", length: 10)) # a very ...

# Float#truncate(n) still gives a Float.
f = 1.234
puts f.truncate(2)                                       # 1.23
puts f.truncate(2) + 0.001                               # 1.2309999999999999
