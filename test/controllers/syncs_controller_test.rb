require "test_helper"

class SyncsControllerTest < ActionDispatch::IntegrationTest
  CONTACTS_URL = "https://keila.example.com/api/v1/contacts".freeze

  setup do
    sign_in_as(users(:one))
    @project = keila_projects(:alpha)
  end

  def stub_keila_contacts(contacts)
    stub_request(:get, CONTACTS_URL)
      .with(query: hash_including({}), headers: { "Authorization" => "Bearer alpha-key" })
      .to_return(status: 200, body: { data: contacts, meta: { page_count: 1, count: contacts.size } }.to_json)
  end

  # Both fixture contacts as Keila has them after a sync.
  def mark_synced
    [ contacts(:one), contacts(:two) ].each_with_index.map do |contact, i|
      contact.update!(keila_id: "nc_#{i}", sync_snapshot: contact.sync_state)
      contact.sync_state.merge("id" => "nc_#{i}", "data" => contact.data.merge(Contact::RESERVED_DATA_KEY => contact.uuid))
    end.tap { @project.update!(last_synced_at: 1.hour.ago) }
  end

  test "status says when everything is in sync" do
    stub_keila_contacts(mark_synced)

    get status_sync_path

    assert_response :success
    assert_match "In sync with Keila", response.body
  end

  test "status offers one-click sync for plain changes" do
    remote = mark_synced
    remote[0]["first_name"] = "Ally"
    stub_keila_contacts(remote)

    get status_sync_path

    assert_match "Sync due", response.body
    assert_match "1 change in Keila", response.body
    assert_match "Sync now", response.body
  end

  test "status asks for a review before the first sync" do
    stub_keila_contacts([])

    get status_sync_path

    assert_match "Not synced with Keila yet", response.body
  end

  test "status reports when Keila can't be reached" do
    stub_request(:get, CONTACTS_URL).with(query: hash_including({})).to_return(status: 401, body: "unauthorized")

    get status_sync_path

    assert_response :success
    assert_match "Couldn't check Keila", response.body
  end

  test "status says sync is off without a Keila instance" do
    with_keila_url(nil) { get status_sync_path }

    assert_match "no Keila instance configured", response.body
  end

  test "show lists changes and conflicts" do
    remote = mark_synced
    contacts(:one).update!(first_name: "Ally")
    remote[0]["first_name"] = "Alicia"
    remote[1]["last_name"] = "Browne"
    stub_keila_contacts(remote)

    get sync_path

    assert_response :success
    assert_match "Ally", response.body
    assert_match "Alicia", response.body
    assert_match "Browne", response.body
  end

  test "create carries out the sync and reports what it did" do
    remote = mark_synced
    remote[1]["last_name"] = "Browne"
    stub_keila_contacts(remote)

    post sync_path, params: { one_click: 1 }

    assert_redirected_to contacts_path
    assert_equal "Synced with Keila: 1 updated from Keila.", flash[:notice]
    assert_equal "Browne", contacts(:two).reload.last_name
  end

  test "create pushes local changes to Keila" do
    remote = mark_synced
    contacts(:one).update!(first_name: "Ally")
    stub_keila_contacts(remote)
    update = stub_request(:patch, "#{CONTACTS_URL}/nc_0")
      .with(body: { data: { "first_name" => "Ally" } }.to_json)
      .to_return(status: 200, body: { data: remote[0].merge("first_name" => "Ally") }.to_json)

    post sync_path

    assert_requested update
    assert_match "1 updated in Keila", flash[:notice]
  end

  test "create refuses one-click when there's something to review" do
    remote = mark_synced
    remote.pop # bob deleted in Keila
    stub_keila_contacts(remote)

    post sync_path, params: { one_click: 1 }

    assert_redirected_to sync_path
    assert contacts(:two).reload
  end

  test "create insists on a decision for every conflict" do
    remote = mark_synced
    contacts(:one).update!(first_name: "Ally")
    remote[0]["first_name"] = "Alicia"
    stub_keila_contacts(remote)

    post sync_path

    assert_redirected_to sync_path
    assert_match(/decide every conflict/, flash[:alert])
  end

  test "create applies the chosen side of a conflict" do
    remote = mark_synced
    contacts(:one).update!(first_name: "Ally")
    remote[0]["first_name"] = "Alicia"
    stub_keila_contacts(remote)
    token = KeilaSync.token(contacts(:one).uuid, "first_name")

    post sync_path, params: { resolutions: { token => "remote" } }

    assert_redirected_to contacts_path
    assert_equal "Alicia", contacts(:one).reload.first_name
  end

  test "requires an active project" do
    users(:one).update!(current_keila_project: nil)

    get sync_path

    assert_redirected_to keila_projects_path
  end
end
