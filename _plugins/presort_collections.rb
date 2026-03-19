# frozen_string_literal: true

# Runs once after Jekyll reads all content (posts, collections, data).
# Pre-sorts collections in-place and stores split event arrays in site.data
# so Liquid templates can iterate without sorting per-page.
#
# Exposes:
#   site.announcements        — sorted by sent_at descending
#   site.posts                — sorted by post_created_at descending
#   site.events               — sorted by event_start_time ascending
#   site.data.upcoming_events — events with event_start_time >= now, ascending
#   site.data.past_events     — events with event_start_time < now, descending

Jekyll::Hooks.register :site, :post_read do |site|
  current_time = Time.now.to_i

  # --- Announcements: sort by sent_at descending ---
  if (ann = site.collections["announcements"])
    ann.docs.sort_by! { |d| -d.data["sent_at"].to_i }
  end

  # --- Posts: sort by post_created_at descending ---
  site.posts.docs.sort_by! { |d| -d.data["post_created_at"].to_i }

  # --- Events: sort ascending, then split past/upcoming into site.data ---
  if (ev = site.collections["events"])
    sorted = ev.docs.sort_by { |d| d.data["event_start_time"].to_i }
    ev.docs.replace(sorted)

    site.data["upcoming_events"] = sorted.select { |d| d.data["event_start_time"].to_i >= current_time }
    site.data["past_events"]     = sorted.select { |d| d.data["event_start_time"].to_i < current_time }.reverse
  end
end
