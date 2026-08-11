require 'erb'

module RedmineMcp
  # One MCP tool wrapping one REST URL, built from a Catalog row rather than a
  # hand-written class per endpoint.
  #
  # ":param" in a path becomes a required string argument. Everything else rides
  # on two generic arguments: "query" (merged into the query string) and "body"
  # (the JSON request body, for writes).
  class RestEndpoint
    WRITE_METHODS = %i[post put patch].freeze

    attr_reader :tool_name, :http_method, :path, :description

    def initialize(name:, method:, path:, description:)
      @tool_name = name
      @http_method = method.to_sym
      @path = path
      @description = description
      @path_params = path.scan(/:(\w+)/).flatten
    end

    # MCP descriptor for tools/list.
    def definition
      { 'name' => tool_name, 'description' => full_description, 'inputSchema' => input_schema }
    end

    # Invoked by the Server for tools/call. Returns a Hash so the result also
    # surfaces as MCP structuredContent.
    def call(arguments, context)
      arguments ||= {}
      api_key = api_key_for(context)

      response = RestClient.request(
        method: http_method,
        path: resolve_path(arguments),
        api_key: api_key,
        query: arguments['query'],
        body: write? ? arguments['body'] : nil
      )

      unless response.success?
        raise ToolError, "#{http_method.to_s.upcase} #{path} -> HTTP #{response.status}: #{summarize(response.body)}"
      end

      { 'status' => response.status, 'body' => response.body }
    end

    private

    def write?
      WRITE_METHODS.include?(http_method)
    end

    def api_key_for(context)
      user = context && context[:user]
      raise ToolError, 'No authenticated user for this request.' if user.nil?

      user.api_key
    end

    # Substitute :placeholders in the path from arguments, URL-encoding each.
    def resolve_path(arguments)
      path.gsub(/:(\w+)/) do
        key = Regexp.last_match(1)
        value = arguments[key]
        raise ToolError, "Missing required parameter '#{key}'." if value.nil? || value.to_s.empty?

        # Path-segment encoding: spaces become %20 (not '+', which is literal in a path).
        ERB::Util.url_encode(value.to_s)
      end
    end

    def input_schema
      properties = {}
      @path_params.each do |param|
        properties[param] = { 'type' => 'string', 'description' => "Path parameter :#{param}." }
      end
      properties['query'] = {
        'type' => 'object',
        'additionalProperties' => true,
        'description' => 'Parameters appended to the URL query string ' \
                         '(filters, pagination such as offset/limit, include=...).'
      }
      if write?
        properties['body'] = {
          'type' => 'object',
          'additionalProperties' => true,
          'description' => 'JSON request body, shaped as the REST API expects ' \
                           '(e.g. {"issue": {"subject": "..."}}).'
        }
      end

      schema = { 'type' => 'object', 'additionalProperties' => false, 'properties' => properties }
      schema['required'] = @path_params unless @path_params.empty?
      schema
    end

    def full_description
      "#{http_method.to_s.upcase} #{path} — #{description}"
    end

    def summarize(body)
      text = body.is_a?(String) ? body : JSON.generate(body)
      text.to_s.length > 500 ? "#{text[0, 500]}…" : text
    end
  end
end
