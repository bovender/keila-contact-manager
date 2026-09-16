require "application_system_test_case"

class BulkSelectTest < ApplicationSystemTestCase
  setup do
    sign_in_via_ui(users(:one))
  end

  test "selecting all matching a filter reaches every contact, not just the current page" do
    project = users(:one).current_keila_project
    55.times { |i| Contact.create!(email: "bulk#{i}@example.com", tag_list: "vip", keila_project: project) }
    total_vip = project.contacts.tagged_with("vip").count

    visit contacts_path(tag: "vip")
    assert_no_text "contacts on this page are selected"
    assert_selector "[data-bulk-select-ready='true']"

    js_click(:checkbox, "select_all")
    assert_text "Select all #{total_vip} matching this filter"
    js_click(:button, "Select all #{total_vip} matching this filter")

    # A plain fill_in intermittently leaves this field empty here -- likely
    # the datalist attached to it (for tag autocomplete) interfering with
    # Selenium's native keystroke simulation against this remote Chrome.
    # This field has no JS behavior of its own to exercise, so setting its
    # value directly is just as valid a test of the submission behavior.
    execute_script(%(document.getElementById("bulk-form").tag.value = "vip"))
    js_click(:button, "Remove tag")

    assert_text "Updated #{total_vip} contact(s)."
    # The identical count query earlier in this test would otherwise be
    # served from this thread's query cache, oblivious to the writes the
    # separate Puma thread just committed.
    assert_equal 0, Contact.uncached { Contact.tagged_with("vip").count }
  end
end
