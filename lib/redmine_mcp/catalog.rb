module RedmineMcp
  # The declarative catalogue of REST API endpoints exposed as MCP tools.
  #
  # Each entry is [tool_name, http_method, path_template, description]. The path
  # is the real Redmine/ERPmine URL (always the .json representation); ":name"
  # segments are required path parameters. RestEndpoint turns each entry into a
  # callable tool, and RestClient performs the HTTP request with the caller's
  # API key.
  #
  # MINIMAL TOOL SET: to keep the tool list small (a large tool list inflates
  # every model request), only each module's "list" endpoint (list_* / *_index)
  # and its "detail/edit" endpoint (get_* / *_edit) are exposed — plus
  # create/update writes for the high-traffic Issues and Time entries modules.
  # Other endpoints (remaining writes, dropdown/option helpers, reports,
  # exports, sub-resource lookups, search, etc.) are intentionally omitted. To
  # expose another core Redmine endpoint, add a row here — no new class is
  # needed.
  #
  # PLUGIN TOOLS: this plugin only owns the MCP protocol/server and the core
  # Redmine REST surface. Tools that belong to a specific plugin (e.g. the
  # ERPmine modules in redmine_wktime) are NOT listed here. Instead each plugin
  # contributes its own rows at runtime through the :redmine_mcp_register_tools
  # hook (see #plugin_endpoints), so those tool definitions ship and version
  # with the plugin that implements them. If a contributing plugin is absent,
  # its tools are simply not registered.
  module Catalog
    module_function

    # The official Redmine REST API (controllers declaring accept_api_auth).
    def redmine_endpoints
      [
        # --- Issues ---------------------------------------------------------
        ['list_issues', :get, '/issues.json',     'List issues. Filter via query: project_id, status_id, assigned_to_id, tracker_id, sort, offset, limit, include=journals,attachments,relations.'],
        ['get_issue',   :get, '/issues/:id.json', 'Get one issue. query include=children,attachments,relations,changesets,journals,watchers.'],
        ['create_issue', :post, '/issues.json',     'Create an issue. body {"issue": {project_id, subject, tracker_id, status_id, priority_id, assigned_to_id, description, ...}}.'],
        ['update_issue', :put,  '/issues/:id.json', 'Update an issue. body {"issue": {subject, status_id, assigned_to_id, notes, done_ratio, ...}}.'],

        # --- Issue relations ------------------------------------------------
        ['list_issue_relations', :get, '/issues/:issue_id/relations.json', 'List an issue\'s relations.'],
        ['get_issue_relation',   :get, '/relations/:id.json',              'Get one issue relation.'],

        # --- Projects -------------------------------------------------------
        ['list_projects', :get, '/projects.json',     'List projects. query include=trackers,issue_categories,enabled_modules.'],
        ['get_project',   :get, '/projects/:id.json', 'Get one project. query include=trackers,issue_categories,enabled_modules,time_entry_activities.'],
        ['update_project', :put, '/projects/:id.json', 'Update a project. body {"project": {name, description, homepage, is_public, parent_id, inherit_members, enabled_module_names, tracker_ids, ...}}. Cannot change status — use archive_project/unarchive_project/close_project for that.'],
        ['archive_project',   :put, '/projects/:id/archive.json',   'Archive a project and all its subprojects (status becomes archived). Admin only. Takes no body.'],
        ['unarchive_project', :put, '/projects/:id/unarchive.json', 'Unarchive an archived project (restores it and its archived ancestors to active/closed). Admin only. Takes no body.'],
        ['close_project',     :put, '/projects/:id/close.json',     'Close a project and its subprojects (status becomes closed / read-only). Takes no body.'],

        # --- Project memberships --------------------------------------------
        ['list_project_memberships', :get, '/projects/:project_id/memberships.json', 'List a project\'s memberships.'],
        ['get_membership',           :get, '/memberships/:id.json',                  'Get one membership.'],
        ['create_membership',        :post, '/projects/:project_id/memberships.json', 'Add a member to a project. body {"membership": {user_id OR group_id, role_ids}}. Get role_ids from list_roles first — never guess them.'],
        ['update_membership',        :put,  '/memberships/:id.json',                  'Update a membership. body {"membership": {role_ids}}. Get role_ids from list_roles first — never guess them.'],

        # --- Roles ----------------------------------------------------------
        ['list_roles', :get, '/roles.json',     'List all roles (id and name). Use to resolve a role name like "Developer", "Manager" or "Reporter" to its role_id before create_membership/update_membership.'],
        ['get_role',   :get, '/roles/:id.json', 'Get one role with its permissions.'],

        # --- Users ----------------------------------------------------------
        ['list_users', :get, '/users.json',     'List users. query status, name, group_id, offset, limit.'],
        ['get_user',   :get, '/users/:id.json', 'Get one user (use id "current" for the caller). query include=memberships,groups.'],

        # --- Time entries ---------------------------------------------------
        ['list_time_entry_activities', :get, '/enumerations/time_entry_activities.json', 'List time-entry activities (id and name). Use to resolve an activity name to its activity_id before create_time_entry/update_time_entry.'],
        ['list_time_entries', :get, '/time_entries.json',     'List time entries. query user_id, project_id, issue_id, spent_on, from, to, offset, limit.'],
        ['get_time_entry',    :get, '/time_entries/:id.json', 'Get one time entry.'],
        ['create_time_entry', :post, '/time_entries.json',     'Log time. body {"time_entry": {issue_id OR project_id, hours, activity_id, spent_on, comments}}. activity_id is required — resolve a named activity via list_time_entry_activities; never send a null/blank activity_id.'],
        ['update_time_entry', :put,  '/time_entries/:id.json', 'Update a time entry. body {"time_entry": {hours, activity_id, comments, spent_on, ...}}.'],

        # --- Project files --------------------------------------------------
        ['list_files', :get, '/projects/:project_id/files.json', 'List a project\'s files (the Files module). Not the same as documents '],

        # --- Attachments ----------------------------------------------------
        ['get_attachment', :get, '/attachments/:id.json', 'Get attachment metadata.'],

        # --- Groups ---------------------------------------------------------
        ['list_groups', :get, '/groups.json',     'List groups.'],
        ['get_group',   :get, '/groups/:id.json', 'Get one group, including its members. query include=users,memberships.'],
        ['create_group', :post, '/groups.json', 'Create a group.'],
        ['add_group_user', :post, '/groups/:group_id/users.json', 'Add a user to a group.'],
      ]
    end

    # Rows contributed by other plugins through the :redmine_mcp_register_tools
    # hook. Each listener returns an array of catalogue rows in the same
    # [tool_name, http_method, path, description] shape used above; call_hook
    # wraps those per-listener returns in an outer array, which we flatten by
    # one level. Malformed returns (non-arrays, or rows that are not 4-element
    # arrays) are ignored so a misbehaving plugin cannot break tools/list.
    def plugin_endpoints
      Redmine::Hook.call_hook(:redmine_mcp_register_tools)
                   .flatten(1)
                   .select { |row| row.is_a?(Array) && row.size == 4 }
    end

    # All catalogue rows (core Redmine first, then plugin-contributed).
    def entries
      redmine_endpoints + plugin_endpoints
    end
  end
end
