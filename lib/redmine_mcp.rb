# Redmine MCP
# Copyright (C) 2026-  Adhi software pvt ltd
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

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
