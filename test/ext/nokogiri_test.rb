# frozen_string_literal: true
# zr-test: runtime

require "test_helper"
require_relative "../support/c_ext"

# nokogiri, a real gem whose precompiled bundle holds libxml2, libxslt and
# gumbo, in a zr binary that loads that bundle (`--native-ext`): the
# binary exports zr's C API, and the bundle's imports bind to it. Each
# program gives ruby's output, also with a minor collection at each
# allocation after nokogiri loads (`GC.stress = 1`, which STRESS turns on
# in zr's runs only): under ZR_GC_STRESS, the load alone takes minutes.
class CExtNokogiriTest < Minitest::Test
  # Each program is a test for each run, by the name's suffix, so a test
  # runs one binary in the worker's time limit; the build is cached.
  RUNS = { "" => {}, "_under_stress" => { "STRESS" => "1" } }.freeze
  VERIFIED = RUNS.merge("_verified" => { "STRESS" => "1", "ZR_GC_VERIFY" => "1" }).freeze
  STRESS = %(GC.stress = 1 if ENV.key?("STRESS")\n)

  def self.same_as_ruby(name, program, runs: RUNS)
    runs.each { |suffix, env| define_method(:"test_#{name}#{suffix}") { assert_same_as_ruby(program, env) } }
  end

  def setup
    skip "needs an aarch64-apple-darwin host" unless Zr::Target::AARCH64_DARWIN.native?
    @version = Zr::Test::CExt.installed("nokogiri")
    skip "nokogiri is not installed in this ruby" unless @version
  end

  # `program` starts with its require of nokogiri; the stress starts
  # after it.
  def assert_same_as_ruby(program, env)
    program = program.sub(%(require "nokogiri"\n)) { |line| line + STRESS }
    ruby, (zr,) = Zr::Test::CExt.gem_outputs("nokogiri", @version, program, [env])
    assert_equal 0, ruby.status, "ruby failed:\n#{ruby.stderr}"
    assert_equal [ruby.stdout, ruby.status], [zr.stdout, zr.status], "zr's output differs from ruby's under #{env}\nzr stderr:\n#{zr.stderr}"
  end

  same_as_ruby "xml_parses_queries_and_writes_as_in_ruby", <<~RUBY
    require "nokogiri"
    doc = Nokogiri::XML(<<~XML)
      <?xml version="1.0"?>
      <shelf xmlns:b="urn:book">
        <b:book id="1" lang="en"><title>One &amp; Two</title><price>10.5</price></b:book>
        <b:book id="2"><title>Caf\\u00e9</title><price>3</price></b:book>
        <!-- a comment -->
      </shelf>
    XML
    p doc.root.name, doc.root.namespaces, doc.encoding
    p doc.xpath("//b:book", "b" => "urn:book").map { |n| [n["id"], n.at("title").text] }
    p doc.xpath("sum(//price)"), doc.xpath("count(//title)")
    p doc.css("title").map(&:content), doc.at_css("[lang]")&.name
    book = doc.at_xpath("//b:book[@id='2']", "b" => "urn:book")
    book["lang"] = "fr"
    book.add_child("<note>new</note>")
    book.at("title").content = "Caf\\u00e9 <b>"
    p book.to_s, book.attributes.keys, book.children.size, book.parent.name
    p doc.root.element_children.map(&:node_name), doc.xpath("//comment()").map(&:text)
    puts doc.to_xml(indent: 1)
    p doc.at("title").ancestors.map(&:name), doc.root.traverse { |n| }.class
  RUBY

  same_as_ruby "html4_and_html5_parse_as_in_ruby", <<~RUBY
    require "nokogiri"
    html = Nokogiri::HTML4("<html><head><title>T</title></head><body><p class=a>Hi<br>there<p class=b>Two</body></html>")
    p html.title, html.css("p").map { |n| [n["class"], n.text] }
    p html.at("body").inner_html
    p html.errors.size
    h5 = Nokogiri::HTML5("<!DOCTYPE html><table><tr><td>cell</table><div id=x data-k=v>&eacute;</div>")
    p h5.at("td").text, h5.at("#x").attributes.transform_values(&:value), h5.at("#x").text
    puts h5.to_html
    frag = Nokogiri::HTML5.fragment("<li>a</li><li>b</li>")
    p frag.children.map(&:name), frag.to_html
  RUBY

  same_as_ruby "sax_calls_back_into_ruby_and_its_errors_pass_through_c", <<~RUBY
    require "nokogiri"
    class Collect < Nokogiri::XML::SAX::Document
      attr_reader :events
      def initialize = (@events = [])
      def start_element(name, attrs = []) = @events << [:start, name, attrs]
      def characters(text) = (@events << [:text, text] unless text.strip.empty?)
      def end_element(name) = @events << [:end, name]
    end
    handler = Collect.new
    Nokogiri::XML::SAX::Parser.new(handler).parse("<a x='1'><b>hi</b><c/></a>")
    p handler.events
    class Boom < Nokogiri::XML::SAX::Document
      def start_element(name, attrs = [])
        raise ArgumentError, "boom at \#{name}" if name == "b"
      end
    end
    begin
      Nokogiri::XML::SAX::Parser.new(Boom.new).parse("<a><b/></a>")
    rescue ArgumentError => e
      p [e.class, e.message]
    end
    p :after
  RUBY

  same_as_ruby "xslt_builder_and_errors_as_in_ruby", <<~RUBY
    require "nokogiri"
    xsl = Nokogiri::XSLT(<<~XSL)
      <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
        <xsl:param name="tag"/>
        <xsl:template match="/"><out tag="{$tag}"><xsl:for-each select="//i"><v><xsl:value-of select="."/></v></xsl:for-each></out></xsl:template>
      </xsl:stylesheet>
    XSL
    doc = Nokogiri::XML("<r><i>1</i><i>2</i></r>")
    puts xsl.transform(doc, Nokogiri::XSLT.quote_params(["tag", "t"])).to_xml
    built = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |x|
      x.root(version: 2) { x.item("a & b"); x.cdata("raw <x>"); x.comment(" c ") }
    end
    puts built.to_xml
    begin
      Nokogiri::XML("<a><b></a>") { |config| config.strict }
    rescue Nokogiri::XML::SyntaxError => e
      p [e.class, e.line, e.message.lines.first.strip]
    end
    loose = Nokogiri::XML("<a><b></a>")
    p loose.errors.map { |e| [e.level, e.line] }, loose.to_xml.lines.size
    begin
      Nokogiri::XML("<a/>").xpath("//[")
    rescue Nokogiri::XML::XPath::SyntaxError => e
      p e.class
    end
  RUBY

  same_as_ruby "a_larger_document_survives_the_collector", <<~RUBY, runs: VERIFIED
    require "nokogiri"
    xml = "<list>" + (1..60).map { |i| "<item n='\#{i}'><name>item \#{i}</name><tags>\#{"t" * (i % 7)}</tags></item>" }.join + "</list>"
    results = 2.times.map do
      doc = Nokogiri::XML(xml)
      nodes = doc.xpath("//item[@n mod 3 = 0]")
      nodes.each { |n| n["seen"] = "yes" }
      [nodes.size, doc.css("item[seen]").size, doc.at("item:last-child name").text, doc.to_xml.bytesize]
    end
    p results.uniq
  RUBY
end
