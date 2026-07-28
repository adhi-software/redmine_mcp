# MCP Streamable-HTTP endpoint.
# Clients POST JSON-RPC 2.0 messages here. A GET is used by some clients to
# open an SSE stream; we don't push server-initiated messages, so it returns 405.
post 'mcp', to: 'mcp#handle'
get  'mcp', to: 'mcp#info'

# OAuth 2.0 discovery for MCP clients that authenticate via OAuth (e.g. the
# claude.ai web connector). Served at the domain root; backed by Redmine's
# Doorkeeper provider (/oauth/authorize, /oauth/token). See McpOauthController.
get  '.well-known/oauth-protected-resource',       to: 'mcp_oauth#protected_resource'
get  '.well-known/oauth-protected-resource/mcp',   to: 'mcp_oauth#protected_resource'
get  '.well-known/oauth-authorization-server',     to: 'mcp_oauth#authorization_server'
get  '.well-known/oauth-authorization-server/mcp', to: 'mcp_oauth#authorization_server'
post 'oauth/mcp_register', to: 'mcp_oauth#register'
