# frozen_string_literal: true

require "json"
require "net/http"
require_relative "../../../../../lib/zr/paths"

module Zr
  module Dev
    module Gems
      # The most downloaded gems, from packages.ecosyste.ms, in
      # gems/top.tsv: a header, then `name<TAB>downloads` for each gem,
      # most downloads first. `zr-dev gems top --refresh` writes it, and a
      # sweep reads it for `--top N` and for the downloads column.
      module Top
        URL = "https://packages.ecosyste.ms/api/v1/registries/rubygems.org/packages"
        PAGE = 100

        module_function

        def path = Dev.path("gems/top.tsv")

        # `{ name => downloads }`, most downloads first, or {} with no file.
        def read(file = path)
          return {} unless File.file?(file)

          File.foreach(file, chomp: true).drop(1).reject(&:empty?).to_h do |line|
            name, downloads = line.split("\t")
            [name, Integer(downloads)]
          end
        end

        def write(list, file = path)
          FileUtils.mkdir_p(File.dirname(file))
          Paths.write_atomic(file, ["gem\tdownloads", *list.map { |name, downloads| "#{name}\t#{downloads}" }].join("\n") << "\n")
        end

        # The `count` most downloaded gems, from the API, one page at a time.
        # Yields the count so far after each page.
        def fetch(count)
          list = {}
          (1..).each do |page|
            batch = get(page)
            batch.each { |package| list[package.fetch("name")] ||= Integer(package.fetch("downloads")) }
            yield list.size if block_given?
            break if batch.size < PAGE || list.size >= count
          end
          list.first(count).to_h
        end

        # One page of the list. A failed request is tried again, after 2,
        # 4 and 8 seconds, so one error does not lose a long fetch.
        def get(page, tries: 4, wait: 2)
          uri = URI("#{URL}?sort=downloads&order=desc&per_page=#{PAGE}&page=#{page}")
          response = Net::HTTP.get_response(uri, { "User-Agent" => "zr-dev gems (https://github.com/ryanseys/zr)" })
          raise Failure.new("top", "#{uri}: HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        rescue Failure, SystemCallError, IOError, Timeout::Error, JSON::ParserError
          raise if tries <= 1

          sleep wait
          get(page, tries: tries - 1, wait: wait * 2)
        end
      end
    end
  end
end
