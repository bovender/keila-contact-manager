require "test_helper"

class KeilaProjectsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as(users(:one)) }

  test "index lists all projects" do
    get keila_projects_path
    assert_response :success
    assert_match "Alpha", response.body
    assert_match "Beta", response.body
  end

  test "create adds a project and activates it if none is active yet" do
    users(:one).update!(current_keila_project: nil)

    assert_difference "KeilaProject.count", 1 do
      post keila_projects_path, params: { keila_project: { name: "Gamma", keila_api_key: "gamma-key" } }
    end

    assert_redirected_to keila_projects_path
    assert_equal "Gamma", users(:one).reload.current_keila_project.name
  end

  test "create does not steal the active project away from an already-active one" do
    assert_difference "KeilaProject.count", 1 do
      post keila_projects_path, params: { keila_project: { name: "Gamma", keila_api_key: "gamma-key" } }
    end

    assert_equal keila_projects(:alpha), users(:one).reload.current_keila_project
  end

  test "create rejects a duplicate name" do
    assert_no_difference "KeilaProject.count" do
      post keila_projects_path, params: { keila_project: { name: keila_projects(:alpha).name } }
    end
    assert_response :unprocessable_entity
  end

  test "create requires an API key" do
    assert_no_difference "KeilaProject.count" do
      post keila_projects_path, params: { keila_project: { name: "Gamma" } }
    end
    assert_response :unprocessable_entity
  end

  test "update changes the name and api key" do
    patch keila_project_path(keila_projects(:alpha)), params: {
      keila_project: { name: "Alpha 2", keila_api_key: "secret" }
    }

    assert_redirected_to keila_projects_path
    project = keila_projects(:alpha).reload
    assert_equal "Alpha 2", project.name
    assert_equal "secret", project.keila_api_key
  end

  test "update with a blank api key leaves the existing key untouched" do
    patch keila_project_path(keila_projects(:alpha)), params: {
      keila_project: { keila_api_key: "" }
    }

    assert_redirected_to keila_projects_path
    assert_equal "alpha-key", keila_projects(:alpha).reload.keila_api_key
  end

  test "destroy removes the project and its local contacts only" do
    assert_difference "KeilaProject.count" => -1, "Contact.count" => -2 do
      delete keila_project_path(keila_projects(:alpha))
    end
    assert_redirected_to keila_projects_path
    assert_match(/Nothing was deleted in Keila/, flash[:notice])
  end

  test "activate switches the user's active project" do
    post activate_keila_project_path(keila_projects(:beta))

    assert_redirected_to contacts_path
    assert_equal keila_projects(:beta), users(:one).reload.current_keila_project
  end

  test "test_connection reports success" do
    stub_request(:get, "https://keila.example.com/api/v1/contacts")
      .with(query: { "paginate[page]" => "0", "paginate[page_size]" => "1" },
            headers: { "Authorization" => "Bearer alpha-key" })
      .to_return(status: 200, body: { data: [], meta: { count: 7 } }.to_json)

    post test_connection_keila_project_path(keila_projects(:alpha))

    assert_redirected_to keila_projects_path
    assert_equal "Connected to Keila: Alpha has 7 contact(s) there.", flash[:notice]
  end

  test "test_connection reports failure" do
    stub_request(:get, "https://keila.example.com/api/v1/contacts")
      .with(query: { "paginate[page]" => "0", "paginate[page_size]" => "1" })
      .to_return(status: 401, body: { error: "unauthorized" }.to_json)

    post test_connection_keila_project_path(keila_projects(:alpha))

    assert_redirected_to keila_projects_path
    assert_match(/Could not connect to Keila/, flash[:alert])
  end

  test "test_connection without a configured instance redirects with an alert" do
    with_keila_url(nil) { post test_connection_keila_project_path(keila_projects(:beta)) }

    assert_redirected_to keila_projects_path
    assert_match(/set the KEILA_URL/, flash[:alert])
  end
end
