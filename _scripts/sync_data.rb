require 'open-uri'
require 'json'
require 'optparse'
require 'tzinfo'
require 'time'

begin
  script_start_time = Time.now
  options = {}
  OptionParser.new do |opts|
    opts.banner = 'Usage: sync_data.rb [options]'

    opts.on('-c', '--council COUNCIL_NUMBER', 'Council number') do |c|
      options[:council_number] = c
    end

    opts.on('-u', '--url KOC_URL', 'Kocp URL') do |u|
      options[:kocp_url] = u
    end
  end.parse!

  council_number = options[:council_number] || 2431
  kocp_url = options[:kocp_url] || 'http://127.0.0.1'

  api_start = Time.now
  all_council_info_api_url = "#{kocp_url}/public_api/get_all_council_info/#{council_number}"
  all_council_info_api_response = URI.open(all_council_info_api_url, read_timeout: 10, open_timeout: 5).read
  all_council_info_data = JSON.parse(all_council_info_api_response)
  api_duration = Time.now - api_start

  File.open('_data/all_council_info_data.json', 'w') do |f|
    f.write(all_council_info_data.to_json)
  end

  puts "Synced all council #{council_number} data to _data/all_council_info_data.json (API call took #{api_duration.round(2)}s)"

  website_tz = 'US/Pacific'
  tz = TZInfo::Timezone.get(website_tz)
  tz_cache = { website_tz => tz }

  def escape_html_for_yaml(content)
    return '""' if content.nil? || content.empty?

    escaped = content.gsub('"', '\\"') # Escape double quotes
    "\"#{escaped}\""
  end

  Dir.mkdir('_events') unless Dir.exist?('_events')
  # Delete existing event files
  Dir.glob('_events/*.md').each { |file| File.delete(file) }
  all_council_info_data['council_events'].each do |event|
    event_timezone = event['timezone'] || website_tz
    tz_cache[event_timezone] ||= TZInfo::Timezone.get(event_timezone)
    event_tz = tz_cache[event_timezone]
    event_start_time_localized = event_tz.to_local(Time.at(event['event_start_time']))
    sanitized_event_name = event['event_name'].downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '_').gsub(/_+/, '_').gsub(
      /^_|_$/, ''
    )
    filename = "_events/#{event_start_time_localized.strftime('%Y-%m-%d')}-#{sanitized_event_name}.md"
    location_address_original = event['location_address'] || ''
    location_address_str = escape_html_for_yaml(location_address_original)
    # Split strictly on commas, trim whitespace, ignore empty parts
    parts = location_address_original.split(',').map(&:strip).reject { |p| p.nil? || p.empty? }
    if parts.length <= 2
      # 2 or fewer parts: return as-is
      location_address_name_str = parts.join(', ')
    elsif parts.length == 3
      # exactly 3 parts: drop the final part (usually state/postal)
      location_address_name_str = parts[0..1].join(', ')
    else
      # 4 or more parts: drop the last two parts (usually state and country)
      location_address_name_str = parts[0...-2].join(', ')
    end
    # Remove any lingering double quotes just in case
    location_address_name_str = location_address_name_str.gsub('"', '')
    location_address_nospace_str = location_address_original.gsub('"', '').gsub(' ', '+')
    location_map_link_str = "http://maps.apple.com/?near=#{event['location_coordinates'][0]},#{event['location_coordinates'][1]}&q=#{location_address_nospace_str}"
    File.open(filename, 'w') do |file|
      file.puts '---'
      file.puts 'layout: event'
      file.puts "title: #{escape_html_for_yaml(event['event_name'])}"
      file.puts "event_id: \"#{event['event_id']}\""
      file.puts "event_name: #{escape_html_for_yaml(event['event_name'])}"
      # file.puts "event_description: #{escape_html_for_yaml(event['event_description'])}"
      file.puts "event_details: #{escape_html_for_yaml(event['event_details'])}"
      file.puts "event_start_time: #{event['event_start_time']}"
      file.puts "event_start_time_formatted: \"#{event_start_time_localized.strftime('%m/%d/%Y (%A) starting at %-I:%M %p')}\""
      file.puts "event_end_time: #{event['event_end_time']}"
      # file.puts "video_call_url: #{escape_html_for_yaml(event['video_call_url'])}"
      file.puts "timezone: #{escape_html_for_yaml(event['timezone'])}"
      file.puts "calendar_link: #{escape_html_for_yaml(event['calendar_link'])}"
      # file.puts "location_name: #{escape_html_for_yaml(event['location_name'])}"
      file.puts "location_address: #{escape_html_for_yaml(event['location_address'])}"
      file.puts "location_address_name: #{location_address_name_str}"
      file.puts "location_map_link: #{location_map_link_str}"
      file.puts "location_gps_coordinates_lat: #{event['location_coordinates'][0]}"
      file.puts "location_gps_coordinates_lon: #{event['location_coordinates'][1]}"
      file.puts "event_last_updated: #{event['event_last_updated']}"

      file.puts "permalink: /events/#{event['event_id']}"

      if event['event_flyer'].is_a?(Hash) && !event['event_flyer'].empty?
        flyer = event['event_flyer']
        file.puts 'event_flyer:'
        file.puts "  image_id: \"#{flyer['image_id']}\"" if flyer['image_id']
        alt_text_fixed = flyer['alt_text'].nil? ? '""' : "\"#{flyer['alt_text'].gsub('"', "'")}\""
        file.puts "  alt_text: #{alt_text_fixed}"
        file.puts "  uploaded_at: #{flyer['uploaded_at']}" if flyer['uploaded_at']
        file.puts "  thumbnail_url: \"#{flyer['thumbnail_url']}\"" if flyer['thumbnail_url']
        file.puts "  original_url: \"#{flyer['original_url']}\"" if flyer['original_url']
      end

      if event['event_images'] && !event['event_images'].empty?
        sorted_images = event['event_images'].sort_by { |img| img['order'] }
        file.puts 'event_images:'
        sorted_images.each do |image|
          file.puts "  - image_id: \"#{image['image_id']}\""
          file.puts "    caption: #{escape_html_for_yaml(image['caption'])}"
          alt_text_fixed = image['alt_text'].nil? ? '""' : "\"#{image['alt_text'].gsub('"', "'")}\""
          file.puts "    alt_text: #{alt_text_fixed}"
          file.puts "    order: #{image['order']}"
          file.puts "    uploaded_at: #{image['uploaded_at']}"
          file.puts "    thumbnail_url: \"#{image['thumbnail_url']}\""
          file.puts "    original_url: \"#{image['original_url']}\""
        end
      end

      file.puts '---'
    end
  end

  puts "Generated #{all_council_info_data['council_events'].length} event files in _events directory"

  Dir.mkdir('_posts') unless Dir.exist?('_posts')
  # Delete existing post files
  Dir.glob('_posts/*.md').each { |file| File.delete(file) }
  all_council_info_data['council_posts'].each do |post|
    post_edit_log = post['post_edit_log']
    post_created_at_unixtime = post_edit_log[0]['edit_time']
    post_created_at_localized = tz.to_local(Time.at(post_created_at_unixtime))
    post_created_by = post_edit_log[0]['member_name']
    post_last_edited_at_unixtime = post_edit_log[-1]['edit_time']
    post_last_edited_at_localized = tz.to_local(Time.at(post_last_edited_at_unixtime))
    post_last_edited_by = post_edit_log[-1]['member_name']

    filename = "_posts/#{post_created_at_localized.strftime('%Y-%m-%d')}-#{post['post_title'].downcase.gsub(' ',
                                                                                                            '_')}.md"
    File.open(filename, 'w') do |file|
      file.puts '---'
      file.puts 'layout: post'
      file.puts "title: \"#{post['post_title']}\""
      file.puts "post_id: \"#{post['post_id']}\""
      file.puts "permalink: /posts/#{post['post_id']}"
      file.puts "post_created_at: #{post_created_at_unixtime}"
      file.puts "post_created_by: \"#{post_created_by}\""
      file.puts "post_last_edited_at: #{post_last_edited_at_unixtime}"
      file.puts "post_last_edited_by: \"#{post_last_edited_by}\""

      # Add post images sorted by order
      if post['post_images'] && !post['post_images'].empty?
        sorted_images = post['post_images'].sort_by { |img| img['order'] }
        file.puts 'post_images:'
        sorted_images.each do |image|
          file.puts "  - image_id: \"#{image['image_id']}\""
          file.puts "    caption: #{escape_html_for_yaml(image['caption'])}"
          alt_text_fixed = image['alt_text'].nil? ? '""' : "\"#{image['alt_text'].gsub('"', "'")}\""
          file.puts "    alt_text: #{alt_text_fixed}"
          file.puts "    order: #{image['order']}"
          file.puts "    uploaded_at: #{image['uploaded_at']}"
          file.puts "    thumbnail_url: \"#{image['thumbnail_url']}\""
          file.puts "    original_url: \"#{image['original_url']}\""
        end
      end

      file.puts '---'
      file.puts post['post_body'].gsub('<p><br></p>', '<p></p>')
    end
  end

  puts "Generated #{all_council_info_data['council_posts'].length} post files in _posts directory"

  # Process announcements
  Dir.mkdir('_announcements') unless Dir.exist?('_announcements')
  # Delete existing announcement files
  Dir.glob('_announcements/*.md').each { |file| File.delete(file) }
  if all_council_info_data.key?('council_announcements') && !all_council_info_data['council_announcements'].empty?
    all_council_info_data['council_announcements'].each do |announcement|
      sent_at_localized = tz.to_local(Time.at(announcement['sent_at']))
      # Use email subject if available, otherwise create generic title
      title_for_filename = announcement['email_subject'] || announcement['sent_at'].to_s
      sanitized_title = title_for_filename.downcase.gsub(/[^a-z0-9\s]/, '').gsub(/\s+/, '_').gsub(/_+/, '_').gsub(
        /^_|_$/, ''
      )
      filename = "_announcements/#{sent_at_localized.strftime('%Y-%m-%d')}-#{sanitized_title}.md"

      # Create announcement markdown file
      File.open(filename, 'w') do |file|
        file.puts '---'
        file.puts 'layout: announcement'
        file.puts "announcement_id: #{announcement['announcement_id']}"
        file.puts "announcement_types: #{announcement['announcement_types'].to_json}"
        file.puts "sent_at: #{announcement['sent_at']}"

        # Include email content if it exists
        if announcement['announcement_types'].include?('email')
          file.puts "title: #{escape_html_for_yaml(announcement['email_subject'])}"
          file.puts "email_subject: #{escape_html_for_yaml(announcement['email_subject'])}"
          file.puts "email_body: #{escape_html_for_yaml(announcement['email_body'])}"
          # check that email_attachment_urls exists and handle the new structure
          if announcement['email_attachment_urls'] && !announcement['email_attachment_urls'].empty?
            file.puts "email_attachment_urls: #{announcement['email_attachment_urls'].to_json}"
          end
        else
          file.puts 'title: Council Announcement'
        end

        # Include SMS content if it exists
        if announcement['announcement_types'].include?('sms')
          file.puts "sms_body: #{escape_html_for_yaml(announcement['sms_body'])}"
        end

        # Include author if it exists
        file.puts "author: #{escape_html_for_yaml(announcement['author'])}" if announcement['author']

        file.puts "permalink: /announcements/#{announcement['announcement_id']}"

        file.puts '---'
      end
    end
    puts "Generated #{all_council_info_data['council_announcements'].length} announcement files in _announcements directory"
  else
    puts 'No announcements found in API response'
  end

  Dir.mkdir('assets/opengraph') unless Dir.exist?('assets/opengraph')

  # Generate robots.txt
  File.open('robots.txt', 'w') do |file|
    file.puts 'User-agent: *'
    file.puts 'Allow: /'
    file.puts "Sitemap: #{all_council_info_data['council_website_settings']['website_url']}/sitemap.xml"
  end
  puts 'Generated robots.txt'

  puts "\nEditing _config.yml..."
  config_path = '_config.yml'
  if File.exist?(config_path)
    config_content = File.read(config_path)

    council_site_url = all_council_info_data['council_website_settings']['website_url']
    updated_content = config_content.gsub(/^url: .*$/, "url: #{council_site_url}")

    File.write(config_path, updated_content)
    puts "Updated #{config_path}"
  else
    puts "Warning: #{config_path} not found, skipping config update."
  end

  total_duration = Time.now - script_start_time
  puts "\n=== sync_data.rb completed in #{total_duration.round(2)}s ==="
rescue StandardError => e
  puts "ERROR: sync_data.rb failed: #{e.message}"
  puts e.backtrace.first(5).join("\n") if e.backtrace
  exit 1
end
