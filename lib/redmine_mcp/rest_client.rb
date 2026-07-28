require 'net/http'
require 'uri'

module RedmineMcp
  # Thin HTTP client that calls the Redmine/ERPmine REST API on behalf of the
  # authenticated user. Every MCP "REST" tool funnels through here, so the tools
  # themselves stay declarative (see RestEndpoint / Catalog).
  #
  # The request is sent to this same Redmine instance over HTTP, authenticated
  # with the user's own Redmine API key, so the call is subject to exactly the
  # permissions and JSON serialisation of the real REST endpoint.
  #
  # Base URL resolution (first match wins):
  #   1. ENV['REDMINE_MCP_BASE_URL']   e.g. http://127.0.0.1:3000
  #   2. "#{Setting.protocol}://#{Setting.host_name}"
  #
  # Set ENV['REDMINE_MCP_VERIFY_SSL'] = '0' to skip TLS verification when the
  # instance uses a self-signed certificate.
  module RestClient
    DEFAULT_OPEN_TIMEOUT = 10
    DEFAULT_READ_TIMEOUT = 60

    # Returned by .request. `body` is the parsed JSON (Hash/Array) when the
    # response is JSON, otherwise the raw string (or nil for an empty body).
    Response = Struct.new(:status, :body, :content_type, keyword_init: true) do
      def success?
        status.to_i.between?(200, 299)
      end

      def json?
        content_type.to_s.include?('json')
      end
    end

    module_function

    # Perform a request and return a Response.
    #   method   - :get / :post / :put / :patch / :delete
    #   path     - absolute path beginning with '/', e.g. '/issues/42.json'
    #   api_key  - the user's Redmine API key
    #   query    - Hash appended as the query string
    #   body     - Hash serialised as a JSON request body (write methods)
    def request(method:, path:, api_key:, query: nil, body: nil)
      uri = build_uri(path, query)
      http_request = build_request(method, uri, api_key, body)

      http = Net::HTTP.new(uri.host, uri.port)
      configure_transport(http, uri)

      response = http.request(http_request)
      Response.new(
        status: response.code.to_i,
        body: parse_body(response),
        content_type: response['Content-Type']
      )
    rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
      raise ToolError, "Could not reach the Redmine REST API at #{base_url}: #{e.class}: #{e.message}. " \
                       "Set REDMINE_MCP_BASE_URL if the host is not reachable from the server process."
    end

    # The base URL all requests are sent to.
    def base_url
      override = ENV['REDMINE_MCP_BASE_URL'].to_s.strip
      return override.chomp('/') unless override.empty?

      "#{Setting.protocol}://#{Setting.host_name}".chomp('/')
    end

    # --- internals ---------------------------------------------------------

    def build_uri(path, query)
      uri = URI.parse("#{base_url}#{path}")
      qs = encode_query(query)
      uri.query = [uri.query, qs].compact.reject(&:empty?).join('&') if qs
      uri
    end

    # Flatten a params hash into a query string. Array values are comma-joined,
    # which matches Redmine's list filters (e.g. issue_id=1,2,3).
    def encode_query(query)
      return nil if query.blank?

      query.map do |key, value|
        v = value.is_a?(Array) ? value.join(',') : value
        "#{URI.encode_www_form_component(key.to_s)}=#{URI.encode_www_form_component(v.to_s)}"
      end.join('&')
    end

    def build_request(method, uri, api_key, body)
      klass = {
        get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put,
        patch: Net::HTTP::Patch, delete: Net::HTTP::Delete
      }.fetch(method.to_sym) { raise ToolError, "Unsupported HTTP method: #{method}" }

      req = klass.new(uri)
      req['X-Redmine-API-Key'] = api_key
      req['Accept'] = 'application/json'
      unless body.nil?
        req['Content-Type'] = 'application/json'
        req.body = JSON.generate(body)
      end
      req
    end

    def configure_transport(http, uri)
      http.open_timeout = DEFAULT_OPEN_TIMEOUT
      http.read_timeout = DEFAULT_READ_TIMEOUT
      return unless uri.scheme == 'https'

      http.use_ssl = true
      http.verify_mode = if ENV['REDMINE_MCP_VERIFY_SSL'].to_s == '0'
                           OpenSSL::SSL::VERIFY_NONE
                         else
                           OpenSSL::SSL::VERIFY_PEER
                         end
      system_ca_file = ENV.fetch('SSL_CERT_FILE', '/etc/ssl/certs/ca-certificates.crt')
      http.ca_file = system_ca_file if File.exist?(system_ca_file)
    end

    def parse_body(response)
      raw = response.body
      return nil if raw.nil? || raw.empty?
      return raw unless response['Content-Type'].to_s.include?('json')

      JSON.parse(raw)
    rescue JSON::ParserError
      raw
    end
  end
end
