# rdoc's markup formatters and its markdown parser, as ruby's bundled
# rdoc gives them.
require "rdoc"

html = RDoc::Markup::ToHtml.new
puts html.convert(<<~RDOC)
  = Title

  Some *bold*, _em_ and +code+ text, with a link to https://ruby-lang.org.

  * one
  * two
    1. nested

  [term] its description

    def indented
      :code
    end
RDOC

puts RDoc::Markup::ToRdoc.new.convert("== Section\n\nA paragraph that the formatter wraps at its width, which is long enough to wrap.\n")
puts RDoc::Markup::ToMarkdown.new.convert("= Head\n\n* a\n* b\n")

doc = RDoc::Markdown.parse(<<~MD)
  # Heading

  A [link](https://example.com) and `code`, **strong** and *em*.

  ```ruby
  p 1
  ```

  | a | b |
  |---|---|
  | 1 | 2 |
MD
puts doc.accept(RDoc::Markup::ToHtml.new)
p RDoc::Markup::ToTableOfContents.to_toc.convert(RDoc::Markup.parse("= A\n== B\n= C\n")).map(&:text)
p RDoc::VERSION
