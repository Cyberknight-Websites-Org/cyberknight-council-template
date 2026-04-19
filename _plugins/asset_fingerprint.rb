# frozen_string_literal: true

# Asset fingerprinting plugin — appends an 8-char MD5 hash to target asset
# filenames and rewrites all HTML references accordingly.
#
# Runs as a :post_write hook so it operates on the fully-written _site/ output.
#
# Target assets:
#   /assets/css/main.css
#   /assets/js/leaflet.js
#   /assets/js/newsletter.js
#
# Also deletes main.css.map (sourcemaps should not ship to production).

require "digest"

Jekyll::Hooks.register :site, :post_write do |site|
  dest = site.dest

  # Map from original web path → fingerprinted web path
  renames = {}

  targets = %w[
    assets/css/main.css
    assets/js/leaflet.js
    assets/js/newsletter.js
  ]

  targets.each do |rel_path|
    abs_path = File.join(dest, rel_path)
    unless File.file?(abs_path)
      Jekyll.logger.warn "Asset Fingerprint:", "Skipping missing file: #{rel_path}"
      next
    end

    hash = Digest::MD5.hexdigest(File.read(abs_path, mode: "rb"))[0, 8]
    ext  = File.extname(rel_path)
    base = File.basename(rel_path, ext)
    dir  = File.dirname(rel_path)
    new_name = "#{base}.#{hash}#{ext}"
    new_rel  = "#{dir}/#{new_name}"
    new_abs  = File.join(dest, new_rel)

    FileUtils.cp(abs_path, new_abs)
    File.delete(abs_path)

    renames["/#{rel_path}"] = "/#{new_rel}"
    Jekyll.logger.info "Asset Fingerprint:", "#{rel_path} → #{new_rel}"
  end

  # Delete sourcemaps
  %w[assets/css/main.css.map].each do |rel_path|
    abs_path = File.join(dest, rel_path)
    if File.file?(abs_path)
      File.delete(abs_path)
      Jekyll.logger.info "Asset Fingerprint:", "Deleted sourcemap: #{rel_path}"
    end
  end

  # Rewrite HTML files
  unless renames.empty?
    Dir.glob(File.join(dest, "**", "*.html")).each do |html_path|
      content = File.read(html_path, mode: "rb")
      rewritten = false

      renames.each do |old_ref, new_ref|
        if content.include?(old_ref)
          content = content.gsub(old_ref, new_ref)
          rewritten = true
        end
      end

      next unless rewritten

      File.write(html_path, content, mode: "wb")
    end
  end
end
