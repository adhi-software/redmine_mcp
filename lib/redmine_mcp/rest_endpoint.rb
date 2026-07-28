require 'erb'

module RedmineMcp
  # One MCP tool that maps to one Redmine/ERPmine REST API URL.
  #
  # Instead of hand-writing a class per endpoint, each endpoint is described
  # declaratively in Catalog and wrapped by an instance of this class. The
  # instance exposes the same surface the Server expects from a tool:
  #   * #tool_name   - the MCP tool name
  #   * #definition  - the tools/list descriptor (name, description, inputSchema)
  #   * #call(args, context) - perform the HTTP request and return the result
  #
  # Path templates use ":param" placeholders (e.g. "/issues/:id.json"); each
  # placeholder becomes a required string argument. Two generic arguments cover
  # everything else the REST API accepts:
  #   * "query" - object merged into the URL query string (filters, pagination,
  #               include=..., and any identifiers an ERPmine action reads from
  #               params).
  #   * "body"  - object sent as the JSON request body for write methods, shaped
  #               exactly like the REST API expects (e.g. {"issue": {...}}).
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
