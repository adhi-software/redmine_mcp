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
