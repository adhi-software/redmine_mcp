# MCP Streamable-HTTP transport for Redmine/ERPmine.
#
# Speaks JSON-RPC 2.0 over HTTP POST. Authenticates with a Redmine REST API key
# supplied as `Authorization: Bearer <key>`, the `X-Redmine-API-Key` header, or
# a `key` query param. The authenticated user becomes User.current for the
# duration of the request, so every tool runs with that user's data scope and
# ERPmine permissions.
#
# Inherits from ActionController::Base (not Redmine's ApplicationController) to
# bypass session/login/menu machinery and CSRF; we do our own key auth instead.
class McpController < ActionController::Base
  skip_forgery_protection

  # POST /mcp - handle one JSON-RPC message or a batch.
  def handle
    user = authenticate
    return render_unauthorized if user.nil?

    payload = parse_body
    return render(json: jsonrpc_parse_error, status: :ok) if payload == :parse_error

    User.current = user
    server = RedmineMcp::Server.new(user)

    if payload.is_a?(Array)
      responses = payload.map { |message| server.handle(message) }.compact
      responses.empty? ? head(:accepted) : render(json: responses)
    elsif payload.is_a?(Hash)
      response = server.handle(payload)
      response.nil? ? head(:accepted) : render(json: response)
    else
      render json: { 'jsonrpc' => '2.0', 'id' => nil,
                     'error' => { 'code' => -32_600, 'message' => 'Invalid Request' } }
    end
  ensure
    User.current = User.anonymous
  end

  # GET /mcp - we do not offer a server->client SSE stream.
  def info
    response.headers['Allow'] = 'POST'
    render json: { 'jsonrpc' => '2.0', 'id' => nil,
                   'error' => { 'code' => -32_000,
                                'message' => 'This MCP endpoint only supports POST (JSON-RPC).' } },
           status: :method_not_allowed
  end

  private

  # Authenticate via a Redmine API key (header/bearer/param) or, failing that,
  # an OAuth 2.0 bearer token issued by Redmine's Doorkeeper provider (used by
  # the claude.ai web connector — see McpOauthController).
  def authenticate
    authenticate_with_api_key || authenticate_with_oauth
  end

  def authenticate_with_api_key
    key = api_key_from_request
    return nil if key.blank?

    user = User.find_by_api_key(key)
    user if user&.active?
  end

  def authenticate_with_oauth
    token = Doorkeeper.authenticate(request)
    return nil unless token&.accessible?

    User.active.find_by(id: token.resource_owner_id)
  rescue => e
    Rails.logger.error("[redmine_mcp] OAuth auth failed: #{e.class}: #{e.message}")
    nil
  end

  def api_key_from_request
    auth = request.authorization.to_s
    if auth =~ /\ABearer\s+(.+)\z/i
      Regexp.last_match(1).strip
    elsif request.headers['X-Redmine-API-Key'].present?
      request.headers['X-Redmine-API-Key'].to_s
    elsif params[:key].present?
      params[:key].to_s
    end
  end

  def parse_body
    raw = request.body.read
    return nil if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    :parse_error
  end

  def render_unauthorized
    # Point OAuth-capable clients (e.g. the claude.ai web connector) at the
    # protected-resource metadata so they can discover the authorization server
    # and run the OAuth flow. API-key clients can ignore this header.
    metadata_url = "#{RedmineMcp::RestClient.base_url}/.well-known/oauth-protected-resource"
    response.headers['WWW-Authenticate'] =
      %(Bearer realm="Redmine MCP", resource_metadata="#{metadata_url}")
    render json: { 'jsonrpc' => '2.0', 'id' => nil,
                   'error' => { 'code' => -32_001,
                                'message' => 'Unauthorized: provide a valid Redmine API key ' \
                                             '(Authorization: Bearer <key> or X-Redmine-API-Key) ' \
                                             'or an OAuth bearer token.' } },
           status: :unauthorized
  end

  def jsonrpc_parse_error
    { 'jsonrpc' => '2.0', 'id' => nil,
      'error' => { 'code' => -32_700, 'message' => 'Parse error' } }
  end
end
