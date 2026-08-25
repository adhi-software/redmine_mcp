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
  # Builds the tool list from Catalog. Eager rather than class auto-discovery, so
  # behaviour is the same under lazy (development) and eager (production) loading.
  module Registry
    module_function

    # All tool instances, built once from the catalogue.
    def tools
      @tools ||= Catalog.entries.map do |name, method, path, description|
        RestEndpoint.new(name: name, method: method, path: path, description: description)
      end.freeze
    end

    # Tool descriptors for tools/list.
    def definitions
      tools.map(&:definition)
    end

    # Look up a tool by its declared name.
    def find(name)
      tools.find { |tool| tool.tool_name == name }
    end
  end
end
