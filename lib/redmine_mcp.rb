# Top-level namespace for the Redmine/ERPmine MCP server.
module RedmineMcp
  VERSION = '1.0'

  # Fallback when the client requests a version we don't support, or none. MUST
  # be a real revision we speak (the newest in Server::SUPPORTED_PROTOCOL_VERSIONS)
  # — otherwise clients reject the handshake and disconnect.
  DEFAULT_PROTOCOL_VERSION = '2025-06-18'

  # Raised by a tool to return a clean, user-facing tool error
  # (isError: true) instead of a JSON-RPC protocol error.
  class ToolError < StandardError; end
end
