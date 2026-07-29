# ERPmine MCP - Model Context Protocol server for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# NOTE: Files under lib/ and app/ are loaded by Redmine through Zeitwerk
# (see Redmine::PluginLoader#add_autoload_paths). Do NOT require them here:
#  - lib/redmine_mcp.rb                  -> RedmineMcp
#  - lib/redmine_mcp/server.rb           -> RedmineMcp::Server
#  - lib/redmine_mcp/registry.rb         -> RedmineMcp::Registry
#  - lib/redmine_mcp/catalog.rb          -> RedmineMcp::Catalog
#  - lib/redmine_mcp/rest_endpoint.rb    -> RedmineMcp::RestEndpoint
#  - lib/redmine_mcp/rest_client.rb      -> RedmineMcp::RestClient
#  - app/controllers/mcp_controller.rb   -> McpController
#  - app/controllers/mcp_oauth_controller.rb -> McpOauthController

Redmine::Plugin.register :redmine_mcp do
  name 'Redmine MCP'
  author 'Adhi Software Pvt Ltd'
  description 'Redmine MCP'
  version RedmineMcp::VERSION
  requires_redmine version_or_higher: '6.0.0'
  author_url 'http://www.adhisoftware.co.in/'

  # The MCP endpoint authenticates with a Redmine REST API key, so it does not
  # add its own project/global permission. Access to data is still bounded by
  # the authenticated user (ERPmine permissions are enforced inside each tool).
  settings(
    partial: 'settings/redmine_mcp_settings',
    default: {}
  )
end
