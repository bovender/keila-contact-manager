require "application_system_test_case"

class ViewportPaginationTest < ApplicationSystemTestCase
  setup do
    sign_in_via_ui(users(:one))
    project = users(:one).current_keila_project
    80.times do |i|
      Contact.create!(email: "fit#{i.to_s.rjust(3, '0')}@example.com", tag_list: (i % 3).zero? ? "vip" : "", keila_project: project)
    end
  end

  teardown { resize_window(1400, 1400) }

  test "a page of contacts fills the window, and the browser remembers its size" do
    visit contacts_path
    assert_current_path(/per_page=/)
    assert_fits_window
    rows = row_count

    visit contacts_path(page: 2)
    assert_selector "tbody tr", count: rows
    sleep 1 # time enough for a correction, which mustn't come
    assert_current_path contacts_path(page: 2)
  end

  test "a smaller window gets fewer contacts" do
    visit contacts_path
    assert_current_path(/per_page=/)
    rows = row_count

    resize_window(1400, 1100)
    visit contacts_path
    assert_current_path(/per_page=/)
    assert_fits_window
    assert_operator row_count, :<, rows
  end

  test "a flash message isn't reloaded away" do
    visit new_contact_path
    execute_script(%(document.getElementById("contact_email").value = "new@example.com"))
    js_click(:button, "Create Contact")

    assert_text "Contact created."
    sleep 1 # time enough for a correction, which mustn't come
    assert_text "Contact created."
    assert_current_path contacts_path
  end

  private

  def resize_window(width, height)
    page.driver.browser.manage.window.resize_to(width, height)
  end

  def row_count
    all("tbody tr").size
  end

  # The pager is in view, and there's no room for another row.
  def assert_fits_window
    assert_selector "nav[aria-label=Pages]"
    room, row_height = evaluate_script(<<~JS)
      [ document.documentElement.clientHeight - document.querySelector("nav[aria-label=Pages]").getBoundingClientRect().bottom,
        document.querySelector("tbody tr").getBoundingClientRect().height ]
    JS
    assert_operator room, :>=, 0
    assert_operator room, :<, row_height + 24 + 1
  end
end
