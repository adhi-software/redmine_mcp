# Top-level namespace for the Redmine/ERPmine MCP server.
# Zeitwerk maps this file to the RedmineMcp constant; nested files under
# lib/redmine_mcp/ are autoloaded by convention (no manual requires).
module RedmineMcp
  VERSION = '1.0'

  # Protocol version the server falls back to when the client requests a version
  # we don't list in Server::SUPPORTED_PROTOCOL_VERSIONS (or requests none).
  # This MUST be a real MCP revision the server actually speaks — the newest
  # entry in SUPPORTED_PROTOCOL_VERSIONS — otherwise clients that requested a
  # newer version (e.g. Claude sends 2025-11-25) reject the handshake and
  # disconnect with "mcp returned an error when connecting".
  DEFAULT_PROTOCOL_VERSION = '2025-06-18'

  # Raised by a tool to return a clean, user-facing tool error
  # (isError: true) instead of a JSON-RPC protocol error.
  class ToolError < StandardError; end
end
