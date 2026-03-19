# frozen_string_literal: true

# Fast sitemap generator — replaces jekyll-sitemap gem.
# Writes _site/sitemap.xml directly in Ruby, bypassing Liquid rendering entirely.
#
# Performance: avoids per-URL Liquid filter calls (absolute_url, xml_escape,
# where_exp) that made the Liquid template take ~2.2s for ~160 URLs.

require "time"

module CyberknightSitemap
  class Generator < Jekyll::Generator
    safe true
    priority :low

    def generate(site)
      base_url = (site.config["url"] || "").chomp("/")
      entries = []

      # Collection docs
      site.collections.each_value do |col|
        next if col.metadata["output"] == false

        col.docs.each do |doc|
          next if doc.data["sitemap"] == false

          loc = base_url + clean_url(doc.url)
          lastmod = lastmod_for(doc.data["last_modified_at"] || doc.data["date"])
          entries << url_entry(loc, lastmod)
        end
      end

      # HTML pages (excludes 404)
      site.pages.each do |page|
        next unless page.html? || page.url.end_with?(".html")
        next if page.data["sitemap"] == false
        next if page.url == "/404.html"

        loc = base_url + clean_url(page.url)
        lastmod = lastmod_for(page.data["last_modified_at"])
        entries << url_entry(loc, lastmod)
      end

      xml = <<~XML
        <?xml version="1.0" encoding="UTF-8"?>
        <urlset xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:schemaLocation="http://www.sitemaps.org/schemas/sitemap/0.9 http://www.sitemaps.org/schemas/sitemap/0.9/sitemap.xsd" xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
        #{entries.join("\n")}
        </urlset>
      XML

      dest = File.join(site.dest, "sitemap.xml")
      FileUtils.mkdir_p(site.dest)
      File.write(dest, xml)

      # Tell Jekyll not to clean up the file we just wrote
      site.keep_files << "sitemap.xml"
    end

    private

    def clean_url(url)
      url.gsub("/index.html", "/")
    end

    def lastmod_for(value)
      return nil unless value

      case value
      when Time, DateTime
        value.utc.strftime("%Y-%m-%dT%H:%M:%S+00:00")
      when Date
        value.strftime("%Y-%m-%d")
      when String
        Time.parse(value).utc.strftime("%Y-%m-%dT%H:%M:%S+00:00") rescue nil
      end
    end

    def url_entry(loc, lastmod)
      if lastmod
        "  <url>\n    <loc>#{loc}</loc>\n    <lastmod>#{lastmod}</lastmod>\n  </url>"
      else
        "  <url>\n    <loc>#{loc}</loc>\n  </url>"
      end
    end
  end
end
