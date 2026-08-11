# OAuth 2.0 discovery + dynamic client registration, for MCP clients that
# authenticate with OAuth rather than an API key (the claude.ai web connector).
#
# Only the discovery documents (RFC 9728, RFC 8414) and dynamic registration
# (RFC 7591) live here — Redmine's own Doorkeeper provider handles authorize,
# token and PKCE, and McpController accepts the bearer tokens it issues.
#
# Inherits ActionController::Base to stay outside Redmine's session/login
# machinery: these endpoints are unauthenticated by design.
class McpOauthController < ActionController::Base
  skip_forgery_protection

  # GET /.well-known/oauth-protected-resource(/mcp)
  def protected_resource
    render json: {
      'resource' => "#{base_url}/mcp",
      'authorization_servers' => [base_url],
      'bearer_methods_supported' => %w[header],
      'resource_name' => 'Redmine/ERPmine MCP'
    }
  end

  # GET /.well-known/oauth-authorization-server(/mcp)
  def authorization_server
    render json: {
      'issuer' => base_url,
      'authorization_endpoint' => "#{base_url}/oauth/authorize",
      'token_endpoint' => "#{base_url}/oauth/token",
      'registration_endpoint' => "#{base_url}/oauth/mcp_register",
      'response_types_supported' => %w[code],
      'response_modes_supported' => %w[query],
      'grant_types_supported' => %w[authorization_code refresh_token],
      'token_endpoint_auth_methods_supported' => %w[client_secret_basic client_secret_post none],
      'code_challenge_methods_supported' => %w[S256 plain]
    }
  end

  # POST /oauth/mcp_register (RFC 7591). Creates a Doorkeeper application so the
  # connector gets a client_id with no human pre-registration. Public clients
  # (token_endpoint_auth_method "none", PKCE) are created non-confidential.
  def register
    body = parse_json_body
    redirect_uris = Array(body['redirect_uris']).reject(&:blank?)
    if redirect_uris.empty?
      return render json: { 'error' => 'invalid_redirect_uri',
                            'error_description' => 'redirect_uris is required' }, status: :bad_request
    end

    auth_method = body['token_endpoint_auth_method'].presence || 'client_secret_basic'
    confidential = auth_method != 'none'

    app = Doorkeeper::Application.new(
      name: body['client_name'].presence || 'MCP Client',
      redirect_uri: redirect_uris.join("\n"),
      scopes: '',
      confidential: confidential
    )
    unless app.save
      return render json: { 'error' => 'invalid_client_metadata',
                            'error_description' => app.errors.full_messages.join(', ') }, status: :bad_request
    end

    response = {
      'client_id' => app.uid,
      'client_id_issued_at' => Time.now.to_i,
      'client_name' => app.name,
      'redirect_uris' => redirect_uris,
      'grant_types' => %w[authorization_code refresh_token],
      'response_types' => %w[code],
      'token_endpoint_auth_method' => confidential ? 'client_secret_basic' : 'none',
      'scope' => app.scopes.to_s
    }
    response['client_secret'] = app.plaintext_secret if confidential
    render json: response, status: :created
  rescue => e
    Rails.logger.error("[redmine_mcp] DCR failed: #{e.class}: #{e.message}")
    render json: { 'error' => 'server_error', 'error_description' => e.message }, status: :internal_server_error
  end

  private

  # Reuses the REST base-URL resolution so advertised endpoints match what the
  # connector actually calls.
  def base_url
    RedmineMcp::RestClient.base_url
  end

  def parse_json_body
    raw = request.body.read
    raw.blank? ? {} : JSON.parse(raw)
  rescue JSON::ParserError
    {}
  end
end
