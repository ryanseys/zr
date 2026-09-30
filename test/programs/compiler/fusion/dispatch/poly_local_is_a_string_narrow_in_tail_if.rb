# Tail-position `if x.is_a?(C) ... end` narrows `x` inside the body.
# Here `Regexp.escape` gets a String from a local narrowed by
# `is_a?(String)`.

def matcher(content_or_opts)
  if content_or_opts.is_a?(Hash)
    content = nil
  else
    content = content_or_opts
  end
  if content.is_a?(String)
    pattern = Regexp.new("<h1>#{Regexp.escape(content)}<")
    body = "<h1>Title<"
    puts pattern.match?(body) ? "match" : "no match"
  end
end

matcher("Title")
matcher({ "opt" => 1 })   # content is nil, skips the inner if entirely
