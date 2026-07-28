# frozen_string_literal: true
#
# Stdio MCP transport for clients that launch a local subprocess
# (e.g. Claude Desktop). It reuses RedmineMcp::Server, so it exposes exactly
# the same tools as the HTTP endpoint.
#
# Run it through Rails so the full ERPmine environment is loaded, e.g.:
#
#   cd <redmine-root>
#   REDMINE_API_KEY=<your-api-key> RAILS_ENV=production \
#     bundle exec rails runner plugins/redmine_mcp/extra/mcp_stdio_server.rb
#
# Messages are newline-delimited JSON-RPC 2.0 (one object per line), per the
# MCP stdio transport. Diagnostics go to stderr; stdout carries protocol only.

$stdout.sync = true

api_key = ENV['REDMINE_API_KEY'].to_s
if api_key.empty?
  warn '[redmine_mcp] REDMINE_API_KEY env var is required for the stdio server.'
  exit 1
end

user = User.find_by_api_key(api_key)
unless user&.active?
  warn '[redmine_mcp] REDMINE_API_KEY did not match an active user.'
  exit 1
end

User.current = user
server = RedmineMcp::Server.new(user)
warn "[redmine_mcp] stdio server ready as #{user.login} (#{user.name})."

STDIN.each_line do |line|
  line = line.strip
  next if line.empty?

  begin
    message = JSON.parse(line)
  rescue JSON::ParserError
    $stdout.puts({ 'jsonrpc' => '2.0', 'id' => nil,
                   'error' => { 'code' => -32_700, 'message' => 'Parse error' } }.to_json)
    next
  end

  response = server.handle(message)
  $stdout.puts(response.to_json) unless response.nil?
end
