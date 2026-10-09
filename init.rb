# ERPmine MCP - Model Context Protocol server for Redmine / ERPmine
# Copyright (C) 2026
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.

# Files under lib/ and app/ are autoloaded by Zeitwerk — do NOT require them here.

Redmine::Plugin.register :redmine_mcp do
  name 'Redmine MCP'
  author 'Adhi Software Pvt Ltd'
  description 'Redmine MCP'
  version RedmineMcp::VERSION
  requires_redmine version_or_higher: '6.0.0'
  author_url 'http://www.adhisoftware.co.in/'

  # No permission of its own: the endpoint authenticates with a REST API key and
  # every tool is bounded by that user's own permissions.
  settings(
    partial: 'settings/redmine_mcp_settings',
    default: {}
  )
end
