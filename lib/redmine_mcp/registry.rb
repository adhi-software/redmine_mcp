module RedmineMcp
  # Central catalogue of available tools.
  #
  # Every tool is a REST endpoint described declaratively in Catalog and wrapped
  # by a RestEndpoint instance. Building the list eagerly (rather than
  # auto-discovering classes) keeps behaviour identical under Rails lazy
  # autoloading (development) and eager loading (production).
  #
  # To expose a new core Redmine endpoint, add a row to RedmineMcp::Catalog.
  # Plugin-specific tools (e.g. ERPmine) are contributed from their own plugin
  # via the :redmine_mcp_register_tools hook and merged in by Catalog.entries.
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
