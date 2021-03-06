module Onebox
  module Helpers

    class DownloadTooLarge < StandardError; end;

    def self.symbolize_keys(hash)
      return {} if hash.nil?

      hash.inject({}){|result, (key, value)|
        new_key = key.is_a?(String) ? key.to_sym : key
        new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
        result[new_key] = new_value
        result
      }
    end

    def self.clean(html)
      html.gsub(/<[^>]+>/, ' ').gsub(/\n/, '')
    end

    def self.extract_opengraph(doc)
      return {} unless doc

      og = {}

      doc.css('meta').each do |m|
        if (m["property"] && m["property"][/^og:(.+)$/i]) || (m["name"] && m["name"][/^og:(.+)$/i])
          value = (m["content"] || m["value"]).to_s
          og[$1.tr('-:','_').to_sym] ||= value unless Onebox::Helpers::blank?(value)
        end
      end

      # Attempt to retrieve the title from the meta tag
      title_element = doc.at_css('title')
      if title_element && title_element.text
        og[:title] ||= title_element.text unless Onebox::Helpers.blank?(title_element.text)
      end

      og
    end

    def self.fetch_response(location, limit=nil, domain=nil, headers=nil)

      limit ||= 5
      limit = Onebox.options.redirect_limit if limit > Onebox.options.redirect_limit

      raise Net::HTTPError.new('HTTP redirect too deep', location) if limit == 0

      uri = URI(location)
      uri = URI("#{domain}#{location}") if !uri.host

      result = StringIO.new
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.is_a?(URI::HTTPS)) do |http|
        http.open_timeout = Onebox.options.connect_timeout
        http.read_timeout = Onebox.options.timeout
        if uri.is_a?(URI::HTTPS)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end

        headers ||= {}

        if Onebox.options.user_agent && !headers['User-Agent']
          headers['User-Agent'] = Onebox.options.user_agent
        end

        request = Net::HTTP::Get.new(uri.request_uri, headers)
        start_time = Time.now

        size_bytes = Onebox.options.max_download_kb * 1024
        http.request(request) do |response|

          if cookie = response.get_fields('set-cookie')
            header = { 'Cookie' => cookie.join }
          end

          header = nil unless header.is_a? Hash

          code = response.code.to_i
          unless code === 200
            response.error! unless [301, 302].include?(code)
            return fetch_response(
              response['location'],
              limit - 1,
              "#{uri.scheme}://#{uri.host}",
              header
            )
          end

          response.read_body do |chunk|
            result.write(chunk)
            raise DownloadTooLarge.new if result.size > size_bytes
            raise Timeout::Error.new if (Time.now - start_time) > Onebox.options.timeout
          end

          return result.string
        end
      end
    end

    def self.fetch_content_length(location)
      uri = URI(location)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.is_a?(URI::HTTPS)) do |http|
        http.open_timeout = Onebox.options.connect_timeout
        http.read_timeout = Onebox.options.timeout
        if uri.is_a?(URI::HTTPS)
          http.use_ssl = true
          http.verify_mode = OpenSSL::SSL::VERIFY_NONE
        end

        http.request_head([uri.path, uri.query].join("?")) do |response|
          code = response.code.to_i
          unless code === 200 || response.header['content-length'].blank?
            return nil
          end
          return response.header['content-length']
        end
      end
    end

    def self.pretty_filesize(size)
      conv = [ 'B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB' ];
      scale = 1024;

      ndx=1
      if( size < 2*(scale**ndx)  ) then
        return "#{(size)} #{conv[ndx-1]}"
      end
      size=size.to_f
      [2,3,4,5,6,7].each do |i|
        if (size < 2*(scale**i)) then
          return "#{'%.2f' % (size/(scale**(i-1)))} #{conv[i-1]}"
        end
      end
      ndx=7
      return "#{'%.2f' % (size/(scale**(ndx-1)))} #{conv[ndx-1]}"
    end

    def self.click_to_scroll_div(width = 690, height = 400)
      "<div style=\"background:transparent;position:relative;width:#{width}px;height:#{height}px;top:#{height}px;margin-top:-#{height}px;\" onClick=\"style.pointerEvents='none'\"></div>"
    end

    def self.blank?(value)
      if value.respond_to?(:blank?)
        value.blank?
      else
        value.respond_to?(:empty?) ? !!value.empty? : !value
      end
    end

    def self.truncate(string, length = 50)
      string.size > length ? string[0...(string.rindex(" ", length)||length)] + "..." : string
    end

    def self.title_attr(meta)
      (meta && !blank?(meta[:title])) ? "title='#{meta[:title]}'" : ""
    end

    def self.normalize_url_for_output(url)
      return "" unless url
      url = url.dup
      # expect properly encoded url, remove any unsafe chars
      url.gsub!("'", "&apos;")
      url.gsub!('"', "&quot;")
      url.gsub!(/[^\w\-`.~:\/?#\[\]@!$&'\(\)*+,;=%]/, "")
      url
    end

  end
end
