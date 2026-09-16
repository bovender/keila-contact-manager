require "test_helper"

class KeilaProjectTest < ActiveSupport::TestCase
  test "requires a unique, present name" do
    project = KeilaProject.new
    assert_not project.valid?
    assert_includes project.errors[:name], "can't be blank"

    project = KeilaProject.new(name: keila_projects(:alpha).name)
    assert_not project.valid?
    assert_includes project.errors[:name], "has already been taken"
  end

  test "configured_for_sync? requires both a URL and an API key" do
    project = keila_projects(:alpha)
    assert_not project.configured_for_sync?

    project.keila_api_key = "secret"
    assert project.configured_for_sync?
  end

  test "keila_api_key is stored encrypted" do
    project = KeilaProject.create!(name: "Encrypted test", keila_url: "https://keila.example.com", keila_api_key: "secret")
    raw = ActiveRecord::Base.connection.select_value(
      "SELECT keila_api_key FROM keila_projects WHERE id = #{project.id}"
    )
    assert_not_equal "secret", raw
    assert_equal "secret", project.reload.keila_api_key
  end

  test "cannot be destroyed while it still has contacts" do
    project = keila_projects(:alpha)
    assert project.contacts.any?

    assert_not project.destroy
    assert_match(/dependent contacts exist/, project.errors[:base].join)
  end
end
