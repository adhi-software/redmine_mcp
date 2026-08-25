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

module RedmineMcp
  # Transport-agnostic MCP server: turns a single parsed JSON-RPC 2.0 message
  # into a response hash (or nil for notifications). Used by both the HTTP
  # controller and the stdio bridge.
  #
  # Implements the methods an MCP client needs: initialize, ping, tools/list,
  # tools/call, and the notifications/* acknowledgements.
  class Server
    SERVER_INFO = { 'name' => 'redmine-erpmine-mcp', 'version' => RedmineMcp::VERSION }.freeze
    SUPPORTED_PROTOCOL_VERSIONS = %w[2025-06-18 2025-03-26 2024-11-05].freeze

    def initialize(user)
      @user = user
    end

    # message: parsed JSON-RPC object (Hash). Returns a response Hash, or nil
    # when no response is due (notifications carry no id).
    def handle(message)
      return invalid_request(nil) unless message.is_a?(Hash)

      id = message['id']
      method = message['method']
      params = message['params'] || {}

      # Notifications (no id) are acknowledged at the transport layer, not here.
      return nil if id.nil? && method.to_s.start_with?('notifications/')

      case method
      when 'initialize'
        result(id, initialize_result(params))
      when 'ping'
        result(id, {})
      when 'tools/list'
        result(id, { 'tools' => Registry.definitions })
      when 'tools/call'
        handle_tool_call(id, params)
      when 'notifications/initialized', 'notifications/cancelled'
        nil
      else
        error(id, -32_601, "Method not found: #{method}")
      end
    rescue => e
      Rails.logger.error("[redmine_mcp] #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
      error(message.is_a?(Hash) ? message['id'] : nil, -32_603, "Internal error: #{e.message}")
    end

    private

    def initialize_result(params)
      requested = params['protocolVersion']
      version = SUPPORTED_PROTOCOL_VERSIONS.include?(requested) ? requested : RedmineMcp::DEFAULT_PROTOCOL_VERSION
      {
        'protocolVersion' => version,
        'capabilities' => { 'tools' => { 'listChanged' => false } },
        'serverInfo' => SERVER_INFO,
        'instructions' => 'Redmine/ERPmine tools'
      }
    end

    def handle_tool_call(id, params)
      name = params['name']
      arguments = params['arguments'] || {}
      tool = Registry.find(name)
      return error(id, -32_602, "Unknown tool: #{name}") if tool.nil?

      begin
        output = tool.call(arguments, context)
        result(id, tool_content(output))
      rescue ToolError => e
        result(id, tool_content(e.message, is_error: true))
      rescue => e
        Rails.logger.error("[redmine_mcp] tool #{name} failed: #{e.class}: #{e.message}\n#{e.backtrace&.first(5)&.join("\n")}")
        result(id, tool_content("#{e.class}: #{e.message}", is_error: true))
      end
    end

    def context
      { user: @user }
    end

    # Build an MCP tools/call result payload from a tool's return value.
    def tool_content(output, is_error: false)
      if output.is_a?(String)
        { 'content' => [text_block(output)], 'isError' => is_error }
      else
        payload = { 'content' => [text_block(JSON.pretty_generate(output))], 'isError' => is_error }
        payload['structuredContent'] = output if output.is_a?(Hash)
        payload
      end
    end

    def text_block(text)
      { 'type' => 'text', 'text' => text.to_s }
    end

    # --- JSON-RPC envelope helpers -----------------------------------------

    def result(id, value)
      { 'jsonrpc' => '2.0', 'id' => id, 'result' => value }
    end

    def error(id, code, msg)
      { 'jsonrpc' => '2.0', 'id' => id, 'error' => { 'code' => code, 'message' => msg } }
    end

    def invalid_request(id)
      error(id, -32_600, 'Invalid Request')
    end
  end
end
