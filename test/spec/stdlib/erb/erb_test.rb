# frozen_string_literal: true

require "spec_helper"

describe "ERB programs" do
  it "a block tag makes the snippet a block over the snippet's own _erbout local" do
    result = zr(<<~'RUBY')
      # An ERB template compiles to a Ruby snippet the eval VM runs, and a block tag
      # makes that snippet a block over the snippet's OWN local: every `<%= %>`
      # inside `<% 3.times do |i| %>` appends to the `_erbout` the line above it
      # bound. A block that got a fresh scope read that name as a method call.
      require "erb"

      p ERB.new("<% 3.times do |i| %><%= i %><% end %>").result(binding)
      p ERB.new("<% [1, 2, 3].each { |i| %>[<%= i * 2 %>]<% } %>").result(binding)
      p ERB.new("<% %w[a b].each_with_index do |s, i| %><%= i %>:<%= s %> <% end %>").result(binding)
      p ERB.new("<% h = { x: 1, y: 2 } %><% h.each do |k, v| %><%= k %>=<%= v %>;<% end %>").result(binding)
      p ERB.new("<%= [1, 2].map { |z| z + 1 }.inspect %>").result(binding)

      # A local of the CALLER's binding is in scope inside a block tag too.
      n = 4
      p ERB.new("<%= n %> items<% if n > 2 %> (many)<% end %>").result(binding)
      p ERB.new("<% 2.times do %><%= n %><% end %>").result(binding)

      # Nested blocks, and the tags that carry no block at all.
      p ERB.new("<% 2.times do |a| %><% 2.times do |b| %><%= a %><%= b %><% end %><% end %>").result(binding)
      p ERB.new("plain").result(binding)
      p ERB.new("<%# a comment %>ok").result(binding)
    RUBY

    _(result).must_answer <<~'OUT'
      "012"
      "[2][4][6]"
      "0:a 1:b "
      "x=1;y=2;"
      "[2, 3]"
      "4 items (many)"
      "44"
      "00011011"
      "plain"
      "ok"
    OUT
  end

  it "module_function names a method the body did not write, so ERB::Util reaches html_escape" do
    result = zr(<<~'RUBY')
      # `require "erb"` -- the vendored gem loads and templates render. `erb/util.rb`
      # reaches `html_escape` through `include ERB::Escape` and then
      # `module_function :html_escape`, so it exercises `module_function` naming a
      # method this body did not define.
      require "erb"

      p ERB::Util.html_escape("a > b & c")
      p ERB::Util.h("<x>")
      p ERB::Util.url_encode("a b")
      # Rendering a template needs `TOPLEVEL_BINDING` -- see
      # `tests/gaps/issue_erb_render_needs_binding.rb`.

      # `module_function` keeps BOTH halves: a public module method and a private
      # instance method for the include-mixin.
      module Greet
        def hello(who) = "hi #{who}"
      end

      module Util
        include Greet
        module_function :hello
      end

      class User
        include Util
      end

      p Util.hello("a")
      p User.new.respond_to?(:hello)
      p User.new.send(:hello, "b")
    RUBY

    _(result).must_answer <<~'OUT'
      "a &gt; b &amp; c"
      "&lt;x&gt;"
      "a%20b"
      "hi a"
      false
      "hi b"
    OUT
  end

  it "ERB::Util.html_escape rewrites the markup characters" do
    result = zr(<<~'RUBY')
      require "erb"
      puts ERB::Util.html_escape("<a & b>")
    RUBY

    _(result).must_answer "&lt;a &amp; b&gt;\n"
  end

  it "issue erb render needs binding" do
    result = zr(<<~'RUBY')
      # Rendering an ERB template evaluates the compiled source in a Binding:
      # `ERB#result`/`#result_with_hash` default to `new_toplevel`, which derives
      # a binding from `TOPLEVEL_BINDING`. zr has neither the constant nor
      # `Kernel#binding`, so the vendored gem loads and compiles but cannot render.
      require "erb"

      p ERB.new("<%= 1 + 1 %> and <%= name %>").result_with_hash(name: "zr")
      p ERB.new("<%= 2 * 3 %>").result(binding)
    RUBY

    _(result).must_answer <<~'OUT'
      "2 and zr"
      "6"
    OUT
  end

  it "reports template lines off by one" do
    result = zr(<<~'RUBY')
      # An error raised inside an ERB template names the TEMPLATE line: a
      # raise on template line 3 reports "(erb):3" (or "tpl.erb:3" with a
      # filename). zr reports one line further (the generated code's
      # "#coding:UTF-8" preamble line is being counted). (Found by the
      # 2026-08-24 probe sweep.)
      require "erb"
      t = ERB.new("l1\nl2\n<% raise 'boom' %>\nl4")
      begin
        t.result
      rescue RuntimeError => e
        p e.backtrace.first[/\(erb\):\d+/]
      end
      t2 = ERB.new("<% raise 'b' %>")
      t2.filename = "tpl.erb"
      begin
        t2.result
      rescue RuntimeError => e
        p e.backtrace.first[/tpl\.erb:\d+/]
      end
    RUBY

    _(result).must_answer <<~'OUT'
      "(erb):3"
      "tpl.erb:1"
    OUT
  end
end
