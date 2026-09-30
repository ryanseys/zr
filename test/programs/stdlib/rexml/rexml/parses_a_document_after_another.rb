require "rexml/document"
names = ["<a/>", "<b><c/></b>", "<d x='1'/>"].map { |xml| REXML::Document.new(xml).root.name }
p names
